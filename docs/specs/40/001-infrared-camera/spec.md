# 40-001 — Infrared Camera — Retired

## Status

Retired on 2026-09-06 by product decision. This feature is removed, not deferred.
Camera hardware, capture, infrared illumination, calibration, and image processing
are outside the product scope. No replacement presence sensor is planned.

This file preserves the specification identity for existing code, tests, and
historical reports. Earlier design details remain available in Git history;
they are not implementation or hardware acceptance requirements.

## Retired requirements

- `CAM-001` — Retired; no longer a delivery gate.
- `CAM-002` — Retired; no longer a delivery gate.
- `CAM-003` — Retired; no longer a delivery gate.
- `CAM-004` — Retired; no longer a delivery gate.
- `CAM-005` — Retired; no longer a delivery gate.
- `CAM-006` — Retired; no longer a delivery gate.
- `CAM-007` — Retired; no longer a delivery gate.

## Migration

Remove the corresponding runtime services, configuration, UI/API controls, and
health dependencies. Legacy observations must not stop or delay an active alarm.
Existing software has not been removed by this documentation change.

See [system architecture](../../00/001-system-architecture/spec.md),
[wake session](../../20/002-wake-session/spec.md), and
[bed vibration](../../30/004-bed-vibration/spec.md) for the active product contract.
