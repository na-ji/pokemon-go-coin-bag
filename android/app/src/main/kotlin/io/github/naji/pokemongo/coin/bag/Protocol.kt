package io.github.naji.pokemongo.coin.bag

import java.math.BigInteger
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Base64

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

private const val CONSTANTS_BASE64 = """
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

object Constants {
    private val json: JSONObject by lazy {
        val cleaned = CONSTANTS_BASE64.replace(Regex("\\s"), "")
        val decoded = Base64.getDecoder().decode(cleaned)
        JSONObject(String(decoded, Charsets.UTF_8))
    }

    val uuids: Map<String, String> by lazy {
        val obj = json.getJSONObject("UUIDS")
        obj.keys().asSequence().associateWith { obj.getString(it) }
    }

    val applicationIdSuffix: String by lazy { json.getString("APPLICATION_ID_SUFFIX") }
    val applicationIdGattWidth: Int by lazy { json.getInt("APPLICATION_ID_GATT_WIDTH") }

    val rsaModulus: java.math.BigInteger by lazy {
        java.math.BigInteger(json.getString("RSA_MODULUS").removePrefix("0x"), 16)
    }
    val rsaPrivateExponent: java.math.BigInteger by lazy {
        java.math.BigInteger(json.getString("RSA_PRIVATE_EXPONENT").removePrefix("0x"), 16)
    }
    val sha256DigestInfoPrefix: ByteArray by lazy {
        hexToBytes(json.getString("SHA256_DIGEST_INFO_PREFIX"))
    }
}

fun peripheralRsaSignature(message: ByteArray): ByteArray {
    val digest = MessageDigest.getInstance("SHA-256").digest(message)
    val paddingLength = 256 - 3 - Constants.sha256DigestInfoPrefix.size - digest.size
    require(paddingLength >= 8) { "Digest encoding does not fit RSA modulus" }
    val encoded = concatBytes(
        byteArrayOf(0x00, 0x01),
        ByteArray(paddingLength) { 0xff.toByte() },
        byteArrayOf(0x00),
        Constants.sha256DigestInfoPrefix,
        digest,
    )
    val signature = bytesToBigInt(encoded).modPow(Constants.rsaPrivateExponent, Constants.rsaModulus)
    return bigIntToBytes(signature, 256)
}

fun encodeProtocolComplete(transactionId: Long, nonce: String): ByteArray {
    val share = encodeProtocolShare(transactionId, nonce)
    val applicationSignature = peripheralRsaSignature(share)
    val firmwareSignature = applicationSignature.copyOfRange(0, 16)
    return concatBytes(
        bytesField(1, share),
        bytesField(2, applicationSignature),
        bytesField(3, firmwareSignature),
    )
}
