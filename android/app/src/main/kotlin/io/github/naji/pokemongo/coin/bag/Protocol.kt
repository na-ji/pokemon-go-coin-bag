package io.github.naji.pokemongo.coin.bag

import java.math.BigInteger

fun concatBytes(vararg parts: ByteArray): ByteArray {
    val result = ByteArray(parts.sumOf { it.size })
    var offset = 0
    for (part in parts) {
        System.arraycopy(part, 0, result, offset, part.size)
        offset += part.size
    }
    return result
}

private val HEX_REGEX = Regex("^[0-9a-fA-F]*$")

fun hexToBytes(hex: String): ByteArray {
    require(hex.length % 2 == 0 && HEX_REGEX.matches(hex)) { "Invalid hexadecimal string" }
    val result = ByteArray(hex.length / 2)
    for (index in result.indices) {
        result[index] = hex.substring(index * 2, index * 2 + 2).toInt(16).toByte()
    }
    return result
}

fun bytesToHex(bytes: ByteArray): String =
    bytes.joinToString("") { "%02x".format(it) }

fun bytesToBigInt(bytes: ByteArray): BigInteger =
    if (bytes.isEmpty()) BigInteger.ZERO else BigInteger(1, bytes)

fun bigIntToBytes(value: BigInteger, width: Int): ByteArray {
    require(value.signum() >= 0) { "Cannot encode a negative integer as unsigned bytes" }
    val magnitude = value.toByteArray()
    val raw = if (magnitude.size > 1 && magnitude[0] == 0.toByte()) {
        magnitude.copyOfRange(1, magnitude.size)
    } else {
        magnitude
    }
    require(raw.size <= width) { "Integer does not fit in $width bytes" }
    val result = ByteArray(width)
    System.arraycopy(raw, 0, result, width - raw.size, raw.size)
    return result
}

fun encodeVarint(inputValue: Long): ByteArray {
    var value = inputValue
    val bytes = mutableListOf<Byte>()
    while (true) {
        val septet = (value and 0x7fL).toInt()
        value = value ushr 7
        if (value != 0L) {
            bytes.add((septet or 0x80).toByte())
        } else {
            bytes.add(septet.toByte())
            break
        }
    }
    return bytes.toByteArray()
}

data class VarintResult(val value: Long, val offset: Int)

fun decodeVarint(data: ByteArray, initialOffset: Int = 0): VarintResult {
    var value = 0L
    var shift = 0
    var offset = initialOffset
    while (offset < data.size && shift < 70) {
        val octet = data[offset].toInt() and 0xff
        offset += 1
        value = value or ((octet.toLong() and 0x7f) shl shift)
        if (octet and 0x80 == 0) return VarintResult(value, offset)
        shift += 7
    }
    throw IllegalArgumentException("Invalid or truncated protobuf varint")
}
