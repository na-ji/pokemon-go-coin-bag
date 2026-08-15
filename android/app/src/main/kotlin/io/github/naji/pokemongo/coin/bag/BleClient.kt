package io.github.naji.pokemongo.coin.bag

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.ParcelUuid
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeout
import java.time.Instant
import java.util.UUID

class GattError(message: String) : Exception(message)

private object ServiceUuids {
    val advertisementService: UUID = UUID.fromString(Constants.uuids.getValue("advertisementService"))
    val gattService: UUID = UUID.fromString(Constants.uuids.getValue("gattService"))
    val readProtocol: UUID = UUID.fromString(Constants.uuids.getValue("readProtocol"))
    val readName: UUID = UUID.fromString(Constants.uuids.getValue("readName"))
    val readMode: UUID = UUID.fromString(Constants.uuids.getValue("readMode"))
    val writeApplicationId: UUID = UUID.fromString(Constants.uuids.getValue("writeApplicationId"))
    val writeInitialNonce: UUID = UUID.fromString(Constants.uuids.getValue("writeInitialNonce"))
    val writeComplete: UUID = UUID.fromString(Constants.uuids.getValue("writeComplete"))
    val writeFinalNonce: UUID = UUID.fromString(Constants.uuids.getValue("writeFinalNonce"))
    val indicateData: UUID = UUID.fromString(Constants.uuids.getValue("indicateData"))
    val indicateStage: UUID = UUID.fromString(Constants.uuids.getValue("indicateStage"))
}

private val CLIENT_CHARACTERISTIC_CONFIG_UUID: UUID =
    UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

private const val INDICATION_TIMEOUT_MS = 15_000L
private const val POST_SUCCESS_DELAY_MS = 5_000L
private const val POST_FAILURE_DELAY_MS = 3_000L
private const val SETTLE_MS = 75L
private const val GATT_OP_TIMEOUT_MS = 10_000L

@SuppressLint("MissingPermission") // caller (MainActivity) verifies runtime permissions before calling run()
class BleClient(private val context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("paired_app_ids", Context.MODE_PRIVATE)

    private val _state = MutableStateFlow<AppState>(AppState.Idle)
    val state: StateFlow<AppState> = _state.asStateFlow()

    private val _log = MutableStateFlow<List<LogEntry>>(emptyList())
    val log: StateFlow<List<LogEntry>> = _log.asStateFlow()

    private fun addLogEntry(entry: LogEntry) {
        _log.value = _log.value + entry
    }

    private var gatt: BluetoothGatt? = null
    private var connectionResult: CompletableDeferred<Unit>? = null
    private var servicesResult: CompletableDeferred<Unit>? = null
    private var mtuResult: CompletableDeferred<Int>? = null
    private var readResult: CompletableDeferred<ByteArray>? = null
    private var writeResult: CompletableDeferred<Unit>? = null
    private var descriptorResult: CompletableDeferred<Unit>? = null
    private val indications = MutableSharedFlow<Pair<UUID, ByteArray>>(extraBufferCapacity = 8)

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                connectionResult?.complete(Unit)
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                failAllPending("Disconnected (status $status)")
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                mtuResult?.complete(mtu)
            } else {
                mtuResult?.completeExceptionally(GattError("MTU negotiation failed (status $status)"))
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                servicesResult?.complete(Unit)
            } else {
                servicesResult?.completeExceptionally(GattError("Service discovery failed (status $status)"))
            }
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicRead(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            completeRead(status, characteristic.value ?: ByteArray(0))
        }

        override fun onCharacteristicRead(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) {
            completeRead(status, value)
        }

        private fun completeRead(status: Int, value: ByteArray) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                readResult?.complete(value)
            } else {
                readResult?.completeExceptionally(GattError("Read failed (status $status)"))
            }
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                writeResult?.complete(Unit)
            } else {
                writeResult?.completeExceptionally(GattError("Write failed (status $status)"))
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                descriptorResult?.complete(Unit)
            } else {
                descriptorResult?.completeExceptionally(GattError("Descriptor write failed (status $status)"))
            }
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            indications.tryEmit(characteristic.uuid to (characteristic.value ?: ByteArray(0)))
        }

        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            indications.tryEmit(characteristic.uuid to value)
        }
    }

    private fun failAllPending(reason: String) {
        val error = GattError(reason)
        listOf<CompletableDeferred<*>?>(
            connectionResult,
            servicesResult,
            mtuResult,
            readResult,
            writeResult,
            descriptorResult,
        ).forEach { deferred ->
            if (deferred?.isCompleted == false) deferred.completeExceptionally(error)
        }
    }

    suspend fun run() {
        while (true) {
            try {
                _state.value = AppState.Scanning
                val device = scanForDevice()

                _state.value = AppState.Connecting
                val connectedGatt = connectAndDiscover(device)
                gatt = connectedGatt

                _state.value = AppState.ReadingDevice
                val chars = requireCharacteristics(connectedGatt)
                val protocolValue = readCharacteristic(connectedGatt, chars.getValue(ServiceUuids.readProtocol))
                require(protocolValue.size == 1 && protocolValue[0] == 0x01.toByte()) { "Unsupported protocol value" }
                val nameValue = readCharacteristic(connectedGatt, chars.getValue(ServiceUuids.readName))
                val playerName = decodePlayerName(nameValue)
                val modeValue = readCharacteristic(connectedGatt, chars.getValue(ServiceUuids.readMode))
                require(modeValue.size == 1) { "Invalid mobile app mode characteristic" }

                val nonce = randomPeripheralNonce()
                val applicationId = prefs.getString("applicationId", null)
                    ?: generateApplicationId().also {
                        prefs.edit().putString("applicationId", it).apply()
                    }

                when (modeValue[0]) {
                    0x00.toByte() -> {
                        _state.value = AppState.Pairing
                        delay(250)
                        writeCharacteristic(
                            connectedGatt,
                            chars.getValue(ServiceUuids.writeApplicationId),
                            applicationIdGattValue(applicationId),
                            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
                        )
                        _state.value = AppState.SuccessPair(playerName)
                        addLogEntry(LogEntry(Instant.now(), LogEventType.PAIRED, playerName = playerName))
                    }
                    0x01.toByte() -> {
                        _state.value = AppState.Exchanging
                        performExchange(connectedGatt, chars, applicationId, nonce)
                        _state.value = AppState.SuccessExchange(playerName)
                        addLogEntry(LogEntry(Instant.now(), LogEventType.EXCHANGED, playerName = playerName))
                    }
                    else -> throw GattError("Unsupported mobile app mode 0x${"%02x".format(modeValue[0])}")
                }
                delay(POST_SUCCESS_DELAY_MS)
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (error: Exception) {
                val message = error.message ?: error.toString()
                _state.value = AppState.Failure(message)
                addLogEntry(LogEntry(Instant.now(), LogEventType.FAILED, message = message))
                delay(POST_FAILURE_DELAY_MS)
            } finally {
                gatt?.disconnect()
                gatt?.close()
                gatt = null
            }
        }
    }

    fun cancel() {
        gatt?.disconnect()
        gatt?.close()
        gatt = null
    }

    private suspend fun scanForDevice(): BluetoothDevice {
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter ?: throw GattError("Bluetooth is not available on this device")
        require(adapter.isEnabled) { "Bluetooth is turned off" }
        val scanner = adapter.bluetoothLeScanner ?: throw GattError("BLE scanning is not available")

        val result = CompletableDeferred<BluetoothDevice>()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scanResult: ScanResult) {
                result.complete(scanResult.device)
            }
            override fun onScanFailed(errorCode: Int) {
                result.completeExceptionally(GattError("Scan failed (error $errorCode)"))
            }
        }
        val filters = listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(ServiceUuids.advertisementService)).build())
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()

        scanner.startScan(filters, settings, callback)
        return try {
            result.await()
        } finally {
            scanner.stopScan(callback)
        }
    }

    private suspend fun <T> awaitGattOp(operation: String, block: suspend () -> T): T =
        try {
            withTimeout(GATT_OP_TIMEOUT_MS) { block() }
        } catch (timeout: TimeoutCancellationException) {
            throw GattError("Timed out waiting for $operation after ${GATT_OP_TIMEOUT_MS / 1000}s")
        }

    private suspend fun connectAndDiscover(device: BluetoothDevice): BluetoothGatt {
        connectionResult = CompletableDeferred()
        val connectedGatt = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        gatt = connectedGatt
        awaitGattOp("GATT connection") { connectionResult!!.await() }
        delay(SETTLE_MS)

        // Default ATT MTU is 23 bytes; the ~295-byte exchange payload needs a larger one and only
        // the central can negotiate it.
        mtuResult = CompletableDeferred()
        if (!connectedGatt.requestMtu(517)) throw GattError("Failed to start MTU negotiation")
        awaitGattOp("MTU negotiation") { mtuResult!!.await() }
        delay(SETTLE_MS)

        servicesResult = CompletableDeferred()
        if (!connectedGatt.discoverServices()) throw GattError("Failed to start service discovery")
        awaitGattOp("service discovery") { servicesResult!!.await() }
        delay(SETTLE_MS)
        return connectedGatt
    }

    private fun requireCharacteristics(connectedGatt: BluetoothGatt): Map<UUID, BluetoothGattCharacteristic> {
        val service = connectedGatt.getService(ServiceUuids.gattService)
            ?: throw GattError("Peripheral primary service was not discovered")
        val required = listOf(
            ServiceUuids.readProtocol, ServiceUuids.readName, ServiceUuids.readMode,
            ServiceUuids.writeApplicationId, ServiceUuids.writeInitialNonce, ServiceUuids.writeComplete,
            ServiceUuids.writeFinalNonce, ServiceUuids.indicateData, ServiceUuids.indicateStage,
        )
        return required.associateWith { uuid ->
            service.getCharacteristic(uuid) ?: throw GattError("Required characteristic $uuid was not discovered")
        }
    }

    private suspend fun readCharacteristic(
        connectedGatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        settle: Boolean = true,
    ): ByteArray {
        readResult = CompletableDeferred()
        if (!connectedGatt.readCharacteristic(characteristic)) throw GattError("Failed to start characteristic read")
        val value = awaitGattOp("read of ${characteristic.uuid}") { readResult!!.await() }
        if (settle) delay(SETTLE_MS)
        return value
    }

    @Suppress("DEPRECATION")
    private suspend fun writeCharacteristic(
        connectedGatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
        writeType: Int,
        settle: Boolean = true,
    ) {
        writeResult = CompletableDeferred()
        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            connectedGatt.writeCharacteristic(characteristic, value, writeType) == BluetoothStatusCodes.SUCCESS
        } else {
            characteristic.writeType = writeType
            characteristic.value = value
            connectedGatt.writeCharacteristic(characteristic)
        }
        if (!started) throw GattError("Failed to start characteristic write")
        awaitGattOp("write of ${characteristic.uuid}") { writeResult!!.await() }
        if (settle) delay(SETTLE_MS)
    }

    @Suppress("DEPRECATION")
    private suspend fun enableIndications(
        connectedGatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        settle: Boolean = true,
    ) {
        if (!connectedGatt.setCharacteristicNotification(characteristic, true)) {
            throw GattError("Failed to enable notifications for ${characteristic.uuid}")
        }
        val cccd = characteristic.getDescriptor(CLIENT_CHARACTERISTIC_CONFIG_UUID)
            ?: throw GattError("Missing CCCD descriptor for ${characteristic.uuid}")
        descriptorResult = CompletableDeferred()
        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            connectedGatt.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_INDICATION_VALUE) == BluetoothStatusCodes.SUCCESS
        } else {
            cccd.value = BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
            connectedGatt.writeDescriptor(cccd)
        }
        if (!started) throw GattError("Failed to start CCCD write for ${characteristic.uuid}")
        awaitGattOp("CCCD write of ${characteristic.uuid}") { descriptorResult!!.await() }
        if (settle) delay(SETTLE_MS)
    }

    private suspend fun awaitIndication(uuid: UUID, timeoutMs: Long): ByteArray =
        try {
            withTimeout(timeoutMs) { indications.first { it.first == uuid }.second }
        } catch (timeout: TimeoutCancellationException) {
            throw GattError("Timed out after ${timeoutMs / 1000}s waiting for indication on $uuid")
        }

    private suspend fun performExchange(
        connectedGatt: BluetoothGatt,
        chars: Map<UUID, BluetoothGattCharacteristic>,
        applicationId: String,
        nonce: String,
    ) {
        writeCharacteristic(
            connectedGatt,
            chars.getValue(ServiceUuids.writeApplicationId),
            applicationIdGattValue(applicationId),
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
            settle = false,
        )
        writeCharacteristic(
            connectedGatt,
            chars.getValue(ServiceUuids.writeInitialNonce),
            initialNonceGattValue(nonce),
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE,
            settle = false,
        )

        val dataChar = chars.getValue(ServiceUuids.indicateData)
        val firstRaw = coroutineScope {
            val waiter = async { awaitIndication(dataChar.uuid, INDICATION_TIMEOUT_MS) }
            enableIndications(connectedGatt, dataChar, settle = false)
            waiter.await()
        }
        require(firstRaw.size >= 303) {
            "First indication is only ${firstRaw.size} bytes; the negotiated ATT MTU may be insufficient"
        }
        val send = decodeProtocolBleSend(firstRaw)
        validateSend(send, applicationId, nonce)

        val complete = encodeProtocolComplete(send.serverResponse.transactionId, send.serverResponse.nonce)

        val stageChar = chars.getValue(ServiceUuids.indicateStage)
        val finalRaw = coroutineScope {
            val dataWaiter = async { awaitIndication(dataChar.uuid, INDICATION_TIMEOUT_MS) }
            val stageWaiter = async { awaitIndication(stageChar.uuid, INDICATION_TIMEOUT_MS) }
            enableIndications(connectedGatt, stageChar, settle = false)
            writeCharacteristic(
                connectedGatt,
                chars.getValue(ServiceUuids.writeComplete),
                complete,
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE,
                settle = false,
            )
            try {
                select<ByteArray> {
                    dataWaiter.onAwait { it }
                    stageWaiter.onAwait { it }
                }
            } catch (_: TimeoutCancellationException) {
                null
            } finally {
                dataWaiter.cancel()
                stageWaiter.cancel()
            }
        }

        if (finalRaw != null) {
            writeCharacteristic(
                connectedGatt,
                chars.getValue(ServiceUuids.writeFinalNonce),
                finalNonceGattValue(nonce),
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
                settle = false,
            )
            val finalize = decodeProtocolBleFinalize(finalRaw)
            validateFinalize(finalize, applicationId, nonce)
        }
    }
}
