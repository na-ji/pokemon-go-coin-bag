import Foundation
@preconcurrency import CoreBluetooth

enum BleError: Error, LocalizedError {
    case noCentral
    case bluetoothUnavailable(CBManagerState)
    case connectFailed
    case disconnected(String)
    case serviceNotFound
    case characteristicNotFound(CBUUID)
    case unsupportedProtocol
    case invalidMode
    case unsupportedMode(UInt8)
    case mtuInsufficient(Int)
    case servicesChanged
    case readTimedOut

    var errorDescription: String? {
        switch self {
        case .noCentral:
            return "Bluetooth is not available on this device"
        case .bluetoothUnavailable(let state):
            switch state {
            case .unauthorized: return "Bluetooth permission denied"
            case .poweredOff: return "Bluetooth is turned off"
            case .unsupported: return "Bluetooth is not supported on this device"
            default: return "Bluetooth is not ready (state \(state.rawValue))"
            }
        case .connectFailed:
            return "Bluetooth connection failed"
        case .disconnected(let reason):
            return "Disconnected (\(reason))"
        case .serviceNotFound:
            return "Peripheral primary service was not discovered"
        case .characteristicNotFound(let uuid):
            return "Required characteristic \(uuid.uuidString) was not discovered"
        case .unsupportedProtocol:
            return "Unsupported protocol value"
        case .invalidMode:
            return "Invalid mobile app mode characteristic"
        case .unsupportedMode(let mode):
            return String(format: "Unsupported mobile app mode 0x%02x", mode)
        case .mtuInsufficient(let size):
            return "First indication is only \(size) bytes; the negotiated ATT MTU may be insufficient"
        case .servicesChanged:
            return "The peripheral changed its GATT services mid-operation"
        case .readTimedOut:
            return "Timed out waiting for a characteristic read response"
        }
    }
}

private enum ServiceUuids {
    static let advertisement = CBUUID(string: Constants.uuids["advertisementService"]!)
    static let gatt = CBUUID(string: Constants.uuids["gattService"]!)
    static let readProtocol = CBUUID(string: Constants.uuids["readProtocol"]!)
    static let readName = CBUUID(string: Constants.uuids["readName"]!)
    static let readMode = CBUUID(string: Constants.uuids["readMode"]!)
    static let writeApplicationId = CBUUID(string: Constants.uuids["writeApplicationId"]!)
    static let writeInitialNonce = CBUUID(string: Constants.uuids["writeInitialNonce"]!)
    static let writeComplete = CBUUID(string: Constants.uuids["writeComplete"]!)
    static let writeFinalNonce = CBUUID(string: Constants.uuids["writeFinalNonce"]!)
    static let indicateData = CBUUID(string: Constants.uuids["indicateData"]!)
    static let indicateStage = CBUUID(string: Constants.uuids["indicateStage"]!)
}

private let INDICATION_TIMEOUT: TimeInterval = 15
private let READ_TIMEOUT: TimeInterval = 8
private let POST_SUCCESS_DELAY_NS: UInt64 = 5_000_000_000
private let POST_FAILURE_DELAY_NS: UInt64 = 3_000_000_000
private let SETTLE_NS: UInt64 = 75_000_000

private final class IndicationWaiter: @unchecked Sendable {
    let uuid: CBUUID
    var continuation: CheckedContinuation<Data?, Never>?
    var received: Data?
    var timer: DispatchWorkItem?
    var resumed = false

    init(uuid: CBUUID) {
        self.uuid = uuid
    }
}

/// Mirrors android/.../BleClient.kt: a continuous scan → connect → pair/exchange loop.
/// All BLE state is confined to `queue`; `@Published` updates hop to the main thread.
final class BleClient: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var state: AppState = .idle
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var permissionDenied = false

    private let queue = DispatchQueue(label: "io.github.naji.pokemongo.coin.bag.ble")
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?

    // Pending GATT operation continuations (one outstanding op per kind at a time).
    private var powerOnCont: CheckedContinuation<Void, Error>?
    private var scanCont: CheckedContinuation<CBPeripheral, Error>?
    private var connectCont: CheckedContinuation<Void, Error>?
    private var servicesCont: CheckedContinuation<Void, Error>?
    private var characteristicsCont: CheckedContinuation<Void, Error>?
    private var readCont: CheckedContinuation<Data, Error>?
    private var writeCont: CheckedContinuation<Void, Error>?
    private var notifyCont: CheckedContinuation<Void, Error>?

    private var waiters: [CBUUID: [IndicationWaiter]] = [:]
    private var servicesStale = false
    private var readTimer: DispatchWorkItem?

    private let prefsKey = "applicationId"
    private var runTask: Task<Void, Never>?

    override init() {
        super.init()
        queue.async { [weak self] in
            guard let self else { return }
            self.central = CBCentralManager(
                delegate: self,
                queue: self.queue,
                options: [CBCentralManagerOptionShowPowerAlertKey: true]
            )
        }
    }

    // MARK: - Public lifecycle

    func start() {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        queue.async { [weak self] in
            self?.performCleanup()
        }
    }

    // MARK: - Main loop

    private func runLoop() async {
        while !Task.isCancelled {
            do {
                try await runOnce()
                try? await Task.sleep(nanoseconds: POST_SUCCESS_DELAY_NS)
            } catch is CancellationError {
                break
            } catch {
                if Task.isCancelled { break }
                let message = error.localizedDescription
                setState(.failure(message))
                appendLog(LogEntry(timestamp: Date(), type: .failed, playerName: nil, message: message))
                try? await Task.sleep(nanoseconds: POST_FAILURE_DELAY_NS)
            }
            await cleanup()
        }
    }

    private func runOnce() async throws {
        try await awaitPoweredOn()

        setState(.scanning)
        let device = try await scanForDevice()

        setState(.connecting)
        try await connectAndDiscover(device)
        try await requireCharacteristics()

        setState(.readingDevice)
        let protocolValue = try await readCharacteristic(ServiceUuids.readProtocol)
        guard protocolValue.count == 1, protocolValue[0] == 0x01 else {
            throw BleError.unsupportedProtocol
        }
        let nameValue = try await readCharacteristic(ServiceUuids.readName)
        let playerName = try decodePlayerName(nameValue)
        let modeValue = try await readCharacteristic(ServiceUuids.readMode)
        guard modeValue.count == 1 else { throw BleError.invalidMode }

        let nonce = randomPeripheralNonce()
        let applicationId = persistedApplicationId()

        switch modeValue[0] {
        case 0x00:
            setState(.pairing)
            try await Task.sleep(nanoseconds: 250_000_000)
            try await writeCharacteristic(
                ServiceUuids.writeApplicationId,
                applicationIdGattValue(applicationId),
                withResponse: true
            )
            setState(.successPair(playerName))
            appendLog(LogEntry(timestamp: Date(), type: .paired, playerName: playerName, message: nil))
        case 0x01:
            setState(.exchanging)
            try await performExchange(applicationId: applicationId, nonce: nonce)
            setState(.successExchange(playerName))
            appendLog(LogEntry(timestamp: Date(), type: .exchanged, playerName: playerName, message: nil))
        default:
            throw BleError.unsupportedMode(modeValue[0])
        }
    }

    // MARK: - BLE operations

    private func awaitPoweredOn() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else { cont.resume(throwing: BleError.noCentral); return }
                guard let central = self.central else {
                    cont.resume(throwing: BleError.noCentral)
                    return
                }
                switch central.state {
                case .poweredOn:
                    self.setPermissionDenied(false)
                    cont.resume()
                case .unknown, .resetting:
                    self.powerOnCont = cont
                case .unauthorized:
                    self.setPermissionDenied(true)
                    cont.resume(throwing: BleError.bluetoothUnavailable(.unauthorized))
                case .poweredOff:
                    self.setPermissionDenied(false)
                    cont.resume(throwing: BleError.bluetoothUnavailable(.poweredOff))
                case .unsupported:
                    cont.resume(throwing: BleError.bluetoothUnavailable(.unsupported))
                @unknown default:
                    cont.resume(throwing: BleError.bluetoothUnavailable(central.state))
                }
            }
        }
    }

    private func scanForDevice() async throws -> CBPeripheral {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CBPeripheral, Error>) in
            queue.async { [weak self] in
                guard let self, let central = self.central else {
                    cont.resume(throwing: BleError.noCentral)
                    return
                }
                guard central.state == .poweredOn else {
                    cont.resume(throwing: BleError.bluetoothUnavailable(central.state))
                    return
                }
                self.scanCont = cont
                central.scanForPeripherals(withServices: [ServiceUuids.advertisement], options: nil)
            }
        }
    }

    private func connectAndDiscover(_ device: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self, let central = self.central else {
                    cont.resume(throwing: BleError.noCentral)
                    return
                }
                self.peripheral = device
                device.delegate = self
                self.connectCont = cont
                central.connect(device)
            }
        }
        try await Task.sleep(nanoseconds: SETTLE_NS)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else { cont.resume(throwing: BleError.noCentral); return }
                self.servicesCont = cont
                device.discoverServices(nil)
            }
        }
        try await Task.sleep(nanoseconds: SETTLE_NS)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else { cont.resume(throwing: BleError.noCentral); return }
                guard let service = device.services?.first(where: { $0.uuid == ServiceUuids.gatt }) else {
                    cont.resume(throwing: BleError.serviceNotFound)
                    return
                }
                self.characteristicsCont = cont
                device.discoverCharacteristics(nil, for: service)
            }
        }
        try await Task.sleep(nanoseconds: SETTLE_NS)
    }

    private func requireCharacteristics() async throws {
        if servicesStale { try await rediscoverService() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else { cont.resume(throwing: BleError.noCentral); return }
                do {
                    try self.validateCharacteristics()
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func validateCharacteristics() throws {
        guard let peripheral, let service = peripheral.services?.first(where: { $0.uuid == ServiceUuids.gatt }) else {
            throw BleError.serviceNotFound
        }
        guard let discovered = service.characteristics else {
            throw BleError.serviceNotFound
        }
        let required: [CBUUID] = [
            ServiceUuids.readProtocol, ServiceUuids.readName, ServiceUuids.readMode,
            ServiceUuids.writeApplicationId, ServiceUuids.writeInitialNonce, ServiceUuids.writeComplete,
            ServiceUuids.writeFinalNonce, ServiceUuids.indicateData, ServiceUuids.indicateStage,
        ]
        for uuid in required {
            guard discovered.first(where: { $0.uuid == uuid }) != nil else {
                throw BleError.characteristicNotFound(uuid)
            }
        }
    }

    private func readCharacteristic(_ uuid: CBUUID, settle: Bool = true) async throws -> Data {
        var lastError: Error = BleError.readTimedOut
        for _ in 0..<2 {
            let characteristic = try await freshCharacteristic(uuid)
            do {
                let data = try await readCharacteristicRaw(characteristic)
                if settle { try await Task.sleep(nanoseconds: SETTLE_NS) }
                return data
            } catch BleError.servicesChanged {
                // Peripheral re-registered its GATT table mid-read; re-discover and retry.
                lastError = BleError.servicesChanged
                continue
            } catch BleError.readTimedOut {
                // A dropped read usually means the cached handle went stale; force a
                // fresh service discovery before retrying.
                lastError = BleError.readTimedOut
                servicesStale = true
                continue
            }
        }
        throw lastError
    }

    private func readCharacteristicRaw(_ characteristic: CBCharacteristic) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            queue.async { [weak self] in
                guard let self, let peripheral = self.peripheral else {
                    cont.resume(throwing: BleError.noCentral)
                    return
                }
                self.readCont = cont
                let timer = DispatchWorkItem { [weak self] in
                    self?.timeoutRead()
                }
                self.readTimer = timer
                self.queue.asyncAfter(deadline: .now() + READ_TIMEOUT, execute: timer)
                peripheral.readValue(for: characteristic)
            }
        }
    }

    private func timeoutRead() {
        // Runs on `queue`.
        guard let cont = readCont else { return }
        readCont = nil
        readTimer = nil
        cont.resume(throwing: BleError.readTimedOut)
    }

    private func freshCharacteristic(_ uuid: CBUUID) async throws -> CBCharacteristic {
        if servicesStale || resolveCharacteristic(uuid) == nil {
            try await rediscoverService()
        }
        guard let characteristic = resolveCharacteristic(uuid) else {
            throw BleError.characteristicNotFound(uuid)
        }
        return characteristic
    }

    private func resolveCharacteristic(_ uuid: CBUUID) -> CBCharacteristic? {
        guard let service = peripheral?.services?.first(where: { $0.uuid == ServiceUuids.gatt }),
              let characteristics = service.characteristics else {
            return nil
        }
        return characteristics.first(where: { $0.uuid == uuid })
    }

    private func rediscoverService() async throws {
        servicesStale = false
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self, let peripheral = self.peripheral else {
                    cont.resume(throwing: BleError.noCentral)
                    return
                }
                self.servicesCont = cont
                peripheral.discoverServices(nil)
            }
        }
        try await Task.sleep(nanoseconds: SETTLE_NS)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self, let peripheral = self.peripheral else {
                    cont.resume(throwing: BleError.noCentral)
                    return
                }
                guard let service = peripheral.services?.first(where: { $0.uuid == ServiceUuids.gatt }) else {
                    cont.resume(throwing: BleError.serviceNotFound)
                    return
                }
                self.characteristicsCont = cont
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
        try await Task.sleep(nanoseconds: SETTLE_NS)
    }

    private func writeCharacteristic(
        _ uuid: CBUUID,
        _ value: Data,
        withResponse: Bool,
        settle: Bool = true
    ) async throws {
        let characteristic = try await freshCharacteristic(uuid)
        try await writeCharacteristicRaw(characteristic, value, withResponse: withResponse)
        if settle { try await Task.sleep(nanoseconds: SETTLE_NS) }
    }

    /// Writes to a specific characteristic reference without re-resolving or re-discovering.
    /// Used for the final-nonce write: Pokémon GO tears its GATT table down right after the
    /// finalize indication, so that write must land within ~90ms (no time for re-discovery).
    private func writeCharacteristicRaw(
        _ characteristic: CBCharacteristic,
        _ value: Data,
        withResponse: Bool
    ) async throws {
        if withResponse {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                queue.async { [weak self] in
                    guard let self, let peripheral = self.peripheral else {
                        cont.resume(throwing: BleError.noCentral)
                        return
                    }
                    self.writeCont = cont
                    peripheral.writeValue(value, for: characteristic, type: .withResponse)
                }
            }
        } else {
            // CoreBluetooth provides no callback for writes-without-response; the write is
            // fire-and-forget (matching the Android/WEB no-response semantics).
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                queue.async { [weak self] in
                    self?.peripheral?.writeValue(value, for: characteristic, type: .withoutResponse)
                    cont.resume()
                }
            }
        }
    }

    private func enableIndications(_ uuid: CBUUID, settle: Bool = true) async throws {
        let characteristic = try await freshCharacteristic(uuid)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self, let peripheral = self.peripheral else {
                    cont.resume(throwing: BleError.noCentral)
                    return
                }
                self.notifyCont = cont
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        if settle { try await Task.sleep(nanoseconds: SETTLE_NS) }
    }

    private func performExchange(
        applicationId: String,
        nonce: String
    ) async throws {
        // Resolve the final-nonce characteristic up front. Pokémon GO tears its GATT table
        // down immediately after the finalize indication, so the final-nonce write must reuse
        // this reference (no re-discovery) to land within the ~90ms window.
        let finalNonceChar = try await freshCharacteristic(ServiceUuids.writeFinalNonce)

        try await writeCharacteristic(
            ServiceUuids.writeApplicationId,
            applicationIdGattValue(applicationId),
            withResponse: true,
            settle: false
        )
        try await writeCharacteristic(
            ServiceUuids.writeInitialNonce,
            initialNonceGattValue(nonce),
            withResponse: false,
            settle: false
        )

        let dataUUID = ServiceUuids.indicateData
        let firstGetter = prepareIndication(dataUUID, timeout: INDICATION_TIMEOUT)
        try await enableIndications(dataUUID, settle: false)
        guard let firstRaw = await firstGetter(), firstRaw.count >= 303 else {
            throw BleError.mtuInsufficient(0)
        }

        let send = try decodeProtocolBleSend(firstRaw)
        try validateSend(send, expectedApplicationId: applicationId, expectedNonce: nonce)
        let complete = encodeProtocolComplete(send.serverResponse.transactionId, send.serverResponse.nonce)

        let stageUUID = ServiceUuids.indicateStage
        let dataGetter = prepareIndication(dataUUID, timeout: INDICATION_TIMEOUT)
        let stageGetter = prepareIndication(stageUUID, timeout: INDICATION_TIMEOUT)
        try await enableIndications(stageUUID, settle: false)
        try await writeCharacteristic(ServiceUuids.writeComplete, complete, withResponse: false, settle: false)

        // Finalize indication arrives on DATA (Android GO) or STAGE (iOS GO).
        let finalRaw = await firstNonNil(dataGetter, stageGetter)
        clearWaiters([dataUUID, stageUUID])

        if let finalRaw {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await self.writeCharacteristicRaw(finalNonceChar, finalNonceGattValue(nonce), withResponse: true)
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 3_000_000_000)
                        throw BleError.readTimedOut
                    }
                    try await group.next()
                    group.cancelAll()
                }
            } catch {
                print("[BLE] finalNonce write failed (expected if GO tore down): \(error.localizedDescription)")
            }
            let finalize = try decodeProtocolBleFinalize(finalRaw)
            try validateFinalize(finalize, expectedApplicationId: applicationId, expectedNonce: nonce)
        }
        // If finalRaw is nil (finalize indication timed out), the postcard was likely sent.
    }

    // MARK: - Indication waiters

    private func prepareIndication(_ uuid: CBUUID, timeout: TimeInterval) -> @Sendable () async -> Data? {
        let waiter = IndicationWaiter(uuid: uuid)
        queue.async { [weak self] in
            guard let self else { return }
            self.waiters[uuid, default: []].append(waiter)
            let timer = DispatchWorkItem { [weak self] in
                self?.timeoutWaiter(waiter, uuid: uuid)
            }
            waiter.timer = timer
            self.queue.asyncAfter(deadline: .now() + timeout, execute: timer)
        }
        let q = queue
        return {
            await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
                q.async {
                    if waiter.resumed {
                        cont.resume(returning: waiter.received)
                    } else {
                        waiter.continuation = cont
                    }
                }
            }
        }
    }

    private func timeoutWaiter(_ waiter: IndicationWaiter, uuid: CBUUID) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !waiter.resumed else { return }
            waiter.resumed = true
            self.removeWaiter(waiter, uuid: uuid)
            if let cont = waiter.continuation {
                waiter.continuation = nil
                cont.resume(returning: nil)
            }
        }
    }

    private func deliverIndication(_ uuid: CBUUID, _ data: Data) {
        guard var list = waiters[uuid], !list.isEmpty else {
            print("[BLE] deliverIndication \(uuid.uuidString) DROPPED — no waiter registered")
            return
        }
        let waiter = list.removeFirst()
        waiters[uuid] = list.isEmpty ? nil : list
        guard !waiter.resumed else {
            print("[BLE] deliverIndication \(uuid.uuidString) DROPPED — waiter already resumed")
            return
        }
        waiter.resumed = true
        waiter.timer?.cancel()
        if let cont = waiter.continuation {
            waiter.continuation = nil
            print("[BLE] deliverIndication \(uuid.uuidString) → resumed continuation (\(data.count) bytes)")
            cont.resume(returning: data)
        } else {
            waiter.received = data
            print("[BLE] deliverIndication \(uuid.uuidString) → buffered (\(data.count) bytes)")
        }
    }

    private func removeWaiter(_ waiter: IndicationWaiter, uuid: CBUUID) {
        guard var list = waiters[uuid] else { return }
        list.removeAll { $0 === waiter }
        waiters[uuid] = list.isEmpty ? nil : list
    }

    private func clearWaiters(_ uuids: [CBUUID]) {
        for uuid in uuids {
            guard let list = waiters[uuid] else { continue }
            waiters[uuid] = nil
            for waiter in list {
                waiter.timer?.cancel()
                guard !waiter.resumed else { continue }
                waiter.resumed = true
                if let cont = waiter.continuation {
                    waiter.continuation = nil
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func firstNonNil(
        _ a: @escaping () async -> Data?,
        _ b: @escaping () async -> Data?
    ) async -> Data? {
        await withCheckedContinuation { cont in
            let lock = NSLock()
            var resumed = false
            var finishedCount = 0

            func deliver(_ value: Data?) {
                lock.lock()
                defer { lock.unlock() }
                finishedCount += 1
                if !resumed, let value {
                    resumed = true
                    print("[BLE] firstNonNil resolved: \(value.count) bytes")
                    cont.resume(returning: value)
                } else if finishedCount == 2, !resumed {
                    resumed = true
                    print("[BLE] firstNonNil: both nil")
                    cont.resume(returning: nil)
                }
            }

            Task { deliver(await a()) }
            Task { deliver(await b()) }
        }
    }

    // MARK: - Helpers

    private func persistedApplicationId() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: prefsKey) {
            return existing
        }
        let fresh = generateApplicationId()
        defaults.set(fresh, forKey: prefsKey)
        return fresh
    }

    private func setState(_ newState: AppState) {
        DispatchQueue.main.async { [weak self] in
            self?.state = newState
        }
    }

    private func setPermissionDenied(_ value: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.permissionDenied = value
        }
    }

    private func appendLog(_ entry: LogEntry) {
        DispatchQueue.main.async { [weak self] in
            self?.log.append(entry)
        }
    }

    private func failAllPending(_ reason: String) {
        let error = BleError.disconnected(reason)
        if let cont = connectCont { connectCont = nil; cont.resume(throwing: error) }
        if let cont = servicesCont { servicesCont = nil; cont.resume(throwing: error) }
        if let cont = characteristicsCont { characteristicsCont = nil; cont.resume(throwing: error) }
        readTimer?.cancel()
        readTimer = nil
        if let cont = readCont { readCont = nil; cont.resume(throwing: error) }
        if let cont = writeCont { writeCont = nil; cont.resume(throwing: error) }
        if let cont = notifyCont { notifyCont = nil; cont.resume(throwing: error) }
        if let cont = scanCont { scanCont = nil; cont.resume(throwing: error) }
    }

    private func cleanup() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                self?.performCleanup()
                cont.resume()
            }
        }
    }

    /// Runs on `queue`. Tears down the connection and cancels every pending waiter.
    private func performCleanup() {
        failAllPending("disconnected")
        for uuid in Array(waiters.keys) {
            clearWaiters([uuid])
        }
        if let peripheral, let central {
            central.cancelPeripheralConnection(peripheral)
        }
        central?.stopScan()
        peripheral = nil
        servicesStale = false
    }
}

// MARK: - CBCentralManagerDelegate

extension BleClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            setPermissionDenied(false)
            if let cont = powerOnCont {
                powerOnCont = nil
                cont.resume()
            }
        case .unauthorized:
            setPermissionDenied(true)
            let error = BleError.bluetoothUnavailable(.unauthorized)
            if let cont = powerOnCont {
                powerOnCont = nil
                cont.resume(throwing: error)
            }
            failAllPending(error.localizedDescription)
        case .poweredOff:
            setPermissionDenied(false)
            let error = BleError.bluetoothUnavailable(.poweredOff)
            if let cont = powerOnCont {
                powerOnCont = nil
                cont.resume(throwing: error)
            }
            failAllPending(error.localizedDescription)
        case .unsupported:
            let error = BleError.bluetoothUnavailable(.unsupported)
            if let cont = powerOnCont {
                powerOnCont = nil
                cont.resume(throwing: error)
            }
            failAllPending(error.localizedDescription)
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if let cont = scanCont {
            scanCont = nil
            central.stopScan()
            cont.resume(returning: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if let cont = connectCont {
            connectCont = nil
            cont.resume()
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let cont = connectCont {
            connectCont = nil
            cont.resume(throwing: error ?? BleError.connectFailed)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        failAllPending(error?.localizedDescription ?? "disconnected")
    }
}

// MARK: - CBPeripheralDelegate

extension BleClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        print("[BLE] didDiscoverServices error=\(error?.localizedDescription ?? "nil") services=\(peripheral.services?.map(\.uuid.uuidString) ?? [])")
        if let error {
            if let cont = servicesCont {
                servicesCont = nil
                cont.resume(throwing: error)
            }
            return
        }
        if let cont = servicesCont {
            servicesCont = nil
            cont.resume()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        print("[BLE] didDiscoverCharacteristics error=\(error?.localizedDescription ?? "nil") count=\(service.characteristics?.count ?? 0)")
        if let error {
            if let cont = characteristicsCont {
                characteristicsCont = nil
                cont.resume(throwing: error)
            }
            return
        }
        if let cont = characteristicsCont {
            characteristicsCont = nil
            cont.resume()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        print("[BLE] didUpdateValue char=\(characteristic.uuid.uuidString) isNotifying=\(characteristic.isNotifying) error=\(error?.localizedDescription ?? "nil") bytes=\(characteristic.value?.count ?? 0) readCont=\(readCont != nil)")
        if let error {
            if let cont = readCont {
                readCont = nil
                readTimer?.cancel()
                readTimer = nil
                cont.resume(throwing: error)
            }
            return
        }
        let data = characteristic.value ?? Data()
        if characteristic.isNotifying {
            deliverIndication(characteristic.uuid, data)
        } else if let cont = readCont {
            readCont = nil
            readTimer?.cancel()
            readTimer = nil
            cont.resume(returning: data)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        print("[BLE] didWriteValue char=\(characteristic.uuid.uuidString) error=\(error?.localizedDescription ?? "nil")")
        guard let cont = writeCont else { return }
        writeCont = nil
        if let error {
            cont.resume(throwing: error)
        } else {
            cont.resume()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        print("[BLE] didUpdateNotificationState char=\(characteristic.uuid.uuidString) isNotifying=\(characteristic.isNotifying) error=\(error?.localizedDescription ?? "nil")")
        guard let cont = notifyCont else { return }
        notifyCont = nil
        if let error {
            cont.resume(throwing: error)
        } else {
            cont.resume()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        print("[BLE] didModifyServices invalidated=\(invalidatedServices.map(\.uuid.uuidString))")
        servicesStale = true
        let error = BleError.servicesChanged
        if let cont = readCont {
            readCont = nil
            readTimer?.cancel()
            readTimer = nil
            cont.resume(throwing: error)
        }
        if let cont = writeCont {
            writeCont = nil
            cont.resume(throwing: error)
        }
        if let cont = notifyCont {
            notifyCont = nil
            cont.resume(throwing: error)
        }
        for (uuid, list) in waiters {
            for waiter in list {
                guard !waiter.resumed else { continue }
                waiter.resumed = true
                waiter.timer?.cancel()
                if let cont = waiter.continuation {
                    waiter.continuation = nil
                    cont.resume(returning: nil)
                }
            }
            waiters[uuid] = nil
        }
    }
}
