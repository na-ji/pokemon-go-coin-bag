# Coin Bag Emulator — Android

Native Android app. Scans continuously in foreground — auto-pairs and receives postcards from Pokémon GO without pressing anything.

Download APK: [GitHub Releases](https://github.com/na-ji/pokemon-go-coin-bag/releases)

## Features

- Continuous BLE scanning, no timeout
- Auto-handles pairing (mode 0x00) and exchange (mode 0x01)
- Persists application ID per player for multi-account support
- Event history log with player names and timestamps

## Build

Requires JDK 17 and Android SDK (compileSdk 34).

    ./gradlew :app:assembleDebug

## Install on a device

    ./gradlew :app:installDebug

## How it works

`Protocol.kt` is a Kotlin port of [`../docs/protocol.js`](../docs/protocol.js) — same RSA key and UUIDs. `BleClient.kt` handles the BLE scan → connect → pair/exchange loop. Full protocol writeup: [`../PROTOCOL.md`](../PROTOCOL.md).
