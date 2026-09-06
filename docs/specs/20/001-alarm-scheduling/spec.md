# 20-001 — Alarm Scheduling

## Purpose

Manage alarm creation, recurrence, and reliable triggering in an explicit time
zone.

## `Alarm` model

| Field | Type | Rule |
|---|---|---|
| `id` | UUID | immutable |
| `label` | string, 0–80 chars | user-provided text |
| `enabled` | boolean | defaults to `true` |
| `local_time` | time | minute precision |
| `days_of_week` | set | empty for a one-time alarm |
| `one_shot_date` | optional date | required when non-recurring |
| `timezone` | IANA name | e.g. `Europe/Paris` |
| `sound_id` | identifier | progressive-wake sound; must be available |
| `strong_sound_id` | identifier | fallback sound after the gentle ramp; must be available |
| `prewake_seconds` | integer, 0–3600 | how long before `local_time` the gentle phase starts |
| `volume_profile` | structure | start, ceiling, ramp duration |
| `dismiss_policy` | enum | `manual` only; migrate legacy `bed_exit` and `either` to `manual` |
| `vibration_profile` | structure | enabled, calibrated start/ceiling, progression duration; disabled until configured |
| `snooze` | structure | enabled, duration, maximum count |
| `revision` | integer | optimistic concurrency control |

## Legacy presence settings

Migrate stored `bed_exit` and `either` policies to `manual` atomically, preserving
alarm IDs, schedules, sound choices, revisions, and snooze settings. New writes
using retired policies are rejected with `validation_failed`; they must never
reactivate a detector. Old presence settings cannot prevent boot or arming.
Missing vibration settings default to disabled until the bed has been calibrated.

## Next-trigger calculation

The scheduler computes a UTC instant from local rules. During a daylight-saving
time transition:

- nonexistent local time: trigger at the first valid local minute;
- repeated local time: trigger once, at the first occurrence;
- changing the time zone recalculates every next occurrence;
- session and snooze durations use the monotonic clock.

The configured local time remains the target wake time. The scheduler starts the
gentle session `prewake_seconds` earlier and retains the target occurrence for
deduplication and history. Any modification invalidates the previous timer.

## Catch-up window

After restart, an alarm less than 5 minutes late triggers once if no corresponding
session has been recorded. Beyond that window it is marked `missed` and shown in
history without playback. The window is configurable from 0 to 15 minutes.

## Commands

- create, update, enable, disable, and delete an alarm;
- preview the next five occurrences;
- test a sound without creating a real wake session;
- trigger an immediate session for testing.

## Requirements

- `ALM-001` — An enabled alarm shall have exactly one next occurrence.
- `ALM-002` — One occurrence shall create no more than one session.
- `ALM-003` — Calculation shall follow the configured IANA zone and DST rules.
- `ALM-004` — Updating an alarm shall atomically cancel its previous timer.
- `ALM-005` — A one-time alarm shall be disabled after creating its session.
- `ALM-006` — A late boot shall apply the catch-up window.
- `ALM-007` — An untrusted clock shall prevent silent arming.
- `ALM-008` — An alarm shall reference one available progressive sound and one
  available strong fallback sound.
- `ALM-009` — The configurable pre-wake duration shall be available through the
  Web and mobile alarm editors.

- `ALM-010` — Migration shall convert legacy presence dismissal to manual without
  losing or retiming alarms; new presence policies shall be rejected.
- `ALM-011` — Each alarm shall persist a separately bounded vibration profile,
  disabled by default for existing alarms.

## Acceptance criteria

- Deterministic tests before, during, and after two DST transitions.
- Restart tests at +2 minutes and +10 minutes after scheduled time.
- Concurrent-update test rejecting a stale revision.
- Validation tests for unavailable progressive and strong sound identifiers.
- 10,000 recalculations without a duplicate trigger.
- Legacy policy migration preserves schedules; unsupported policy writes fail.
- Invalid vibration bounds are rejected without changing the stored alarm.
