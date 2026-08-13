const CONSTANTS = `
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
`;

const constants = Object.freeze(
  JSON.parse(atob(CONSTANTS.replace(/\s+/g, "")))
);

export const UUIDS = Object.freeze(constants.UUIDS);
export const APPLICATION_ID_SUFFIX = constants.APPLICATION_ID_SUFFIX;
export const APPLICATION_ID_GATT_WIDTH = constants.APPLICATION_ID_GATT_WIDTH;

const textEncoder = new TextEncoder(constants.TEXT_ENCODING);
const textDecoder = new TextDecoder(constants.TEXT_ENCODING, {
  fatal: constants.TEXT_DECODER_FATAL,
});
const RSA_MODULUS = BigInt(constants.RSA_MODULUS);
const RSA_PRIVATE_EXPONENT = BigInt(constants.RSA_PRIVATE_EXPONENT);
const SHA256_DIGEST_INFO_PREFIX = hexToBytes(
  constants.SHA256_DIGEST_INFO_PREFIX
);

export function concatBytes(...parts) {
  const length = parts.reduce((sum, part) => sum + part.length, 0);
  const result = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

export function hexToBytes(hex) {
  if (hex.length % 2 !== 0 || !/^[0-9a-f]*$/i.test(hex)) {
    throw new Error("Invalid hexadecimal string");
  }
  const result = new Uint8Array(hex.length / 2);
  for (let index = 0; index < result.length; index += 1) {
    result[index] = Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }
  return result;
}

export function bytesToHex(bytes) {
  return Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
}

function bytesToBigInt(bytes) {
  const hex = bytesToHex(bytes);
  return hex ? BigInt(`0x${hex}`) : 0n;
}

function bigIntToBytes(value, width) {
  if (value < 0n) {
    throw new Error("Cannot encode a negative integer as unsigned bytes");
  }
  let hex = value.toString(16);
  if (hex.length % 2 !== 0) hex = `0${hex}`;
  const raw = hexToBytes(hex);
  if (raw.length > width) {
    throw new Error(`Integer does not fit in ${width} bytes`);
  }
  const result = new Uint8Array(width);
  result.set(raw, width - raw.length);
  return result;
}

export function encodeVarint(input) {
  let value = typeof input === "bigint" ? input : BigInt(input);
  if (value < 0n) value &= (1n << 64n) - 1n;
  const result = [];
  while (value > 0x7fn) {
    result.push(Number((value & 0x7fn) | 0x80n));
    value >>= 7n;
  }
  result.push(Number(value));
  return Uint8Array.from(result);
}

export function decodeVarint(data, initialOffset = 0) {
  let value = 0n;
  let shift = 0n;
  let offset = initialOffset;
  while (offset < data.length && shift < 70n) {
    const octet = BigInt(data[offset]);
    offset += 1;
    value |= (octet & 0x7fn) << shift;
    if ((octet & 0x80n) === 0n) return { value, offset };
    shift += 7n;
  }
  throw new Error("Invalid or truncated protobuf varint");
}

function bytesField(number, value) {
  return concatBytes(
    encodeVarint(BigInt((number << 3) | 2)),
    encodeVarint(value.length),
    value
  );
}

function stringField(number, value) {
  return bytesField(number, textEncoder.encode(value));
}

function varintField(number, value) {
  return concatBytes(encodeVarint(BigInt(number << 3)), encodeVarint(value));
}

function parseFields(data) {
  const fields = new Map();
  let offset = 0;
  while (offset < data.length) {
    const tagResult = decodeVarint(data, offset);
    const tag = tagResult.value;
    offset = tagResult.offset;
    const number = Number(tag >> 3n);
    const wireType = Number(tag & 7n);
    if (number === 0) throw new Error("Protobuf field number zero");

    if (wireType === 0) {
      const result = decodeVarint(data, offset);
      fields.set(number, { wireType, value: result.value });
      offset = result.offset;
    } else if (wireType === 2) {
      const lengthResult = decodeVarint(data, offset);
      const length = Number(lengthResult.value);
      offset = lengthResult.offset;
      const end = offset + length;
      if (!Number.isSafeInteger(length) || end > data.length) {
        throw new Error("Truncated protobuf length-delimited field");
      }
      fields.set(number, { wireType, value: data.slice(offset, end) });
      offset = end;
    } else {
      throw new Error(`Unsupported protobuf wire type ${wireType}`);
    }
  }
  return fields;
}

function requireBytes(fields, number) {
  const field = fields.get(number);
  if (!field) throw new Error(`Missing protobuf field ${number}`);
  if (field.wireType !== 2 || !(field.value instanceof Uint8Array)) {
    throw new Error(`Protobuf field ${number} is not length-delimited`);
  }
  return field.value;
}

function requireVarint(fields, number) {
  const field = fields.get(number);
  if (!field) throw new Error(`Missing protobuf field ${number}`);
  if (field.wireType !== 0 || typeof field.value !== "bigint") {
    throw new Error(`Protobuf field ${number} is not a varint`);
  }
  return field.value;
}

export function decodeProtocolBleSend(data) {
  const outer = parseFields(data);
  const prep = parseFields(requireBytes(outer, 1));
  return {
    serverResponse: {
      data: requireVarint(prep, 1),
      transactionId: requireVarint(prep, 2),
      applicationId: textDecoder.decode(requireBytes(prep, 3)),
      nonce: textDecoder.decode(requireBytes(prep, 4)),
    },
    serverSignature: requireBytes(outer, 2),
  };
}

export function decodeProtocolBleFinalize(data) {
  const outer = parseFields(data);
  const complete = parseFields(requireBytes(outer, 1));
  return {
    nonce: textDecoder.decode(requireBytes(complete, 1)),
    applicationId: textDecoder.decode(requireBytes(complete, 2)),
    serverSignature: requireBytes(outer, 2),
  };
}

export function encodeProtocolShare(transactionId, nonce) {
  return concatBytes(
    varintField(1, transactionId),
    stringField(2, nonce)
  );
}

function modPow(base, exponent, modulus) {
  if (modulus <= 0n) throw new Error("RSA modulus must be positive");
  let result = 1n;
  let factor = base % modulus;
  let power = exponent;
  while (power > 0n) {
    if ((power & 1n) === 1n) result = (result * factor) % modulus;
    power >>= 1n;
    factor = (factor * factor) % modulus;
  }
  return result;
}

export async function peripheralRsaSignature(message) {
  const digestBuffer = await crypto.subtle.digest("SHA-256", message);
  const digest = new Uint8Array(digestBuffer);
  const paddingLength = 256 - 3 - SHA256_DIGEST_INFO_PREFIX.length - digest.length;
  if (paddingLength < 8) throw new Error("Digest encoding does not fit RSA modulus");
  const encoded = concatBytes(
    Uint8Array.of(0x00, 0x01),
    new Uint8Array(paddingLength).fill(0xff),
    Uint8Array.of(0x00),
    SHA256_DIGEST_INFO_PREFIX,
    digest
  );
  const signature = modPow(bytesToBigInt(encoded), RSA_PRIVATE_EXPONENT, RSA_MODULUS);
  return bigIntToBytes(signature, 256);
}

export async function encodeProtocolComplete(transactionId, nonce) {
  const share = encodeProtocolShare(transactionId, nonce);
  const applicationSignature = await peripheralRsaSignature(share);
  const firmwareSignature = applicationSignature.slice(0, 16);
  return concatBytes(
    bytesField(1, share),
    bytesField(2, applicationSignature),
    bytesField(3, firmwareSignature)
  );
}

function formatUuid(bytes) {
  const hex = bytesToHex(bytes.slice(0, 16));
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20,32)}`;
}

const UUID_V5_NAMESPACE = hexToBytes("6ba7b8109dad11d180b400c04fd430c8");

export async function generateApplicationId() {
  const name = new Uint8Array(16);
  crypto.getRandomValues(name);
  const data = concatBytes(UUID_V5_NAMESPACE, name);
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-1", data));
  hash[6] = (hash[6] & 0x0f) | 0x50;
  hash[8] = (hash[8] & 0x3f) | 0x80;
  return `${formatUuid(hash)}${APPLICATION_ID_SUFFIX}`;
}

export function applicationIdGattValue(applicationId) {
  if (!applicationId.endsWith(APPLICATION_ID_SUFFIX)) {
    throw new Error(`Application ID must end with ${APPLICATION_ID_SUFFIX}`);
  }
  const encoded = textEncoder.encode(applicationId);
  if (encoded.length > APPLICATION_ID_GATT_WIDTH) {
    throw new Error("Application ID exceeds the 69-byte GATT field");
  }
  const result = new Uint8Array(APPLICATION_ID_GATT_WIDTH);
  result.set(encoded);
  return result;
}

export function decodePlayerName(value) {
  if (value.length < 4 || value.length > 15) {
    throw new Error("Player name must be 4..15 UTF-8 bytes");
  }
  return textDecoder.decode(value);
}

export function initialNonceGattValue(nonce) {
  const encoded = textEncoder.encode(nonce);
  if (encoded.includes(0)) throw new Error("Nonce contains NUL");
  return concatBytes(encoded, Uint8Array.of(0));
}

export function finalNonceGattValue(nonce) {
  const encoded = textEncoder.encode(nonce);
  if (encoded.includes(0)) throw new Error("Nonce contains NUL");
  return encoded;
}

export function peripheralNonceFromTick(input) {
  let tick = typeof input === "bigint" ? input : BigInt(input);
  tick &= (1n << 64n) - 1n;
  let value = 0xcbf29ce484222645n;
  for (let index = 0n; index < 8n; index += 1n) {
    const octet = (tick >> (8n * index)) & 0xffn;
    value ^= octet;
    value = (value * 0x100000001b3n) & ((1n << 64n) - 1n);
  }
  return value.toString(16);
}

export function randomPeripheralNonce() {
  const words = new Uint32Array(2);
  crypto.getRandomValues(words);
  const tick = BigInt(words[0]) | (BigInt(words[1]) << 32n);
  return peripheralNonceFromTick(tick);
}

export function validateSend(message, expectedApplicationId, expectedNonce) {
  if (message.serverResponse.applicationId !== expectedApplicationId) {
    throw new Error("Server response application ID mismatch");
  }
  if (message.serverResponse.nonce !== expectedNonce) {
    throw new Error("Server response nonce mismatch");
  }
}

export function validateFinalize(message, expectedApplicationId, expectedNonce) {
  if (message.applicationId !== expectedApplicationId) {
    throw new Error("Finalize application ID mismatch");
  }
  if (message.nonce !== expectedNonce) {
    throw new Error("Finalize nonce mismatch");
  }
}
