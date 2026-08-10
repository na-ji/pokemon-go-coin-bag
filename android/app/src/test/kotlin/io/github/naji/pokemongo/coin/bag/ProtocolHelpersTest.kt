package io.github.naji.pokemongo.coin.bag

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ProtocolHelpersTest {

    @Test
    fun `applicationIdFromUuid and applicationIdGattValue match golden vectors from protocol js`() {
        val uuid = "0f1e2d3c-4b5a-4978-8899-aabbccddeeff"
        val applicationId = applicationIdFromUuid(uuid)
        assertEquals("0f1e2d3c-4b5a-4978-8899-aabbccddeeff+titan", applicationId)

        val gattValue = applicationIdGattValue(applicationId)
        assertEquals(69, gattValue.size)
        assertEquals(
            "30663165326433632d346235612d343937382d383839392d6161626263636464656566662b746974616e" +
                "000000000000000000000000000000000000000000000000000000",
            bytesToHex(gattValue),
        )
    }

    @Test
    fun `applicationIdGattValue rejects non-canonical uuid`() {
        try {
            applicationIdGattValue("not-a-uuid+titan")
            error("expected exception")
        } catch (expected: IllegalArgumentException) {
            // expected
        }
    }

    @Test
    fun `decodePlayerName enforces 4 to 15 byte range`() {
        assertEquals("AshK", decodePlayerName("AshK".toByteArray(Charsets.UTF_8)))
        try {
            decodePlayerName("Ash".toByteArray(Charsets.UTF_8))
            error("expected exception")
        } catch (expected: IllegalArgumentException) {
            // expected
        }
    }

    @Test
    fun `nonce gatt values match golden vectors from protocol js`() {
        assertEquals("61626331323300", bytesToHex(initialNonceGattValue("abc123")))
        assertEquals("616263313233", bytesToHex(finalNonceGattValue("abc123")))
    }

    @Test
    fun `peripheralNonceFromTick matches golden vectors from protocol js`() {
        assertEquals("7875f47453e1e0e5", peripheralNonceFromTick(0L))
        assertEquals("597b2d6b48f296c4", peripheralNonceFromTick(1L))
        assertEquals("1b31785ecb98995d", peripheralNonceFromTick(-1L)) // -1L == 0xffffffffffffffff unsigned
    }

    @Test
    fun `randomPeripheralNonce produces a 16-hex-char string`() {
        val nonce = randomPeripheralNonce()
        assertTrue(nonce.matches(Regex("^[0-9a-f]{1,16}$")))
    }

    @Test
    fun `validateSend passes on matching values and throws on mismatch`() {
        val message = ProtocolBleSend(
            serverResponse = ServerResponse(0, 1, "app-id", "nonce"),
            serverSignature = ByteArray(0),
        )
        validateSend(message, "app-id", "nonce")
        try {
            validateSend(message, "other-id", "nonce")
            error("expected exception")
        } catch (expected: IllegalArgumentException) {
            // expected
        }
    }

    @Test
    fun `validateFinalize passes on matching values and throws on mismatch`() {
        val message = ProtocolBleFinalize("nonce", "app-id", ByteArray(0))
        validateFinalize(message, "app-id", "nonce")
        try {
            validateFinalize(message, "app-id", "other-nonce")
            error("expected exception")
        } catch (expected: IllegalArgumentException) {
            // expected
        }
    }
}
