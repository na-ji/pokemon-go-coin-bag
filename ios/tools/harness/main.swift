import Foundation

var failures = 0

func check(_ name: String, _ cond: Bool) {
    print((cond ? "PASS" : "FAIL") + " — " + name)
    if !cond { failures += 1 }
}

func eq<T: Equatable>(_ name: String, _ got: T, _ want: T) {
    let ok = got == want
    print((ok ? "PASS" : "FAIL") + " — " + name)
    if !ok {
        failures += 1
        print("   got:  \(got)")
        print("   want: \(want)")
    }
}

// 1. hex round trip
eq("hexToBytes round trip", bytesToHex(hexToBytes("0a1b2c")), "0a1b2c")

// 2. varint encode vectors
eq("varint 0", bytesToHex(encodeVarint(0)), "00")
eq("varint 127", bytesToHex(encodeVarint(127)), "7f")
eq("varint 128", bytesToHex(encodeVarint(128)), "8001")
eq("varint 300", bytesToHex(encodeVarint(300)), "ac02")

// 3. varint decode vector
do {
    let r = try decodeVarint(hexToBytes("ac02"))
    eq("decodeVarint 300", r.value, Int64(300))
    eq("decodeVarint offset", r.offset, 2)
} catch { eq("decodeVarint 300 threw", false, true); print(error) }

// 4. truncated varint throws
do {
    _ = try decodeVarint(hexToBytes("80"))
    eq("decodeVarint truncated throws", false, true)
} catch { eq("decodeVarint truncated throws", true, true) }

// 5. encodeProtocolShare golden
eq("encodeProtocolShare", bytesToHex(encodeProtocolShare(42, "test-nonce-1")), "082a120c746573742d6e6f6e63652d31")

// 6. decodeProtocolBleSend golden
do {
    let raw = hexToBytes("0a380807102a1a2a30663165326433632d346235612d343937382d383839392d6161626263636464656566662b746974616e220661626331323312080102030405060708")
    let m = try decodeProtocolBleSend(raw)
    eq("send.data", m.serverResponse.data, 7)
    eq("send.transactionId", m.serverResponse.transactionId, 42)
    eq("send.applicationId", m.serverResponse.applicationId, "0f1e2d3c-4b5a-4978-8899-aabbccddeeff+titan")
    eq("send.nonce", m.serverResponse.nonce, "abc123")
    eq("send.signature", bytesToHex(m.serverSignature), "0102030405060708")
} catch { eq("decodeProtocolBleSend threw", false, true); print(error) }

// 7. decodeProtocolBleFinalize golden
do {
    let raw = hexToBytes("0a340a06616263313233122a30663165326433632d346235612d343937382d383839392d6161626263636464656566662b746974616e12080102030405060708")
    let m = try decodeProtocolBleFinalize(raw)
    eq("finalize.nonce", m.nonce, "abc123")
    eq("finalize.applicationId", m.applicationId, "0f1e2d3c-4b5a-4978-8899-aabbccddeeff+titan")
    eq("finalize.signature", bytesToHex(m.serverSignature), "0102030405060708")
} catch { eq("decodeProtocolBleFinalize threw", false, true); print(error) }

// 8. RSA signature golden vector
let share = encodeProtocolShare(42, "test-nonce-1")
let sig = peripheralRsaSignature(share)
let wantSig = "02e37d0f0082b26982760a94e64ab86aa9abd4479fddf61fed40fb53aba12b0" +
    "43e36c783c651fd08d5cac906a4ccba18708cfc63885b865d0927de318a1bca" +
    "0a1cee2a6eb6efac5f2d0ad7680cc298d94f126f83521e9c2579b3f7ccec14f" +
    "0e8c09009e25a5b1c7a2ce4d173496423d522767b4be082e1edad67f93b534e" +
    "7e813b890bcffd5861d307faf94e015dcb56e01e71523dfed54f9763161bfcf" +
    "505299f9901f1ebccfc1e07a40efcd6f30e1b08ed1a3b3af83afc94c2f5f2ea" +
    "52d9d0b8655f3615f92ddb7de5742ebda62267c7f96a020647e984f55bc3a7e" +
    "957dc16ea1d5f0e246637479ad2d9a3f08e6880aefe8e5eadc952528d03dbb1e4de5145"
eq("peripheralRsaSignature golden", bytesToHex(sig), wantSig)

// 9. encodeProtocolComplete golden
let complete = encodeProtocolComplete(42, "test-nonce-1")
let wantComplete = "0a10082a120c746573742d6e6f6e63652d3112800202e37d0f0082b26982760a94e64ab86aa9abd4479fddf61fed40fb53aba12b043e36c783c651fd08d5cac906a4ccba18708cfc63885b865d0927de318a1bca0a1cee2a6eb6efac5f2d0ad7680cc298d94f126f83521e9c2579b3f7ccec14f0e8c09009e25a5b1c7a2ce4d173496423d522767b4be082e1edad67f93b534e7e813b890bcffd5861d307faf94e015dcb56e01e71523dfed54f9763161bfcf505299f9901f1ebccfc1e07a40efcd6f30e1b08ed1a3b3af83afc94c2f5f2ea52d9d0b8655f3615f92ddb7de5742ebda62267c7f96a020647e984f55bc3a7e957dc16ea1d5f0e246637479ad2d9a3f08e6880aefe8e5eadc952528d03dbb1e4de51451a1002e37d0f0082b26982760a94e64ab86a"
eq("encodeProtocolComplete golden", bytesToHex(complete), wantComplete)

// 10. nonce tick golden vectors
eq("tick 0", peripheralNonceFromTick(0), "7875f47453e1e0e5")
eq("tick 1", peripheralNonceFromTick(1), "597b2d6b48f296c4")
eq("tick -1", peripheralNonceFromTick(UInt64.max), "1b31785ecb98995d")

// 11. nonce gatt values
eq("initialNonce", bytesToHex(initialNonceGattValue("abc123")), "61626331323300")
eq("finalNonce", bytesToHex(finalNonceGattValue("abc123")), "616263313233")

// 12. applicationId gatt value
let appId = "0f1e2d3c-4b5a-4978-8899-aabbccddeeff+titan"
let gatt = applicationIdGattValue(appId)
eq("appId gatt length", gatt.count, 69)
eq("appId gatt hex", bytesToHex(gatt),
   "30663165326433632d346235612d343937382d383839392d6161626263636464656566662b746974616e" +
   "000000000000000000000000000000000000000000000000000000")

// 13. player name
do {
    eq("decodePlayerName", try decodePlayerName("AshK".data(using: .utf8)!), "AshK")
    do {
        _ = try decodePlayerName("Ash".data(using: .utf8)!)
        eq("decodePlayerName too short throws", false, true)
    } catch { eq("decodePlayerName too short throws", true, true) }
} catch { eq("decodePlayerName threw", false, true); print(error) }

// 14. random nonce format
let nonce = randomPeripheralNonce()
check("random nonce 1-16 hex", nonce.count >= 1 && nonce.count <= 16 && nonce.allSatisfy { $0.isHexDigit })

// 15. BigUInt division randomized
var rng = SystemRandomNumberGenerator()
for i in 0..<2000 {
    let aBytes = (0..<Int.random(in: 1...40, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
    let bBytes = (0..<Int.random(in: 1...20, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
    var a = BigUInt(data: Data(aBytes))
    var b = BigUInt(data: Data(bBytes))
    if b.isZero { b = BigUInt(limbs: [1]) }
    let (q, r) = a.quotientAndRemainder(dividingBy: b)
    let checkVal = q * b + r
    if checkVal != a || r >= b {
        print("FAIL — division at iteration \(i)")
        failures += 1
        break
    }
}
if failures == 0 { print("PASS — 2000 randomized divisions") }

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
