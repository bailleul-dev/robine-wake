# 70-001 — Operations and Updates

## Purpose

Make the alarm clock observable, recoverable, and updateable without compromising
its primary function or bedroom privacy.

## Health

Overall state is `healthy`, `degraded`, or `unhealthy`. It aggregates clock,
scheduler, storage, audio, camera, detector, network, and firmware. Every
capability exposes state, last success, last redacted error, and restart count.

Missing network or camera may make the product `degraded`; only an unavailable
scheduler, critical storage failure, or crash loop makes it `unhealthy`.

## Logs and telemetry

Logs are structured with UTC timestamp, level, component, event code, optional
session/alarm ID, and redacted fields. Prohibited content includes pixels,
passwords, an SSID marked sensitive, and authentication request bodies.

Minimum metrics: uptime, BEAM memory, process restarts, clock drift/confidence,
scheduled/triggered/missed alarms, audio latency, camera frame rate, dropped
frames, observation distribution, bed-exit decisions, and errors.

## Diagnostic bundle

A local export contains versions, non-secret configuration, health, metrics,
and recent logs. It never contains a frame or secret. A manifest lists every
file and its digest.

## Updates

Firmware carries a semantic version, build ID, schema compatibility, and
signature. Before installation, verify signature, target, and space. After boot,
run the validation checks from `10-001`. An update does not begin during a wake
session or within 15 minutes before the next alarm, except under an explicit
maintenance command.

## Local alerts

A critical error appears on the home screen and in diagnostics. If an indicator
light exists, patterns remain simple and documented. No cloud service is
required to report status.

## Requirements

- `OPS-001` — Every capability shall publish an explainable health state.
- `OPS-002` — Logs and metrics shall be bounded.
- `OPS-003` — A diagnostic bundle shall exclude pixels and secrets.
- `OPS-004` — Only authenticated, compatible firmware shall be installable.
- `OPS-005` — Updates shall avoid the critical window around an alarm.
- `OPS-006` — Unhealthy new firmware shall not be validated.
- `OPS-007` — Critical events shall survive a controlled restart.

## Acceptance criteria

Tests cover log saturation, automated inspection of diagnostics, rejection of
invalid firmware signatures, simulated rollback, update refusal at T−10 minutes,
and a consistent health table for every missing peripheral.

