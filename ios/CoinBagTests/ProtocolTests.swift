import XCTest
@testable import CoinBag

final class ProtocolPrimitivesTest: XCTestCase {
    func testHexToBytesAndBytesToHexRoundTrip() {
        XCTAssertEqual(bytesToHex(hexToBytes("0a1b2c")), "0a1b2c")
    }

    func testConcatBytesJoinsPartsInOrder() {
        let result = concatBytes(Data([1, 2]), Data(), Data([3]))
        XCTAssertEqual(bytesToHex(result), "010203")
    }

    func testEncodeVarintMatchesKnownVectors() {
        XCTAssertEqual(bytesToHex(encodeVarint(0)), "00")
        XCTAssertEqual(bytesToHex(encodeVarint(127)), "7f")
        XCTAssertEqual(bytesToHex(encodeVarint(128)), "8001")
        XCTAssertEqual(bytesToHex(encodeVarint(300)), "ac02")
    }

    func testDecodeVarintMatchesKnownVector() throws {
        let result = try decodeVarint(hexToBytes("ac02"))
        XCTAssertEqual(result.value, 300)
        XCTAssertEqual(result.offset, 2)
    }

    func testDecodeVarintThrowsOnTruncatedInput() {
        XCTAssertThrowsError(try decodeVarint(hexToBytes("80")))
    }

    func testParseFieldsRejectsFieldNumberZero() {
        XCTAssertThrowsError(try parseFields(Data([0x00])))
    }
}

final class ProtocolCryptoTest: XCTestCase {
    func testConstantsDecodeSameUUIDsAndSuffix() {
        XCTAssertEqual(Constants.uuids["advertisementService"], "b6c3089a-7e4f-487d-b9f8-73a281dd718f")
        XCTAssertEqual(Constants.uuids["gattService"], "abfaf4c7-5a44-445a-a007-ad19fcb29e99")
        XCTAssertEqual(Constants.applicationIdSuffix, "+titan")
        XCTAssertEqual(Constants.applicationIdGattWidth, 69)
    }

    func testPeripheralRsaSignatureMatchesGoldenVector() {
        let share = encodeProtocolShare(42, "test-nonce-1")
        let signature = peripheralRsaSignature(share)
        let expected = "02e37d0f0082b26982760a94e64ab86aa9abd4479fddf61fed40fb53aba12b0" +
            "43e36c783c651fd08d5cac906a4ccba18708cfc63885b865d0927de318a1bca" +
            "0a1cee2a6eb6efac5f2d0ad7680cc298d94f126f83521e9c2579b3f7ccec14f" +
            "0e8c09009e25a5b1c7a2ce4d173496423d522767b4be082e1edad67f93b534e" +
            "7e813b890bcffd5861d307faf94e015dcb56e01e71523dfed54f9763161bfcf" +
            "505299f9901f1ebccfc1e07a40efcd6f30e1b08ed1a3b3af83afc94c2f5f2ea" +
            "52d9d0b8655f3615f92ddb7de5742ebda62267c7f96a020647e984f55bc3a7e" +
            "957dc16ea1d5f0e246637479ad2d9a3f08e6880aefe8e5eadc952528d03dbb1e4de5145"
        XCTAssertEqual(bytesToHex(signature), expected)
    }

    func testEncodeProtocolCompleteMatchesGoldenVector() {
        let complete = encodeProtocolComplete(42, "test-nonce-1")
        let expected = "0a10082a120c746573742d6e6f6e63652d3112800202e37d0f0082b26982760a94e64ab86aa9abd4479fddf61fed40fb53aba12b043e36c783c651fd08d5cac906a4ccba18708cfc63885b865d0927de318a1bca0a1cee2a6eb6efac5f2d0ad7680cc298d94f126f83521e9c2579b3f7ccec14f0e8c09009e25a5b1c7a2ce4d173496423d522767b4be082e1edad67f93b534e7e813b890bcffd5861d307faf94e015dcb56e01e71523dfed54f9763161bfcf505299f9901f1ebccfc1e07a40efcd6f30e1b08ed1a3b3af83afc94c2f5f2ea52d9d0b8655f3615f92ddb7de5742ebda62267c7f96a020647e984f55bc3a7e957dc16ea1d5f0e246637479ad2d9a3f08e6880aefe8e5eadc952528d03dbb1e4de51451a1002e37d0f0082b26982760a94e64ab86a"
        XCTAssertEqual(bytesToHex(complete), expected)
    }
}

final class ProtocolMessagesTest: XCTestCase {
    private let applicationId = "0f1e2d3c-4b5a-4978-8899-aabbccddeeff+titan"
    private let nonce = "abc123"

    func testDecodeProtocolBleSendMatchesGoldenVector() throws {
        let raw = hexToBytes(
            "0a380807102a1a2a30663165326433632d346235612d343937382d383839392d" +
                "6161626263636464656566662b746974616e220661626331323312080102030405060708"
        )
        let message = try decodeProtocolBleSend(raw)
        XCTAssertEqual(message.serverResponse.data, 7)
        XCTAssertEqual(message.serverResponse.transactionId, 42)
        XCTAssertEqual(message.serverResponse.applicationId, applicationId)
        XCTAssertEqual(message.serverResponse.nonce, nonce)
        XCTAssertEqual(bytesToHex(message.serverSignature), "0102030405060708")
    }

    func testDecodeProtocolBleFinalizeMatchesGoldenVector() throws {
        let raw = hexToBytes(
            "0a340a06616263313233122a30663165326433632d346235612d343937382d" +
                "383839392d6161626263636464656566662b746974616e12080102030405060708"
        )
        let message = try decodeProtocolBleFinalize(raw)
        XCTAssertEqual(message.nonce, nonce)
        XCTAssertEqual(message.applicationId, applicationId)
        XCTAssertEqual(bytesToHex(message.serverSignature), "0102030405060708")
    }

    func testEncodeProtocolShareMatchesGoldenVector() {
        XCTAssertEqual(bytesToHex(encodeProtocolShare(42, "test-nonce-1")), "082a120c746573742d6e6f6e63652d31")
    }
}

final class ProtocolHelpersTest: XCTestCase {
    func testApplicationIdGattValueMatchesGoldenVector() {
        let appId = "0f1e2d3c-4b5a-4978-8899-aabbccddeeff+titan"
        let gattValue = applicationIdGattValue(appId)
        XCTAssertEqual(gattValue.count, 69)
        XCTAssertEqual(
            bytesToHex(gattValue),
            "30663165326433632d346235612d343937382d383839392d6161626263636464656566662b746974616e" +
                "000000000000000000000000000000000000000000000000000000"
        )
    }

    func testDecodePlayerNameEnforcesByteRange() throws {
        XCTAssertEqual(try decodePlayerName("AshK".data(using: .utf8)!), "AshK")
        XCTAssertThrowsError(try decodePlayerName("Ash".data(using: .utf8)!))
    }

    func testNonceGattValuesMatchGoldenVectors() {
        XCTAssertEqual(bytesToHex(initialNonceGattValue("abc123")), "61626331323300")
        XCTAssertEqual(bytesToHex(finalNonceGattValue("abc123")), "616263313233")
    }

    func testPeripheralNonceFromTickMatchesGoldenVectors() {
        XCTAssertEqual(peripheralNonceFromTick(0), "7875f47453e1e0e5")
        XCTAssertEqual(peripheralNonceFromTick(1), "597b2d6b48f296c4")
        XCTAssertEqual(peripheralNonceFromTick(UInt64.max), "1b31785ecb98995d")
    }

    func testRandomPeripheralNonceProducesHexString() {
        let nonce = randomPeripheralNonce()
        XCTAssertTrue(nonce.count >= 1 && nonce.count <= 16)
        XCTAssertTrue(nonce.allSatisfy { $0.isHexDigit })
    }

    func testValidateSendAndFinalize() throws {
        let send = ProtocolBleSend(
            serverResponse: ServerResponse(data: 0, transactionId: 1, applicationId: "app-id", nonce: "nonce"),
            serverSignature: Data()
        )
        XCTAssertNoThrow(try validateSend(send, expectedApplicationId: "app-id", expectedNonce: "nonce"))
        XCTAssertThrowsError(try validateSend(send, expectedApplicationId: "other-id", expectedNonce: "nonce"))

        let finalize = ProtocolBleFinalize(nonce: "nonce", applicationId: "app-id", serverSignature: Data())
        XCTAssertNoThrow(try validateFinalize(finalize, expectedApplicationId: "app-id", expectedNonce: "nonce"))
        XCTAssertThrowsError(try validateFinalize(finalize, expectedApplicationId: "app-id", expectedNonce: "other-nonce"))
    }
}
