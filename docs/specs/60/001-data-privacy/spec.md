# 60-001 — Data and Privacy

## Purpose

Define minimal local data and its lifecycle for a camera-free bedroom alarm
with optional tactile output.

## Data categories

| Category | Examples | Persisted | Default retention |
|---|---|---|---|
| configuration | alarms, time zone, volume | yes | until deleted |
| calibration | acoustic/tactile limits, mounting profile | yes | until recalibration |
| session | start, snoozes, terminal reason | yes | 30 days |
| telemetry | errors, latencies, health | bounded | 7 days |
| camera/presence data | retired configuration and observations | no new collection | remove legacy settings during migration |
| secrets | Wi-Fi, password | protected | until replaced |

## Schemas and migrations

Every persisted document includes `schema_version`, `created_at`, and `updated_at`.
Writes use a temporary file, synchronization, and atomic rename, or an embedded
database with transactions. A previous valid backup is kept before migration.
A failed migration leaves the old data intact.

## Data minimization

No images, presence observations, motion scores, confidence or biometric data
are collected. Technical output diagnostics contain mode, bounded gain, timing
and errors only; vibration is never interpreted as a measurement of the sleeper.
Exports exclude secrets and legacy detection configuration.

During atomic migration, remove detection profiles, ROI/polygons, capture settings
and any legacy image/visual-diagnostic artifacts from active data. Normalize old
dismissal policies to `manual`; ignore retired fields received from older clients
or reject retired commands explicitly. Missing vibration settings mean disabled.
Preserve existing alarms and their times, and retain historical session terminal
reasons only under normal 30-day retention. A migration backup follows the existing
restricted-access and retention policy and is never exported as current configuration.

## Security

- passwords hashed with an algorithm suitable for Pi resources;
- Wi-Fi secrets excluded from logs and exports;
- authenticated firmware updates;
- protected administration endpoints;
- login-attempt rate limiting;
- least-privilege permissions on the data partition;
- tokens generated using a cryptographically secure random source.

Full microSD encryption at rest is not guaranteed by the MVP and must be
documented as a physical-security limitation. Stored secrets should therefore
not grant access to other high-value services.

## User commands

The user can review history, erase it, export non-secret configuration, and
restore factory settings. Reset removes configuration, sessions, network data,
and diagnostics through a documented procedure.

## Requirements

- `DAT-001` — Retired: former frame-persistence rule; see `DAT-008`.
- `DAT-002` — Retention shall run automatically at boot and daily thereafter.
- `DAT-003` — Migrations shall be atomic and tested from every supported version.
- `DAT-004` — Exports shall contain no secrets.
- `DAT-005` — Logs shall be bounded by size and time.
- `DAT-006` — Retired: temporary visual diagnostics are removed.
- `DAT-007` — Factory reset shall make application data inaccessible.

- `DAT-008` — The product shall collect no camera/presence data and expose none
  through current state or exports.
- `DAT-009` — Atomic migration shall remove legacy detection configuration and
  normalize dismissal policies without losing or retiming alarms.
- `DAT-010` — Persisted tactile calibration shall contain validated bounded levels
  and no inferred physiological or presence measurements.

## Acceptance criteria

- Automated search for image signatures and secrets in generated files.
- Simulated power loss at every write/migration stage.
- Purge test with the clock advanced by 31 days.
- Inspection of both an export and a diagnostic bundle.
- Legacy profile/policy migration and rejected retired commands preserve alarms;
  no detection configuration remains in current exports or active state.

