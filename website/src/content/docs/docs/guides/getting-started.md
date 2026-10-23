---
title: Getting started
description: Run Robine Wake on a development computer with simulated hardware.
sidebar:
  order: 1
---

The whole product runs on a computer with simulated hardware (the `host`
target). No Raspberry Pi is needed to try alarms, wake sessions and the web
interface.

## Prerequisites

- Erlang/OTP and Elixir — versions are pinned in `.tool-versions`.
- A C toolchain for NIFs.

## Run it

```sh
cp .env.dist .env      # public template; the host build needs no secret
mix deps.get
mix verify             # format, compile, Credo, audit, tests, coverage
mix run --no-halt
```

Open <http://localhost:4110>. The local web interface has no login; it is meant
for the trusted home network only.

## What you get

| URL | What |
|---|---|
| `http://localhost:4110` | Alarm editor, sessions, manual tests |
| `http://localhost:4110/mcp` | MCP endpoint (Streamable HTTP) for assistants |
| `http://127.0.0.1:4111` | **Hardware Lab**: emulate audio failures, network loss, clock trust, advance time |

The Hardware Lab drives the real domain processes, so a scenario you replay
there is the behaviour the device will have. See
[the emulator specification](../../specs/80-002-host-hardware-emulator/).

## Demo mode

The same server can run as a public demo with a photoreal 3D bedroom next to the
product app:

```sh
ROBINE_DEMO=1 ROBINE_DEMO_ACCESS_CODE=change-me mix run --no-halt
```

## Mobile app

The iOS / Android app lives in `mobile/` (Expo / React Native, written in
Gleam). On the device it talks to the clock over Wi-Fi.
