# Pokémon Go Coin Bag Emulator

Web app that emulates a Nintendo Switch over Web Bluetooth so you can pair it with the Pokémon GO app and receive postcards. No real Switch needed.

Background on the real feature: https://scarletviolet.pokemon.com/en-gb/news/pokemon_go_connect/

Use it here: https://na-ji.github.io/pokemon-go-coin-bag/

## Use it

1. Open this page's GitHub Pages URL over HTTPS, in a browser with Web Bluetooth support (Chrome or Edge, desktop or Android - not Safari/Firefox/iOS).
2. Follow the two steps shown on the page:
   - **Step 1 · Pair Switch**: start pairing in Pokémon GO, then press the button here to complete it.
   - **Step 2 · Send postcard**: send a postcard to your Switch in Pokémon GO, then press the button here to receive it.

Each step is a separate Bluetooth connection. Press the button once per step.

## How it works

The app impersonates the Switch's Bluetooth identity and signs the handshake with the Switch's RSA key (embedded in `protocol.js`), so Pokémon GO accepts it as a real device. Full protocol writeup: [PROTOCOL.md](PROTOCOL.md).

## Development

Static site, no build step. Any LLM can read `protocol.js` and port this to another platform (Linux, Android, ESP32) if needed.
