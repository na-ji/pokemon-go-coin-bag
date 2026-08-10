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
