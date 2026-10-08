# 20-002 — Wake Session

## Purpose

Orchestrate one alarm occurrence from trigger to completion by combining audio,
optional bed vibration, light, and explicit user commands.

## State machine

```text
scheduled -> starting -> ringing -> dismissed
                            +-> snoozed -> ringing
                            +-> failed_safe -> dismissed / snoozed / timed_out
                            +-> timed_out
```

`failed_safe` records an output failure. A tactile failure leaves the audio signal
active; exhausted audio retries expose the audible failure. Physical controls
remain available in either case. No state depends on bed observations.

## Startup

On `alarm_due`, persist the session before sending output commands. Start audio
without waiting for vibration hardware. If enabled and calibrated, the tactile
channel follows its own bounded progression from the same monotonic session clock.
No detector state is requested, and no presence condition can suppress startup.

## Two-stage audio

Every scheduled ringing period begins in the `gentle` audio phase at the alarm's
configurable pre-wake offset. Gain rises from the configured start level to its
ceiling exactly at the target wake time. It remains at that ceiling for five
minutes; if the session has not been dismissed or snoozed, playback then switches
to `strong_sound_id`, the phase becomes `strong`, and gain moves to the alarm's
strong level (`volume_profile.strong`, which defaults to the ceiling). The transition is recorded as `gentle_wake_escalated` so diagnostics can
distinguish a normal escalation from an audio failure.

Snoozing stops either phase. A snooze restart always begins again with the
gentle sound and a fresh ramp. Failure to prepare or start the strong sound
enters `failed_safe`, retains manual controls, and exposes the failure reason.

## Vibration and removal of automatic dismissal

The tactile wake motif is synthesized independently of the chosen audio track.
Its progression, limiter, calibration and stop rules are defined in
[bed vibration](../../30/004-bed-vibration/spec.md). Failure, readiness or completion
of the tactile ramp cannot move the gentle-to-strong audio deadline.

`exit_candidate` is retired. On recovery, map a legacy active candidate to
`ringing`, preserving elapsed time, snoozes and the original strong/timeout
deadlines. Historical terminal reasons remain readable but never drive new
actions. Ignore obsolete observations and confirmation timers; do not infer
presence, wakefulness or absence of response from vibration.

## Snooze and dismissal

Snooze fades out audio and vibration and schedules a monotonic restart. Default
maximum: 3 snoozes of 8 minutes each. Once the limit is reached, the command is rejected with an explicit response.

Manual dismissal is idempotent. Holding a physical button for more than 2
seconds may dismiss; a short press may snooze. Final thresholds require hardware
validation.

The firmware gate controls whether smartphone dismissal may be enabled. The
current product default is disabled and remote settings remain locked while the
gate is off, including when a legacy preference was enabled. Any firmware-authorized
permission is captured when a wake session starts and cannot be changed until that session ends. When
disabled, Wi-Fi, Bluetooth, web, and MCP dismissal commands are rejected; the
physical remote button and safety timeout remain available.

## Safety durations

- default maximum audible duration: 30 minutes;
- on expiry: reduce volume, stop vibration, mark `timed_out`, and keep a visible alert;
- restore a session across restart while still inside its active window;
- never reopen a completed session.

## Requirements

- `SES-001` — Session creation shall precede audio side effects.
- `SES-002` — All user commands shall be idempotent.
- `SES-003` — Retired: camera-input confirmation constraint.
- `SES-004` — Retired: continuous-vacancy confirmation.
- `SES-005` — Retired: return-to-bed cancellation.
- `SES-006` — The snooze limit shall survive restart.
- `SES-007` — A session shall have one timestamped terminal reason.
- `SES-008` — An undismissed gentle phase shall switch exactly once to the
  configured strong sound after the five-minute ceiling plateau.
- `SES-009` — The gentle ramp shall reach its configured ceiling at the target
  wake time independently of the selected pre-wake duration.
- `SES-010` — Smartphone dismissal permission shall be immutable for the full
  lifetime of an active wake session and enforced by the device.

- `SES-011` — Only authorized explicit commands or the safety timeout shall end
  ringing; legacy presence events/timers shall neither dismiss nor delay it.
- `SES-012` — Snooze, dismissal and timeout shall stop tactile output; resumption
  shall begin from the calibrated start, never jump to a previous high intensity.
- `SES-013` — Recovery shall migrate legacy exit candidates without resetting
  session deadlines or reopening completed sessions.

## Acceptance criteria

Mandatory Given/When/Then scenarios: physical dismissal, rejection of disabled
remote dismissal, maximum snooze count, repeated commands, restart while ringing,
legacy candidate recovery, ignored legacy observations/timers, gentle-to-strong
escalation with tactile output failed, and 30-minute timeout with tactile silence.
