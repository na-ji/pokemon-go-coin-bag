package io.github.naji.pokemongo.coin.bag

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import java.math.BigInteger

class ProtocolPrimitivesTest {

    @Test
    fun `hexToBytes and bytesToHex round trip`() {
        val bytes = hexToBytes("0a1b2c")
        assertArrayEquals(byteArrayOf(0x0a, 0x1b, 0x2c), bytes)
        assertEquals("0a1b2c", bytesToHex(bytes))
    }

    @Test
    fun `hexToBytes rejects odd length`() {
        try {
            hexToBytes("abc")
            error("expected exception")
        } catch (expected: IllegalArgumentException) {
            // expected
        }
    }

    @Test
    fun `concatBytes joins parts in order`() {
        val result = concatBytes(byteArrayOf(1, 2), byteArrayOf(), byteArrayOf(3))
        assertArrayEquals(byteArrayOf(1, 2, 3), result)
    }

    @Test
    fun `bigIntToBytes right-aligns into fixed width`() {
        val result = bigIntToBytes(BigInteger.valueOf(255), 4)
        assertArrayEquals(byteArrayOf(0, 0, 0, 0xff.toByte()), result)
    }

    @Test
    fun `bytesToBigInt of empty array is zero`() {
        assertEquals(BigInteger.ZERO, bytesToBigInt(ByteArray(0)))
    }

    @Test
    fun `encodeVarint matches known vectors from protocol js`() {
        assertEquals("00", bytesToHex(encodeVarint(0L)))
        assertEquals("7f", bytesToHex(encodeVarint(127L)))
        assertEquals("8001", bytesToHex(encodeVarint(128L)))
        assertEquals("ac02", bytesToHex(encodeVarint(300L)))
    }

    @Test
    fun `decodeVarint matches known vector from protocol js`() {
        val result = decodeVarint(hexToBytes("ac02"))
        assertEquals(300L, result.value)
        assertEquals(2, result.offset)
    }

    @Test
    fun `decodeVarint throws on truncated input`() {
        try {
            decodeVarint(hexToBytes("80"))
            error("expected exception")
        } catch (expected: IllegalArgumentException) {
            // expected
        }
    }
}
