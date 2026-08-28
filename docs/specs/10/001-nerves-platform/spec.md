# 10-001 — Nerves Platform

## Purpose

Define firmware construction, boot, configuration, and updates for Raspberry
Pi 3.

## Targets

- `host`: development and testing without hardware;
- `rpi3`: Raspberry Pi 3 B/B+ using the official Nerves system where possible;
- `robine_rpi3`: derived system if camera drivers, HiFiBerry overlays, or native
  packages are absent from the official system.

The final choice between `rpi3` and `robine_rpi3` is made after hardware spike
`VAL-HW-001`. Application code must not depend on that choice.

## Target application structure

```text
lib/robine_wake/             domain logic
lib/robine_wake/adapters/    host and target implementations
lib/robine_wake_web/         local interface
config/                      compile-time and runtime configuration
rootfs_overlay/              target-specific files when required
test/                        unit and host integration tests
test/fixtures/vision/        anonymized or synthetic sequences
```

## Configuration

Compile-time configuration contains structural choices only: adapter modules,
target, and included capabilities. Runtime configuration contains the network
name, time zone, ALSA device, and camera settings. Secrets are neither compiled
into firmware nor written to logs.

Priority order is: validated persisted values, factory provisioning, defaults.
A migration transforms older versions before exposing them to the domain.

## Network and time

- Ethernet is the preferred maintenance connection for the first prototype.
- Wi-Fi is optional and provisioned without logging the password.
- The system clock synchronizes through NTP whenever a network is available.
- Without NTP, the device retains the last known time if hardware allows it; an
  external RTC is recommended for a durable deployed product.
- An alarm is armed only when time quality is `trusted`, or after the user
  explicitly confirms local time following boot.

## Safe boot

Firmware exposes `booting`, `ready`, `degraded`, and `maintenance` states. New
firmware is validated only after configuration is readable, the scheduler is
alive, audio is initialized or declared degraded, and the local server is
reachable. If validation does not occur within the allotted time, the previous
firmware must remain recoverable.

## Watchdog and recovery

The watchdog is fed only while the root supervisor, scheduler, and event loop
respond. Device crashes use exponential restart delays capped at 60 seconds to
avoid restart loops.

## Requirements

- `NRV-001` — `MIX_TARGET=host mix test` shall require no Raspberry Pi tooling.
- `NRV-002` — Target firmware shall be reproducible from the repository and lockfile.
- `NRV-003` — Runtime settings shall be validated before publication.
- `NRV-004` — The system shall continue in degraded mode without camera or audio.
- `NRV-005` — Unvalidated firmware shall be able to revert to its predecessor.
- `NRV-006` — No secret shall appear in public firmware, logs, or diagnostics.
- `NRV-007` — Clock health shall be observable by the domain layer.

## Acceptance criteria

- The project compiles and tests on macOS/Linux for target `host`.
- A firmware image is generated for `rpi3` without manual changes.
- Corrupt configuration produces a documented degraded boot.
- A simulated adapter failure is contained by its supervisor.

