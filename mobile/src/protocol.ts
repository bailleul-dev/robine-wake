export function utf8Bytes(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

export function bytesToString(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

export function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return globalThis.btoa(binary);
}

export function base64ToBytes(value: string): Uint8Array {
  const binary = globalThis.atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function uint16(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] ?? 0) * 256 + (bytes[offset + 1] ?? 0);
}

function uint32(bytes: Uint8Array, offset: number): number {
  return (
    ((bytes[offset] ?? 0) * 16_777_216 +
      (bytes[offset + 1] ?? 0) * 65_536 +
      (bytes[offset + 2] ?? 0) * 256 +
      (bytes[offset + 3] ?? 0)) >>>
    0
  );
}

export function crc32(bytes: Uint8Array): number {
  let crc = 0xffff_ffff;
  for (const byte of bytes) {
    let value = crc ^ byte;
    for (let bit = 0; bit < 8; bit += 1)
      value = (value >>> 1) ^ (value & 1 ? 0xedb8_8320 : 0);
    crc = value;
  }
  return (crc ^ 0xffff_ffff) >>> 0;
}

export function concatBytes(left: Uint8Array, right: Uint8Array): Uint8Array {
  const result = new Uint8Array(left.length + right.length);
  result.set(left, 0);
  result.set(right, left.length);
  return result;
}

export interface ResponsePage {
  final: boolean;
  sequence: number;
  index: number;
  count: number;
  total: number;
  crc: number;
  payload: Uint8Array;
}

export function parsePage(value: string): ResponsePage {
  const bytes = base64ToBytes(value);
  if (bytes.length < 20)
    throw new Error("En-tête de réponse Bluetooth incomplet");
  if (bytes[0] !== 0x52 || bytes[1] !== 0x57 || bytes[2] !== 1)
    throw new Error("En-tête de réponse Bluetooth invalide");
  return {
    final: ((bytes[3] ?? 0) & 1) === 1,
    sequence: uint32(bytes, 4),
    index: uint16(bytes, 8),
    count: uint16(bytes, 10),
    total: uint32(bytes, 12),
    crc: uint32(bytes, 16),
    payload: bytes.slice(20),
  };
}
