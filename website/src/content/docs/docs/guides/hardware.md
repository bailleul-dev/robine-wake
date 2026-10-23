---
title: Hardware & targets
description: Supported boards, amplifiers and wiring.
sidebar:
  order: 3
---

## Firmware targets

| Target | Board | Notes |
|---|---|---|
| `host` | any computer | simulation, tests, demo |
| `rpi3` | Raspberry Pi 3 B / B+ | reference target, HiFiBerry Amp2 |
| `rpi0` | Raspberry Pi Zero W | ARMv6, 1 core, 512 MB; USB-gadget first access |

```sh
make firmware                 # rpi3
make firmware-rpi0            # Pi Zero W
```

## Wiring

Step-by-step diagrams:

- [Current setup, Raspberry Pi 3](../wiring-pi3/): amplifier, ESP32 light strip, LoRa button.
- [Raspberry Pi Zero W](../wiring-pi-zero/): InnoMaker amplifier.
- [Wi-Fi bedside button](../wiring-remote-button/): ESP32 / Heltec, optional external button.
- [Future board bench](../wiring-bench/) (not the current build): ESP32-S3 + ESP32, amplifier, LoRa and status LED on a breadboard.

## Amplifiers

| Board | Amplifier | Overlay |
|---|---|---|
| Pi 3 | HiFiBerry Amp2 (PCM512x + TAS5756) | `hifiberry-dacplus` |
| Pi Zero W | InnoMaker HiFi AMP Pro Mini HAT (Infineon MA12070P) | `merus-amp` |

The audio driver finds the card automatically (`alsa_device: "auto"`) and
sets the volume through the card's own mixer control (`Digital` on the
HiFiBerry, `A.Mstr Vol` on the MA12070P).

:::caution
The Linux driver of the MA12070P accepts sample rates up to 48 kHz only. The
stock `merus-amp` overlay claims GPIO 14/15 (enable, mute), which are the ESP32
UART pins: the `rpi0` firmware loads `merus-amp-uart`, a variant without them.
That is only valid if the HAT does not depend on those pins: do the continuity
check in the [Pi Zero W wiring guide](../wiring-pi-zero/). The SX1276 LoRa radio
(SPI CE0 on GPIO 8) cannot be used on a Zero with this HAT.
:::

## Light

A 60-LED WS2812B strip driven by an ESP32 co-processor over UART
(Pi GPIO 14/15, mini UART). Programs: dawn, sunset, evening breathing,
reading light, ambience. See [guided breathing](../../specs/30-003-guided-breathing/).

## Bedside remote

A LoRa (SX1276, 868 MHz) button dismisses the alarm physically. See the
[remote button note](../../notes/remote-alarm-button/).

## Bed vibration (planned)

A DIY tactile channel for breathing, music and progressive waking, coupled to
the rigid frame of a slatted bed. Specified, not yet implemented — see
[the specification](../../specs/30-004-bed-vibration/) and the
[design note](../../notes/diy-bed-vibration/).

## Not in the product

Camera, infrared illumination and bed-presence detection were removed on
2026-09-06. Nothing observes the sleeper.
