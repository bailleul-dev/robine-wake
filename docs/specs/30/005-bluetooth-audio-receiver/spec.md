# 30-005 — Bluetooth Audio Receiver

## Purpose

Let any phone, Android included, use Robine Wake as a bedroom speaker over
Bluetooth, alongside [AirPlay](../002-airplay-receiver/spec.md), without
weakening its primary responsibility as a reliable alarm clock.

## Radio topology

The Raspberry Pi 3 onboard controller is used, without an additional adapter.
It moves from the mini UART at 115 200 baud, far below the bandwidth of an A2DP
stream, to the full-speed PL011 UART (`miniuart-bt` overlay removed,
`dtparam=krnbt=on`), where the kernel `hci_uart` driver attaches it to BlueZ.
The Broadcom firmware ships in the image (`rpi-distro-bluez-firmware`).

This retires the BlueHeron BLE control service, which drove the same controller
directly: it is disabled on the target and its application is not started, so
the iOS prototype only reaches the clock over Wi-Fi.

The controller shares its antenna with the 2.4 GHz Wi-Fi. The chip arbitrates
both radios, but high-bitrate codecs (aptX HD) may drop out under heavy Wi-Fi
traffic; streaming stability must be measured with Wi-Fi active.

## Runtime architecture

`RobineWake.BluetoothAudio` starts only on the target and owns, in order:

1. `dbus-daemon --system`;
2. `bluetoothd`, configured by `/etc/bluetooth/main.conf`;
3. `bluealsad` (BlueALSA 5) as an A2DP sink only;
4. `bluetoothctl --agent auto`, the pairing agent;
5. `bluealsa-aplay`, the only process that opens the HiFiBerry.

Items 1–4 form the radio stack. Any of them exiting stops the stack and
restarts it after two seconds; the player restarts on its own. A missing
executable or adapter is reported through health and never prevents the alarm
application from booting. Pairing keys persist under `/data/bluetooth`.

## Codecs

The phone selects the best codec both sides support:

| Codec | Typical bitrate | Phones |
|---|---|---|
| SBC | 345 kbit/s | Every A2DP source (mandatory) |
| AAC | ~256 kbit/s | iPhone, most Android phones (Samsung included) |
| aptX | 352 kbit/s | Qualcomm Snapdragon Android phones |
| aptX HD | 576 kbit/s | Qualcomm Snapdragon Android phones |

LDAC is not offered: Sony only publishes the encoder, and receiving LDAC needs
its proprietary decoder. Samsung Seamless Codec is proprietary as well. A
Galaxy phone therefore uses AAC, or aptX/aptX HD on Snapdragon models.

AAC decoding uses Fraunhofer FDK AAC and aptX uses libopenaptx (GPL-3.0); both
licenses must be reviewed before distributing firmware beyond personal use.

Only the A2DP sink profile is registered: the receiver never appears as a
hands-free device, so phone calls stay on the phone.

## Audio/video synchronisation

The receiver reports its playback delay to the phone through A2DP delay
reporting, so a video player can delay the picture to match the sound, as it
does with AirPlay. BlueALSA 5 measures the player's real buffering (BlueALSA
FIFO, read buffer and ALSA device) and adds the codec delay; BlueZ forwards the
total to the phone and updates it when it drifts by more than 10 ms. Buildroot
only ships BlueALSA 4.3.1, which advertises the capability but always reports
zero, so the system builds release 5 from `package/bluez-alsa5`.

Whether the picture is actually delayed depends on the phone honouring the
report.

## Pairing

Pairing is open, without a button or PIN: the adapter is always discoverable as
`Robine Wake Bedroom` and the agent accepts every pairing and service request.
Android shows its usual confirmation dialog on the phone only.

Anyone in radio range can therefore pair and play audio. A later setup screen
may restrict pairing to a time window opened from the local interface; such a
setting must not be allowed to block alarm startup.

## Audio ownership and alarm priority

Bluetooth follows the same rules as AirPlay; `RobineWake.Audio` treats both as
music receivers:

1. Before attempting alarm playback, `RobineWake.Audio` suspends every music
   receiver. For Bluetooth this stops `bluealsa-aplay`, releasing ALSA; the
   phone link and the radio stack stay up.
2. A receiver that fails, raises or times out while suspending or resuming is
   logged and skipped; it never prevents wake audio.
3. After a normal stop or terminal playback failure, receivers resume and
   Bluetooth playback becomes audible again.

AirPlay and Bluetooth never mix: whichever stream opens the device first keeps
it until it goes idle.

## Volume and bedroom safety

Phone volume is applied in software by BlueALSA below a fixed hardware level,
set on the Amp2 `Digital` mixer when the player starts and after each alarm.
That level, `-6.0 dB` by default (`bluetooth_audio_mixer_db`), matches the AirPlay
`volume_max_db` and is the receiver's hard ceiling. Like the AirPlay value, it
must be replaced by the measured bedroom limit.

## Requirements

- `BTA-001` — The target shall expose one discoverable, pairable A2DP sink
  named `Robine Wake Bedroom` without a physical pairing action on the device.
- `BTA-002` — Alarm playback shall stop Bluetooth playback before opening ALSA,
  and Bluetooth playback shall return after alarm audio releases ALSA.
- `BTA-003` — A failing or unresponsive music receiver shall never prevent,
  delay beyond the audio latency target, or crash wake audio.
- `BTA-004` — Bluetooth audio shall output stereo through the HiFiBerry Amp2
  under an independent hardware ceiling.
- `BTA-005` — The receiver shall offer SBC, AAC, aptX and aptX HD and shall not
  register a hands-free profile.
- `BTA-006` — An unexpected stack or player exit shall be visible in health and
  shall trigger bounded automatic recovery without restarting the BEAM.
- `BTA-007` — Only BlueZ shall drive the onboard controller; the BlueHeron
  transport shall not be started on the target.
- `BTA-009` — The receiver shall report its measured playback delay to the
  phone through A2DP delay reporting.
- `BTA-008` — Bluetooth audio shall be disabled on the host build and remain
  optional to every P0 alarm function, including without an adapter.

## Acceptance criteria

- A Galaxy S24 and an iPhone pair without touching the device, and the codec
  shown in the phone's developer settings matches the table above.
- Ten minutes of music plays in stereo without underruns or dropouts with Wi-Fi
  active.
- A scheduled alarm started during Bluetooth streaming becomes audible within
  the normal alarm latency target; music resumes after dismissal without
  re-pairing.
- Killing `bluetoothd` or `bluealsa-aplay`, a controller that fails to
  initialise, and rebooting do not restart or block the alarm application;
  pairings survive a reboot.
- A YouTube video with a visible speaker stays lip-synced on Bluetooth.
- Phone volume at 100 % never exceeds the measured bedroom acoustic limit.
