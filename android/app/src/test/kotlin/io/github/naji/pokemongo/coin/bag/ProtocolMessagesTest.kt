package io.github.naji.pokemongo.coin.bag

import org.junit.Assert.assertEquals
import org.junit.Test

class ProtocolMessagesTest {

    private val applicationId = "0f1e2d3c-4b5a-4978-8899-aabbccddeeff+titan"
    private val nonce = "abc123"

    @Test
    fun `decodeProtocolBleSend matches golden vector from protocol js`() {
        val raw = hexToBytes(
            "0a380807102a1a2a30663165326433632d346235612d343937382d383839392d" +
                "6161626263636464656566662b746974616e220661626331323312080102030405060708"
        )
        val message = decodeProtocolBleSend(raw)
        assertEquals(7L, message.serverResponse.data)
        assertEquals(42L, message.serverResponse.transactionId)
        assertEquals(applicationId, message.serverResponse.applicationId)
        assertEquals(nonce, message.serverResponse.nonce)
        assertEquals("0102030405060708", bytesToHex(message.serverSignature))
    }

    @Test
    fun `decodeProtocolBleFinalize matches golden vector from protocol js`() {
        val raw = hexToBytes(
            "0a340a06616263313233122a30663165326433632d346235612d343937382d" +
                "383839392d6161626263636464656566662b746974616e12080102030405060708"
        )
        val message = decodeProtocolBleFinalize(raw)
        assertEquals(nonce, message.nonce)
        assertEquals(applicationId, message.applicationId)
        assertEquals("0102030405060708", bytesToHex(message.serverSignature))
    }

    @Test
    fun `encodeProtocolShare matches golden vector from protocol js`() {
        val share = encodeProtocolShare(42L, "test-nonce-1")
        assertEquals("082a120c746573742d6e6f6e63652d31", bytesToHex(share))
    }

    @Test
    fun `parseFields rejects field number zero`() {
        // tag byte 0x00 encodes field number 0, wire type 0 — invalid per protobuf spec
        try {
            parseFields(byteArrayOf(0x00))
            error("expected exception")
        } catch (expected: IllegalArgumentException) {
            // expected
        }
    }
}
