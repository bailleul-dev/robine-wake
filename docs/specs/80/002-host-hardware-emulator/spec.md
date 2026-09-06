# 80-002 — Host Hardware Emulator

## Purpose

Provide an interactive development laboratory for the alarm clock before the
Raspberry Pi, HiFiBerry, and tactile actuator are connected. The laboratory must
exercise the production domain processes and host hardware boundaries; it must
not be a disconnected UI mock.

## Architecture

Two local servers run from the same OTP supervision tree on `MIX_TARGET=host`:

| Server | Default address | Responsibility |
|---|---|---|
| product interface | `http://127.0.0.1:4110` | the lightweight interface; the Nerves target independently keeps port 4000 |
| Hardware Lab | `http://127.0.0.1:4111` | Phoenix LiveView development controls and live state inspection |

The Hardware Lab is compiled from `lib_host/`. Phoenix, LiveView, their endpoint,
and the emulator module are dependencies and compilation paths for `host` only.
The `rpi3` build compiles `lib/` without `lib_host/`; the firmware therefore
keeps the existing Plug/Bandit interface and does not contain Phoenix or
LiveView applications.

The LiveView calls `RobineWakeDev.Emulator`, which in turn uses the public
interfaces of `Vibration`, `ClockQuality`, `Scheduler`, `Settings`, and
`WakeSession`. Audio, vibration, and network availability are exposed through the
same host drivers used by integration tests. A 500 ms refresh displays the
aggregated production `Health.snapshot/0` rather than a separate presentation
model.

## Emulated capabilities

| Capability | Controls | Production behavior exercised |
|---|---|---|
| bed vibration | configured/disabled, calibration limits, available, disconnected, blocked generator, lost control | three use profiles, bounded gain, ownership, electrical cutoff, residual-stop simulation and health |
| HiFiBerry audio | available, persistent playback failure, disconnected, active-player crash | retry/fail-safe paths, health reporting, active-session error handling |
| network | available or disconnected | degraded health without blocking local alarms |
| clock quality | trusted or untrusted | scheduler arming policy |
| wall clock | system/manual selection and bounded manual advance | deterministic scheduling, catch-up, session ticks |
| alarm | create a safe demo alarm and trigger any stored alarm | real settings persistence, scheduler, audio, and wake-session startup |
| active session | snooze and dismiss | the production state machine and idempotent terminal behavior |

Display tactile owner, mode, commanded intensity, envelope phase, calibrated
ceiling and recent commands. Host controls use the same arbitration as production.
Remove camera controls, image synthesis and presence/confidence widgets; they are
not retained as an alternate product mode. These changes remain to be implemented.

## Operation

```sh
mix deps.get
mix run --no-halt
```

Open `http://127.0.0.1:4111`. Override the two ports when necessary:

```sh
ROBINE_WEB_PORT=4210 ROBINE_DEV_PORT=4211 mix run --no-halt
```

The Hardware Lab is always bound to loopback. It has no production
authentication because it is a development actuator with process-level access;
it must not be exposed through a reverse proxy or port-forward. The product
interface retains its trusted-local-network access policy on its separate port.

When switching between system and manual time, no wake session may be active.
This prevents a change of monotonic-clock origin from corrupting an in-progress
session. Advancing manual time is limited to 1–1,440 minutes per action.

## Requirements

- `EMU-001` — Emulator controls shall drive production domain APIs, not duplicate
  the alarm state machine in LiveView.
- `EMU-002` — Phoenix and LiveView shall be excluded from `rpi3` compilation and
  firmware contents.
- `EMU-003` — The emulator shall bind only to loopback.
- `EMU-004` — Retired: synthetic camera pixels.
- `EMU-005` — Retired: camera-loss dismissal constraint.
- `EMU-006` — LiveView tests shall connect, render, send events, and assert the
  resulting domain state.
- `EMU-007` — Hardware controls shall be resettable without erasing alarms or
  session history.

- `EMU-008` — The laboratory shall exercise tactile profiles, ownership, failure
  and cutoff through production APIs and simulated hardware.
- `EMU-009` — The laboratory shall expose no camera/presence controls or dependency.

## Acceptance criteria

- Connected LiveView tests drive tactile modes, calibration limits, disconnect
  and blocked generation; camera/presence widgets are absent.
- A connected LiveView test changes audio/network capability health, creates an
  alarm, starts a real session, snoozes it, and dismisses it.
- A connected LiveView test advances `Clock.Manual` without sleeping.
- `mix verify` passes on `host`.
- `MIX_TARGET=rpi3 mix compile --warnings-as-errors` and
  `MIX_TARGET=rpi3 mix firmware` pass.
- `_build/rpi3_dev/lib/phoenix` and
  `_build/rpi3_dev/lib/phoenix_live_view` do not exist after the target build.

This emulator accelerates development but does not replace electrical, mechanical,
thermal, acoustic, power-loss, or overnight hardware acceptance.
