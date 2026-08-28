# 20-002 — Wake Session

## Purpose

Orchestrate one alarm occurrence from trigger to completion by combining audio,
bed detection, and user commands.

## State machine

```text
scheduled -> starting -> ringing -> exit_candidate -> dismissed
                            |  ^          |
                            |  +----------+ (presence detected again)
                            +-> snoozed -> ringing
                            +-> failed_safe
```

`failed_safe` means vision or an auxiliary function failed: the audio signal
remains active and manual dismissal remains available.

## Startup

On `alarm_due`, the session is persisted before the audio command is sent. It
then requests an initial detector state. If the bed is already vacant, the
default policy is still to sound and require 30 seconds of vacancy after session
start. This prevents an obstructed camera from suppressing sound.

## Two-stage audio

Every scheduled ringing period begins in the `gentle` audio phase at the alarm's
configurable pre-wake offset. Gain rises from the configured start level to its
ceiling exactly at the target wake time. It remains at that ceiling for five
minutes; if the session has not been dismissed or snoozed, playback then switches
to `strong_sound_id`, the phase becomes `strong`, and gain remains at the alarm
ceiling. The transition is recorded as `gentle_wake_escalated` so diagnostics can
distinguish a normal escalation from an audio failure.

Snoozing stops either phase. A snooze restart always begins again with the
gentle sound and a fresh ramp. Failure to prepare or start the strong sound
enters `failed_safe`, retains manual controls, and exposes the failure reason.

## Bed exit

A sufficiently confident `vacant` observation opens `exit_candidate`. Its timer
uses monotonic duration. Any reliable `occupied` observation cancels the
candidate. On expiry, `bed_exit_confirmed` permits dismissal only if the alarm's
policy includes `bed_exit`.

Initial values are: 30-second confirmation, 0.75 minimum confidence, and a
5-second grace period after session start. Values are configurable within safe
bounds.

## Snooze and dismissal

Snooze fades out audio, suspends bed-exit interpretation, and schedules a
monotonic restart. Default maximum: 3 snoozes of 8 minutes each. Once the limit
is reached, the command is rejected with an explicit response.

Manual dismissal is idempotent. Holding a physical button for more than 2
seconds may dismiss; a short press may snooze. Final thresholds require hardware
validation.

A persistent global setting controls whether a smartphone may dismiss an alarm.
The default remains enabled for backward compatibility. Its value is captured
when a wake session starts and cannot be changed until that session ends. When
disabled, Wi-Fi, Bluetooth, web, and MCP dismissal commands are rejected; the
physical remote button, confirmed bed exit, and safety timeout remain available.

## Safety durations

- default maximum audible duration: 30 minutes;
- on expiry: reduce volume, mark `timed_out`, and keep a visible alert;
- restore a session across restart while still inside its active window;
- never reopen a completed session.

## Requirements

- `SES-001` — Session creation shall precede audio side effects.
- `SES-002` — All user commands shall be idempotent.
- `SES-003` — Missing camera input shall never produce `bed_exit_confirmed`.
- `SES-004` — Bed exit shall be confirmed only after continuous vacancy.
- `SES-005` — Returning to bed shall cancel an exit candidate.
- `SES-006` — The snooze limit shall survive restart.
- `SES-007` — A session shall have one timestamped terminal reason.
- `SES-008` — An undismissed gentle phase shall switch exactly once to the
  configured strong sound after the five-minute ceiling plateau.
- `SES-009` — The gentle ramp shall reach its configured ceiling at the target
  wake time independently of the selected pre-wake duration.
- `SES-010` — Smartphone dismissal permission shall be immutable for the full
  lifetime of an active wake session and enforced by the device.

## Acceptance criteria

Mandatory Given/When/Then scenarios: normal exit, 10-second false exit, camera
disconnection, maximum snooze count, simultaneous UI/button dismissal, restart
while ringing, initially vacant bed, gentle-to-strong escalation, and 30-minute
timeout.
