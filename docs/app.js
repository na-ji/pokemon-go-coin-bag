import {
  UUIDS,
  applicationIdGattValue,
  generateApplicationId,
  decodeProtocolBleFinalize,
  decodeProtocolBleSend,
  decodePlayerName,
  encodeProtocolComplete,
  finalNonceGattValue,
  initialNonceGattValue,
  randomPeripheralNonce,
  validateFinalize,
  validateSend,
} from "./protocol.js";

const CLIENT_VERSION = "1.3.0-minimal";
const GATT_SETTLE_MS = 75;
const button = document.querySelector("#thing");
const stateText = document.querySelector("#thing-state");
const detailText = document.querySelector("#thing-detail");

const BUSY_STATES = new Set([
  "requesting-device",
  "connecting",
  "reading-device",
  "pairing",
  "exchanging",
]);

let activeDevice = null;
let busy = false;

function setState(state, detail = "") {
  const labels = {
    unsupported: "Web Bluetooth not supported",
    ready: "Connect",
    "requesting-device": "choose your phone…",
    connecting: "connecting…",
    "reading-device": "checking device…",
    pairing: "pairing Switch…",
    exchanging: "receiving postcard…",
    "success-pair": "Switch paired!",
    "success-exchange": "postcard received!",
    failure: "failed",
  };
  stateText.textContent = labels[state] ?? state;
  detailText.textContent = detail;
  button.dataset.state = state;
  button.disabled = state === "unsupported" || BUSY_STATES.has(state);
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function toBytes(dataView) {
  return new Uint8Array(
    dataView.buffer.slice(dataView.byteOffset, dataView.byteOffset + dataView.byteLength)
  );
}

function describeError(error) {
  if (error instanceof DOMException || error instanceof Error) {
    return `${error.name}: ${error.message}`;
  }
  return String(error);
}

async function gattOperation(label, operation, { settleMs = GATT_SETTLE_MS } = {}) {
  console.log(`→ ${label}`);
  try {
    const result = await operation();
    console.log(`✓ ${label}`);
    if (settleMs > 0) await sleep(settleMs);
    return result;
  } catch (error) {
    const detail = describeError(error);
    console.error(`✗ ${label}: ${detail}`, error);
    const wrapped = new Error(`${label} failed — ${detail}`);
    wrapped.cause = error;
    throw wrapped;
  }
}

async function writeWithResponse(characteristic, value, label) {
  await gattOperation(`${label} (${value.byteLength} bytes, with response)`, async () => {
    if (typeof characteristic.writeValueWithResponse === "function") {
      await characteristic.writeValueWithResponse(value);
      return;
    }
    if (typeof characteristic.writeValue === "function") {
      await characteristic.writeValue(value);
      return;
    }
    throw new Error("This browser does not support GATT writes with response");
  });
}

function isAmbiguousRegistrationWriteError(error) {
  const cause = error?.cause ?? error;
  const name = cause?.name ?? "";
  const message = cause?.message ?? String(cause ?? "");
  const normalized = `${name}: ${message}`.toLowerCase();

  return (
    ["NotSupportedError", "NetworkError", "OperationError"].includes(name) &&
    (normalized.includes("gatt error unknown") ||
      normalized.includes("gatt operation failed for unknown reason"))
  );
}

async function writeRegistrationApplicationId(characteristic, value) {
  try {
    await writeWithResponse(characteristic, value, "Write application ID");
  } catch (error) {
    if (!isAmbiguousRegistrationWriteError(error)) throw error;

    console.warn(
      "The registration write may have reached the mobile app, but the browser did not receive a usable ATT acknowledgement."
    );
    console.warn("No retry is attempted because the first write may already have succeeded.");
    await sleep(1000);
    throw error;
  }
}

async function writeWithoutResponse(characteristic, value, label) {
  await gattOperation(`${label} (${value.byteLength} bytes, without response)`, async () => {
    if (typeof characteristic.writeValueWithoutResponse !== "function") {
      throw new Error("This browser does not expose writeValueWithoutResponse()");
    }
    await characteristic.writeValueWithoutResponse(value);
  });
}

function characteristicValueWaiter(characteristic, timeoutMs, label) {
  let settled = false;
  let rejectPromise;
  let resolvePromise;
  let timer;

  function cleanup() {
    clearTimeout(timer);
    characteristic.removeEventListener("characteristicvaluechanged", onValue);
  }

  function onValue(event) {
    if (settled) return;
    settled = true;
    cleanup();
    resolvePromise(toBytes(event.target.value));
  }

  const promise = new Promise((resolve, reject) => {
    resolvePromise = resolve;
    rejectPromise = reject;
    timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      cleanup();
      reject(new Error(`Timed out after ${timeoutMs / 1000}s waiting for ${label}`));
    }, timeoutMs);
    characteristic.addEventListener("characteristicvaluechanged", onValue);
  });

  return {
    promise,
    cancel(reason = "Indication wait cancelled") {
      if (settled) return;
      settled = true;
      cleanup();
      rejectPromise(new Error(reason));
      promise.catch(() => {});
    },
  };
}

async function getCharacteristics(service) {
  const discovered = await gattOperation(
    "Discover all Peripheral GATT characteristics",
    () => service.getCharacteristics(),
    { settleMs: 125 }
  );
  const byUuid = new Map(discovered.map((characteristic) => [characteristic.uuid, characteristic]));
  const requested = {
    protocol: UUIDS.readProtocol,
    name: UUIDS.readName,
    mode: UUIDS.readMode,
    applicationId: UUIDS.writeApplicationId,
    initialNonce: UUIDS.writeInitialNonce,
    complete: UUIDS.writeComplete,
    finalNonce: UUIDS.writeFinalNonce,
    data: UUIDS.indicateData,
    stage: UUIDS.indicateStage,
  };

  const result = {};
  for (const [name, uuid] of Object.entries(requested)) {
    const characteristic = byUuid.get(uuid);
    if (!characteristic) {
      throw new Error(`Required characteristic ${name} (${uuid}) was not discovered`);
    }
    result[name] = characteristic;
  }
  return result;
}

async function performExchange(chars, applicationId, nonce, timeoutMs) {
  await writeWithResponse(
    chars.applicationId,
    applicationIdGattValue(applicationId),
    "Write application ID"
  );

  await writeWithoutResponse(
    chars.initialNonce,
    initialNonceGattValue(nonce),
    "Write initial nonce"
  );

  const firstWaiter = characteristicValueWaiter(chars.data, timeoutMs, "first DATA indication");
  try {
    await gattOperation(
      "Enable DATA indications",
      () => chars.data.startNotifications(),
      { settleMs: 0 }
    );
  } catch (error) {
    firstWaiter.cancel("DATA subscription failed");
    throw error;
  }

  console.log("→ Wait for first DATA indication");
  const firstRaw = await firstWaiter.promise;
  console.log(`✓ Received first DATA indication (${firstRaw.length} bytes)`);
  if (firstRaw.length < 303) {
    throw new Error(
      `First indication is only ${firstRaw.length} bytes; the negotiated ATT MTU may be insufficient`
    );
  }

  const send = decodeProtocolBleSend(firstRaw);
  validateSend(send, applicationId, nonce);
  console.log("Transaction ID:", send.serverResponse.transactionId.toString());

  const complete = await encodeProtocolComplete(
    send.serverResponse.transactionId,
    send.serverResponse.nonce
  );
  await writeWithoutResponse(chars.complete, complete, "Write RSA completion");

  const finalWaiter = characteristicValueWaiter(chars.stage, timeoutMs, "STAGE indication");
  try {
    await gattOperation(
      "Enable STAGE indications",
      () => chars.stage.startNotifications(),
      { settleMs: 0 }
    );
  } catch (error) {
    finalWaiter.cancel("STAGE subscription failed");
    throw error;
  }

  console.log("→ Wait for STAGE indication");
  const finalRaw = await finalWaiter.promise;
  console.log(`✓ Received STAGE indication (${finalRaw.length} bytes)`);

  const finalize = decodeProtocolBleFinalize(finalRaw);
  validateFinalize(finalize, applicationId, nonce);

  await writeWithResponse(
    chars.finalNonce,
    finalNonceGattValue(nonce),
    "Write final nonce"
  );
}

async function doTheThing() {
  if (busy) return;
  busy = true;

  try {
    if (!navigator.bluetooth) throw new Error("Web Bluetooth is unavailable");
    if (!crypto.randomUUID || !crypto.subtle) {
      throw new Error("Required Web Crypto features are unavailable");
    }

    console.group(`do the thing — ${CLIENT_VERSION}`);
    console.log("Browser:", navigator.userAgent);

    const nonce = randomPeripheralNonce();
    console.log("Nonce:", nonce);

    setState("requesting-device");
    activeDevice = await navigator.bluetooth.requestDevice({
      filters: [{ services: [UUIDS.advertisementService] }],
      optionalServices: [UUIDS.gattService],
    });
    console.log("Selected device:", activeDevice.name || "unnamed device", "id:", activeDevice.id);

    setState("connecting");
    const server = await gattOperation(
      `Connect to ${activeDevice.name || "unnamed device"}`,
      () => activeDevice.gatt.connect(),
      { settleMs: 150 }
    );
    const service = await gattOperation(
      "Discover Peripheral primary service",
      () => server.getPrimaryService(UUIDS.gattService),
      { settleMs: 125 }
    );
    const chars = await getCharacteristics(service);

    setState("reading-device");
    const protocolValue = await gattOperation(
      "Read protocol characteristic",
      () => chars.protocol.readValue()
    );
    const nameValue = await gattOperation(
      "Read player-name characteristic",
      () => chars.name.readValue()
    );
    const modeValue = await gattOperation(
      "Read mode characteristic",
      () => chars.mode.readValue()
    );

    const protocol = toBytes(protocolValue);
    const playerName = decodePlayerName(toBytes(nameValue));
    const mode = toBytes(modeValue);

    if (protocol.length !== 1 || protocol[0] !== 0x01) {
      throw new Error(`Unsupported protocol value: ${Array.from(protocol).join(",")}`);
    }
    if (mode.length !== 1) throw new Error("Invalid mobile app mode characteristic");

    console.log("Player:", playerName);
    console.log(`Mode: 0x${mode[0].toString(16).padStart(2, "0")}`);

    const storageKey = `pairedApplicationId:${playerName}`;
    let applicationId;
    if (mode[0] === 0x01) {
      const stored = localStorage.getItem(storageKey);
      if (stored) {
        applicationId = stored;
        console.log("Reusing stored applicationId for", playerName);
      } else {
        applicationId = await generateApplicationId();
        console.log("No stored applicationId for", playerName, "— generating new");
      }
    } else {
      applicationId = await generateApplicationId();
    }

    if (mode[0] === 0x00) {
      setState("pairing");
      await sleep(250);
      await writeRegistrationApplicationId(
        chars.applicationId,
        applicationIdGattValue(applicationId)
      );
      localStorage.setItem(storageKey, applicationId);
      setState("success-pair", `Paired with ${playerName}. Now in GO: Items → Postcard Book → SEND TO NINTENDO SWITCH, then click Connect again`);
    } else if (mode[0] === 0x01) {
      setState("exchanging");
      await performExchange(chars, applicationId, nonce, 15_000);
      setState("success-exchange", `Postcard received from ${playerName}`);
    } else {
      throw new Error(`Unsupported mobile app mode 0x${mode[0].toString(16).padStart(2, "0")}`);
    }

    console.log("Thing completed.");
  } catch (error) {
    console.error("Thing probably failed.", error);
    setState("failure", describeError(error));
  } finally {
    if (activeDevice?.gatt?.connected) {
      console.log("Closing BLE connection…");
      activeDevice.gatt.disconnect();
    }
    activeDevice = null;
    busy = false;
    console.groupEnd();
  }
}

button.addEventListener("click", doTheThing);

if (!navigator.bluetooth) {
  setState("unsupported");
} else {
  setState("ready");
}
