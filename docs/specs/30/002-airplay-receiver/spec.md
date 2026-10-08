# 30-002 — AirPlay Receiver

## Purpose

Allow Robine Wake to serve as a bedroom speaker for Apple devices without
weakening its primary responsibility as a reliable alarm clock.

## MVP scope

The target firmware embeds Shairport Sync 5.5.2 built for AirPlay 2. The
receiver advertises the name `Robine Wake Bedroom`, accepts audio from devices
on the local network, and sends stereo PCM directly to the HiFiBerry Amp2 ALSA
device. The host emulator does not start or emulate an AirPlay protocol server.
This direct-output path describes the existing implementation. The tactile
extension specified below remains to be implemented.

AirPlay 2 replaced classic AirPlay so that the receiver, not the source,
proposes the volume when it is selected. This is an audio receiver only:
photos, screen mirroring, and video are out of scope.

## Runtime architecture

`RobineWake.AirPlay` owns one foreground Shairport Sync operating-system
process through an Erlang port. It starts only on the Raspberry Pi target,
captures process output into bounded system logging, observes exit status, and
restarts unexpected exits after two seconds. A missing executable or
configuration file is reported through health and retried without preventing
the alarm application from booting.

Shairport Sync performs Bonjour/mDNS advertisement and network protocol
handling. It opens `plughw:0` in 32-bit and has no hardware mixer: see volume below.
This selection matches the hardware-validated HiFiBerry card for the current
single-board product profile and must be revisited if another ALSA card is
added.

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

1. Before attempting alarm playback, `RobineWake.Audio` suspends AirPlay and
   closes the Shairport Sync process.
2. The alarm opens the HiFiBerry and applies its normal progressive gain rules.
3. AirPlay remains unavailable for the complete wake-session audio interval,
   including retries.
4. After a normal stop or terminal playback failure, the receiver restarts and
   advertises itself again.

The same rules apply to the [Bluetooth receiver](../005-bluetooth-audio-receiver/spec.md):
`RobineWake.Audio` suspends and resumes every music receiver, and a receiver
that fails to answer is logged and skipped rather than delaying the alarm.

An active phone stream may therefore disconnect when an alarm begins. This is
intentional. A network client, malformed stream, or crashed receiver must never
delay, replace, attenuate, or suppress an alarm.

## Volume and bedroom safety

Shairport Sync attenuates in software, in 32-bit, and never writes the Amp2
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
vibration continue locally. Classic AirPlay normally uses mDNS on UDP 5353, TCP 5000, and
a small negotiated UDP audio/control range beginning near 6001. No inbound
internet connectivity or cloud account is required.

The application continues to run its existing local mDNS advertisement for the
web and SSH services. AirPlay 2 is advertised by Avahi under its own host name
(`robine-wake-airplay.local`), next to that responder on port 5353.

## AirPlay 2 decision

AirPlay 2 is enabled. Shairport Sync comes from the system's own
`package/shairport-sync5` (release 5.5.2): Buildroot's 4.3.7 negotiates the
AirPlay 2 buffered stream with iOS 26 but plays silence, while the Mac's
realtime stream works. Release 5 decodes both ALAC and AAC through FFmpeg,
which is trimmed to those decoders, the ffmpeg CLI and a few audio filters so
the root filesystem still fits its partition. The image also adds Avahi, NQPTP
(shared-memory interface version 10, matching nqptp 1.2.4), and the
cryptographic libraries; NQPTP owns PTP UDP ports 319 and 320. Release 5 is
built without metadata support, whose pipe initialisation crashes at startup
when no pipe name is configured.
`RobineWake.AirPlay` starts Avahi and NQPTP before Shairport Sync and keeps
them running while wake audio suspends the receiver. Avahi needs the system
D-Bus, which `RobineWake.BluetoothAudio` starts.

Still to record on the Raspberry Pi 3: idle-memory delta, CPU load during
buffered playback, alarm-preemption latency, iOS/macOS compatibility, and
overnight timing stability.

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
- `APY-007` — AirPlay 2 shall be advertised through Avahi with NQPTP timing;
  its resource and compatibility acceptance evidence remains to be recorded.

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
  forcibly terminated Shairport process do not restart or block the alarm
  application.
- Reboot and overnight tests show no mDNS conflict with the local web and SSH
  advertisements.
