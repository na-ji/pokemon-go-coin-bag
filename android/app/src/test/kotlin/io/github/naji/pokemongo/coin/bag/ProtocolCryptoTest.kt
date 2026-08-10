package io.github.naji.pokemongo.coin.bag

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ProtocolCryptoTest {

    @Test
    fun `Constants decode the same UUIDs and suffix as protocol js`() {
        assertEquals("b6c3089a-7e4f-487d-b9f8-73a281dd718f", Constants.uuids.getValue("advertisementService"))
        assertEquals("abfaf4c7-5a44-445a-a007-ad19fcb29e99", Constants.uuids.getValue("gattService"))
        assertEquals("+titan", Constants.applicationIdSuffix)
        assertEquals(69, Constants.applicationIdGattWidth)
        assertTrue(Constants.rsaModulus.bitLength() in 2040..2048)
    }

    @Test
    fun `peripheralRsaSignature matches golden vector from protocol js`() {
        val share = encodeProtocolShare(42L, "test-nonce-1")
        val signature = peripheralRsaSignature(share)
        assertEquals(
            "02e37d0f0082b26982760a94e64ab86aa9abd4479fddf61fed40fb53aba12b0" +
                "43e36c783c651fd08d5cac906a4ccba18708cfc63885b865d0927de318a1bca" +
                "0a1cee2a6eb6efac5f2d0ad7680cc298d94f126f83521e9c2579b3f7ccec14f" +
                "0e8c09009e25a5b1c7a2ce4d173496423d522767b4be082e1edad67f93b534e" +
                "7e813b890bcffd5861d307faf94e015dcb56e01e71523dfed54f9763161bfcf" +
                "505299f9901f1ebccfc1e07a40efcd6f30e1b08ed1a3b3af83afc94c2f5f2ea" +
                "52d9d0b8655f3615f92ddb7de5742ebda62267c7f96a020647e984f55bc3a7e" +
                "957dc16ea1d5f0e246637479ad2d9a3f08e6880aefe8e5eadc952528d03dbb1e4de5145",
            bytesToHex(signature),
        )
    }

    @Test
    fun `encodeProtocolComplete matches golden vector from protocol js`() {
        val complete = encodeProtocolComplete(42L, "test-nonce-1")
        assertEquals(
            "0a10082a120c746573742d6e6f6e63652d3112800202e37d0f0082b26982760a94e64ab86aa9abd4479fddf61fed40fb53aba12b043e36c783c651fd08d5cac906a4ccba18708cfc63885b865d0927de318a1bca0a1cee2a6eb6efac5f2d0ad7680cc298d94f126f83521e9c2579b3f7ccec14f0e8c09009e25a5b1c7a2ce4d173496423d522767b4be082e1edad67f93b534e7e813b890bcffd5861d307faf94e015dcb56e01e71523dfed54f9763161bfcf505299f9901f1ebccfc1e07a40efcd6f30e1b08ed1a3b3af83afc94c2f5f2ea52d9d0b8655f3615f92ddb7de5742ebda62267c7f96a020647e984f55bc3a7e957dc16ea1d5f0e246637479ad2d9a3f08e6880aefe8e5eadc952528d03dbb1e4de51451a1002e37d0f0082b26982760a94e64ab86a",
            bytesToHex(complete),
        )
    }
}
