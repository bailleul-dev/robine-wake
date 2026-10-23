---
title: Architecture
description: The components of Robine Wake and how they degrade.
sidebar:
  order: 2
---

```text
 iOS / Android app ──Wi-Fi──┐
 Browser / MCP client ──────┤        ┌──────────────────────────┐
 AirPlay · Bluetooth A2DP ──┼──────▶ │ Raspberry Pi · Nerves    │──I2S──▶ amplifier ─▶ speakers
                            │        │ Elixir/OTP application   │
 Bedside remote (LoRa) ─────┘        │  scheduler · wake session│──UART─▶ ESP32 ─▶ WS2812B strip
                                     └──────────────────────────┘
```

## Pi: the master

The Raspberry Pi runs a Nerves firmware with an Elixir/OTP application. It owns
time, alarms and the wake-session state machine. Everything else is an actuator
or a client:

- **Scheduler** — supervised, duplicate-proof, recovers after a restart or a
  clock jump with a bounded catch-up window, and refuses to arm while the
  device clock is untrusted.
- **Wake session** — restart-recoverable state machine: gentle then strong
  stage, volume ramp, snooze, manual dismissal, timeout, fail-safe.
- **Audio** — ALSA output with automatic amplifier detection, mixer volume,
  an AirPlay receiver and a Bluetooth A2DP receiver. An alarm always has
  priority over music on the shared device.
- **Local interface** — web UI and JSON API, plus an MCP endpoint.

## ESP32: a dumb light

The light strip is driven by an ESP32 that receives `light.program` /
`light.set` commands over UART and computes each frame from its own clock, so a
sunrise stays smooth even if the Pi is busy. The Pi's Elixir code is the
reference; the ESP32 firmware (Rust, `no_std`) holds no policy.

## Degradation rules

A light, vibration, network or interface failure **never** suppresses the
audible alarm. After a power loss the system restarts in a deterministic state.
The alarm works offline.

Details: [system architecture specification](../../specs/00-001-system-architecture/).

## Why Nerves

A read-only root filesystem, atomic A/B firmware slots, signed updates, a
single Erlang VM supervising everything. See the
[platform specification](../../specs/10-001-nerves-platform/) and
[operations & updates](../../specs/70-001-operations-updates/).
