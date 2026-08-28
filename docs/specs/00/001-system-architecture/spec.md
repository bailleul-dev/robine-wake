# 00-001 — System Architecture

## Status

Proposed — version 1.0.

## Purpose

Define the product boundaries, components, contracts, and degradation rules.
This specification takes precedence when domains are ambiguous.

## Expected outcomes

- A configured alarm sounds at the intended local time, even when offline.
- The camera can confirm that a person has left the bed.
- Confirmation may stop the alarm according to the selected policy.
- A camera, network, or interface failure never suppresses an alarm.
- The system restarts in a deterministic state after power loss.

## Execution context

The product consists of Nerves firmware running on a Raspberry Pi 3 B/B+, a
HiFiBerry board, a CSI or USB infrared camera, an infrared illuminator, and a
web interface available on the local network. Video processing runs entirely
on the device.

## Logical components

| Component | Responsibility | Inputs | Outputs |
|---|---|---|---|
| `Clock` | provide reliable time | system clock, synchronization | UTC instant, local time |
| `AlarmScheduler` | compute the next trigger | alarms, time zone | `alarm_due` event |
| `WakeSession` | orchestrate one wake-up | clock, vision, user events | audio commands, state |
| `AudioOutput` | play the alarm signal | playback commands | audio state and errors |
| `Camera` | produce normalized images | capture commands | timestamped frames |
| `BedDetector` | produce observations | frames | presence, motion, confidence |
| `Settings` | validate and persist settings | UI/API commands | versioned snapshots |
| `WebUI` | expose controls and diagnostics | local HTTP | domain commands |
| `Telemetry` | publish structured metrics | internal events | logs, counters |

## Dependency direction

The domain layer depends on Elixir behaviours, never directly on ALSA, V4L2,
the filesystem, or the operating-system clock. Hardware adapters implement these
behaviours. `Host` adapters provide a controllable clock, fake audio output, and
recorded or synthetic image streams.

## OTP supervision

Recommended startup order:

1. configuration storage and validation;
2. clock and network state;
3. audio and camera;
4. detector;
5. scheduler and sessions;
6. web interface and telemetry.

Devices run under independent supervisors with a `one_for_one` strategy. A
camera crash must not restart the scheduler. An active session has its own
dynamic supervisor.

## Normalized domain events

Every event includes `event_id`, `occurred_at_monotonic`, `occurred_at_utc`,
`source`, and `payload`.

- `alarm_due(alarm_id, scheduled_for)`
- `wake_session_started(session_id, alarm_id)`
- `audio_started(session_id)` / `audio_failed(reason)`
- `bed_observation(occupied, motion_score, confidence)`
- `bed_exit_candidate_started`
- `bed_exit_confirmed`
- `session_snoozed(until)`
- `session_dismissed(reason)`
- `device_degraded(capability, reason)`

## Availability and degradation

| Failure | Required behaviour |
|---|---|
| network unavailable | previously saved local schedules remain operational |
| time not synchronized on first boot | expose status; do not blindly replay past alarms |
| camera unavailable | use a normal audio alarm and keep manual dismissal available |
| uncertain detection | continue the alarm; do not confirm a bed exit |
| HiFiBerry unavailable | try the configured fallback and report the error |
| storage unreadable | load safe defaults and expose degraded mode |
| crash during a session | restore the session if it remains in its active window |

## Performance budgets

- boot to operational scheduler: target below 20 seconds;
- trigger error after time stabilization: below 1 second;
- application memory at rest: target below 160 MiB;
- video analysis: 2–5 frames/s at 320×240 or 640×480;
- observation-to-decision latency: below 1 second;
- local UI response p95: below 500 ms, excluding image capture.

## Requirements

- `ARCH-001` — The system shall boot and schedule alarms without a network.
- `ARCH-002` — Every hardware access shall be behind a testable behaviour.
- `ARCH-003` — Vision shall never silently cancel an alarm.
- `ARCH-004` — Domain decisions shall use a monotonic clock for durations.
- `ARCH-005` — Persisted instants shall use UTC with a separate IANA time zone.
- `ARCH-006` — Events from one session shall share a correlation identifier.
- `ARCH-007` — Every degraded capability shall appear in health status.

## Acceptance criteria

1. On `host`, a full simulation proceeds from scheduled time to confirmed bed
   exit without hardware dependencies.
2. Removing the camera stream during a simulation interrupts neither sound nor
   the wake session.
3. A simulated restart reloads alarms and settings without replaying an alarm
   whose catch-up window has expired.
4. All events from a scenario can be correlated to the same session.

