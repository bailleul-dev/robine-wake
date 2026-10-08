# 30-001 — Audio Output

## Purpose

Produce an audible, progressive alarm through HiFiBerry while retaining a
defined fallback strategy.

## Adapter contract

The adapter exposes `capabilities/0`, `prepare/1`, `play/2`, `set_gain/1`,
`stop/1`, and `status/0`. Calls carry a session identifier so an old command
cannot stop a newer session.

## Formats and sound library

The firmware ships a curated MP3 library under `priv/sounds`; each entry has a
stable identifier, title, artist attribution, duration, intensity, byte size,
version, and SHA-256 digest in a manifest. Target playback uses `mpg123` with
the configured ALSA device.

User imports remain deliberately narrower: mono or stereo WAV PCM at 44.1/48
kHz and 16 bits, with a 5 MB limit. A user sound is copied atomically only after
validating size, structure, and digest. Custom WAV identifiers override bundled
identifiers only after successful validation. The generated `default` WAV is
always retained as an offline fallback.

## Volume profile

Logical volume ranges from 0 to 100 and maps to mixer gain through a
hardware-calibrated curve. On HiFiBerry Amp2, logical values 1 through the
absolute safety ceiling map linearly from -45 dB to -15 dB; logical zero uses
the ALSA minimum. This avoids applying a raw ALSA percentage to the Amp2's
roughly 107 dB control range, where the first third is effectively inaudible.
Initial alarm values are start 15, ceiling 85, and a configurable pre-wake ramp
defaulting to 20 minutes. The ramp reaches its ceiling at the target wake time.
The absolute safety ceiling is separate from the user setting.

## Music level

`RobineWake.Audio` is the only writer of the hardware mixer. Wake audio ramps
it; at startup and whenever wake audio releases ALSA, it is set back to the
music ceiling (`music_mixer_db`, `0.0 dB`, never above the `0.0 dB` music
maximum; wake audio keeps its own `0.0 dB` maximum). Music receivers (AirPlay, Bluetooth) attenuate in software below that
level, so a receiver can never leave the device silent or louder than the
ceiling for another one.

Start, snooze, and stop transitions use at least a 500 ms fade to prevent clicks.
The engine must loop without a perceptible gap.

Stopping playback must terminate the complete decoder process group; closing an
Erlang port without reaping the external process is not sufficient. A normally
completed track restarts until the owning wake session stops or replaces it.

## Device selection

ALSA selection uses a configured stable identifier. At startup, a non-audible
test verifies that the device can be opened. If HiFiBerry is unavailable, a
fallback output is used only when explicitly configured.

## Independent tactile output

The HiFiBerry retains both speakers. Bed vibration uses a separate actuator and
power stage with its own ceiling. Audio start and fallback never wait for the
tactile path. A coarse music intensity envelope is sufficient; a second sound
card and faithful bass reproduction are not required. Control and timing are defined in
[bed vibration](../004-bed-vibration/spec.md); a wake vibration motif is independent
of the audio track. Snooze and stop are coordinated by the owning session.

## Errors

After a playback error, make three retry attempts after 250 ms, 1 second, and
3 seconds. A retry resumes at the current ramp volume. Final failure publishes
a critical event and leaves the session active for manual action.

## Requirements

- `AUD-001` — A command from an older session shall not affect the active session.
- `AUD-002` — Gain shall never exceed the hardware ceiling.
- `AUD-003` — Sound shall start within 500 ms of an accepted command.
- `AUD-004` — Audio files shall be validated before becoming available.
- `AUD-005` — Stop and volume-change operations shall be idempotent.
- `AUD-006` — An ALSA error shall be visible and invoke the retry policy.
- `AUD-007` — The host adapter shall record commands without playing sound.
- `AUD-008` — Bundled MP3 and imported PCM WAV sounds shall resolve through one
  stable sound-library contract.
- `AUD-009` — Stopping or replacing playback shall leave no decoder process
  running for the previous sound.

## Acceptance criteria

- Automated verification of the gain curve and ceiling.
- Concurrency test involving two simulated sessions.
- Invalid-file and missing-device tests.
- Target verification that bundled MP3 playback loops and leaves no `mpg123`
  process after stop, snooze, dismissal, or gentle-to-strong replacement.
- On hardware: no audible clicks, smooth ramp, and measured maximum level at a
  defined distance.
