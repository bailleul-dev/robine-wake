---
title: Build & flash
description: Build signed firmware and put it on an SD card.
sidebar:
  order: 6
---

## Build

```sh
make firmware           # MIX_TARGET=rpi3
make firmware-rpi0      # MIX_TARGET=rpi0
```

The first build compiles a complete Buildroot system and takes a while; later
builds are incremental. The AirPlay daemon (`robine-airplayd`, Rust, static
musl ARMv6 hard-float) is built first and shared by both targets.

## Wi-Fi at build time

Without values in `.env` the Pi 3 uses Ethernet only. Set both
`ROBINE_WIFI_SSID` and `ROBINE_WIFI_PASSPHRASE` (WPA2) to embed Wi-Fi in your
local image; they are never written to the repository or printed.

The Pi Zero W has no Ethernet. Its micro-USB **data** port is an Ethernet
gadget (`usb0`), so you can reach it before Wi-Fi is configured.

## Signed updates

Updates are accepted only when signed with the Ed25519 key whose public half is
embedded in the firmware; the private half stays outside the repository.

```sh
scripts/build_signed_firmware.sh
make verify-firmware
```

## Flash

```sh
make burn-sd DEVICE=/dev/diskN                      # Pi 3
make burn-sd MIX_TARGET=rpi0 DEVICE=/dev/diskN      # Pi Zero W
```

`burn-sd` refuses any disk that is not external and removable.

## Over the air

Once running, firmware is pushed over authenticated SSH/fwup with a pre-check
policy. See [operations & updates](../../specs/70-001-operations-updates/).
