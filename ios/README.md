# Coin Bag Emulator — iOS

Native iOS app. Scans continuously in the foreground — auto-pairs and receives
postcards from Pokémon GO without pressing anything. Feature-for-feature port of
the Android app ([`../android`](../android)).

## Features

- Continuous BLE scanning, no timeout
- Auto-handles pairing (mode `0x00`) and exchange (mode `0x01`)
- Persists application ID in `UserDefaults` (multi-account ready)
- Event history log with player names and timestamps
- Dark UI mirroring the Android `StatusScreen`

## Requirements

- Xcode 16+ (built and tested with Xcode 26)
- iOS 17.0+

## Open, build, run

    open ios/CoinBag.xcodeproj

Or from the command line:

    xcodebuild -project ios/CoinBag.xcodeproj -scheme CoinBag \
      -destination 'generic/platform=iOS Simulator' build

## Run tests

Ports the Android golden-vector tests (`ProtocolCryptoTest`,
`ProtocolMessagesTest`, `ProtocolPrimitivesTest`, `ProtocolHelpersTest`):

    xcodebuild -project ios/CoinBag.xcodeproj -scheme CoinBag \
      -destination 'platform=iOS Simulator,name=iPhone 17' test

## Structure

```
ios/
  CoinBag/
    Protocol.swift     Swift port of ../docs/protocol.js (UUIDs, protobuf, RSA-2048, nonce, appId)
    BleClient.swift    CoreBluetooth scan → connect → pair/exchange loop
    StatusView.swift   SwiftUI UI
    CoinBagApp.swift   @main entry point
    AppState.swift     state machine
    LogEntry.swift     event history model
  CoinBagTests/
    ProtocolTests.swift  golden-vector unit tests
  tools/harness/        standalone swiftc protocol verifier (no simulator needed)
```

## How it works

Same protocol as web and Android — full writeup in [`../PROTOCOL.md`](../PROTOCOL.md).
`Protocol.swift` is a straight port; RSA signing uses a small built-in big-integer
`modPow` (no third-party deps), verified against the same golden signature vector
as the Kotlin tests.

### iOS-specific differences from Android

- **MTU**: CoreBluetooth has no `requestMtu()` API — the OS negotiates the ATT MTU
  automatically. The exchange still enforces the same "first indication ≥ 303 bytes"
  check as Android/Web and fails loudly if the negotiated MTU is too small.
- **No-response writes**: CoreBluetooth does not call `didWriteValueFor` for
  `.withoutResponse` writes, so those are fire-and-forget (matches Web
  `writeValueWithoutResponse`, which also resolves immediately).
- **Finalize indication**: still raced across both DATA and STAGE characteristics
  (Android GO finalizes on DATA, iOS GO finalizes on STAGE), same as Android.

## CI

`.github/workflows/ios-build.yml` builds an unsigned IPA on a macOS runner and
uploads it as a build artifact (`CoinBag-unsigned.ipa`). No code signing —
install it on a device with a signing tool (e.g. sideload) or sign it manually.

## Bluetooth permission

The app declares `NSBluetoothAlwaysUsageDescription`. iOS shows the Bluetooth
permission prompt on first launch; denying it shows a "permission needed" card.
Grant it in Settings → Privacy → Bluetooth if it was skipped.
