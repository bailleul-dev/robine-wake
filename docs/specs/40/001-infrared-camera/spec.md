# 40-001 — Infrared Camera

## Purpose

Provide normalized nighttime frames to the detector without storing video and
without coupling the domain to CSI, libcamera, or V4L2.

## Selected candidate hardware

The selected candidate is the **APKLVSR V0348** (Amazon ASIN `B0CLGTM3Z8`), a
third-party Raspberry Pi camera module advertised with the following properties:

| Property | Vendor claim | Project treatment |
|---|---|---|
| sensor | OmniVision OV5647, 5 MP | plausible and supported by the Raspberry Pi camera stack; verify device detection |
| maximum still resolution | 2592×1944 | not required by the detector; retain the 320×240 analysis profile |
| interface | two-lane MIPI CSI through a 15-pin, 15 cm ribbon cable | selected interface for Raspberry Pi 3 |
| infrared illumination | two automatically switched 850 nm boards | treat as uncontrolled external illumination and measure its current and thermal load |
| field of view | approximately 130° | verify usable bed-pixel density and privacy framing in the installed position |
| dimensions and mass | approximately 73×25×15 mm and 17 g | provisional enclosure inputs only |
| focus | listing alternately describes the lens as fixed and adjustable | unresolved; verify focus mechanism and lock it after calibration |

The vendor page is not an engineering datasheet. No claim above becomes accepted
evidence until the received board identity, wiring, electrical load, optical
behavior, and camera-stack compatibility are measured. Product reference:
<https://www.amazon.fr/dp/B0CLGTM3Z8> (reviewed 2026-08-19).

Raspberry Pi documents that the Pi 3 uses the standard 15-pin CSI connector and
that its current `libcamera`/`rpicam` stack supports the OV5647. This establishes
design compatibility, not compatibility of this particular third-party board:
<https://www.raspberrypi.com/documentation/accessories/camera.html> and
<https://www.raspberrypi.com/documentation/computers/camera_software.html>.

The target adapter is therefore `Camera.Driver.Rpi` over `rpicam-still`. A UVC
adapter is no longer part of the selected MVP path, but remains a contingency if
the received V0348 fails `VAL-HW-003`.

## `Camera` contract

- `capabilities/0`: resolutions, frame rates, exposure/gain controls;
- `start_stream/1`: start with validated settings;
- `next_frame/1`: return a frame, dimensions, and monotonic time;
- `set_controls/1`: exposure, gain, and optional IR control;
- `stop_stream/0`: release the device;
- `health/0`: frame rate, errors, and last-frame time.

A domain frame is 8-bit grayscale. Any color conversion happens inside the
adapter. Initial profile: 320×240 at 5 frames/s, falling back to 2 frames/s if
CPU load persistently exceeds its budget.

## Calibration

Calibration guides the user through framing the bed, defining the region polygon,
checking focus, measuring black/white levels, detecting saturation, and selecting
exposure/gain. Valid settings are versioned with the sensor profile and become
invalid if resolution or orientation changes.

## Day/night management

The system computes mean brightness, contrast, and saturated-pixel ratio. It
does not assume a bright image is usable. Quality is `good`, `poor`, or `unusable`.
In a stable night mode, exposure may be locked so automatic variation does not
appear as motion.

The V0348 illumination threshold is adjusted on the IR boards and is not assumed
to be software-controllable. The installed threshold shall prevent repeated
day/night oscillation. Automatic exposure and gain must settle before the empty-
bed reference is captured; if controls cannot be locked, the quality gate must
reject illumination transitions rather than interpreting them as occupancy.

## Electrical and mechanical constraints

- Connect or disconnect the CSI ribbon only while the Raspberry Pi is unpowered.
- Confirm ribbon orientation against the Pi 3 and camera-board pin-1 markings.
- Do not assume the two IR boards are safely powered merely because they mount
  to the camera PCB. Measure their steady-state and switching current from the
  complete 5 V input and include them in the system power budget.
- Record temperatures after 30 minutes in darkness at the IR boards, camera PCB,
  ribbon connector, enclosure surface, Pi, and HiFiBerry.
- Mechanically secure the adjustable parts after focus and threshold calibration.
- Position the 130° field so pixels outside the bed ROI are minimized; software
  cropping is not a substitute for privacy-conscious physical framing.

## Privacy

Frames live in a bounded, overwriting memory buffer. By default there is no disk
write, video endpoint, pixel logging, or crash dump containing a frame. Diagnostic
capture requires local activation, has a maximum duration of 10 minutes, and is
deleted explicitly or automatically.

## Requirements

- `CAM-001` — The domain shall receive one sensor-independent grayscale format.
- `CAM-002` — Every frame shall carry a monotonic timestamp.
- `CAM-003` — Frames shall never be persisted during normal operation.
- `CAM-004` — The camera shall become degraded after 2 seconds without a frame.
- `CAM-005` — Camera recovery shall not restart the wake session.
- `CAM-006` — Settings incompatible with the profile shall be rejected.
- `CAM-007` — The buffer shall remain bounded when detection is slower than capture.

## Acceptance criteria

- Host adapter reads fixture sequences under controlled time.
- Tests cover lost, delayed, duplicated, and resized frames.
- Normal mode produces no image file.
- The received module reports an OV5647 sensor through the target camera stack,
  or any deviation is recorded and explicitly reviewed.
- A 320×240 luminance capture runs at 5 frames/s for 30 minutes in complete
  darkness without a stale interval longer than 2 seconds.
- The two 850 nm illuminators switch on and remain stable without oscillation,
  visible saturation over the bed, unsafe temperature, undervoltage, or audio
  interference.
- Focus remains stable over the complete bed after the mechanism is secured.
- On hardware: an 8-hour sequence shows no memory leak and reports frame-rate
  statistics.
