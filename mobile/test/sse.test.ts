import assert from "node:assert/strict";
import test from "node:test";
import { consumeChunk, eventsEndpoint, parseFrame } from "../src/sse";

test("derives events endpoint", () => {
  assert.equal(eventsEndpoint("/api/v1/command"), "/api/v1/events");
  assert.equal(
    eventsEndpoint("http://robine.local:4000/api/v1/command"),
    "http://robine.local:4000/api/v1/events",
  );
  assert.equal(
    eventsEndpoint("http://robine.local:4000/api/v1/command?ignored=true"),
    "http://robine.local:4000/api/v1/events",
  );
  assert.throws(
    () => eventsEndpoint("http://robine.local:4000/state"),
    /Adresse Wi-Fi/,
  );
});

test("parses SSE frames across network chunks", () => {
  const first = consumeChunk("", "id: 41\r\nevent: state.changed\r\nda");
  const second = consumeChunk(
    first.buffer,
    'ta: {"event":"state.changed"}\r\n\r\n: keep-alive\r\n\r\n',
  );
  assert.deepEqual(first.events, []);
  assert.deepEqual(second.events, [
    { id: "41", event: "state.changed", data: '{"event":"state.changed"}' },
  ]);
  assert.equal(second.buffer, "");
});

test("joins multiple data lines", () => {
  assert.deepEqual(parseFrame("data: hello\ndata: world"), {
    event: "message",
    data: "hello\nworld",
  });
});

test("preserves a CRLF split between network chunks", () => {
  const first = consumeChunk("", "id: 9\r");
  const second = consumeChunk(
    first.buffer,
    "\nevent: session.changed\r\ndata: {}\r\n\r\n",
  );
  assert.deepEqual(first.events, []);
  assert.deepEqual(second.events, [
    { id: "9", event: "session.changed", data: "{}" },
  ]);
});
