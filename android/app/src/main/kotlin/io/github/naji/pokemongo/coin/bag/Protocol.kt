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

sealed class ProtoField {
    data class Varint(val value: Long) : ProtoField()
    data class Bytes(val value: ByteArray) : ProtoField()
}

internal fun bytesField(number: Int, value: ByteArray): ByteArray =
    concatBytes(
        encodeVarint(((number shl 3) or 2).toLong()),
        encodeVarint(value.size.toLong()),
        value,
    )

internal fun stringField(number: Int, value: String): ByteArray =
    bytesField(number, value.toByteArray(Charsets.UTF_8))

internal fun varintField(number: Int, value: Long): ByteArray =
    concatBytes(encodeVarint((number shl 3).toLong()), encodeVarint(value))

fun parseFields(data: ByteArray): Map<Int, ProtoField> {
    val fields = mutableMapOf<Int, ProtoField>()
    var offset = 0
    while (offset < data.size) {
        val tagResult = decodeVarint(data, offset)
        val tag = tagResult.value
        offset = tagResult.offset
        val number = (tag ushr 3).toInt()
        val wireType = (tag and 7).toInt()
        require(number != 0) { "Protobuf field number zero" }

        when (wireType) {
            0 -> {
                val result = decodeVarint(data, offset)
                fields[number] = ProtoField.Varint(result.value)
                offset = result.offset
            }
            2 -> {
                val lengthResult = decodeVarint(data, offset)
                val length = lengthResult.value
                offset = lengthResult.offset
                require(length in 0..Int.MAX_VALUE.toLong()) { "Truncated protobuf length-delimited field" }
                val end = offset + length.toInt()
                require(end <= data.size) { "Truncated protobuf length-delimited field" }
                fields[number] = ProtoField.Bytes(data.copyOfRange(offset, end))
                offset = end
            }
            else -> throw IllegalArgumentException("Unsupported protobuf wire type $wireType")
        }
    }
    return fields
}

fun requireBytes(fields: Map<Int, ProtoField>, number: Int): ByteArray {
    val field = fields[number] ?: throw IllegalArgumentException("Missing protobuf field $number")
    return (field as? ProtoField.Bytes)?.value
        ?: throw IllegalArgumentException("Protobuf field $number is not length-delimited")
}

fun requireVarint(fields: Map<Int, ProtoField>, number: Int): Long {
    val field = fields[number] ?: throw IllegalArgumentException("Missing protobuf field $number")
    return (field as? ProtoField.Varint)?.value
        ?: throw IllegalArgumentException("Protobuf field $number is not a varint")
}

data class ServerResponse(
    val data: Long,
    val transactionId: Long,
    val applicationId: String,
    val nonce: String,
)

data class ProtocolBleSend(
    val serverResponse: ServerResponse,
    val serverSignature: ByteArray,
)

fun decodeProtocolBleSend(data: ByteArray): ProtocolBleSend {
    val outer = parseFields(data)
    val prep = parseFields(requireBytes(outer, 1))
    return ProtocolBleSend(
        serverResponse = ServerResponse(
            data = requireVarint(prep, 1),
            transactionId = requireVarint(prep, 2),
            applicationId = String(requireBytes(prep, 3), Charsets.UTF_8),
            nonce = String(requireBytes(prep, 4), Charsets.UTF_8),
        ),
        serverSignature = requireBytes(outer, 2),
    )
}

data class ProtocolBleFinalize(
    val nonce: String,
    val applicationId: String,
    val serverSignature: ByteArray,
)

fun decodeProtocolBleFinalize(data: ByteArray): ProtocolBleFinalize {
    val outer = parseFields(data)
    val complete = parseFields(requireBytes(outer, 1))
    return ProtocolBleFinalize(
        nonce = String(requireBytes(complete, 1), Charsets.UTF_8),
        applicationId = String(requireBytes(complete, 2), Charsets.UTF_8),
        serverSignature = requireBytes(outer, 2),
    )
}

fun encodeProtocolShare(transactionId: Long, nonce: String): ByteArray =
    concatBytes(varintField(1, transactionId), stringField(2, nonce))
