# 10-002 — Hardware Profile

## Purpose

Define hardware assumptions, electrical interfaces, and decisions to confirm
when components become available.

## Minimum bill of materials

| Item | Minimum requirement | Deferred decision |
|---|---|---|
| compute | Raspberry Pi 3 B+ revision 1.3 (`a020d3`) | enclosure validation |
| storage | high-endurance microSD, at least 16 GiB | manufacturer/capacity |
| audio | HiFiBerry Amp2 with two passive speakers | acoustic validation |
| camera | APKLVSR V0348 candidate, OV5647, 15-pin CSI, advertised 130° | received-board verification |
| illumination | two V0348-mounted 850 nm auto-switched IR boards | current, temperature, threshold, and beam validation |
| power | regulated 16.5 V / 2 A supply through Amp2 for bring-up | measured margin with camera/IR |
| control | physical dismiss/snooze button recommended | GPIO and model |
| time | external I²C RTC recommended when offline | model |

## Integration constraints

HiFiBerry generally uses I²S and part of the GPIO header. The selected candidate
camera uses the Pi 3 dedicated 15-pin CSI connector, so it has no planned GPIO
signal conflict with the HiFiBerry. The V0348 IR boards appear to receive power
through their mechanical connection to the camera board; their actual rail,
current, switching behavior, and interaction with the CSI supply are unknown
until inspection. They must not be wired to or powered directly by a GPIO.
Grounding and current requirements must be verified before enclosure use.

The enclosure must provide ventilation, restrict microSD access, prevent direct
IR glare, secure the camera cable, and keep hot parts out of reach. The camera
must cover the bed without unnecessarily filming the rest of the room.

## Infrared considerations

- 850 nm: generally better sensitivity, with a possibly visible red glow.
- 940 nm: more discreet, often with shorter range at equal power.
- Illumination must be diffuse and avoid saturated hot spots.
- Exposure and gain must be lockable after calibration.
- A visible indicator or the UI must show when camera analysis is active.

## Capability profile

At startup, every adapter publishes `available`, `degraded`, or `unavailable`,
with manufacturer/model when detectable. The product must not assume ALSA device
0 is the HiFiBerry; it selects audio by stable name or validated configuration.

## Hardware decision register

| ID | Question | Expected evidence |
|---|---|---|
| `HW-DEC-001` | Raspberry Pi 3 B+ rev 1.3 (`a020d3`) | verified from `/proc/cpuinfo` on 2026-08-20 |
| `HW-DEC-002` | HiFiBerry Amp2 | verified with `hifiberry-dacplus`, card `snd_rpi_hifiberry_dacplus` |
| `HW-DEC-003` | APKLVSR V0348 CSI candidate | ASIN `B0CLGTM3Z8`; confirm received OV5647 identity |
| `HW-DEC-004` | integrated 850 nm IR candidate | real nighttime, power, and thermal test |
| `HW-DEC-005` | power supply | measured current budget |
| `HW-DEC-006` | RTC requirement | intended offline behaviour |

## Requirements

- `HW-001` — No GPIO shall directly power the illuminator.
- `HW-002` — Audio hardware shall be addressed by a stable identifier.
- `HW-003` — GPIO/I²C/I²S conflicts shall be documented before wiring.
- `HW-004` — The camera shall cover only the area needed for operation.
- `HW-005` — Loss of camera shall leave manual controls operational.
- `HW-006` — The electrical budget shall include 25% margin over measured peak.

## Acceptance criteria

A completed validation sheet contains assembly photographs, overlay list, device
detection output, idle/load voltage measurements, day/night samples, and results
from a 30-minute wake-session test.

The V0348 purchase listing is selection evidence only. `HW-DEC-003` and
`HW-DEC-004` remain open until the physical unit passes the camera and electrical
acceptance criteria in `40/001-infrared-camera`.
