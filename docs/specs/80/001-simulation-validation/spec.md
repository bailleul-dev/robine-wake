# 80-001 — Simulation and Validation

## Purpose

Validate the camera-free alarm and its DIY tactile extension on host, then on
Raspberry Pi and the installed bed. Scope revised 2026-09-06; newly specified
checks are acceptance work, not claims that tests have already passed.

## Test pyramid

1. **Unit**: time calculation, session transitions, validation and bounded envelopes.
2. **Property**: no duplicate session, gain bounds, idempotence and stale ownership.
3. **Host integration**: supervisors with simulated audio and tactile adapters.
4. **Session scenarios**: breathing, music, alarm preemption and explicit controls.
5. **Firmware smoke**: boot, devices, actuator interface, network and storage.
6. **Hardware system**: measured audio/tactile timing, mounting, power and endurance.

## Simulation adapters

### Clock

A manually advanced virtual clock with separate UTC, time-zone and monotonic
values simulates NTP jumps, restart and DST without real sleeps.

### Audio and vibration

Record commands, timestamps, gain and owner; inject unavailability, latency,
transient failure, blocked generation, lost control or a crash. The tactile
adapter verifies envelopes, calibration limits and stop deadlines without hardware.
No camera adapter, image fixture or detector is required by the active product suite.

### Storage and network

Storage simulates partial writes, full disk and old schema versions, including
retired presence policies and exit candidates. Network simulates absence,
reconnection and late time synchronization.

## Minimum scenario catalog

IDs are never reused. Retired image scenarios remain listed for old reports.

| ID | Scenario | Expected result |
|---|---|---|
| `SIM-001` | Retired: confirmed bed exit | no longer a delivery gate |
| `SIM-002` | Retired: motion/stillness | no longer a delivery gate |
| `SIM-003` | Retired: camera loss | no longer a delivery gate |
| `SIM-004` | Retired: initially vacant bed | no longer a delivery gate |
| `SIM-005` | Retired: interrupted vacancy | no longer a delivery gate |
| `SIM-006` | three snoozes, then a fourth | fourth rejected; accepted snoozes silence outputs |
| `SIM-007` | restart while ringing | deadlines preserved; tactile restarts from calibrated initial level |
| `SIM-008` | clock jumps forward 10 minutes | catch-up policy applied |
| `SIM-009` | audio failure | retries, then critical error; controls remain available |
| `SIM-010` | Retired: saturated image | no longer a delivery gate |
| `SIM-011` | tactile enabled, then unavailable | sound and its strong deadline continue |
| `SIM-012` | physical dismissal / snooze / timeout | tactile silence within specified deadline |
| `SIM-013` | old `bed_exit` / `either` settings and exit candidate | manual policy and ringing recovery without retiming |
| `SIM-014` | obsolete observations and confirmation timers | no dismissal or escalation extension |
| `SIM-015` | 20 breathing cycles and phone disconnect | 4/6 timing continues and session ends locally |
| `SIM-016` | music pause, mute, lost source | both outputs silent |
| `SIM-017` | alarm preempts music or breathing | one tactile owner; stale commands ignored |
| `SIM-018` | invalid/missing tactile calibration | bounded rejection or inactive default; alarm still sounds |
| `SIM-019` | blocked tactile generator or lost control | electrical cutoff within one second; model residual mechanical decay; no runaway restart |
| `SIM-020` | camera-free startup and interface | no capture/detector worker, presence state or calibration command |

## Hardware validation milestones

- `VAL-HW-001`: Nerves boot and Pi 3 inventory, without a camera dependency;
- `VAL-HW-002`: HiFiBerry detection, playback, acoustic ceiling and startup latency;
- `VAL-HW-003`: retired — camera capture;
- `VAL-HW-004`: retired — nighttime visual calibration;
- `VAL-HW-005`: retired — bed-exit scenario;
- `VAL-HW-006`: eight-hour endurance and power-cycle recovery;
- `VAL-HW-007`: retired — annotated visual scenarios;
- `VAL-HW-008`: actuator/controller, stable addressing, dedicated power stage/supply and cutoff;
- `VAL-HW-009`: occupied slatted-bed mounting, distribution, floor noise and calibration;
- `VAL-HW-010`: breathing/music timing, wake escalation and explicit output shutdown;
- `VAL-HW-011`: physical dismissal and audible fallback with tactile/network loss;
- `VAL-HW-012`: camera-free boot, legacy data migration and clean UI/health/exports.

Record date, hardware/firmware versions, wiring, commands, measurements,
deviations and decisions for every active milestone. Document per-circuit peak
current with 25% supply margin, thermal measurements, stable fixation, synchronization
at start/end of sessions and behavior under forced output failures. Do not hide a
failed run by silently changing the calibration. Tactile timing and thermal
acceptance are specified in `30-004`. Exact frequency and faithful audio reproduction
are not gates; measure starting threshold, comfort, noise and motor coasting.

## Delivery gates

- P0: all active offline alarm tests, explicit physical controls, no duplicate
  trigger, audible fault reporting, legacy policy migration and camera-free startup;
- P0 hardware: `VAL-HW-001`, `VAL-HW-002`, `VAL-HW-006`, `VAL-HW-011`, `VAL-HW-012`;
- P1 tactile: `VAL-HW-008`, `VAL-HW-009`, `VAL-HW-010`, and endurance with vibration;
- no image dataset, optical acceptance or false-bed-exit metric remains required;
- disabled/unconfigured vibration must leave a fully usable audio-only product.

## Requirements

- `TST-001` — No domain test shall use real time or `sleep`.
- `TST-002` — Every P0 requirement shall link to at least one test.
- `TST-003` — Failure injection shall cover every active adapter.
- `TST-004` — Retired: seeded vision tests.
- `TST-005` — Hardware validations shall record versions and revisions.
- `TST-006` — Sensitive real-world data shall remain outside public repositories.
- `TST-007` — Tactile timing, limits, ownership and cutoff shall be reproducible
  with the host clock and simulated output.
- `TST-008` — Legacy camera/presence removal shall be verified across boot, alarms,
  active-session recovery, interfaces, health and exports.

## Acceptance criteria

One command runs the host suite and generates a report of active scenarios,
covered requirements and failures. Reports label retired IDs explicitly and must
not count their old test results as evidence for new vibration requirements.
Hardware records use the same format, with all tactile measurements attached.
