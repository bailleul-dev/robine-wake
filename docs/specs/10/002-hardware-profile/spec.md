# 10-002 — Hardware Profile

## Purpose

Define the camera-free hardware profile and the DIY bed-vibration extension.
Scope updated 2026-09-06; new hardware selection and validation remain pending.

## Bill of materials

| Item | Requirement | Remaining decision |
|---|---|---|
| compute | Raspberry Pi 3 B+ revision 1.3 (`a020d3`) | enclosure validation |
| storage | high-endurance microSD, at least 16 GiB | manufacturer/capacity |
| audio | HiFiBerry Amp2 with two passive speakers | acoustic validation |
| main power | regulated 16.5 V / 2 A through Amp2 for bring-up | measured margin with final peripherals |
| tactile control | dedicated motor driver or simple oscillator/amplifier | stable Nerves interface, progressive response and cutoff |
| tactile actuator | one enclosed vibrating motor or tactile shaker, frame-mounted | occupied-bed distribution, start threshold, inertia and noise |
| tactile power | dedicated external certified supply, low-voltage protection and cutoff | voltage/current, gain limit and thermal validation |
| control | physical dismiss/snooze button | installed button/link and end-to-end validation |
| time | external I²C RTC recommended when offline | model |

Camera and infrared illumination are removed from the bill of materials. There
is no bed-presence sensor. Tactile hardware is optional for operation, but its
three use cases are part of the P1 prototype scope.

The priority is felt vibration with progressive intensity. Accurate frequency,
audio reproduction and a second sound card are not hardware requirements.

## Integration constraints

HiFiBerry uses I²S and part of the GPIO header. Record conflicts with the physical
button, its radio link and any RTC before wiring. Keep speaker outputs on the
Amp2; a separate power stage drives the tactile actuator. GPIO may carry logic
commands to a compatible driver only, not actuator current. Do not bridge Amp2
outputs or power the actuator from GPIO or the Pi's 5 V rail. Protect a motor
driver against inductive transients and overcurrent; keep rotating masses captive.

The bed has a slatted base. Couple the actuator rigidly to a load-bearing frame
crossmember or to the surrounding casing only if it is structurally connected
to that frame. Use a removable plate; verify transmission through the slats and
mattress with the bed occupied. Dimensions and coverage of sleeping places remain
open. Isolation pads must not compromise bed stability or load capacity.

The enclosure must provide ventilation, cable retention, protected terminals,
restricted microSD access, and separation of hot parts from bedding. Verify each
power circuit with at least 25% margin over measured peak demand.

## Capability profile

At startup, adapters publish availability and manufacturer/model when detectable.
Select HiFiBerry and the chosen tactile interface by stable configuration. USB
audio is optional; if selected, its addressing must not depend on enumeration order.
Disabled or uncalibrated vibration is an explicit inactive state, not a fault.
Requested but unavailable vibration reports degradation without blocking sound.
Camera absence is normal and must not affect startup or health.

## Hardware decision register

| ID | Question | Expected evidence |
|---|---|---|
| `HW-DEC-001` | Raspberry Pi 3 B+ rev 1.3 (`a020d3`) | verified 2026-08-20 |
| `HW-DEC-002` | HiFiBerry Amp2 | verified with `hifiberry-dacplus` and stable card name |
| `HW-DEC-003` | Retired: camera candidate | removed 2026-09-06 |
| `HW-DEC-004` | Retired: IR illumination | removed 2026-09-06 |
| `HW-DEC-005` | power supplies | measured budget per circuit |
| `HW-DEC-006` | RTC requirement | intended offline behaviour |
| `HW-DEC-007` | actuator technology, count and mounting | trial enclosed motor first; shaker alternative if smoothness/noise requires it |
| `HW-DEC-008` | controller, power stage and tactile supply | logic interface, load/current, cutoff, coasting and temperature; no mandatory DAC |

## Requirements

- `HW-001` — Retired: illuminator power constraint.
- `HW-002` — Audio hardware shall be addressed by a stable identifier.
- `HW-003` — GPIO/I²C/I²S conflicts shall be documented before wiring.
- `HW-004` — Retired: camera framing.
- `HW-005` — Retired: camera-loss behavior.
- `HW-006` — The electrical budget shall include 25% margin over measured peak.
- `HW-007` — Tactile power shall use a dedicated protected circuit with no load
  on the Pi's GPIO/5 V power rails and no shared Amp2 speaker output.
- `HW-008` — Frame coupling, fixation, bed stability, distribution, thermal load
  and floor noise shall be validated on the actual occupied bed.
- `HW-009` — Audio and vibration devices shall remain correctly assigned across
  controller reconnect/restart; USB enumeration applies only if that variant is used.

## Acceptance criteria

Record assembly photographs, wiring, overlays, device detection, per-circuit
idle/load measurements, cutoff results, and a 30-minute wake/breathing run plus
prolonged music validation. Camera capture and optical tests are not gates.
See [bed vibration](../../30/004-bed-vibration/spec.md) and
[validation milestones](../../80/001-simulation-validation/spec.md).
