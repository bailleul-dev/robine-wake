import assert from "node:assert/strict";
import test from "node:test";
import {
  base64ToBytes,
  bytesToBase64,
  bytesToString,
  crc32,
  parsePage,
  utf8Bytes,
} from "../src/protocol";

function putUint16(bytes: Uint8Array, offset: number, value: number): void {
  bytes[offset] = (value >>> 8) & 0xff;
  bytes[offset + 1] = value & 0xff;
}

function putUint32(bytes: Uint8Array, offset: number, value: number): void {
  for (let index = 0; index < 4; index += 1)
    bytes[offset + index] = (value >>> (8 * (3 - index))) & 0xff;
}

test("UTF-8 round-trip", () => {
  const message = "Réveil — pluie 🌧️";
  const bytes = utf8Bytes(message);
  assert.equal(bytesToString(bytes), message);
  assert.equal(bytesToString(base64ToBytes(bytesToBase64(bytes))), message);
});

test("CRC32 reference vector", () => {
  assert.equal(crc32(utf8Bytes("123456789")), 0xcbf43926);
});

test("parses a response page", () => {
  const payload = utf8Bytes('{"status":"ok"}');
  const checksum = crc32(payload);
  const pageBytes = new Uint8Array(20 + payload.length);
  pageBytes[0] = 0x52;
  pageBytes[1] = 0x57;
  pageBytes[2] = 1;
  pageBytes[3] = 1;
  putUint32(pageBytes, 4, 42);
  putUint16(pageBytes, 8, 0);
  putUint16(pageBytes, 10, 1);
  putUint32(pageBytes, 12, payload.length);
  putUint32(pageBytes, 16, checksum);
  pageBytes.set(payload, 20);
  const page = parsePage(bytesToBase64(pageBytes));
  assert.equal(page.final, true);
  assert.equal(page.sequence, 42);
  assert.equal(page.index, 0);
  assert.equal(page.count, 1);
  assert.equal(page.total, payload.length);
  assert.equal(page.crc, checksum);
  assert.equal(bytesToString(page.payload), '{"status":"ok"}');
});
