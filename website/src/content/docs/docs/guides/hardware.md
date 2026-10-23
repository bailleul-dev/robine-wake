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

Step-by-step diagrams: [Raspberry Pi 3](../wiring-pi3/) (amplifier, light strip,
LoRa button) and [Raspberry Pi Zero W](../wiring-pi-zero/) (InnoMaker amplifier).
The breadboard bench for the future all-in-one board (ESP32-S3 + ESP32) is in
[`hardware/dev_bench`](https://github.com/bailleul-dev/robine-wake/tree/main/hardware/dev_bench).

## Amplifiers

| Board | Amplifier | Overlay |
|---|---|---|
| Pi 3 | HiFiBerry Amp2 (PCM512x + TAS5756) | `hifiberry-dacplus` |
| Pi Zero W | InnoMaker HiFi AMP Pro Mini HAT (Infineon MA12070P) | `merus-amp` |

The audio driver finds the card automatically (`alsa_device: "auto"`) and
sets the volume through the card's own mixer control (`Digital` on the
HiFiBerry, `A.Mstr Vol` on the MA12070P).

:::caution
The MA12070P overlay claims GPIO 14, 15, 17, 23 and 8, and its driver accepts
sample rates up to 48 kHz. The ESP32 UART (GPIO 14/15) and the SX1276 LoRa
radio (SPI CE0 on GPIO 8) therefore cannot share a Zero with this HAT.
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
