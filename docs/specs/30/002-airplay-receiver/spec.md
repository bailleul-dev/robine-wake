# 30-002 — AirPlay Receiver

## Purpose

Allow Robine Wake to serve as a bedroom speaker for Apple devices without
weakening its primary responsibility as a reliable alarm clock.

## MVP scope

The target firmware embeds `robine-airplayd`, the project's own AirPlay 2
receiver. It advertises the name `Robine Wake Bedroom`, accepts audio from
devices on the local network, and sends stereo PCM directly to the HiFiBerry
Amp2 ALSA device. The host emulator does not start or emulate an AirPlay
protocol server. This direct-output path describes the existing
implementation. The tactile extension specified below remains to be
implemented.

AirPlay 2 lets the receiver, not the source, propose the volume when it is
selected. This is an audio receiver only: photos, screen mirroring, and video
are out of scope.

## Runtime architecture

`robine-airplayd` (`experimental/robine-wake-rs/crates/robine-airplayd`) is a
1.4 MB static binary on the project's own AirPlay 2 core, the one the ESP32
runs. `make airplayd` (a prerequisite of `make firmware`) builds it into
`rootfs_overlay/usr/bin`. It replaced Shairport Sync, NQPTP and Avahi on
2026-10-19, after listening tests from an iPhone; the image no longer ships
them.

`RobineWake.AirPlay` owns it through an Erlang port, one JSON message per
line. It starts only on the Raspberry Pi target, logs the process output,
observes exit status, and restarts unexpected exits after two seconds. A
missing executable is reported through health and retried without
preventing the alarm application from booting.

The receiver advertises itself over mDNS as `robine-wake-airplay.local`,
follows the sender's PTP clock on ports 319/320, plays through `aplay` in
S32_LE on `plughw:0` with a software volume, and keeps its identity in
`/data/airplay`. The process exits when the port closes. This selection
matches the hardware-validated HiFiBerry card for the current single-board
product profile and must be revisited if another ALSA card is added.

Both streams play on the sender's clock: buffered ones from their
`SETRATEANCHORTIME` anchor, realtime ones from the sync packets of the
control port, with lost packets requested again. The output is written
continuously at the DAC's pace; sync errors beyond 50 ms are corrected at
once, smaller ones and the sender/DAC clock drift by dropping or repeating
an occasional frame. `/info` proposes the last volume to new sessions,
back to -7.5 dB after an hour idle at -3 dB or more.

Still to validate on the Pi: a long listening session, including the
realtime anchor correction taken from Shairport Sync and the output latency
estimate, through the `stats` events (debug log of `RobineWake.AirPlay`).

## Tactile music extension — specified, pending implementation

When music vibration is enabled, derive a smoothed bass-energy or accent envelope
from the musical signal to drive tactile intensity as specified in
[bed vibration](../004-bed-vibration/spec.md). No faithful frequency reproduction,
second audio card or full PCM duplication is required. Access to the source signal
for envelope extraction remains to be implemented. Preserve common transport
pause/mute and independently bounded intensity, and measure perceived delay.
Direct bass playback through a shaker is an optional implementation variant.

Loss of the tactile sink must not stall the audible sink. An alarm preempts both
music outputs; a voluntary breathing session also suspends music. Releasing either
session may restore receiver availability but never replay a stale tactile buffer.

## Audio ownership and alarm priority

ALSA access is exclusive. The alarm path is authoritative and never mixes with
AirPlay:

1. Before attempting alarm playback, `RobineWake.Audio` suspends AirPlay: the
   receiver keeps its session and releases ALSA, and is stopped if it does
   not confirm within one second.
2. The alarm opens the HiFiBerry and applies its normal progressive gain rules.
3. AirPlay remains unavailable for the complete wake-session audio interval,
   including retries.
4. After a normal stop or terminal playback failure, the receiver resumes
   without the sender reconnecting, or restarts and advertises itself again
   if it was stopped.

The same rules apply to the [Bluetooth receiver](../005-bluetooth-audio-receiver/spec.md):
`RobineWake.Audio` suspends and resumes every music receiver, and a receiver
that fails to answer is logged and skipped rather than delaying the alarm.

An active phone stream may therefore disconnect when an alarm begins. This is
intentional. A network client, malformed stream, or crashed receiver must never
delay, replace, attenuate, or suppress an alarm.

## Volume and bedroom safety

The receiver attenuates in software, in 32-bit, and never writes the Amp2
`Digital` mixer. That hardware level belongs to `RobineWake.Audio`, which keeps
it at the music ceiling (`music_mixer_db`, `0.0 dB`) between alarms; see
[audio output](../001-audio-output/spec.md#music-level). A source at full volume
therefore plays at that ceiling. The suggested volume after reset is `-7.5 dB` (75 % on the source); volume at or above
`-3.0 dB` is considered high and returns to the suggested value after 60 idle
minutes. These are conservative bring-up values, not a substitute for acoustic
calibration. The final maximum must be measured at the sleeping position and
recorded alongside the alarm safety-ceiling validation.

No AirPlay password is configured for the prototype. Access control therefore
depends on the trusted local Wi-Fi boundary. A later setup screen may offer an
independent receiver enable switch, display name, or password, but those values
must not be allowed to block alarm startup.

## Network behavior

The receiver must remain optional: loss of Wi-Fi or mDNS only removes AirPlay
availability. The scheduler, alarm audio, physical controls, and generated breathing/wake
vibration continue locally. AirPlay 2 uses mDNS on UDP 5353, the control
connection on TCP 7000, PTP on UDP 319/320 and negotiated audio ports. No
inbound internet connectivity or cloud account is required.

The application continues to run its existing local mDNS advertisement for the
web and SSH services. The receiver advertises AirPlay 2 under its own host
name (`robine-wake-airplay.local`), next to that responder on port 5353.

## Requirements

- `APY-001` — The target shall advertise one discoverable local AirPlay audio
  receiver when no alarm owns the output.
- `APY-002` — Alarm playback shall preempt AirPlay before opening ALSA and
  AirPlay shall return after alarm audio releases ALSA.
- `APY-003` — AirPlay shall output stereo audio through the HiFiBerry Amp2 and
  shall not fall back silently to another device.
- `APY-004` — Receiver gain shall have an independent hard maximum no greater
  than the acoustically accepted bedroom limit.
- `APY-005` — An unexpected receiver exit shall be visible in health and shall
  trigger bounded automatic recovery without restarting the BEAM.
- `APY-006` — AirPlay shall be disabled on the host build and shall remain
  optional to every P0 alarm function.
- `APY-007` — AirPlay 2 shall be advertised and timed by the receiver itself,
  without Avahi or NQPTP; its resource and compatibility acceptance evidence
  remains to be recorded.

- `APY-008` — Music shall support a separately limited tactile intensity envelope,
  with stable control, transport silence and measured response; its failure
  shall not block audible playback or alarm preemption.

## Acceptance criteria

- `Robine Wake Bedroom` appears in the AirPlay picker of one current iPhone and
  one current Mac on the same Wi-Fi network.
- Ten minutes of music plays in stereo without underruns, distortion, or an
  unexpected receiver restart.
- Source volume changes never exceed the measured bedroom acoustic limit.
- A scheduled alarm started during active streaming becomes audible within the
  normal alarm latency target; the source disconnects and the receiver becomes
  discoverable again after dismissal.
- Wi-Fi loss, source disappearance, malformed connection attempts, and a
  forcibly terminated receiver process do not restart or block the alarm
  application.
- Reboot and overnight tests show no mDNS conflict with the local web and SSH
  advertisements.
