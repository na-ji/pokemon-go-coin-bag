# Pokémon GO Coin Bag Emulator

Emulates a Nintendo Switch over Bluetooth so you can pair with Pokémon GO and receive postcards. No real Switch needed.

Background on the real feature: https://scarletviolet.pokemon.com/en-gb/news/pokemon_go_connect/

## Three versions

**Web app** — works in Chrome/Edge on desktop or Android. Open and go:
https://na-ji.github.io/pokemon-go-coin-bag/

**Android app** — scans continuously in background, handles pairing and exchange automatically. Download APK from [GitHub Releases](https://github.com/na-ji/pokemon-go-coin-bag/releases).

**iOS app** — same as Android: scans continuously in the foreground, handles pairing and exchange automatically. Build from [`ios/`](ios/).

## How to use

1. In Pokémon GO: Settings → Connected devices → Nintendo Switch → Connect
2. Pair using the web app button or let the Android app pick it up
3. In Pokémon GO: Items → Postcard Book → pick a postcard → Send to Nintendo Switch
4. Connect again (web: press button, Android: automatic)

Each step is a separate Bluetooth connection.

## How it works

Impersonates the Switch's Bluetooth identity and signs the handshake with the Switch's RSA key. Pokémon GO accepts it as a real device. Full protocol writeup: [PROTOCOL.md](PROTOCOL.md).

## Repository structure

```
docs/           Web app (static site, no build step)
  app.js        BLE logic + UI
  protocol.js   Protocol implementation (UUIDs, protobuf, RSA signing)
  index.html
  style.css
android/        Android app (Kotlin, Jetpack Compose)
ios/            iOS app (Swift, SwiftUI + CoreBluetooth)
  CoinBag/      app sources (Protocol.swift, BleClient.swift, StatusView.swift)
  CoinBagTests/ golden-vector unit tests
PROTOCOL.md     Protocol documentation
```
