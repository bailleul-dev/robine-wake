# Robine Wake Specifications

## Purpose

Robine Wake is a standalone alarm clock built around a Raspberry Pi 3, Nerves,
a HiFiBerry audio output, and a DIY bed-vibration channel. It provides a
progressive alarm, guided breathing, and music with tactile bass. Alarm dismissal
uses explicit user controls; the product does not detect bed presence or bed exit.

This directory is the functional and technical source of truth. Implementations and tests must reference the requirement IDs
defined here.

## Scope decision — 2026-09-06

Camera capture, infrared illumination, vision processing, bed-exit detection and
automatic dismissal from presence are removed, not deferred. No replacement
presence sensor is planned. The retired `40` specifications preserve their IDs
for historical references. The DIY vibration feature is P1, individually
optional for each use; offline audible alarms remain P0. Implementation of this
scope change is pending: existing camera code is not evidence of an active feature.

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
| `30` | Sound and vibration | audio, breathing, tactile output and error recovery |
| `40` | Retired | former camera and bed-exit specifications; no active feature |
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
- [Vibration DIY du lit](30/004-bed-vibration/spec.md)
- [Local interface](50/001-local-interface/spec.md)
- [HTTP Model Context Protocol](50/002-http-mcp/spec.md)
- [Data and privacy](60/001-data-privacy/spec.md)
- [Operations and updates](70/001-operations-updates/spec.md)
- [Simulation and validation](80/001-simulation-validation/spec.md)
- [Host hardware emulator](80/002-host-hardware-emulator/spec.md)

### Retired specifications

- [Infrared camera — retired](40/001-infrared-camera/spec.md)
- [Bed-exit detection — retired](40/002-bed-exit-detection/spec.md)

## Priorities

- **P0**: required for a reliable offline alarm.
- **P1**: required for the first complete prototype.
- **P2**: improvement that may be deferred until after prototype validation.

## Non-negotiable principles

1. The alarm must work without a network or vibration hardware.
2. A vibration failure must never prevent the alarm from sounding or being stopped.
3. No camera capture, presence inference, or automatic bed-exit dismissal is part of the product.
4. The functional core must be testable with `MIX_TARGET=host`.
5. Invalid configuration must not prevent the system from booting.
6. Time, time zone, and daylight-saving transitions are handled explicitly.

## Initial non-goals

- facial recognition or identifying a person;
- sending video to a cloud service;
- medical diagnosis or sleep analysis;
- always-on voice control;
- camera hardware, infrared capture, or bed-presence sensors;
- automatic alarm dismissal based on presence;
- support for multiple beds.
