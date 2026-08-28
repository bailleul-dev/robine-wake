# Robine Wake Specifications

## Purpose

Robine Wake is a standalone alarm clock built around a Raspberry Pi 3, Nerves,
a HiFiBerry audio output, and an infrared camera. Its primary purpose is to start
a progressive alarm and then determine locally whether the user has actually
left the bed.

This directory is the functional and technical source of truth until hardware
is available. Implementations and tests must reference the requirement IDs
defined here.

## Directory convention

Every specification uses the following path:

```text
docs/specs/<domain-id>/<feat-id>-<feature-name>/spec.md
```

IDs are stable. Changing a title must not change an ID already referenced by
code, tests, or tickets.

| Domain | Name | Responsibility |
|---|---|---|
| `00` | Product | goals, architecture, and vocabulary |
| `10` | Platform | Nerves, hardware, and device abstraction |
| `20` | Alarm | schedules, sessions, and state machines |
| `30` | Audio | playback, volume, and error recovery |
| `40` | Vision | IR camera and bed-exit detection |
| `50` | Interface | local configuration and API |
| `60` | Data | persistence, privacy, and security |
| `70` | Operations | observability and updates |
| `80` | Quality | simulation, testing, and hardware validation |

## Index

- [System architecture](00/001-system-architecture/spec.md)
- [Gentle awakening mechanisms](00/002-gentle-awakening-mechanisms/spec.md)
- [Nerves platform](10/001-nerves-platform/spec.md)
- [Hardware profile](10/002-hardware-profile/spec.md)
- [Alarm scheduling](20/001-alarm-scheduling/spec.md)
- [Wake session](20/002-wake-session/spec.md)
- [Audio output](30/001-audio-output/spec.md)
- [AirPlay receiver](30/002-airplay-receiver/spec.md)
- [Respiration guidée Hue et ambiance sonore](30/003-guided-breathing/spec.md)
- [Infrared camera](40/001-infrared-camera/spec.md)
- [Bed-exit detection](40/002-bed-exit-detection/spec.md)
- [Local interface](50/001-local-interface/spec.md)
- [HTTP Model Context Protocol](50/002-http-mcp/spec.md)
- [Data and privacy](60/001-data-privacy/spec.md)
- [Operations and updates](70/001-operations-updates/spec.md)
- [Simulation and validation](80/001-simulation-validation/spec.md)
- [Host hardware emulator](80/002-host-hardware-emulator/spec.md)

## Priorities

- **P0**: required for a reliable offline alarm.
- **P1**: required for the first complete prototype.
- **P2**: improvement that may be deferred until after prototype validation.

## Non-negotiable principles

1. The alarm must work without a network or camera.
2. A vision failure must never prevent the alarm from sounding.
3. Images remain in memory and are not recorded by default.
4. The functional core must be testable with `MIX_TARGET=host`.
5. Invalid configuration must not prevent the system from booting.
6. Time, time zone, and daylight-saving transitions are handled explicitly.

## Initial non-goals

- facial recognition or identifying a person;
- sending video to a cloud service;
- medical diagnosis or sleep analysis;
- always-on voice control;
- a native mobile application;
- support for multiple beds or multiple cameras.
