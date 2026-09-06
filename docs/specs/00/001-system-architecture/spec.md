# 00-001 — System Architecture

## Status

Product specification — scope revised 2026-09-06; implementation migration pending.

## Purpose

Define the product boundaries, components, contracts, and degradation rules.
This specification takes precedence when domains are ambiguous.

## Expected outcomes

- A configured alarm sounds at the intended local time, even when offline.
- DIY bed vibration supports breathing guidance, music bass, and progressive waking.
- Explicit user controls stop or snooze the alarm; no presence sensor is used.
- A vibration, network, or interface failure never suppresses an audible alarm.
- The system restarts in a deterministic state after power loss.

## Execution context

The product consists of Nerves firmware running on a Raspberry Pi 3 B/B+, a
HiFiBerry board, an independently powered vibration actuator fixed to the bed
frame, and local web/mobile interfaces. A motor driver or simple periodic-signal
generator controls the tactile output; a second audio card is optional. All
session timing and signal generation remain on the device; no camera is included.

## Logical components

| Component | Responsibility | Inputs | Outputs |
|---|---|---|---|
| `Clock` | provide reliable time | system clock, synchronization | UTC instant, local time |
| `AlarmScheduler` | compute the next trigger | alarms, time zone | `alarm_due` event |
| `WakeSession` | orchestrate one wake-up | clock, user events | audio/light/vibration commands, state |
| `AudioOutput` | play the alarm signal | playback commands | audio state and errors |
| `Vibration` | own tactile output and its limiter | breathing clock, music intensity envelope, wake commands | bounded tactile signal, health |
| `Settings` | validate and persist settings | UI/API commands | versioned snapshots |
| `WebUI` | expose controls and diagnostics | local HTTP | domain commands |
| `Telemetry` | publish structured metrics | internal events | logs, counters |

## Dependency direction

The domain layer depends on Elixir behaviours, never directly on ALSA, USB,
the filesystem, or the operating-system clock. Hardware adapters implement these
behaviours. `Host` adapters provide a controllable clock, fake audio output, and
a simulated tactile output with recorded commands and injected failures.

## OTP supervision

Recommended startup order:

1. configuration storage and validation;
2. clock and network state;
3. audio and optional vibration output;
4. scheduler and sessions;
5. web interface and telemetry.

Devices run under independent supervisors with a `one_for_one` strategy. A
vibration worker crash must not restart the scheduler. An active session has its own
dynamic supervisor.

## Normalized domain events

Every event includes `event_id`, `occurred_at_monotonic`, `occurred_at_utc`,
`source`, and `payload`.

- `alarm_due(alarm_id, scheduled_for)`
- `wake_session_started(session_id, alarm_id)`
- `audio_started(session_id)` / `audio_failed(reason)`
- `vibration_started(session_id, mode)` / `vibration_failed(reason)`
- `vibration_stopped(session_id, reason)`
- `session_snoozed(until)`
- `session_dismissed(reason)`
- `device_degraded(capability, reason)`

## Availability and degradation

| Failure | Required behaviour |
|---|---|
| network unavailable | previously saved local schedules remain operational |
| time not synchronized on first boot | expose status; do not blindly replay past alarms |
| vibration unavailable while enabled | stop tactile output, retain sound and physical controls, report degradation |
| vibration disabled/unconfigured | normal supported audio-only operation; no fault |
| HiFiBerry unavailable | try the configured fallback and report the error |
| storage unreadable | load safe defaults and expose degraded mode |
| crash during a session | restore the session if it remains in its active window |

## Performance budgets

- boot to operational scheduler: target below 20 seconds;
- trigger error after time stabilization: below 1 second;
- application memory at rest: target below 160 MiB;
- local UI response p95: below 500 ms;
- tactile timing and shutdown budgets: see `30/004-bed-vibration`.

## Requirements

- `ARCH-001` — The system shall boot and schedule alarms without a network.
- `ARCH-002` — Every hardware access shall be behind a testable behaviour.
- `ARCH-003` — Retired: former vision cancellation constraint.
- `ARCH-004` — Domain decisions shall use a monotonic clock for durations.
- `ARCH-005` — Persisted instants shall use UTC with a separate IANA time zone.
- `ARCH-006` — Events from one session shall share a correlation identifier.
- `ARCH-007` — Every degraded capability shall appear in health status.
- `ARCH-008` — The product shall not start camera capture or detection processes,
  infer bed presence, or use those signals to dismiss or delay an alarm.
- `ARCH-009` — A tactile failure shall not block audible alarms or physical controls.

## Acceptance criteria

1. On `host`, a full simulation proceeds from scheduled time through progressive
   vibration to physical dismissal without hardware dependencies.
2. Losing tactile output interrupts neither sound nor the wake session.
   A startup inspection confirms no camera/detector process or health dependency.
3. A simulated restart reloads alarms and settings without replaying an alarm
   whose catch-up window has expired.
4. All events from a scenario can be correlated to the same session.

