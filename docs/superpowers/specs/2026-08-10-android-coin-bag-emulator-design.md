# Android port of Coin Bag Emulator

Native Android equivalent of the web app (`docs/`) — same Nintendo Switch BLE emulation, no button press: scans and runs automatically whenever the app is in the foreground.

## Approach

Plain Android BLE APIs (`BluetoothLeScanner` + `BluetoothGatt`, coroutine-wrapped) + Jetpack Compose for the single status screen. No third-party BLE library — code stays a direct line-by-line mirror of `docs/app.js` / `docs/protocol.js`, easiest to audit against the web version. Protocol logic ported 1:1 into Kotlin, reusing the *same* base64 constants blob (decoded via `org.json.JSONObject`, built into Android) as single source of truth for the embedded RSA key/UUIDs — not a hand-copied second version that can drift.

## Project layout

```
android/
  settings.gradle.kts, build.gradle.kts, gradle/wrapper/...
  app/
    build.gradle.kts
    src/main/
      AndroidManifest.xml
      kotlin/io/github/naji/pokemongo/coin/bag/
        Protocol.kt        # port of protocol.js: constants, varint, protobuf, RSA sign, nonce/appId helpers
        BleClient.kt        # port of app.js: scan, connect, characteristic discovery, gattOperation-style suspend helpers, performExchange
        MainActivity.kt     # Compose screen, permission request, auto-launch flow
        ui/StatusScreen.kt  # Compose UI: instructions + live state text (mirrors index.html content)
```

Gradle Kotlin DSL, single `:app` module. `applicationId = "io.github.naji.pokemongo.coin.bag"`, label "Coin Bag Emulator". `minSdk 26`, `targetSdk` latest stable.

## Permissions & lifecycle

- Manifest: `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` (Android 12+, `neverForLocation` on the scan permission since we filter by service UUID, not location) and `ACCESS_FINE_LOCATION` (`maxSdkVersion=30`, required by OS for BLE scan pre-Android 12).
- On launch: request whichever runtime permissions aren't granted yet — the one unavoidable OS-mandated tap (system dialog, not an app button). Once granted, scanning starts immediately.
- `onResume` (app opened/foregrounded): if permissions already granted, auto-start scan. `onPause`/backgrounded: stop scan/disconnect. Foreground-only — matches web app's "one attempt per open" model.
- No retry button: result stays on screen until the user reopens the app.

## BLE flow (`BleClient.kt`, mirrors `app.js`)

`startScan` filtered on `advertisementService` UUID → first matching result → `stopScan` → `connectGatt` → discover `gattService` + characteristics by UUID → read protocol/name/mode → branch on mode:

- `0x00`: write `applicationId` (registration). Same ambiguous-ack tolerance as web (`writeRegistrationApplicationId`, no retry).
- `0x01`: full exchange — write appId+nonce, subscribe `data`, wait indication, decode+validate, RSA-sign share, write `complete`, subscribe `stage`, wait indication, decode+validate, write `finalNonce`.

Each GATT op wrapped in a `suspendCancellableCoroutine` (Android's `BluetoothGattCallback` is callback-based) with the same settle-delay/error-wrapping pattern as `gattOperation()` in `app.js`.

## UI (Compose, one screen)

Same content as `docs/index.html`: title, big status text, small detail line, the two numbered step instructions below. States mirror `setState()` in `app.js` minus `requesting-device` (Android scan+auto-connect has no browser device-picker step) — replaced by `scanning`. Web-Bluetooth-support note replaced with permission-state text if denied.

## Error handling

Every GATT op failure wrapped with a descriptive message (mirrors `describeError`), surfaced in the detail line. Scan timeout (no matching device found) is its own failure state with a clear message, not a silent hang.

## Testing

No BLE hardware in CI — manual verification against the real Pokémon GO flow, same as the web app. Local unit tests for the pure/protocol parts (varint encode/decode, RSA `modPow`, appId/nonce formatting) ported from `protocol.js`, since they have no Android dependency and are easy to get wrong in translation.
