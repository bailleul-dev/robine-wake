# PLT-002 — Support carte Raspberry Pi 3

## Statut

Brouillon — 2026-10-17.

## Héritage v1

`10/002-hardware-profile`, `nerves_system_rpi3/config.txt`,
`config/rpi3-config.txt`, `knowledges/remote-alarm-button.md`.

## Objectif

Configurer le démarrage, les overlays et les périphériques du Pi 3 B+ pour le
matériel Robine Wake.

## Matériel de référence

| Élément | Référence Pi 3 (format standard) | Référence Pi Zero 2 W (format compact) |
|---|---|---|
| Carte | Raspberry Pi 3 B+ rev 1.3 (`a020d3`) | Raspberry Pi Zero 2 W (`902120`, 512 Mo RAM) |
| Audio | HiFiBerry Amp2 (`hifiberry-dacplus`, mixeur `Digital`) | **InnoMaker HiFi AMP Pro Mini HAT** (`merus-amp`, puce Infineon MA12070P 2×80 W crête, mixeur `A.Mstr Vol`) |
| Alimentation | 16,5 V / 2 A via l'Amp2 | 4–26 V (ex. 16,5 V) via l'InnoMaker Mini HAT |
| Stockage | microSD haute endurance ≥ 16 Go | microSD haute endurance ≥ 16 Go |
| Radio LoRa | RFM95/SX1276 868 MHz sur SPI0 CE0 (optionnel) | RFM95/SX1276 868 MHz sur SPI0 CE0 (optionnel) |
| RTC | module I²C recommandé hors ligne | module I²C recommandé hors ligne |

## `config.txt` cible

```ini
arm_64bit=1              # si aarch64 retenu (PLT-001)
kernel=Image
disable_splash=1
gpu_mem=16               # v1 : 192, sans usage sans caméra ni écran
[pi3]
dtoverlay=hifiberry-dacplus
enable_uart=1            # console série sur Pi 3
[pi02]
dtoverlay=merus-amp
enable_uart=0            # merus-amp utilise GPIO 14 (enable) et GPIO 15 (mute)
[all]
dtparam=audio=off        # pas de sortie analogique interne
dtparam=spi=on           # seulement si LoRa
dtparam=i2c_arm=on       # seulement si RTC
dtparam=krnbt=on         # Bluetooth sur PL011 (AUD-003)
dtoverlay=ramoops        # journal de panique noyau persistant en RAM
boot_delay=0
```

Supprimés par rapport à la v1 : `camera_auto_detect`, `rpi-ft5406`,
`rpi-backlight`, `miniuart-bt`, `core_freq=250` (à revérifier si la console
série devient instable).

## Périphériques

- **ALSA** : la carte HiFiBerry est sélectionnée par son nom stable, jamais par
  son index (`HW-002` v1).
- **Wi-Fi** : `brcmfmac` + firmware Broadcom ; le Pi 3 B+ supporte 5 GHz, le
  Pi 3 B seulement 2,4 GHz.
- **Bluetooth** : `hci_uart` sur PL011 seulement si AUD-003 est activé ; sinon
  le contrôleur reste éteint pour libérer l'UART.
- **SPI** : `spidev0.0` pour le SX1276 (ACC-003).
- **Watchdog** : `bcm2835_wdt` exposé en `/dev/watchdog` (PLT-004).
- **Conflits GPIO** : l'Amp2 utilise l'I²S et une partie du connecteur ; tout
  nouveau câblage (SPI, I²C, bouton local) est documenté avant soudure
  (`HW-003` v1).

## Exigences

- `PLT-002.1` — L'Amp2 est détectée au démarrage sous un nom de carte ALSA stable.
- `PLT-002.2` — Aucun overlay ni module lié à la caméra ou à un écran n'est chargé.
- `PLT-002.3` — Le Wi-Fi fonctionne en 2,4 GHz sur Pi 3 B et en 2,4/5 GHz sur Pi 3 B+.
- `PLT-002.4` — Le Bluetooth n'est initialisé que si la fonction est incluse
  dans l'image.
- `PLT-002.5` — La même image démarre sur Pi 3 B, Pi 3 B+ et Pi Zero 2 W (même
  SoC BCM2710), Amp2 mise à part.

## Critères d'acceptation

- `aplay -l` (image de debug) ou la santé du démon montrent l'Amp2 sous son
  nom stable.
- `dmesg` ne contient ni erreur de firmware Wi-Fi ni module caméra.
- La même image démarre sur un Pi 3 B+ et un Pi Zero 2 W.

## Questions ouvertes

- Modèle de RTC et son intégration (`rtc-ds3231` ou équivalent).
- `gpu_mem=16` est-il compatible avec le firmware actuel sans sortie HDMI ?
