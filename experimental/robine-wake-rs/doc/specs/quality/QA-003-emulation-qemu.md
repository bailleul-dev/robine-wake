# QA-003 — Émulation QEMU

## Statut

Brouillon — 2026-10-17. Phase 1, en attendant un Raspberry Pi 3 physique.

## Objectif

Développer et valider la plateforme (PLT-001 à PLT-004, OPS-001, OPS-002) sans
matériel, avec QEMU, et savoir exactement ce qui reste à valider sur un vrai Pi.

## Deux machines émulées

| | `raspi3b` | `virt` (cortex-a53) |
|---|---|---|
| Rôle | Valider **la vraie image Pi 3** : même noyau, même DTB, même rootfs | Boucle de dev rapide et CI |
| Defconfig | `robine_rpi3_defconfig` | `robine_qemu_defconfig` (même `br-external`, mêmes paquets et overlays, noyau mainline) |
| CPU / RAM | 4 × Cortex-A53, 1 Go (fixe) | réglable (ex. 256 Mo ou 128 Mo pour simuler une cible légère) |
| Démarrage | `-kernel` + `-dtb` directs : le firmware GPU (`bootcode.bin`, `start.elf`, `config.txt`) n'est **pas** exécuté | `-kernel` direct ou U-Boot |
| Disque | carte SD émulée (image de taille puissance de 2) | virtio-blk |
| Réseau | `usb-net` sur le contrôleur USB dwc2 (pas le LAN9514 réel) | virtio-net |
| Audio | aucun (pas d'I²S, pas d'Amp2) | `virtio-sound` ou `intel-hda` : vraie carte ALSA pour tester le moteur audio |
| Watchdog | partiel, à vérifier | `i6300esb` |
| Vitesse | lente (émulation TCG d'un SoC complet) | correcte |

Les deux se lancent par le même `Makefile` :

```sh
make image BOARD=rpi3 && make qemu BOARD=rpi3   # -M raspi3b
make image && make qemu                         # virt ; HTTP localhost:4000, SSH localhost:2222
```

QEMU vient du paquet hôte `qemu-system-arm` (Ubuntu 26.04 : 10.2), ou de
`host-qemu` construit par Buildroot pour ne pas dépendre de la distribution.

## Ce que QEMU valide

- Démarrage du noyau et de l'init, montages, rootfs en lecture seule, `/data`
  créée au premier démarrage (PLT-001, PLT-004).
- Supervision : relance du démon, services accessoires `down` par défaut.
- Réseau, DHCP, mDNS dans le réseau QEMU, SSH par clé, `make deploy` (OPS-002).
- Écriture d'un paquet fwup dans le slot inactif, vérification de signature,
  refus d'un paquet non signé, règle de mise à jour du démon (OPS-001).
- Validation du firmware par le démon et bascule A/B sur `virt` via un
  démarrage simulé (voir limites).
- Moteur audio contre une vraie carte ALSA (`virt` + `virtio-sound`) : ouverture,
  gain logiciel, boucle, fondu, préemption (AUD-001, sans la courbe Amp2).
- Coupures brutales (`kill` de QEMU) pendant les écritures sur `/data`.
- Empreinte : taille d'image, RAM et RSS au repos (indicatif, à confirmer sur Pi).

## Ce que QEMU ne valide pas (reste pour le vrai Pi)

- `config.txt`, overlays (`hifiberry-dacplus`), `autoboot.txt` et **tryboot** :
  le firmware GPU n'est pas émulé. Le retour automatique A/B réel n'est
  vérifiable que sur matériel.
- Amp2 : nom de carte, mixeur `Digital`, courbe de gain, niveau sonore.
- Wi-Fi, Bluetooth, firmware Broadcom, coexistence radio.
- SPI réel (LoRa), I²C (RTC), watchdog matériel `bcm2835_wdt`.
- Temps de démarrage et performances réels.

## Exigences

- `QA-003.1` — `make qemu-pi` démarre l'image Pi 3 jusqu'à `/health` sans matériel.
- `QA-003.2` — Les defconfigs `rpi3` et `qemu` partagent le même arbre
  `br-external` ; seuls le noyau, le DTB et `board/` diffèrent.
- `QA-003.3` — Un test automatique démarre l'image `virt`, vérifie `/health`,
  SSH et une mise à jour fwup, et tourne en CI.
- `QA-003.4` — Chaque résultat obtenu sous QEMU est marqué comme tel dans le
  comparatif (QA-002) tant qu'il n'est pas confirmé sur Pi.

## Questions ouvertes

- Simulation de tryboot sous `virt` : un script lanceur qui lit l'état A/B dans
  l'image et choisit le noyau et le rootfs à démarrer suffit-il pour tester la
  logique de validation ?
