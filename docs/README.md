# Coin Bag Emulator — Web

Static web app using Web Bluetooth. No build step, no dependencies.

Live: https://na-ji.github.io/pokemon-go-coin-bag/

## Browser support

Chrome or Edge, desktop or Android. Not Safari, Firefox, or iOS (no Web Bluetooth).

## Usage

Two-step flow, one button press per step:

1. Start pairing in Pokémon GO, press Connect
2. Send postcard in Pokémon GO, press Connect again

## Files

- `app.js` — BLE scan, connect, pair/exchange logic
- `protocol.js` — UUIDs, protobuf encoding/decoding, RSA signing
- `index.html` / `style.css` — UI

## How it works

Full protocol writeup: [`../PROTOCOL.md`](../PROTOCOL.md).
