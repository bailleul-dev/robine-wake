# 50-001 — Local Interface

## Purpose

Allow configuration and control from a browser on the local network without
making alarm operation depend on that browser.

## MVP screens

1. **Home**: next alarm, device time, and audio/vibration/network health.
2. **Alarms**: list, create, edit, enable, disable, and delete.
3. **Active wake session**: sound and tactile intensity, snooze, and dismissal according to device policy.
4. **Vibration**: per-use activation/intensity, bed calibration, short test and stop.
5. **Diagnostics**: versions, uptime, storage, and recent redacted events.
6. **Maintenance**: configuration export, restart, and signed update.

## Domain API

Mutating routes carry a CSRF token and resource revision. They call domain
services and never control ALSA, the tactile power stage, or an OTP process directly. Errors
use stable codes: `validation_failed`, `revision_conflict`,
`capability_unavailable`, `not_found`, `rate_limited`, and `internal_error`.

## Real-time state

The interface receives updates through LiveView or a local channel: next
occurrence, session state, volume, tactile mode/intensity, and health. Camera
views, bed-presence indicators, confidence, calibration and capture commands are
removed across web and mobile clients. No replacement presence indicator is shown.
Old clients cannot reactivate these capabilities; retired commands return an
explicit unsupported-capability error. Remote dismissal stays subject to the
physical-stop policy, disabled by default.

## Accessibility and safety

- keyboard-operable interface with readable contrast in a dark bedroom;
- clearly distinct dismissal and snooze actions;
- confirmation before deleting an alarm;
- clear display of maximum volume;
- a single alarm editor that explains the gentle-to-strong sound journey and
  keeps both sound choices visible together;
- dates displayed with time zone and unsynchronized-time warning;
- color is never the sole carrier of health information.

## Local access

The service listens only on configured interfaces and exposes the UI directly,
without login or password, on the trusted local network. Browser mutations keep
their CSRF protection. Inbound Internet access is not planned; SSH and signed
firmware updates retain their independent authentication.

## Requirements

- `UI-001` — An alarm shall be fully configurable without an IEx console.
- `UI-002` — The next UTC and local occurrence shall be previewed before saving.
- `UI-003` — Degraded state shall identify the capability and user impact.
- `UI-004` — No continuous video stream shall be exposed.
- `UI-005` — Concurrent writes shall use resource revisions.
- `UI-006` — Dismiss and snooze shall acknowledge visually within 500 ms.
- `UI-007` — Secrets shall never be returned by the API.
- `UI-008` — Alarm creation and editing shall expose progressive and strong
  sound selection, ramp controls, recurrence, snooze, and dismissal in one
  keyboard-operable screen.

- `UI-009` — Web/mobile state, screens and APIs shall not expose camera or presence
  functionality; retired capture/calibration commands shall have no side effects.
- `UI-010` — Vibration controls shall expose independent use profiles, calibration,
  bounded test/stop and capability state without changing the audible gain ceiling.

## Acceptance criteria

Automated journeys cover recurring-alarm creation, edit conflict, active session,
two-stage sound selection, missing tactile output, untrusted time, and tactile
calibration. Verify that no camera/presence screen or active command remains.
Essential screens pass keyboard, responsive-layout, and contrast review. A
network test confirms no listening on unconfigured interfaces.
