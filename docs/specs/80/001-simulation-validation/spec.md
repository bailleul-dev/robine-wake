# 80-001 — Simulation and Validation

## Purpose

Enable full software progress before the camera arrives and before Raspberry Pi
access is available, then govern progressive hardware validation.

## Test pyramid

1. **Unit**: time calculation, session transitions, validation, and scoring.
2. **Property**: no duplicate session, volume bounds, and idempotence.
3. **Host integration**: supervisors with simulated adapters.
4. **Vision scenarios**: frame sequences with ground truth.
5. **Firmware smoke**: boot, devices, network, and storage.
6. **Hardware system**: measured audio, nighttime IR, power loss, and endurance.

## Simulation adapters

### Clock

A manually advanced virtual clock with separate UTC, time-zone, and monotonic
values. It simulates NTP jumps, restart, and DST transitions without real `sleep`.

### Audio

Records commands, timestamps, and gain; can inject unavailability, latency,
transient failure, or a crash. It verifies session identifiers.

### Camera

Reads fixtures as images or synthetic matrices with timestamps. It can lose,
delay, duplicate, or corrupt frames and change their quality.

### Storage and network

Storage simulates partial writes, full disk, and old schema versions. Network
simulates absence, reconnection, and late time synchronization.

## Minimum scenario catalog

| ID | Scenario | Expected result |
|---|---|---|
| `SIM-001` | alarm, occupied bed, 30-second exit | dismissed by bed exit |
| `SIM-002` | movement followed by stillness | alarm continues |
| `SIM-003` | camera lost while ringing | safe mode; sound continues |
| `SIM-004` | bed vacant before trigger | sound, then timed confirmation |
| `SIM-005` | vacancy for 20 seconds, then return | candidate cancelled |
| `SIM-006` | three snoozes, then a fourth | fourth rejected |
| `SIM-007` | restart while ringing | session restored |
| `SIM-008` | clock jumps forward 10 minutes | catch-up policy applied |
| `SIM-009` | audio failure | retries, then critical error |
| `SIM-010` | saturated image | `unknown` observation |

## Vision fixtures

Synthetic fixtures are preferred initially. Future real captures must be
consensual, restricted to the useful region, and anonymized where possible. A
manifest records origin, conditions, resolution, annotation, and license.
Sensitive fixtures are not committed to a public repository.

## Hardware validation milestones

- `VAL-HW-001`: Nerves boot and Pi 3 inventory;
- `VAL-HW-002`: HiFiBerry detection and WAV playback;
- `VAL-HW-003`: identify the received APKLVSR V0348/OV5647, then complete a
  stable 30-minute 320×240, 5 frames/s capture in darkness while recording
  stale frames, CPU load, undervoltage, IR switching, temperature, and current;
- `VAL-HW-004`: nighttime calibration in the target bedroom;
- `VAL-HW-005`: end-to-end scenario with bed exit;
- `VAL-HW-006`: 8-hour endurance run followed by power-cycle recovery;
- `VAL-HW-007`: campaign of 100 annotated scenarios.

Every milestone records date, hardware/firmware, commands, results, metrics,
deviations, and decision. An undocumented tuning change must not hide a failure.

For `VAL-HW-003`, preserve the output of camera enumeration, a redacted health
snapshot, firmware hash, camera-board photographs, power measurements with IR
off/on, maximum recorded temperatures, frame count, stale-frame count, and
process memory before/after. Nighttime sample pixels remain private test data
and are not committed to this repository.

## MVP delivery gates

- all P0 tests pass on `host`;
- state machines and critical errors are covered;
- property tests show no duplicate trigger;
- normal mode persists no pixels;
- `VAL-HW-001` through `VAL-HW-006` pass;
- false-dismissal targets are evaluated and documented;
- manual dismissal is tested with camera and network disconnected.

## Requirements

- `TST-001` — No domain test shall use real time or `sleep`.
- `TST-002` — Every P0 requirement shall link to at least one test.
- `TST-003` — Failure injection shall cover every adapter.
- `TST-004` — Vision results shall be reproducible with a fixed seed.
- `TST-005` — Hardware validations shall record versions and revisions.
- `TST-006` — Sensitive real-world data shall remain outside public repositories.

## Acceptance criteria

One command runs the host suite and generates a report of scenarios, covered
requirements, and failures. Hardware validation uses the same report format so
simulation and target results can be compared.
