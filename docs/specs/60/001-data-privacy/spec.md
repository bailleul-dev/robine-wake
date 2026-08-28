# 60-001 — Data and Privacy

## Purpose

Define persisted data, its lifecycle, and protections appropriate for a camera
inside a bedroom.

## Data categories

| Category | Examples | Persisted | Default retention |
|---|---|---|---|
| configuration | alarms, time zone, volume | yes | until deleted |
| calibration | region, thresholds, statistics | yes | until recalibration |
| session | start, snoozes, terminal reason | yes | 30 days |
| telemetry | errors, latencies, health | bounded | 7 days |
| camera frames | pixels | no | volatile memory only |
| visual diagnostics | explicitly enabled capture | temporary | max. 10 minutes |
| secrets | Wi-Fi, password | protected | until replaced |

## Schemas and migrations

Every persisted document includes `schema_version`, `created_at`, and `updated_at`.
Writes use a temporary file, synchronization, and atomic rename, or an embedded
database with transactions. A previous valid backup is kept before migration.
A failed migration leaves the old data intact.

## Data minimization

Persisted observations contain only state, rounded confidence, and technical
reasons needed for diagnosis. No biometric identifier, silhouette, image
descriptor, or thumbnail is retained. Exports exclude secrets and temporary
captures.

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

- `DAT-001` — Frames shall not be persisted by default.
- `DAT-002` — Retention shall run automatically at boot and daily thereafter.
- `DAT-003` — Migrations shall be atomic and tested from every supported version.
- `DAT-004` — Exports shall contain no secrets.
- `DAT-005` — Logs shall be bounded by size and time.
- `DAT-006` — Diagnostic capture shall stop and erase itself automatically.
- `DAT-007` — Factory reset shall make application data inaccessible.

## Acceptance criteria

- Automated search for image signatures and secrets in generated files.
- Simulated power loss at every write/migration stage.
- Purge test with the clock advanced by 31 days.
- Inspection of both an export and a diagnostic bundle.

