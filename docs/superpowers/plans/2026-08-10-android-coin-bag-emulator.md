# Android Coin Bag Emulator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native Android app (`android/`) that does exactly what the web app (`docs/`) does — emulate a Nintendo Switch over Bluetooth LE to pair with / receive postcards from the Pokémon GO app — except it auto-scans on foreground instead of needing a button press.

**Architecture:** Single `:app` Gradle module, Kotlin, Jetpack Compose for the one status screen. Protocol logic is a 1:1 Kotlin port of `docs/protocol.js` (`Protocol.kt`), reusing the identical base64 constants blob (same embedded RSA key/UUIDs, single source of truth). BLE I/O is a coroutine wrapper around `BluetoothLeScanner`/`BluetoothGatt` (`BleClient.kt`), mirroring `docs/app.js`'s flow and state machine.

**Tech Stack:** Kotlin 1.9.24, AGP 8.5.2, Gradle 8.7, Jetpack Compose (BOM 2024.06.00), kotlinx-coroutines, JDK 17, minSdk 26 / targetSdk 34 / compileSdk 34.

## Global Constraints

- `applicationId` = `io.github.naji.pokemongo.coin.bag`, app label = "Coin Bag Emulator" (from approved spec).
- No button press anywhere in the UI — scanning starts automatically in `onResume`, stops in `onPause` (foreground-only, per approved spec option A).
- Protocol constants (UUIDs, RSA key, GATT width, SHA-256 DigestInfo prefix) must come from the *same* base64 blob embedded in `docs/protocol.js`, copied verbatim — not hand-retyped values.
- Every GATT operation failure surfaces a human-readable message in the UI (mirrors `describeError` in `docs/app.js`), no silent failures.
- No third-party BLE library — plain `android.bluetooth` APIs only.

## Prerequisite (check once, before Task 1)

This plan assumes a machine with: JDK 17, Android SDK (compileSdk 34 platform + build-tools installed, `ANDROID_HOME` set), and a `gradle` binary on `PATH` (only needed once, to generate the Gradle wrapper — after that `./gradlew` is self-contained). On macOS: `brew install --cask temurin17 && brew install gradle`, then install Android SDK command-line tools and accept licenses (`sdkmanager --licenses`), or open the `android/` folder once in Android Studio to have it provision the SDK automatically. If any of this is missing, install it before starting Task 1 — the build-verification steps in this plan will not pass without it.

---

### Task 1: Android project scaffold

**Files:**
- Create: `android/settings.gradle.kts`
- Create: `android/build.gradle.kts`
- Create: `android/gradle.properties`
- Create: `android/.gitignore`
- Create: `android/app/build.gradle.kts`
- Create: `android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/main/res/values/strings.xml`
- Create: `android/app/src/main/res/values/themes.xml`
- Create: `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/MainActivity.kt`

**Interfaces:**
- Produces: a buildable `:app` module with a placeholder `MainActivity` (`ComponentActivity`), package `io.github.naji.pokemongo.coin.bag`. Later tasks add files under the same `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/` source root and `android/app/src/test/kotlin/io/github/naji/pokemongo/coin/bag/` for tests.

- [ ] **Step 1: Create `android/settings.gradle.kts`**

```kotlin
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "coin-bag-emulator"
include(":app")
```

- [ ] **Step 2: Create `android/build.gradle.kts`**

```kotlin
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
```

- [ ] **Step 3: Create `android/gradle.properties`**

```properties
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
kotlin.code.style=official
```

- [ ] **Step 4: Create `android/.gitignore`**

```gitignore
*.iml
.gradle/
/local.properties
/.idea/
.DS_Store
/build
/captures
.externalNativeBuild
.cxx
app/build/
```

- [ ] **Step 5: Create `android/app/build.gradle.kts`**

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "io.github.naji.pokemongo.coin.bag"
    compileSdk = 34

    defaultConfig {
        applicationId = "io.github.naji.pokemongo.coin.bag"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildFeatures {
        compose = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main") {
            kotlin.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            kotlin.srcDirs("src/test/kotlin")
        }
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20231013")
}
```

- [ ] **Step 6: Create `android/app/src/main/AndroidManifest.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />

    <application
        android:allowBackup="true"
        android:label="@string/app_name"
        android:theme="@style/Theme.CoinBagEmulator">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:theme="@style/Theme.CoinBagEmulator">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

- [ ] **Step 7: Create `android/app/src/main/res/values/strings.xml`**

```xml
<resources>
    <string name="app_name">Coin Bag Emulator</string>
</resources>
```

- [ ] **Step 8: Create `android/app/src/main/res/values/themes.xml`**

```xml
<resources>
    <style name="Theme.CoinBagEmulator" parent="android:Theme.Material.Light.NoActionBar" />
</resources>
```

- [ ] **Step 9: Create placeholder `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/MainActivity.kt`**

```kotlin
package io.github.naji.pokemongo.coin.bag

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.Surface
import androidx.compose.material3.Text

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            Surface { Text("Coin Bag Emulator") }
        }
    }
}
```

- [ ] **Step 10: Generate the Gradle wrapper**

Run (from `android/`):

```bash
cd android
gradle wrapper --gradle-version 8.7 --distribution-type bin
cd ..
```

Expected: creates `android/gradlew`, `android/gradlew.bat`, `android/gradle/wrapper/gradle-wrapper.jar`, `android/gradle/wrapper/gradle-wrapper.properties`.

- [ ] **Step 11: Verify the project builds**

Run: `cd android && ./gradlew :app:assembleDebug && cd ..`
Expected: `BUILD SUCCESSFUL`, produces `android/app/build/outputs/apk/debug/app-debug.apk`.

- [ ] **Step 12: Commit**

```bash
git add android/
git commit -m "feat(android): scaffold Gradle/Compose project skeleton"
```

---

### Task 2: Protocol.kt — byte and varint primitives

**Files:**
- Create: `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/Protocol.kt`
- Test: `android/app/src/test/kotlin/io/github/naji/pokemongo/coin/bag/ProtocolPrimitivesTest.kt`

**Interfaces:**
- Consumes: nothing (pure Kotlin, no Android dependency).
- Produces (used by Tasks 3-5): `concatBytes(vararg parts: ByteArray): ByteArray`, `hexToBytes(hex: String): ByteArray`, `bytesToHex(bytes: ByteArray): ByteArray -> String` (signature: `bytesToHex(bytes: ByteArray): String`), `bytesToBigInt(bytes: ByteArray): java.math.BigInteger`, `bigIntToBytes(value: java.math.BigInteger, width: Int): ByteArray`, `encodeVarint(inputValue: Long): ByteArray`, `data class VarintResult(val value: Long, val offset: Int)`, `decodeVarint(data: ByteArray, initialOffset: Int = 0): VarintResult`.

- [ ] **Step 1: Write the failing tests**

Create `android/app/src/test/kotlin/io/github/naji/pokemongo/coin/bag/ProtocolPrimitivesTest.kt`:

```kotlin
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
```

The `varint_...` and `varint_decode_300` values above are golden vectors generated directly from `docs/protocol.js` (`encodeVarint`/`decodeVarint`), not hand-computed — this pins the Kotlin port to the exact same wire output as the web app.

- [ ] **Step 2: Run the tests to verify they fail (nothing implemented yet)**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.ProtocolPrimitivesTest" && cd ..`
Expected: FAIL — compile error, `hexToBytes`/`bytesToHex`/etc. not defined.

- [ ] **Step 3: Implement the primitives in `Protocol.kt`**

Create `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/Protocol.kt`:

```kotlin
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.ProtocolPrimitivesTest" && cd ..`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/Protocol.kt \
        android/app/src/test/kotlin/io/github/naji/pokemongo/coin/bag/ProtocolPrimitivesTest.kt
git commit -m "feat(android): port protocol byte/varint primitives from protocol.js"
```

---

### Task 3: Protocol.kt — protobuf field and message encode/decode

**Files:**
- Modify: `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/Protocol.kt` (append below Task 2's content)
- Test: `android/app/src/test/kotlin/io/github/naji/pokemongo/coin/bag/ProtocolMessagesTest.kt`

**Interfaces:**
- Consumes: `concatBytes`, `encodeVarint`, `decodeVarint`, `VarintResult` (Task 2).
- Produces (used by Tasks 4-6): `sealed class ProtoField` (`Varint(value: Long)`, `Bytes(value: ByteArray)`), `parseFields(data: ByteArray): Map<Int, ProtoField>`, `requireBytes(fields: Map<Int, ProtoField>, number: Int): ByteArray`, `requireVarint(fields: Map<Int, ProtoField>, number: Int): Long`, `data class ServerResponse(val data: Long, val transactionId: Long, val applicationId: String, val nonce: String)`, `data class ProtocolBleSend(val serverResponse: ServerResponse, val serverSignature: ByteArray)`, `data class ProtocolBleFinalize(val nonce: String, val applicationId: String, val serverSignature: ByteArray)`, `decodeProtocolBleSend(data: ByteArray): ProtocolBleSend`, `decodeProtocolBleFinalize(data: ByteArray): ProtocolBleFinalize`, `encodeProtocolShare(transactionId: Long, nonce: String): ByteArray`, plus internal `bytesField`/`stringField`/`varintField` (used again in Task 4).

- [ ] **Step 1: Write the failing tests**

Create `android/app/src/test/kotlin/io/github/naji/pokemongo/coin/bag/ProtocolMessagesTest.kt`. The raw hex fixtures below were generated by hand-building the same wire bytes with `docs/protocol.js`'s own `encodeVarint`, then confirming `decodeProtocolBleSend`/`decodeProtocolBleFinalize` in the JS decode them back to these exact fields — pinning the Kotlin decoder to the JS decoder's behavior.

```kotlin
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.ProtocolMessagesTest" && cd ..`
Expected: FAIL — compile error, message types/functions not defined.

- [ ] **Step 3: Append the protobuf layer to `Protocol.kt`**

Append to `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/Protocol.kt`:

```kotlin
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.ProtocolMessagesTest" && cd ..`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/Protocol.kt \
        android/app/src/test/kotlin/io/github/naji/pokemongo/coin/bag/ProtocolMessagesTest.kt
git commit -m "feat(android): port protobuf message encode/decode from protocol.js"
```

---

### Task 4: Protocol.kt — embedded constants and RSA signing

**Files:**
- Modify: `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/Protocol.kt` (append below Task 3's content)
- Test: `android/app/src/test/kotlin/io/github/naji/pokemongo/coin/bag/ProtocolCryptoTest.kt`

**Interfaces:**
- Consumes: `concatBytes`, `hexToBytes`, `bytesToBigInt`, `bigIntToBytes` (Task 2), `bytesField` (Task 3).
- Produces (used by Tasks 5-6): `object Constants` with `uuids: Map<String, String>`, `applicationIdSuffix: String`, `applicationIdGattWidth: Int`, `rsaModulus: java.math.BigInteger`, `rsaPrivateExponent: java.math.BigInteger`, `sha256DigestInfoPrefix: ByteArray`; `peripheralRsaSignature(message: ByteArray): ByteArray`; `encodeProtocolComplete(transactionId: Long, nonce: String): ByteArray`.

The base64 blob below is copied verbatim from `docs/protocol.js` lines 2-27 — do not retype it by hand, copy it exactly.

- [ ] **Step 1: Write the failing tests**

Create `android/app/src/test/kotlin/io/github/naji/pokemongo/coin/bag/ProtocolCryptoTest.kt`. The `rsaSignature`/`complete` hex values are the actual output of `docs/protocol.js`'s `peripheralRsaSignature`/`encodeProtocolComplete` for the same inputs — generated by running the JS with Node, not hand-computed.

```kotlin
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.ProtocolCryptoTest" && cd ..`
Expected: FAIL — compile error, `Constants`/`peripheralRsaSignature`/`encodeProtocolComplete` not defined.

- [ ] **Step 3: Append constants and RSA signing to `Protocol.kt`**

Append to `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/Protocol.kt`:

```kotlin
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Base64

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
```

Move the `import org.json.JSONObject`, `import java.security.MessageDigest`, and `import java.util.Base64` lines up to the top of the file next to the existing `import java.math.BigInteger` (Kotlin requires all imports before any declarations) — leave everything else where it is.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.ProtocolCryptoTest" && cd ..`
Expected: all tests PASS. If `JSONObject` fails to resolve or throws `RuntimeException: Method ... not mocked`, confirm `testImplementation("org.json:json:20231013")` is present in `app/build.gradle.kts` (Task 1, Step 5) — that dependency provides a real `org.json` implementation for local JVM unit tests.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/Protocol.kt \
        android/app/src/test/kotlin/io/github/naji/pokemongo/coin/bag/ProtocolCryptoTest.kt
git commit -m "feat(android): port embedded constants and RSA signing from protocol.js"
```

---

### Task 5: Protocol.kt — application ID, name, nonce helpers

**Files:**
- Modify: `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/Protocol.kt` (append below Task 4's content)
- Test: `android/app/src/test/kotlin/io/github/naji/pokemongo/coin/bag/ProtocolHelpersTest.kt`

**Interfaces:**
- Consumes: `Constants` (Task 4), `ProtocolBleSend`, `ProtocolBleFinalize` (Task 3).
- Produces (used by Task 6): `normalizeUuid4(value: String): String`, `applicationIdFromUuid(uuid: String): String`, `applicationIdGattValue(applicationId: String): ByteArray`, `decodePlayerName(value: ByteArray): String`, `initialNonceGattValue(nonce: String): ByteArray`, `finalNonceGattValue(nonce: String): ByteArray`, `peripheralNonceFromTick(inputTick: Long): String`, `randomPeripheralNonce(): String`, `validateSend(message: ProtocolBleSend, expectedApplicationId: String, expectedNonce: String)`, `validateFinalize(message: ProtocolBleFinalize, expectedApplicationId: String, expectedNonce: String)`.

- [ ] **Step 1: Write the failing tests**

Create `android/app/src/test/kotlin/io/github/naji/pokemongo/coin/bag/ProtocolHelpersTest.kt`:

```kotlin
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.ProtocolHelpersTest" && cd ..`
Expected: FAIL — compile error, helper functions not defined.

- [ ] **Step 3: Append the helpers to `Protocol.kt`**

Append to `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/Protocol.kt`:

```kotlin
import java.security.SecureRandom

private val UUID_V4_REGEX =
    Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")

fun normalizeUuid4(value: String): String {
    val uuid = value.trim().lowercase()
    require(UUID_V4_REGEX.matches(uuid)) { "Identity must be a canonical UUIDv4" }
    return uuid
}

fun applicationIdFromUuid(uuid: String): String =
    "${normalizeUuid4(uuid)}${Constants.applicationIdSuffix}"

fun applicationIdGattValue(applicationId: String): ByteArray {
    require(applicationId.endsWith(Constants.applicationIdSuffix)) {
        "Application ID must end with ${Constants.applicationIdSuffix}"
    }
    val uuid = applicationId.removeSuffix(Constants.applicationIdSuffix)
    require(applicationIdFromUuid(uuid) == applicationId) {
        "Application ID UUID is not canonical UUIDv4 form"
    }
    val encoded = applicationId.toByteArray(Charsets.UTF_8)
    require(encoded.size <= Constants.applicationIdGattWidth) {
        "Application ID exceeds the ${Constants.applicationIdGattWidth}-byte GATT field"
    }
    val result = ByteArray(Constants.applicationIdGattWidth)
    System.arraycopy(encoded, 0, result, 0, encoded.size)
    return result
}

fun decodePlayerName(value: ByteArray): String {
    require(value.size in 4..15) { "Player name must be 4..15 UTF-8 bytes" }
    return String(value, Charsets.UTF_8)
}

fun initialNonceGattValue(nonce: String): ByteArray {
    val encoded = nonce.toByteArray(Charsets.UTF_8)
    require(!encoded.contains(0)) { "Nonce contains NUL" }
    return concatBytes(encoded, byteArrayOf(0))
}

fun finalNonceGattValue(nonce: String): ByteArray {
    val encoded = nonce.toByteArray(Charsets.UTF_8)
    require(!encoded.contains(0)) { "Nonce contains NUL" }
    return encoded
}

fun peripheralNonceFromTick(inputTick: Long): String {
    val tick = inputTick.toULong()
    var value = 0xcbf29ce484222645UL
    for (index in 0 until 8) {
        val octet = (tick shr (8 * index)) and 0xffUL
        value = value xor octet
        value *= 0x100000001b3UL
    }
    return value.toString(16)
}

fun randomPeripheralNonce(): String = peripheralNonceFromTick(SecureRandom().nextLong())

fun validateSend(message: ProtocolBleSend, expectedApplicationId: String, expectedNonce: String) {
    require(message.serverResponse.applicationId == expectedApplicationId) {
        "Server response application ID mismatch"
    }
    require(message.serverResponse.nonce == expectedNonce) {
        "Server response nonce mismatch"
    }
}

fun validateFinalize(message: ProtocolBleFinalize, expectedApplicationId: String, expectedNonce: String) {
    require(message.applicationId == expectedApplicationId) { "Finalize application ID mismatch" }
    require(message.nonce == expectedNonce) { "Finalize nonce mismatch" }
}
```

Move `import java.security.SecureRandom` up to the top of the file with the other imports.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.ProtocolHelpersTest" && cd ..`
Expected: all tests PASS.

- [ ] **Step 5: Run the full Protocol.kt test suite together**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "io.github.naji.pokemongo.coin.bag.Protocol*Test" && cd ..`
Expected: all tests across `ProtocolPrimitivesTest`, `ProtocolMessagesTest`, `ProtocolCryptoTest`, `ProtocolHelpersTest` PASS. This confirms the full `Protocol.kt` port is wired together correctly.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/Protocol.kt \
        android/app/src/test/kotlin/io/github/naji/pokemongo/coin/bag/ProtocolHelpersTest.kt
git commit -m "feat(android): port applicationId/name/nonce helpers from protocol.js"
```

---

### Task 6: AppState and BleClient — BLE scan/connect/exchange flow

**Files:**
- Create: `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/AppState.kt`
- Create: `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/BleClient.kt`

**Interfaces:**
- Consumes: everything from `Protocol.kt` (Tasks 2-5) — `Constants`, `applicationIdFromUuid`, `applicationIdGattValue`, `decodePlayerName`, `initialNonceGattValue`, `finalNonceGattValue`, `randomPeripheralNonce`, `decodeProtocolBleSend`, `decodeProtocolBleFinalize`, `encodeProtocolComplete`, `validateSend`, `validateFinalize`.
- Produces (used by Tasks 7-8): `sealed interface AppState` (`Idle`, `Scanning`, `Connecting`, `ReadingDevice`, `Pairing`, `Exchanging`, `SuccessPair`, `SuccessExchange`, `Failure(val message: String)`, all as `data object`/`data class`); `class BleClient(context: Context)` with `val state: kotlinx.coroutines.flow.StateFlow<AppState>`, `suspend fun run()`, `fun cancel()`.

No automated test for this task — `BluetoothGatt`/`BluetoothLeScanner` require real BLE hardware and cannot run in a JVM unit test or typical CI without an emulator with Bluetooth support. Verification here is "compiles" (Step 2); full behavioral verification happens manually against the real Pokémon GO app in Task 9.

- [ ] **Step 1: Create `AppState.kt`**

```kotlin
package io.github.naji.pokemongo.coin.bag

sealed interface AppState {
    data object Idle : AppState
    data object Scanning : AppState
    data object Connecting : AppState
    data object ReadingDevice : AppState
    data object Pairing : AppState
    data object Exchanging : AppState
    data object SuccessPair : AppState
    data object SuccessExchange : AppState
    data class Failure(val message: String) : AppState
}
```

- [ ] **Step 2: Create `BleClient.kt`**

```kotlin
package io.github.naji.pokemongo.coin.bag

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.ParcelUuid
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeout
import java.util.UUID

class GattError(message: String) : Exception(message)

private object ServiceUuids {
    val advertisementService: UUID = UUID.fromString(Constants.uuids.getValue("advertisementService"))
    val gattService: UUID = UUID.fromString(Constants.uuids.getValue("gattService"))
    val readProtocol: UUID = UUID.fromString(Constants.uuids.getValue("readProtocol"))
    val readName: UUID = UUID.fromString(Constants.uuids.getValue("readName"))
    val readMode: UUID = UUID.fromString(Constants.uuids.getValue("readMode"))
    val writeApplicationId: UUID = UUID.fromString(Constants.uuids.getValue("writeApplicationId"))
    val writeInitialNonce: UUID = UUID.fromString(Constants.uuids.getValue("writeInitialNonce"))
    val writeComplete: UUID = UUID.fromString(Constants.uuids.getValue("writeComplete"))
    val writeFinalNonce: UUID = UUID.fromString(Constants.uuids.getValue("writeFinalNonce"))
    val indicateData: UUID = UUID.fromString(Constants.uuids.getValue("indicateData"))
    val indicateStage: UUID = UUID.fromString(Constants.uuids.getValue("indicateStage"))
}

private val CLIENT_CHARACTERISTIC_CONFIG_UUID: UUID =
    UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

private const val SCAN_TIMEOUT_MS = 30_000L
private const val INDICATION_TIMEOUT_MS = 15_000L
private const val SETTLE_MS = 75L

@SuppressLint("MissingPermission") // caller (MainActivity) verifies runtime permissions before calling run()
class BleClient(private val context: Context) {

    private val _state = MutableStateFlow<AppState>(AppState.Idle)
    val state: StateFlow<AppState> = _state.asStateFlow()

    private var gatt: BluetoothGatt? = null
    private var connectionResult: CompletableDeferred<Unit>? = null
    private var servicesResult: CompletableDeferred<Unit>? = null
    private var readResult: CompletableDeferred<ByteArray>? = null
    private var writeResult: CompletableDeferred<Unit>? = null
    private var descriptorResult: CompletableDeferred<Unit>? = null
    private val indications = MutableSharedFlow<Pair<UUID, ByteArray>>(extraBufferCapacity = 8)

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                connectionResult?.complete(Unit)
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                connectionResult?.completeExceptionally(GattError("Disconnected (status $status)"))
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                servicesResult?.complete(Unit)
            } else {
                servicesResult?.completeExceptionally(GattError("Service discovery failed (status $status)"))
            }
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicRead(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            completeRead(status, characteristic.value ?: ByteArray(0))
        }

        override fun onCharacteristicRead(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) {
            completeRead(status, value)
        }

        private fun completeRead(status: Int, value: ByteArray) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                readResult?.complete(value)
            } else {
                readResult?.completeExceptionally(GattError("Read failed (status $status)"))
            }
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                writeResult?.complete(Unit)
            } else {
                writeResult?.completeExceptionally(GattError("Write failed (status $status)"))
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                descriptorResult?.complete(Unit)
            } else {
                descriptorResult?.completeExceptionally(GattError("Descriptor write failed (status $status)"))
            }
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            indications.tryEmit(characteristic.uuid to (characteristic.value ?: ByteArray(0)))
        }

        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            indications.tryEmit(characteristic.uuid to value)
        }
    }

    suspend fun run() {
        try {
            _state.value = AppState.Scanning
            val device = scanForDevice()

            _state.value = AppState.Connecting
            val connectedGatt = connectAndDiscover(device)
            gatt = connectedGatt

            _state.value = AppState.ReadingDevice
            val chars = requireCharacteristics(connectedGatt)
            val protocolValue = readCharacteristic(connectedGatt, chars.getValue(ServiceUuids.readProtocol))
            require(protocolValue.size == 1 && protocolValue[0] == 0x01.toByte()) { "Unsupported protocol value" }
            val nameValue = readCharacteristic(connectedGatt, chars.getValue(ServiceUuids.readName))
            decodePlayerName(nameValue)
            val modeValue = readCharacteristic(connectedGatt, chars.getValue(ServiceUuids.readMode))
            require(modeValue.size == 1) { "Invalid mobile app mode characteristic" }

            val applicationId = applicationIdFromUuid(UUID.randomUUID().toString())
            val nonce = randomPeripheralNonce()

            when (modeValue[0]) {
                0x00.toByte() -> {
                    _state.value = AppState.Pairing
                    delay(250)
                    writeCharacteristic(
                        connectedGatt,
                        chars.getValue(ServiceUuids.writeApplicationId),
                        applicationIdGattValue(applicationId),
                        BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
                    )
                    _state.value = AppState.SuccessPair
                }
                0x01.toByte() -> {
                    _state.value = AppState.Exchanging
                    performExchange(connectedGatt, chars, applicationId, nonce)
                    _state.value = AppState.SuccessExchange
                }
                else -> throw GattError("Unsupported mobile app mode 0x${"%02x".format(modeValue[0])}")
            }
        } catch (error: Exception) {
            _state.value = AppState.Failure(error.message ?: error.toString())
        } finally {
            gatt?.disconnect()
            gatt?.close()
            gatt = null
        }
    }

    fun cancel() {
        gatt?.disconnect()
        gatt?.close()
        gatt = null
    }

    private suspend fun scanForDevice(): BluetoothDevice {
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter ?: throw GattError("Bluetooth is not available on this device")
        require(adapter.isEnabled) { "Bluetooth is turned off" }
        val scanner = adapter.bluetoothLeScanner ?: throw GattError("BLE scanning is not available")

        val result = CompletableDeferred<BluetoothDevice>()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scanResult: ScanResult) {
                result.complete(scanResult.device)
            }
            override fun onScanFailed(errorCode: Int) {
                result.completeExceptionally(GattError("Scan failed (error $errorCode)"))
            }
        }
        val filters = listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(ServiceUuids.advertisementService)).build())
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()

        scanner.startScan(filters, settings, callback)
        return try {
            withTimeout(SCAN_TIMEOUT_MS) { result.await() }
        } catch (timeout: TimeoutCancellationException) {
            throw GattError("No matching device found within ${SCAN_TIMEOUT_MS / 1000}s")
        } finally {
            scanner.stopScan(callback)
        }
    }

    private suspend fun connectAndDiscover(device: BluetoothDevice): BluetoothGatt {
        connectionResult = CompletableDeferred()
        val connectedGatt = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        connectionResult!!.await()
        delay(SETTLE_MS)

        servicesResult = CompletableDeferred()
        if (!connectedGatt.discoverServices()) throw GattError("Failed to start service discovery")
        servicesResult!!.await()
        delay(SETTLE_MS)
        return connectedGatt
    }

    private fun requireCharacteristics(connectedGatt: BluetoothGatt): Map<UUID, BluetoothGattCharacteristic> {
        val service = connectedGatt.getService(ServiceUuids.gattService)
            ?: throw GattError("Peripheral primary service was not discovered")
        val required = listOf(
            ServiceUuids.readProtocol, ServiceUuids.readName, ServiceUuids.readMode,
            ServiceUuids.writeApplicationId, ServiceUuids.writeInitialNonce, ServiceUuids.writeComplete,
            ServiceUuids.writeFinalNonce, ServiceUuids.indicateData, ServiceUuids.indicateStage,
        )
        return required.associateWith { uuid ->
            service.getCharacteristic(uuid) ?: throw GattError("Required characteristic $uuid was not discovered")
        }
    }

    private suspend fun readCharacteristic(
        connectedGatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
    ): ByteArray {
        readResult = CompletableDeferred()
        if (!connectedGatt.readCharacteristic(characteristic)) throw GattError("Failed to start characteristic read")
        val value = readResult!!.await()
        delay(SETTLE_MS)
        return value
    }

    @Suppress("DEPRECATION")
    private suspend fun writeCharacteristic(
        connectedGatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
        writeType: Int,
    ) {
        writeResult = CompletableDeferred()
        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            connectedGatt.writeCharacteristic(characteristic, value, writeType) == BluetoothStatusCodes.SUCCESS
        } else {
            characteristic.writeType = writeType
            characteristic.value = value
            connectedGatt.writeCharacteristic(characteristic)
        }
        if (!started) throw GattError("Failed to start characteristic write")
        writeResult!!.await()
        delay(SETTLE_MS)
    }

    @Suppress("DEPRECATION")
    private suspend fun enableIndications(connectedGatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
        if (!connectedGatt.setCharacteristicNotification(characteristic, true)) {
            throw GattError("Failed to enable notifications for ${characteristic.uuid}")
        }
        val cccd = characteristic.getDescriptor(CLIENT_CHARACTERISTIC_CONFIG_UUID)
            ?: throw GattError("Missing CCCD descriptor for ${characteristic.uuid}")
        descriptorResult = CompletableDeferred()
        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            connectedGatt.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_INDICATION_VALUE) == BluetoothStatusCodes.SUCCESS
        } else {
            cccd.value = BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
            connectedGatt.writeDescriptor(cccd)
        }
        if (!started) throw GattError("Failed to start CCCD write for ${characteristic.uuid}")
        descriptorResult!!.await()
        delay(SETTLE_MS)
    }

    private suspend fun awaitIndication(uuid: UUID, timeoutMs: Long): ByteArray =
        try {
            withTimeout(timeoutMs) { indications.first { it.first == uuid }.second }
        } catch (timeout: TimeoutCancellationException) {
            throw GattError("Timed out after ${timeoutMs / 1000}s waiting for indication on $uuid")
        }

    private suspend fun performExchange(
        connectedGatt: BluetoothGatt,
        chars: Map<UUID, BluetoothGattCharacteristic>,
        applicationId: String,
        nonce: String,
    ) {
        writeCharacteristic(
            connectedGatt,
            chars.getValue(ServiceUuids.writeApplicationId),
            applicationIdGattValue(applicationId),
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
        )
        writeCharacteristic(
            connectedGatt,
            chars.getValue(ServiceUuids.writeInitialNonce),
            initialNonceGattValue(nonce),
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE,
        )

        val dataChar = chars.getValue(ServiceUuids.indicateData)
        enableIndications(connectedGatt, dataChar)
        val firstRaw = awaitIndication(dataChar.uuid, INDICATION_TIMEOUT_MS)
        require(firstRaw.size >= 303) {
            "First indication is only ${firstRaw.size} bytes; the negotiated ATT MTU may be insufficient"
        }
        val send = decodeProtocolBleSend(firstRaw)
        validateSend(send, applicationId, nonce)

        val complete = encodeProtocolComplete(send.serverResponse.transactionId, send.serverResponse.nonce)
        writeCharacteristic(
            connectedGatt,
            chars.getValue(ServiceUuids.writeComplete),
            complete,
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE,
        )

        // Notifications are enabled on the STAGE characteristic, but — matching docs/app.js exactly —
        // the final payload is delivered as a second indication on the DATA characteristic, not STAGE.
        enableIndications(connectedGatt, chars.getValue(ServiceUuids.indicateStage))
        val finalRaw = awaitIndication(dataChar.uuid, INDICATION_TIMEOUT_MS)
        val finalize = decodeProtocolBleFinalize(finalRaw)
        validateFinalize(finalize, applicationId, nonce)

        writeCharacteristic(
            connectedGatt,
            chars.getValue(ServiceUuids.writeFinalNonce),
            finalNonceGattValue(nonce),
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
        )
    }
}
```

- [ ] **Step 3: Verify the module compiles**

Run: `cd android && ./gradlew :app:compileDebugKotlin && cd ..`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/AppState.kt \
        android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/BleClient.kt
git commit -m "feat(android): add AppState and BleClient (BLE scan/connect/exchange flow)"
```

---

### Task 7: StatusScreen — Compose UI

**Files:**
- Create: `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/ui/StatusScreen.kt`

**Interfaces:**
- Consumes: `AppState` (Task 6).
- Produces (used by Task 8): `@Composable fun StatusScreen(state: AppState, permissionDenied: Boolean)`.

- [ ] **Step 1: Create `StatusScreen.kt`**

```kotlin
package io.github.naji.pokemongo.coin.bag.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.naji.pokemongo.coin.bag.AppState

private fun stateLabel(state: AppState): String = when (state) {
    AppState.Idle -> "waiting…"
    AppState.Scanning -> "scanning…"
    AppState.Connecting -> "connecting…"
    AppState.ReadingDevice -> "checking device…"
    AppState.Pairing -> "pairing Switch…"
    AppState.Exchanging -> "receiving postcard…"
    AppState.SuccessPair -> "Switch paired!"
    AppState.SuccessExchange -> "postcard received!"
    is AppState.Failure -> "failed"
}

private fun stateColor(state: AppState): Color = when (state) {
    AppState.SuccessPair, AppState.SuccessExchange -> Color(0xFF69D391)
    is AppState.Failure -> Color(0xFFFF7C8C)
    AppState.Idle -> Color(0xFF8B79FF)
    else -> Color(0xFFD2A63D)
}

@Composable
fun StatusScreen(state: AppState, permissionDenied: Boolean) {
    Surface(color = Color(0xFF11131A)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (permissionDenied) {
                StatusCard(
                    label = "permission needed",
                    detail = "Grant Bluetooth permission to continue",
                    color = Color(0xFF4A4D5C),
                )
            } else {
                StatusCard(
                    label = stateLabel(state),
                    detail = (state as? AppState.Failure)?.message,
                    color = stateColor(state),
                )
            }

            Spacer(modifier = Modifier.height(24.dp))
            InstructionsCard()
        }
    }
}

@Composable
private fun StatusCard(label: String, detail: String?, color: Color) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(color, RoundedCornerShape(24.dp))
            .padding(32.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(text = label, color = Color(0xFF0D0D14), fontSize = 36.sp, fontWeight = FontWeight.Black)
            if (detail != null) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(text = detail, color = Color(0xFF0D0D14), fontSize = 14.sp)
            }
        }
    }
}

@Composable
private fun InstructionsCard() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0x0AFFFFFF), RoundedCornerShape(24.dp))
            .padding(20.dp),
    ) {
        Text("Step 1 · Pair Switch", color = Color.White, fontWeight = FontWeight.Bold)
        Text(
            "In Pokémon GO: Poké Ball menu → Settings → Connected devices and Services → " +
                "Nintendo Switch → Connect to Nintendo Switch → pick your game.",
            color = Color.White.copy(alpha = 0.85f),
        )
        Text("This app connects automatically while open.", color = Color.White.copy(alpha = 0.85f))
        Spacer(modifier = Modifier.height(16.dp))
        Text("Step 2 · Send postcard", color = Color.White, fontWeight = FontWeight.Bold)
        Text(
            "In Pokémon GO: Items → Postcard Book → pick a postcard → SEND TO NINTENDO SWITCH.",
            color = Color.White.copy(alpha = 0.85f),
        )
        Text("This app receives it automatically while open.", color = Color.White.copy(alpha = 0.85f))
    }
}
```

- [ ] **Step 2: Verify the module compiles**

Run: `cd android && ./gradlew :app:compileDebugKotlin && cd ..`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/ui/StatusScreen.kt
git commit -m "feat(android): add StatusScreen Compose UI"
```

---

### Task 8: MainActivity — permission handling and auto-scan lifecycle

**Files:**
- Modify: `android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/MainActivity.kt` (replace Task 1's placeholder body entirely)

**Interfaces:**
- Consumes: `BleClient` + `AppState` (Task 6), `StatusScreen` (Task 7).
- Produces: nothing further downstream — this is the final integration point.

- [ ] **Step 1: Replace `MainActivity.kt`**

```kotlin
package io.github.naji.pokemongo.coin.bag

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import io.github.naji.pokemongo.coin.bag.ui.StatusScreen
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val bleClient by lazy { BleClient(applicationContext) }
    private var scanJob: Job? = null
    private var permissionDenied by mutableStateOf(false)

    private val requiredPermissions: Array<String>
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grants ->
        if (grants.values.all { it }) {
            permissionDenied = false
            startScanIfNeeded()
        } else {
            permissionDenied = true
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val state by bleClient.state.collectAsState()
            StatusScreen(state = state, permissionDenied = permissionDenied)
        }
    }

    override fun onResume() {
        super.onResume()
        if (hasAllPermissions()) {
            permissionDenied = false
            startScanIfNeeded()
        } else {
            permissionLauncher.launch(requiredPermissions)
        }
    }

    override fun onPause() {
        super.onPause()
        scanJob?.cancel()
        bleClient.cancel()
    }

    private fun hasAllPermissions(): Boolean =
        requiredPermissions.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }

    private fun startScanIfNeeded() {
        if (scanJob?.isActive == true) return
        scanJob = lifecycleScope.launch { bleClient.run() }
    }
}
```

- [ ] **Step 2: Verify the app builds**

Run: `cd android && ./gradlew :app:assembleDebug && cd ..`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/io/github/naji/pokemongo/coin/bag/MainActivity.kt
git commit -m "feat(android): wire permission handling and auto-scan lifecycle into MainActivity"
```

---

### Task 9: Manual end-to-end verification and docs

**Files:**
- Create: `android/README.md`

**Interfaces:**
- Consumes: the finished app from Tasks 1-8.
- Produces: nothing further — this is the last task.

- [ ] **Step 1: Install the debug build on a real Android device (API 26+) with Bluetooth**

Run: `cd android && ./gradlew :app:installDebug && cd ..`
Expected: app installs; an emulator without a real Bluetooth radio will not be able to find the phone running Pokémon GO, so this needs a physical Android device.

- [ ] **Step 2: Manually verify the pairing flow (mirrors `docs/`'s Step 1)**

In Pokémon GO on the phone you want to pair: Poké Ball menu → Settings → Connected devices and Services → Nintendo Switch → Connect to Nintendo Switch → pick your game. Open the Android app. Expected: on first launch it requests Bluetooth permission (grant it); status card shows `scanning…` → `connecting…` → `checking device…` → `pairing Switch…` → `Switch paired!`. Confirm in Pokémon GO that pairing completed successfully.

- [ ] **Step 3: Manually verify the postcard exchange flow (mirrors `docs/`'s Step 2)**

In Pokémon GO: Items → Postcard Book → pick a postcard → SEND TO NINTENDO SWITCH. Re-open (or bring to foreground) the Android app. Expected: status card shows `scanning…` → `connecting…` → `checking device…` → `receiving postcard…` → `postcard received!`. Confirm in Pokémon GO that the postcard shows as sent/received.

- [ ] **Step 4: Manually verify failure and permission-denied paths**

Deny the Bluetooth permission when prompted: expected status card shows "permission needed". Force-close Pokémon GO (so no matching BLE advertisement exists) and open the app: expected, after ~30s, status card shows "failed" with a "No matching device found within 30s" detail message, not a silent hang.

- [ ] **Step 5: Create `android/README.md`**

```markdown
# Coin Bag Emulator — Android

Native Android port of the [web app](../docs/) — same Nintendo Switch BLE
emulation to pair with / receive postcards from Pokémon GO, except this one
scans automatically whenever it's in the foreground (no button to press).

## Build

Requires JDK 17 and the Android SDK (compileSdk 34).

    ./gradlew :app:assembleDebug

## Install on a device

    ./gradlew :app:installDebug

## How it works

`Protocol.kt` is a line-for-line Kotlin port of [`../docs/protocol.js`](../docs/protocol.js)
— same embedded RSA key and UUIDs (identical base64 blob). `BleClient.kt` is
the Android BLE equivalent of [`../docs/app.js`](../docs/app.js)'s scan →
connect → read → pair-or-exchange flow. Full protocol writeup:
[`../PROTOCOL.md`](../PROTOCOL.md).
```

- [ ] **Step 6: Commit**

```bash
git add android/README.md
git commit -m "docs(android): add build/run instructions and link to protocol writeup"
```
