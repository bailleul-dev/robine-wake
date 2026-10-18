# PLT-005 — Portage vers des cibles plus légères

## Statut

Retenu — 2026-10-17. Palier A retenu (**Raspberry Pi Zero 2 W + InnoMaker HiFi AMP Pro Mini HAT MA12070P**), supporté directement par l'image `rpi3` unifiée.

## Héritage v1

Conclusion de `experimental/robine-wake-rs/README.md` : le langage ne fixe pas
la carte minimale, les fonctions AirPlay 2 et Bluetooth audio la fixent.

## Objectif

Cadrer les cibles plus légères visées après le Pi 3, et les contraintes que
cela impose dès maintenant au code.

## Paliers de cibles

| Palier | Exemple de carte | RAM | Fonctions possibles | Effort |
|---|---|---|---|---|
| **A (Implémenté : `BOARD=rpi3`)** | **Pi Zero 2 W / Pi 3 B+ + InnoMaker MA12070P / Amp2** | 512 Mo – 1 Go | **Toutes** (AirPlay `soxr`, Bluetooth, MCP) | **Actif** : `aarch64-unknown-linux-musl` |
| **B (Implémenté : `BOARD=rpi0`)** | **Pi Zero 1 W + InnoMaker HiFi AMP Pro Mini HAT (MA12070P)** | 512 Mo | **Toutes** (AirPlay `basic` ~15 % CPU, Bluetooth, MCP) | **Actif** : `arm-unknown-linux-musleabihf` (ARMv6 32-bit, `robine_rpi0_defconfig`) |
| C | Microcontrôleur Wi-Fi (ESP32-S3 + ampli I²S) | 512 Ko + PSRAM | réveil, sons, bouton, API minimale | Nouveau projet no_std (`esp-hal`, `embassy`) |

## Contraintes dès maintenant

- `robine-core` reste sans E/S et compilable en `no_std + alloc` (PRD-002.1),
  pour être réutilisable au palier C et dans le firmware du bouton.
- Les fuseaux horaires et le calcul d'occurrences ne dépendent pas de l'OS.
- Le format des sons embarqués reste décodable sans FFmpeg (MP3 ou ADPCM
  décodés en Rust).
- Chaque fonction lourde est une option (PRD-001.3, PLT-001.6).

## Exigences

- `PLT-005.1` — `robine-core` compile pour `thumbv7em-none-eabihf` ou
  `xtensa-esp32s3-none-elf` dans la CI, sans `std`.
- `PLT-005.2` — L'image Buildroot réduite tient dans les budgets « réduite » de PLT-001.
- `PLT-005.3` — Ajouter une carte Linux = ajouter un defconfig et un dossier
  `board/`, sans modifier le code du démon.

## Décisions actées

- **Paliers retenus et implémentés** :
  - **Palier B (`make image BOARD=rpi0`)** : **Raspberry Pi Zero 1 W** (32-bit ARMv6 `arm-unknown-linux-musleabihf`, noyau `bcmrpi`, DTB `bcm2708-rpi-zero-w.dtb`, interpolation AirPlay `"basic"`) + **InnoMaker HiFi AMP Pro Mini HAT (MA12070P)**.
  - **Palier A (`make image BOARD=rpi3`)** : **Raspberry Pi Zero 2 W / Pi 3 B+** (64-bit `aarch64-unknown-linux-musl`) + **InnoMaker HiFi AMP Pro Mini HAT** ou **HiFiBerry Amp2**.
