# 30-002 — AirPlay Receiver

## Purpose

Allow Robine Wake to serve as a bedroom speaker for Apple devices without
weakening its primary responsibility as a reliable alarm clock.

## MVP scope

The target firmware embeds Shairport Sync 4.3.7 in classic AirPlay mode. The
receiver advertises the name `Robine Wake Bedroom`, accepts audio from devices
on the local network, and sends stereo PCM directly to the HiFiBerry Amp2 ALSA
device. The host emulator does not start or emulate an AirPlay protocol server.

Classic AirPlay is selected for the first hardware iteration because it has a
small embedded dependency footprint, uses Shairport Sync's built-in mDNS
backend, and does not require the AirPlay 2 timing and decoding services. This
is an audio receiver only: photos, screen mirroring, and video are out of scope.

## Runtime architecture

`RobineWake.AirPlay` owns one foreground Shairport Sync operating-system
process through an Erlang port. It starts only on the Raspberry Pi target,
captures process output into bounded system logging, observes exit status, and
restarts unexpected exits after two seconds. A missing executable or
configuration file is reported through health and retried without preventing
the alarm application from booting.

Shairport Sync performs Bonjour/mDNS advertisement and network protocol
handling. It opens `plughw:0`, with `hw:0` / `Digital` as the hardware mixer.
This selection matches the hardware-validated HiFiBerry card for the current
single-board product profile and must be revisited if another ALSA card is
added.

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

An active phone stream may therefore disconnect when an alarm begins. This is
intentional. A network client, malformed stream, or crashed receiver must never
delay, replace, attenuate, or suppress an alarm.

## Volume and bedroom safety

Shairport Sync uses the Amp2 `Digital` mixer and enforces an initial maximum of
`-20.0 dB`. The suggested volume after reset is `-30.0 dB`; volume at or above
`-24.0 dB` is considered high and returns to the suggested value after 60 idle
minutes. These are conservative bring-up values, not a substitute for acoustic
calibration. The final maximum must be measured at the sleeping position and
recorded alongside the alarm safety-ceiling validation.

No AirPlay password is configured for the prototype. Access control therefore
depends on the trusted local Wi-Fi boundary. A later setup screen may offer an
independent receiver enable switch, display name, or password, but those values
must not be allowed to block alarm startup.

## Network behavior

The receiver must remain optional: loss of Wi-Fi or mDNS only removes AirPlay
availability. The scheduler, alarm audio, physical controls, and camera path
continue locally. Classic AirPlay normally uses mDNS on UDP 5353, TCP 5000, and
a small negotiated UDP audio/control range beginning near 6001. No inbound
internet connectivity or cloud account is required.

The application continues to run its existing local mDNS advertisement for the
web and SSH services. Coexistence of that responder and Shairport Sync's
`tinysvcmdns` backend must be verified on the target Wi-Fi interface.

## AirPlay 2 decision

AirPlay 2 is not enabled in the MVP firmware. Shairport Sync 4.3.7 supports it,
but the Buildroot image would also need FFmpeg with AAC decoding, Avahi, NQPTP,
cryptographic libraries, and exclusive access to PTP UDP ports 319 and 320.
Before enabling it, record firmware-size and idle-memory deltas, CPU load during
buffered playback, alarm-preemption latency, mDNS integration, iOS/macOS
compatibility, and overnight timing stability on the Raspberry Pi 3.

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
- `APY-007` — AirPlay 2 shall remain disabled until its dependency, timing,
  compatibility, and resource acceptance evidence is complete.

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
