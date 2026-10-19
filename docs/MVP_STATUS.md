# MVP Implementation Status

Historical implementation audit: 2026-08-20. Product scope updated 2026-09-06.

## Current product scope and pending implementation

Camera, infrared illumination, visual calibration, bed-presence detection and
automatic bed-exit dismissal are removed, not deferred. The accepted P1 addition
is [DIY bed vibration](specs/30/004-bed-vibration/spec.md) for breathing, music and
progressive waking, coupled to the rigid frame/casing of the user's slatted bed.

This change updates specifications only. Existing camera code and controls still
need removal; tactile hardware/control, manual-only legacy migration and updated
host scenarios still need implementation and validation. The earlier delivery and
test evidence below is a historical snapshot, including capabilities since retired;
it does not describe the new scope as already delivered.

## Historical delivered software scope — 2026-08-20

The repository contains a bootable Nerves application for Raspberry Pi 3 and a
fully runnable host simulation. The current MVP implements:

- validated recurring and one-shot alarms with IANA time zones and explicit
  daylight-saving transition rules;
- persistent alarms and wake-session history with atomic writes, optimistic
  revisions, and 30-day session retention;
- a supervised scheduler with duplicate prevention and bounded catch-up after a
  restart or clock jump, including explicit `missed` history outside the
  catch-up window and refusal to arm while device time is untrusted;
- a restart-recoverable wake-session state machine supporting volume ramping,
  snooze, manual dismissal, confirmed bed-exit dismissal, timeout, and
  fail-safe behavior;
- host and Raspberry Pi audio adapters, automatic HiFiBerry ALSA card discovery,
  mixer volume control, a generated local fallback alarm tone, a manifest-backed
  bundled MP3 library, two-stage gentle/strong alarm playback, and atomic
  SHA-256-verified import of bounded PCM WAV sounds;
- a supervised AirPlay receiver for bedroom music, with a conservative volume
  cap and hard alarm priority over the shared HiFiBerry ALSA device;
- host and Raspberry Pi camera adapters, private in-memory empty-bed
  calibration, YUV420 luminance capture, configurable region-of-interest
  and polygon analysis, stale/duplicate frame handling, and conservative
  `unknown` observations for unusable frames;
- an authenticated local web interface and JSON API with a responsive
  product-style alarm editor, two-stage sound selection, occurrence preview,
  manual tests, active-session controls, and camera calibration;
- first-run target password provisioning using salted PBKDF2, login throttling,
  per-boot CSRF protection, and no default target password in the firmware;
- bounded privacy-filtered event telemetry, non-secret configuration export,
  session-history erasure, and diagnostics with a SHA-256 manifest;
- authenticated SSH/Fwup updates requiring an embedded Ed25519 public key,
  with active-session, clock-quality, and 15-minute alarm-window prechecks;
- an unauthenticated minimal health endpoint suitable for local supervision;
- target network, SSH, mDNS, time-zone, persistence, and firmware configuration;
- a loopback-only Phoenix LiveView Hardware Lab that drives synthetic infrared
  frames, hardware failures, clock conditions, alarms, and wake sessions through
  the production domain while remaining excluded from the Raspberry Pi build.

No image is stored by the application and no cloud service is required for the
alarm, audio, or bed-exit decision path.

## Historical verification on the development host

The following checks pass:

```text
mix verify                       78 passed (1 property, 77 tests)
                                 70.1% aggregate coverage + HTML/JSON reports
                                 no retired or advisory dependencies
MIX_TARGET=rpi3 mix firmware     produces a Raspberry Pi 3 .fw image
```

The suite includes 10,000 consecutive occurrence recalculations without a
duplicate. The current signed firmware is 118,165,313 bytes, has SHA-256
`f71563d5c9f13bf1a3842df9b5ed2edfd930952a1debb1bc095c8ffff12e2654`, uses
`/data/robine_wake.json` and `/data/robine_wake_auth.json`, starts with an
untrusted clock, and contains no configured administrator password.
Its embedded Fwup public key has SHA-256
`4294ae42fd12efb31ea0c98d463902152ee0a45d228c980a7b27c27bdffc8de2`;
the matching private key remains outside the repository with mode `0600`.

The local Bandit server was also exercised through HTTP: `/health` correctly
returned `degraded` before camera calibration, the authenticated interface
rendered in English, its JavaScript passed `node --check`, a CSRF-protected
five-occurrence preview succeeded, a digest-verified sound upload succeeded,
and unauthenticated API access was rejected with `401`.

The Phoenix LiveView Hardware Lab was exercised with connected LiveView tests:
synthetic occupied/offline camera states, network/audio degradation, a complete
trigger/snooze/dismiss path, and deterministic time advancement all update the
real application state. A separate `rpi3` compilation and firmware build prove
that Phoenix and LiveView are absent from the target build directory.

Coverage is intentionally lower for target-only ALSA and Raspberry Pi camera
drivers because those paths require the actual peripherals. Their decision
logic and state transitions are covered through the host drivers.

AirPlay 2 is served by `robine-airplayd`, the project's own receiver, which
replaced Shairport Sync, Avahi and NQPTP in the image on 2026-10-19. Its
long-listening and overnight timing behavior remain to be measured on the
Raspberry Pi 3.

## Historical verification on target hardware

On 2026-08-20, a Raspberry Pi 3 B+ revision 1.3 (`a020d3`) at
The test Raspberry Pi booted the signed firmware from the validated B slot. A
HiFiBerry Amp2 powered the Pi from a regulated 16.5 V / 2 A supply. Linux
exposed `snd_rpi_hifiberry_dacplus` as ALSA card 0, automatic selection resolved
to `plughw:0`, and the stereo `Digital` mixer control was available. A four-second
PCM test completed successfully at approximately -31 dB and was confirmed
audible through both connected speakers. The mixer was returned to zero after
the test.

The boot configuration uses `dtoverlay=hifiberry-dacplus`, disables onboard
audio, and sets `force_eeprom_read=0` so the current Linux overlay is used in
place of the legacy overlay stored in the HiFiBerry EEPROM.

The current firmware build `9fb04373-9551-5eaf-1539-9f103b6d53c5` is active and
validated in slot A. It includes the two-stage alarm editor, four bundled MP3
tracks, `mpg123` 1.33.5, and the calibrated Amp2 logical-volume curve. A target
playback drill ran `jazz_for_breakfast` at logical gain 15, measured -39.5 dB
on both channels, reset the mixer to its minimum on stop, left no `mpg123`
process, and restored AirPlay availability. Shairport Sync 4.3.7 runs with
OpenSSL, tinysvcmdns, and
ALSA; macOS Bonjour discovery found `Robine Wake Bedroom`, TCP 5000 was open,
and `/health` reported the receiver as available alongside the existing web
service. A target arbitration drill fully removed the receiver process while
suspended and restored it in under 750 ms. A forced process termination also
recovered after the configured two-second delay without restarting the BEAM.
End-to-end music playback and acoustic-limit measurement remain to be confirmed
from an Apple source device.

## Required validation for the current scope

1. Verify camera-free boot, UI/API/health and exports, plus legacy dismissal/profile
   migration with schedules, snoozes and session deadlines preserved.
2. Record the final enclosure and wiring. Measure the main and tactile power
   circuits separately, with the required margin and protected external supply.
3. Measure audible startup, ramp, ceiling, distortion, stop and restart behavior.
4. Validate the chosen motor/generator and power stage, stable control, frame fixation,
   occupied-bed distribution and transmission to the floor before setting limits.
5. Measure breathing/music synchronization, ramp limits and shutdown; inject
   tactile failures without delaying the audible strong fallback or physical stop.
6. Exercise reboot, power/network loss, untrusted time, DST, snooze and timeout.
7. Complete thermal, electrical, mechanical, acoustic, privacy and endurance
   gates listed in [simulation and validation](specs/80/001-simulation-validation/spec.md).

Camera procurement, nighttime capture/calibration and visual false-exit datasets
are no longer delivery gates. Documentation changes are not firmware validation.

## Deliberate boundaries

No cloud dependency, camera, presence sensor, sleep-stage inference or automatic
presence-based dismissal is part of the current product. The tactile system is
optional in operation; a disabled or unconfigured unit supports audio-only alarms.
