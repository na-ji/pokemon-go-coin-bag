import Foundation
import CryptoKit

// Swift port of docs/protocol.js (and android/.../Protocol.kt).
// Same RSA key, UUIDs, protobuf codec, nonce generation, and applicationId rules.

enum ProtocolError: Error, LocalizedError {
    case invalidHex
    case truncatedVarint
    case fieldNumberZero
    case unsupportedWireType(Int)
    case missingField(Int)
    case notBytesField(Int)
    case notVarintField(Int)
    case negativeInteger
    case integerTooBig
    case nameOutOfRange
    case nonceContainsNul
    case applicationIdSuffixMismatch
    case applicationIdTooLong
    case applicationIdMismatch
    case nonceMismatch
    case digestDoesNotFit

    var errorDescription: String? {
        switch self {
        case .invalidHex: return "Invalid hexadecimal string"
        case .truncatedVarint: return "Invalid or truncated protobuf varint"
        case .fieldNumberZero: return "Protobuf field number zero"
        case .unsupportedWireType(let t): return "Unsupported protobuf wire type \(t)"
        case .missingField(let n): return "Missing protobuf field \(n)"
        case .notBytesField(let n): return "Protobuf field \(n) is not length-delimited"
        case .notVarintField(let n): return "Protobuf field \(n) is not a varint"
        case .negativeInteger: return "Cannot encode a negative integer as unsigned bytes"
        case .integerTooBig: return "Integer does not fit in requested width"
        case .nameOutOfRange: return "Player name must be 4..15 UTF-8 bytes"
        case .nonceContainsNul: return "Nonce contains NUL"
        case .applicationIdSuffixMismatch: return "Application ID must end with +titan"
        case .applicationIdTooLong: return "Application ID exceeds the 69-byte GATT field"
        case .applicationIdMismatch: return "Application ID mismatch"
        case .nonceMismatch: return "Nonce mismatch"
        case .digestDoesNotFit: return "Digest encoding does not fit RSA modulus"
        }
    }
}

// MARK: - Constants (base64 JSON, identical payload to web/android)

private let CONSTANTS_BASE64 = """
eyJVVUlEUyI6eyJhZHZlcnRpc2VtZW50U2VydmljZSI6ImI2YzMwODlhLTdlNGYtNDg3ZC1iOWY4LTczYTI4MWRkNzE4ZiIsImdh
dHRTZXJ2aWNlIjoiYWJmYWY0YzctNWE0NC00NDVhLWEwMDctYWQxOWZjYjI5ZTk5IiwicmVhZFByb3RvY29sIjoiMjkxZTA4ODkt
Y2IyMS00YWRkLWE1ODctM2JiNDk0Y2EyYWNmIiwicmVhZE5hbWUiOiI5NWMzM2M5YS05Yjc2LTQxOTQtOGU0MS0zYjY2YWE4YmIw
MjEiLCJyZWFkTW9kZSI6IjhmODYwZmQ4LTUxZTQtNDk3ZC1hZmVkLTk0MjUzZGJlMmUwYSIsIndyaXRlQXBwbGljYXRpb25JZCI6
IjI4ZmRjNmVjLWIwNzMtNGU0YS1iZjdlLTkxYWYxNmMzZTg5MCIsIndyaXRlSW5pdGlhbE5vbmNlIjoiMmY4YjA2YzItMGU4MC00
NWU1LWEwZGQtYWQzNGM5ZjdjZWIwIiwid3JpdGVDb21wbGV0ZSI6ImM1YjMxOGRhLTg5ZTYtNDgxZi05OGU0LWI0ZTBhNDIwMzQ4
NyIsIndyaXRlRmluYWxOb25jZSI6IjYzMjQ4MDJlLTUyNjYtNGY0YS05NWJlLTNhOGY4MTE4NzRmYyIsImluZGljYXRlRGF0YSI6
IjAwMGRkM2FhLWQ5MTYtNGJjNy04YTA4LWFlMWE4YTAwOGU4YSIsImluZGljYXRlU3RhZ2UiOiJlMzVkYTI2NC0zODRlLTRkYjMt
YWUyNy1hMWJhMmIxZjUzM2QifSwiQVBQTElDQVRJT05fSURfU1VGRklYIjoiK3RpdGFuIiwiQVBQTElDQVRJT05fSURfR0FUVF9X
SURUSCI6NjksIlRFWFRfRU5DT0RJTkciOiJ1dGYtOCIsIlRFWFRfREVDT0RFUl9GQVRBTCI6dHJ1ZSwiUlNBX01PRFVMVVMiOiIw
eDAwY2Y5ZWRiMmFiMjE0YjYzNmYzYTRlYTYzZjc2ZTgyZjIwNjdiNzQ2NTYzYjM3YjY4ZDAxZmNiNTI3MmMxMzA3YTIyMmFiN2Q5
YWM1ZDhlOTA5YmMwMjA2MWIwNzEwNTk1Mjk0MzE1NzRjY2E3NWFkM2Y2Mzk5NzI5NGFjY2YxYzM1ZWQ5ZDc5YjE4ZjdkYTkwZWVm
ZjI0NmUzYWM4MDZmNTdmNDBlNGNiZTQyMWZkZWQ1ODY2OTU5MWJlNmE4OTQ4ZTYzMDQ3NDYyMjY3NmM4MjJhMDQ4MmJlY2YyYzkz
ZmZiZTE1M2FlMWExMzI5MmFjMTcxMzkzNDk1OWM3YTY2OTVkNTNkN2NmYWY4YjdmMDAxYzIyMmY3NTU0YTFhOTMzMDliY2EwODVm
ZjM4NDRmZTM3ZDE4ODhlNzZmNmQzNmI3YTU5ZjBiZDNjZTFiZTc5NTgzYmUxYzNhNjBjN2RiMzk2OTQxZDhkN2E4YTQwNmQzMjAy
ODEwZDkzZTRmYzU5ZWYyYmVkMDJlMWUyN2I2ODIyOGY1MTVmOWMyYzJjMmE1Mzg2NDE5NDEyNzkxMjgzMzc0MDRiODVkNmUzNTY0
NDdhNjZiYmNmNTM2NTNkMjFmMjY3NjE5MzJmMDExYzAwZTE2YzU3MGZjODI5NzdmZjIwOWFkOTZmNjVlY2YxZDciLCJSU0FfUFJJ
VkFURV9FWFBPTkVOVCI6IjB4NDk1ZWUyMjRkYzc5ZTU0YWQ2MWY1OTk1YWE0MzJiOTM0YzI3MjRhMzBmZjBjNTkzZWNiOGNmYTk3
YjU0M2E0NTZlZmQ5OWFiMWFmNjk1MDMxNTg3NzdlYTBkZTg2MzA4YWI2NDQxOThkZDE5ZTc0NzMwYTQ3OTdlZTYyODM2ZTdjYzA1
M2ZlNDU3OTY3ZjZlZTg4NmQxZTEwMjc0ZGRjMGI0MGZjMmNiMmFmYmI4MzhjMDFjYzA4ZTk4YjQxZDdmZGQ5OTAyMTcwZWUxNmRi
ZjMyMGExNjBhNDgzYzgwYjBjODAzYzhhMzIzY2MzMzc5MGQ0ZWE1YTYyZTRjMTdjYTUxNjNmYTAxZDYzZDY1MzQyOWMzMDljNjQ1
MmMwMGYwZTE5ZmQ4YWZhNzZkMzE2Zjg5OTc5MGE1M2Q5ZTI5ODkxYWM1ZTk5MjI0OTQ3NTQ0MzUyNjI3MWExMWVhNWE2OGY4MDMx
OTBhODk2ZDRlZmM1ZmEzM2RjYWQzZTFmNjE1NWUyNTMxNjU0NzU3ZjczN2UxNTgxNGQxNmYzOTZlYjI1ODMzYzUxOGZiZWI1M2Zj
YzM5Mzk0NTEwYTc5YjA3YTM4NGZjMjZhMGVmNGYzNTI0YmE2MDYyYWViYzA2ZmEyNmJiZTZmY2FhMTQzNTMwNDkwNDQ5OGVkNWM5
YTQyYzEiLCJTSEEyNTZfRElHRVNUX0lORk9fUFJFRklYIjoiMzAzMTMwMGQwNjA5NjA4NjQ4MDE2NTAzMDQwMjAxMDUwMDA0MjAi
fQ==
"""

enum Constants {
    private static let json: [String: Any] = {
        let cleaned = CONSTANTS_BASE64.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        let data = Data(base64Encoded: cleaned)!
        return (try! JSONSerialization.jsonObject(with: data) as! [String: Any])
    }()

    static var uuids: [String: String] { json["UUIDS"] as! [String: String] }
    static var applicationIdSuffix: String { json["APPLICATION_ID_SUFFIX"] as! String }
    static var applicationIdGattWidth: Int { json["APPLICATION_ID_GATT_WIDTH"] as! Int }
    static var rsaModulus: BigUInt { BigUInt(hex: json["RSA_MODULUS"] as! String) }
    static var rsaPrivateExponent: BigUInt { BigUInt(hex: json["RSA_PRIVATE_EXPONENT"] as! String) }
    static var sha256DigestInfoPrefix: Data { hexToBytes(json["SHA256_DIGEST_INFO_PREFIX"] as! String) }
}

// MARK: - Byte helpers

func concatBytes(_ parts: Data...) -> Data {
    var result = Data()
    result.reserveCapacity(parts.reduce(0) { $0 + $1.count })
    for part in parts { result.append(part) }
    return result
}

func hexToBytes(_ hex: String) -> Data {
    var hex = hex
    if hex.hasPrefix("0x") || hex.hasPrefix("0X") { hex.removeFirst(2) }
    guard hex.count % 2 == 0, hex.unicodeScalars.allSatisfy({ $0.value <= 0x7f }) else {
        preconditionFailure(ProtocolError.invalidHex.localizedDescription)
    }
    var result = Data()
    result.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<next], radix: 16) else {
            preconditionFailure(ProtocolError.invalidHex.localizedDescription)
        }
        result.append(byte)
        index = next
    }
    return result
}

func bytesToHex(_ bytes: Data) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

func bytesToBigInt(_ bytes: Data) -> BigUInt { BigUInt(data: bytes) }

func bigIntToBytes(_ value: BigUInt, _ width: Int) -> Data {
    let magnitude = value.serialize()
    guard magnitude.count <= width else {
        preconditionFailure(ProtocolError.integerTooBig.localizedDescription)
    }
    var result = Data(repeating: 0, count: width - magnitude.count)
    result.append(magnitude)
    return result
}

// MARK: - Protobuf primitives

func encodeVarint(_ input: UInt64) -> Data {
    var value = input
    var result = Data()
    while true {
        let septet = UInt8(value & 0x7f)
        value >>= 7
        if value != 0 {
            result.append(septet | 0x80)
        } else {
            result.append(septet)
            break
        }
    }
    return result
}

func decodeVarint(_ data: Data, _ initialOffset: Int = 0) throws -> (value: Int64, offset: Int) {
    var value: UInt64 = 0
    var shift = 0
    var offset = initialOffset
    while offset < data.count && shift < 70 {
        let octet = UInt64(data[offset])
        offset += 1
        value |= (octet & 0x7f) &<< UInt64(shift)
        if octet & 0x80 == 0 {
            return (Int64(bitPattern: value), offset)
        }
        shift += 7
    }
    throw ProtocolError.truncatedVarint
}

enum ProtoField {
    case varint(Int64)
    case bytes(Data)
}

private func bytesField(_ number: Int, _ value: Data) -> Data {
    concatBytes(
        encodeVarint(UInt64((number << 3) | 2)),
        encodeVarint(UInt64(value.count)),
        value
    )
}

private func stringField(_ number: Int, _ value: String) -> Data {
    bytesField(number, Data(value.utf8))
}

private func varintField(_ number: Int, _ value: Int64) -> Data {
    concatBytes(
        encodeVarint(UInt64(number << 3)),
        encodeVarint(UInt64(bitPattern: value))
    )
}

func parseFields(_ data: Data) throws -> [Int: ProtoField] {
    var fields: [Int: ProtoField] = [:]
    var offset = 0
    while offset < data.count {
        let tagResult = try decodeVarint(data, offset)
        let tag = tagResult.value
        offset = tagResult.offset
        let number = Int(tag >> 3)
        let wireType = Int(tag & 7)
        guard number != 0 else { throw ProtocolError.fieldNumberZero }

        switch wireType {
        case 0:
            let result = try decodeVarint(data, offset)
            fields[number] = .varint(result.value)
            offset = result.offset
        case 2:
            let lengthResult = try decodeVarint(data, offset)
            offset = lengthResult.offset
            let length = Int(lengthResult.value)
            guard length >= 0, offset + length <= data.count else {
                throw ProtocolError.truncatedVarint
            }
            fields[number] = .bytes(data.subdata(in: offset..<(offset + length)))
            offset += length
        default:
            throw ProtocolError.unsupportedWireType(wireType)
        }
    }
    return fields
}

func requireBytes(_ fields: [Int: ProtoField], _ number: Int) throws -> Data {
    guard let field = fields[number] else { throw ProtocolError.missingField(number) }
    guard case .bytes(let value) = field else { throw ProtocolError.notBytesField(number) }
    return value
}

func requireVarint(_ fields: [Int: ProtoField], _ number: Int) throws -> Int64 {
    guard let field = fields[number] else { throw ProtocolError.missingField(number) }
    guard case .varint(let value) = field else { throw ProtocolError.notVarintField(number) }
    return value
}

// MARK: - Protocol messages

struct ServerResponse {
    let data: Int64
    let transactionId: Int64
    let applicationId: String
    let nonce: String
}

struct ProtocolBleSend {
    let serverResponse: ServerResponse
    let serverSignature: Data
}

func decodeProtocolBleSend(_ data: Data) throws -> ProtocolBleSend {
    let outer = try parseFields(data)
    let prep = try parseFields(try requireBytes(outer, 1))
    return ProtocolBleSend(
        serverResponse: ServerResponse(
            data: try requireVarint(prep, 1),
            transactionId: try requireVarint(prep, 2),
            applicationId: String(decoding: try requireBytes(prep, 3), as: UTF8.self),
            nonce: String(decoding: try requireBytes(prep, 4), as: UTF8.self)
        ),
        serverSignature: try requireBytes(outer, 2)
    )
}

struct ProtocolBleFinalize {
    let nonce: String
    let applicationId: String
    let serverSignature: Data
}

func decodeProtocolBleFinalize(_ data: Data) throws -> ProtocolBleFinalize {
    let outer = try parseFields(data)
    let complete = try parseFields(try requireBytes(outer, 1))
    return ProtocolBleFinalize(
        nonce: String(decoding: try requireBytes(complete, 1), as: UTF8.self),
        applicationId: String(decoding: try requireBytes(complete, 2), as: UTF8.self),
        serverSignature: try requireBytes(outer, 2)
    )
}

func encodeProtocolShare(_ transactionId: Int64, _ nonce: String) -> Data {
    concatBytes(varintField(1, transactionId), stringField(2, nonce))
}

// MARK: - RSA

private let cachedSecKey: SecKey = {
    let n = Constants.rsaModulus
    let d = Constants.rsaPrivateExponent
    let e = BigUInt(limbs: [0x10001])

    let (p, q) = factorFromNED(n: n, e: e, d: d)
    let dp = d % (p - BigUInt(limbs: [1]))
    let dq = d % (q - BigUInt(limbs: [1]))
    let qinv = q.modInverse(p)

    let der = buildPKCS1PrivateKeyDER(
        n: bigIntToBytes(n, 256), e: Data([0x01, 0x00, 0x01]),
        d: bigIntToBytes(d, 256), p: bigIntToBytes(p, 128),
        q: bigIntToBytes(q, 128), dp: bigIntToBytes(dp, 128),
        dq: bigIntToBytes(dq, 128), qinv: bigIntToBytes(qinv, 128)
    )

    let attrs: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        kSecAttrKeySizeInBits: 2048,
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &error) else {
        preconditionFailure("SecKey creation failed: \(error!.takeRetainedValue())")
    }
    return key
}()

func peripheralRsaSignature(_ message: Data) -> Data {
    var error: Unmanaged<CFError>?
    guard let signature = SecKeyCreateSignature(cachedSecKey, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &error) else {
        preconditionFailure("RSA signing failed: \(error!.takeRetainedValue())")
    }
    return signature as Data
}

private func factorFromNED(n: BigUInt, e: BigUInt, d: BigUInt) -> (BigUInt, BigUInt) {
    let one = BigUInt(limbs: [1])
    let two = BigUInt(limbs: [2])
    var k = e * d - one
    var t = 0
    while k.limbs[0] & 1 == 0 {
        k = k >> 1
        t += 1
    }
    for attempt in UInt32(2)...UInt32(100) {
        let g = BigUInt(limbs: [attempt])
        var x = g.modPow(k, n)
        for _ in 0..<t {
            let y = (x * x) % n
            if y == one && x != one && x != n - one {
                let p = gcd(x - one, n)
                let q = n / p
                return p < q ? (p, q) : (q, p)
            }
            x = y
        }
    }
    preconditionFailure("Failed to factor n")
}

private func gcd(_ a: BigUInt, _ b: BigUInt) -> BigUInt {
    var x = a, y = b
    while !y.isZero {
        let t = y
        y = x % y
        x = t
    }
    return x
}

private func buildPKCS1PrivateKeyDER(n: Data, e: Data, d: Data, p: Data, q: Data, dp: Data, dq: Data, qinv: Data) -> Data {
    func derLen(_ length: Int) -> Data {
        if length < 0x80 { return Data([UInt8(length)]) }
        if length < 0x100 { return Data([0x81, UInt8(length)]) }
        if length < 0x10000 { return Data([0x82, UInt8(length >> 8), UInt8(length & 0xff)]) }
        return Data([0x83, UInt8(length >> 16), UInt8((length >> 8) & 0xff), UInt8(length & 0xff)])
    }
    func derInt(_ value: Data) -> Data {
        var bytes = value
        while bytes.count > 1 && bytes[bytes.startIndex] == 0 { bytes = bytes.dropFirst() }
        if bytes[bytes.startIndex] & 0x80 != 0 { bytes = Data([0x00]) + bytes }
        return Data([0x02]) + derLen(bytes.count) + bytes
    }

    let inner = derInt(Data([0x00])) + derInt(n) + derInt(e) + derInt(d) + derInt(p) + derInt(q) + derInt(dp) + derInt(dq) + derInt(qinv)
    return Data([0x30]) + derLen(inner.count) + inner
}

func encodeProtocolComplete(_ transactionId: Int64, _ nonce: String) -> Data {
    let share = encodeProtocolShare(transactionId, nonce)
    let applicationSignature = peripheralRsaSignature(share)
    let firmwareSignature = applicationSignature.prefix(16)
    return concatBytes(
        bytesField(1, share),
        bytesField(2, applicationSignature),
        bytesField(3, Data(firmwareSignature))
    )
}

// MARK: - Application ID

private let UUID_V5_NAMESPACE = hexToBytes("6ba7b8109dad11d180b400c04fd430c8")

private func formatUuid(_ bytes: Data) -> String {
    let hex = bytesToHex(bytes.prefix(16))
    return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
}

func generateApplicationId() -> String {
    var name = Data()
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<16 {
        name.append(UInt8.random(in: 0...255, using: &rng))
    }
    let hash = Data(Insecure.SHA1.hash(data: UUID_V5_NAMESPACE + name))
    var bytes = [UInt8](hash)
    bytes[6] = (bytes[6] & 0x0f) | 0x50
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return formatUuid(Data(bytes)) + Constants.applicationIdSuffix
}

func applicationIdGattValue(_ applicationId: String) -> Data {
    guard applicationId.hasSuffix(Constants.applicationIdSuffix) else {
        preconditionFailure(ProtocolError.applicationIdSuffixMismatch.localizedDescription)
    }
    let encoded = Data(applicationId.utf8)
    guard encoded.count <= Constants.applicationIdGattWidth else {
        preconditionFailure(ProtocolError.applicationIdTooLong.localizedDescription)
    }
    var result = Data(repeating: 0, count: Constants.applicationIdGattWidth)
    result.replaceSubrange(0..<encoded.count, with: encoded)
    return result
}

// MARK: - Player name / nonce

func decodePlayerName(_ value: Data) throws -> String {
    guard value.count >= 4, value.count <= 15 else { throw ProtocolError.nameOutOfRange }
    return String(decoding: value, as: UTF8.self)
}

func initialNonceGattValue(_ nonce: String) -> Data {
    let encoded = Data(nonce.utf8)
    guard !encoded.contains(0) else {
        preconditionFailure(ProtocolError.nonceContainsNul.localizedDescription)
    }
    return concatBytes(encoded, Data([0]))
}

func finalNonceGattValue(_ nonce: String) -> Data {
    let encoded = Data(nonce.utf8)
    guard !encoded.contains(0) else {
        preconditionFailure(ProtocolError.nonceContainsNul.localizedDescription)
    }
    return encoded
}

func peripheralNonceFromTick(_ input: UInt64) -> String {
    var tick = input
    var value: UInt64 = 0xcbf29ce484222645
    for _ in 0..<8 {
        let octet = tick & 0xff
        tick >>= 8
        value = value ^ octet
        value = value &* 0x100000001b3
    }
    return String(value, radix: 16)
}

func randomPeripheralNonce() -> String {
    var rng = SystemRandomNumberGenerator()
    let tick = UInt64.random(in: .min ... .max, using: &rng)
    return peripheralNonceFromTick(tick)
}

// MARK: - Validation

func validateSend(_ message: ProtocolBleSend, expectedApplicationId: String, expectedNonce: String) throws {
    guard message.serverResponse.applicationId == expectedApplicationId else {
        throw ProtocolError.applicationIdMismatch
    }
    guard message.serverResponse.nonce == expectedNonce else {
        throw ProtocolError.nonceMismatch
    }
}

func validateFinalize(_ message: ProtocolBleFinalize, expectedApplicationId: String, expectedNonce: String) throws {
    guard message.applicationId == expectedApplicationId else {
        throw ProtocolError.applicationIdMismatch
    }
    guard message.nonce == expectedNonce else {
        throw ProtocolError.nonceMismatch
    }
}

// MARK: - Minimal unsigned big integer (enough for RSA-2048)

struct BigUInt: Equatable, Comparable {
    // Little-endian 32-bit limbs, no trailing zero limbs. Zero == [].
    fileprivate var limbs: [UInt32]

    init() { limbs = [] }

    init(limbs: [UInt32]) {
        self.limbs = BigUInt.normalize(limbs)
    }

    init(data: Data) {
        // data is big-endian magnitude
        var words: [UInt32] = []
        var idx = data.count
        while idx > 0 {
            let lo = max(0, idx - 4)
            let chunk = data[lo..<idx]
            var w: UInt32 = 0
            for byte in chunk { w = (w << 8) | UInt32(byte) }
            words.append(w)
            idx = lo
        }
        self.init(limbs: words)
    }

    init(hex: String) {
        var hex = hex
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") { hex.removeFirst(2) }
        if hex.count % 2 != 0 { hex = "0" + hex }
        var bytes = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(data: bytes)
    }

    static func normalize(_ words: [UInt32]) -> [UInt32] {
        var words = words
        while let last = words.last, last == 0 { words.removeLast() }
        return words
    }

    var isZero: Bool { limbs.isEmpty }

    func serialize() -> Data {
        var out = Data()
        for limb in limbs.reversed() {
            out.append(UInt8((limb >> 24) & 0xff))
            out.append(UInt8((limb >> 16) & 0xff))
            out.append(UInt8((limb >> 8) & 0xff))
            out.append(UInt8(limb & 0xff))
        }
        while out.first == 0 { out.removeFirst() }
        return out
    }

    static func < (lhs: BigUInt, rhs: BigUInt) -> Bool {
        if lhs.limbs.count != rhs.limbs.count { return lhs.limbs.count < rhs.limbs.count }
        for i in stride(from: lhs.limbs.count - 1, through: 0, by: -1) {
            if lhs.limbs[i] != rhs.limbs[i] { return lhs.limbs[i] < rhs.limbs[i] }
        }
        return false
    }

    static func + (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        let n = max(lhs.limbs.count, rhs.limbs.count)
        var out = [UInt32](repeating: 0, count: n + 1)
        var carry: UInt64 = 0
        for i in 0..<n {
            let a = i < lhs.limbs.count ? UInt64(lhs.limbs[i]) : 0
            let b = i < rhs.limbs.count ? UInt64(rhs.limbs[i]) : 0
            let s = a + b + carry
            out[i] = UInt32(s & 0xffff_ffff)
            carry = s >> 32
        }
        out[n] = UInt32(carry)
        return BigUInt(limbs: out)
    }

    static func - (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        precondition(lhs >= rhs, "subtraction underflow")
        var out = lhs.limbs
        var borrow: UInt64 = 0
        for i in 0..<out.count {
            let a = UInt64(out[i])
            let b = i < rhs.limbs.count ? UInt64(rhs.limbs[i]) : 0
            var d = Int64(a) - Int64(b) - Int64(borrow)
            if d < 0 {
                d += (1 << 32)
                borrow = 1
            } else {
                borrow = 0
            }
            out[i] = UInt32(d)
        }
        return BigUInt(limbs: out)
    }

    static func * (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        if lhs.isZero || rhs.isZero { return BigUInt() }
        var out = [UInt64](repeating: 0, count: lhs.limbs.count + rhs.limbs.count)
        for i in 0..<lhs.limbs.count {
            let a = UInt64(lhs.limbs[i])
            var carry: UInt64 = 0
            for j in 0..<rhs.limbs.count {
                let cur = out[i + j] + a * UInt64(rhs.limbs[j]) + carry
                out[i + j] = cur & 0xffff_ffff
                carry = cur >> 32
            }
            out[i + rhs.limbs.count] += carry
        }
        return BigUInt(limbs: out.map { UInt32($0) })
    }

    static func << (lhs: BigUInt, _ bits: Int) -> BigUInt {
        let limbShift = bits / 32
        let bitShift = bits % 32
        var out = [UInt32](repeating: 0, count: limbShift)
        var carry: UInt32 = 0
        for limb in lhs.limbs {
            let v = (UInt64(limb) << UInt64(bitShift)) | UInt64(carry)
            out.append(UInt32(v & 0xffff_ffff))
            carry = UInt32(v >> 32)
        }
        if carry != 0 { out.append(carry) }
        return BigUInt(limbs: out)
    }

    static func >> (lhs: BigUInt, _ bits: Int) -> BigUInt {
        let limbShift = bits / 32
        let bitShift = bits % 32
        if limbShift >= lhs.limbs.count { return BigUInt() }
        let newCount = lhs.limbs.count - limbShift
        var out = [UInt32](repeating: 0, count: newCount)
        for i in 0..<newCount {
            let lo = lhs.limbs[i + limbShift] >> UInt32(bitShift)
            let hiIdx = i + limbShift + 1
            let hi = hiIdx < lhs.limbs.count ? (lhs.limbs[hiIdx] << UInt32(32 - bitShift)) : 0
            out[i] = lo | hi
        }
        return BigUInt(limbs: out)
    }

    func quotientAndRemainder(dividingBy divisor: BigUInt) -> (quotient: BigUInt, remainder: BigUInt) {
        precondition(!divisor.isZero, "division by zero")
        if self < divisor { return (BigUInt(), self) }
        if divisor.limbs.count == 1 {
            let d = UInt64(divisor.limbs[0])
            var rem: UInt64 = 0
            var q = [UInt32](repeating: 0, count: self.limbs.count)
            for i in stride(from: self.limbs.count - 1, through: 0, by: -1) {
                let cur = (rem << 32) | UInt64(self.limbs[i])
                q[i] = UInt32(cur / d)
                rem = cur % d
            }
            return (BigUInt(limbs: q), BigUInt(limbs: [UInt32(rem)]))
        }
        return knuthDivmod(self.limbs, divisor.limbs)
    }

    private func knuthDivmod(_ uIn: [UInt32], _ vIn: [UInt32]) -> (quotient: BigUInt, remainder: BigUInt) {
        let n = uIn.count
        let m = vIn.count

        // D1: normalize so divisor's top limb has its high bit set.
        let shift = vIn[m - 1].leadingZeroBitCount
        let vn = Array((BigUInt(limbs: vIn) << shift).limbs)
        var un = (BigUInt(limbs: uIn) << shift).limbs
        while un.count <= n { un.append(0) }

        var q = [UInt32](repeating: 0, count: n - m + 1)
        let b: UInt64 = 1 << 32
        let vTop = UInt64(vn[m - 1])
        let vSecond = UInt64(vn[m - 2])

        for j in stride(from: n - m, through: 0, by: -1) {
            // D3: estimate quotient digit.
            let uTop = (UInt64(un[j + m]) << 32) | UInt64(un[j + m - 1])
            var qhat = uTop / vTop
            var rhat = uTop % vTop
            let u2 = UInt64(un[j + m - 2])
            while true {
                if qhat >= b || qhat * vSecond > b * rhat + u2 {
                    qhat -= 1
                    rhat += vTop
                    if rhat < b { continue }
                }
                break
            }

            // D4: multiply-subtract un[j...j+m] -= qhat * vn.
            var carry: UInt64 = 0
            var borrow: UInt64 = 0
            for i in 0..<m {
                let p = qhat * UInt64(vn[i]) + carry
                carry = p >> 32
                let plow = p & 0xffff_ffff
                let a = UInt64(un[j + i])
                if a < plow + borrow {
                    un[j + i] = UInt32(a &+ (1 << 32) &- plow &- borrow)
                    borrow = 1
                } else {
                    un[j + i] = UInt32(a &- plow &- borrow)
                    borrow = 0
                }
            }
            // Subtract final carry+borrow from un[j+m].
            let top = UInt64(un[j + m])
            var finalBorrow: UInt64 = 0
            if top < carry + borrow {
                un[j + m] = UInt32(top &+ (1 << 32) &- carry &- borrow)
                finalBorrow = 1
            } else {
                un[j + m] = UInt32(top &- carry &- borrow)
            }

            // D5/D6: if qhat too big, add back.
            if finalBorrow == 1 {
                qhat -= 1
                var c: UInt64 = 0
                for i in 0..<m {
                    let s = UInt64(un[j + i]) + UInt64(vn[i]) + c
                    un[j + i] = UInt32(s & 0xffff_ffff)
                    c = s >> 32
                }
                un[j + m] = UInt32(UInt64(un[j + m]) + c)
            }

            q[j] = UInt32(qhat)
        }

        // Remainder: un[0..<m] >> shift.
        let remainder = BigUInt(limbs: Array(un[0..<m])) >> shift
        return (BigUInt(limbs: q), remainder)
    }

    func mod(_ modulus: BigUInt) -> BigUInt {
        quotientAndRemainder(dividingBy: modulus).remainder
    }

    static func / (lhs: BigUInt, rhs: BigUInt) -> BigUInt { lhs.quotientAndRemainder(dividingBy: rhs).quotient }
    static func % (lhs: BigUInt, rhs: BigUInt) -> BigUInt { lhs.mod(rhs) }

    func modInverse(_ modulus: BigUInt) -> BigUInt {
        var (old_r, r) = (self % modulus, modulus)
        var (old_s, s) = (BigUInt(limbs: [1]), BigUInt(limbs: [0]))
        var old_s_neg = false
        var s_neg = false
        while !r.isZero {
            let q = old_r / r
            let temp_r = r
            r = old_r - q * r
            old_r = temp_r
            let temp_s = s
            let temp_s_neg = s_neg
            let qs = q * s
            if old_s_neg == s_neg {
                if old_s >= qs {
                    s = old_s - qs
                    s_neg = old_s_neg
                } else {
                    s = qs - old_s
                    s_neg = !old_s_neg
                }
            } else {
                s = old_s + qs
                s_neg = old_s_neg
            }
            old_s = temp_s
            old_s_neg = temp_s_neg
        }
        if old_s_neg {
            return modulus - (old_s % modulus)
        }
        return old_s % modulus
    }

    func modPow(_ exponent: BigUInt, _ modulus: BigUInt) -> BigUInt {
        precondition(!modulus.isZero, "modPow modulus must be positive")
        var result = BigUInt(limbs: [1])
        var base = self % modulus
        for limb in exponent.limbs {
            var bits = limb
            for _ in 0..<32 {
                if bits & 1 == 1 {
                    result = (result * base) % modulus
                }
                bits >>= 1
                base = (base * base) % modulus
            }
        }
        return result
    }
}
