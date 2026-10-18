# PLT-001 — Système Buildroot minimal

## Statut

Brouillon — 2026-10-17. **Première étape du projet.**

## Héritage v1

`10/001-nerves-platform`, système `nerves_system_rpi3/` (Buildroot dérivé du
système Nerves officiel : toolchain Nerves armv7 glibc gcc 15.3, noyau
Raspberry Pi `stable_20260527` 6.18, firmware Pi `1.20260521`).

## Objectif

Produire, depuis ce dépôt et sans étape manuelle, une image carte SD minimale
pour Raspberry Pi 3 qui démarre le démon `robine-wake`, sans Nerves ni BEAM.

## Organisation

```text
br-external/                      arbre BR2_EXTERNAL "ROBINE"
  Config.in, external.mk, external.desc
  configs/robine_rpi3_defconfig
  configs/robine_qemu_defconfig   (QA-003)
  board/common/                   commun à toutes les cartes
    rootfs_overlay/               inittab, services runit, S05data, S06clock
    busybox.fragment, post-build.sh
  board/qemu-aarch64/             noyau mainline, genimage, lanceur QEMU
  board/rpi3/
    config.txt, cmdline.txt
    genimage.cfg.in | fwup.conf   (voir OPS-001)
    post-image.sh, run-qemu.sh    (QEMU raspi3b, QA-003)
    linux.fragment                fragment de config noyau
  package/
    robine-wake/                 le démon Rust
    shairport-sync5/             repris de la v1 (AUD-002)
    bluez-alsa5/                 repris de la v1 (AUD-003)
    libplist-host/               repris de la v1
Makefile                          make image / make menuconfig / make clean
```

Buildroot est récupéré à une version LTS figée (**2026.02.3**, téléchargée et
vérifiée par SHA-256 dans `.cache/`), jamais modifié en place. Le build se fait
hors source (`O=output/<carte>`).

## Choix structurants

| Sujet | Choix proposé | Raison |
|---|---|---|
| Toolchain C | Toolchain externe Bootlin aarch64 musl stable | Précompilée et figée : pas de build de GCC. musl est plus léger. Repli possible sur glibc si AirPlay ou BlueZ posent problème. |
| Architecture | aarch64 | Retenue pour la phase 1 : meilleur support Rust et paquets, compatible Pi Zero 2 W. Le 32 bits armv7 reste possible. |
| Init | BusyBox init + applets runit de BusyBox | Voir PLT-004. Pas de systemd. |
| Gestion de `/dev` | `devtmpfs` + `mdev` | Suffisant pour ALSA, spidev, watchdog et firmware Wi-Fi/BT. |
| Rootfs | squashfs en lecture seule | Résiste aux coupures de courant, comme en v1. |
| Données | partition ext4 `/data` | Configuration, sons importés, appairages, journal critique. |
| Volatile | `tmpfs` sur `/tmp` et `/run` | Aucune écriture SD hors `/data`. |
| Noyau | Noyau Raspberry Pi, même version que la v1 au départ | Le changement de noyau est un risque séparé du changement d'OS. |

## Contenu de l'image

Inclus par défaut :

- noyau, DTB Pi 3 / 3 B+ / Zero 2 W, firmware de démarrage Pi ;
- BusyBox, dropbear (OPS-002), fwup (OPS-001) ;
- `alsa-lib` (sans `alsa-utils` en production, voir AUD-001) ;
- `wpa_supplicant` minimal (WPA2/WPA3 personnel uniquement) ;
- firmwares Wi-Fi et Bluetooth Broadcom du Pi ;
- `ca-certificates` seulement si une fonction en a besoin ;
- le démon `robine-wake`.

Inclus seulement si la fonction est activée :

- AirPlay : `shairport-sync5`, `nqptp`, `avahi`, `dbus`, FFmpeg réduit (AUD-002) ;
- Bluetooth : `bluez5_utils`, `bluez-alsa5`, `fdk-aac`, `libopenaptx`, `dbus` (AUD-003).

Retirés par rapport à la v1 (sans usage dans le périmètre v2) :

- `rpicam-apps`, `libcamera`, `camera_auto_detect` (caméra retirée) ;
- `cairo`, `unixodbc`, `libp11`, toolchain avec Fortran et OpenMP ;
- `BR2_ENABLE_DEBUG` ;
- `mpg123` et le binaire `ffmpeg` pour la lecture d'alarme (décodage dans le
  démon, AUD-001) ;
- `linux-firmware` Ralink, options `wpa_supplicant` mesh, hotspot, WPS, AP ;
- overlays écran tactile `rpi-ft5406`, `rpi-backlight` ;
- `erlinit`, `nbtty`, `nerves_config`, ERTS.

## Paquet `robine-wake`

- Le Rust de Buildroot 2026.02 (1.88) est trop ancien pour les dépendances du
  démon (`uuid` exige 1.89). Le démon est donc compilé **hors Buildroot** par
  `make dist`, avec la toolchain figée par `rust-toolchain.toml`, en binaire
  statique `aarch64-unknown-linux-musl` lié par `rust-lld`.
- Le paquet `robine-wake` est un `generic-package` local qui installe le
  dossier préparé `output/dist/` : binaire, bundle web, sons, clés SSH.
- Quand le démon aura des dépendances C (alsa-lib, AUD-001), il sera lié avec
  la toolchain et le sysroot produits par Buildroot (`output/<carte>/host`),
  toujours compilé par la toolchain Rust figée.
- Les sons de la v1 pèsent 93 Mo : ils ne tiennent pas dans le budget du
  rootfs. Ils ne sont pas embarqués en phase 1 ; leur place (partition
  dédiée, `/data`, sons compressés plus légers) reste à décider avec AUD-001.

## Budgets cibles

À vérifier en phase 1 (QA-002). Valeurs de départ, pas des engagements.

| Mesure | Image complète (AirPlay + BT) | Image réduite (sans AirPlay ni BT) |
|---|---|---|
| Rootfs squashfs | ≤ 60 Mo | ≤ 20 Mo |
| RAM utilisée au repos (système entier) | ≤ 96 Mo | ≤ 40 Mo |
| RSS du démon au repos | ≤ 20 Mo | ≤ 20 Mo |
| Mise sous tension → planificateur prêt | ≤ 10 s | ≤ 8 s |
| Build complet à froid (24 cœurs) | ≤ 45 min | ≤ 30 min |

## Exigences

- `PLT-001.1` — `make image` produit une image flashable depuis un clone propre,
  sans action manuelle autre que l'installation des dépendances hôtes documentées.
- `PLT-001.2` — Le build est reproductible : versions de Buildroot, du noyau,
  du firmware et des crates figées par hash ou lockfile.
- `PLT-001.3` — Le rootfs est monté en lecture seule ; seules `/data`, `/tmp` et
  `/run` sont inscriptibles.
- `PLT-001.4` — Une partition `/data` absente, vide ou corrompue est recréée ou
  remplacée par des valeurs par défaut sans empêcher le démarrage.
- `PLT-001.5` — Aucun secret (Wi-Fi, clé privée de signature) n'est commité ni
  écrit dans les logs de build ; les secrets de provisioning viennent de `.env`,
  comme en v1.
- `PLT-001.6` — Les fonctions AirPlay, Bluetooth et LoRa sont des options du
  defconfig ; les désactiver retire leurs paquets de l'image.
- `PLT-001.7` — Les budgets ci-dessus sont mesurés à chaque version et publiés
  dans le comparatif (QA-002).

## Critères d'acceptation

1. Une image construite depuis un clone propre démarre sous QEMU `raspi3b`
   (QA-003), puis sur un Pi 3 B+ rev 1.3 dès qu'il est disponible, obtient une
   adresse et répond sur `/health`.
2. Le prototype Rust v1 tourne comme démon au démarrage et sert l'interface web.
3. Après 20 coupures de courant brutales, le système redémarre sans fsck
   manuel et `/data` reste lisible.
4. Le rapport de taille et de temps de démarrage est produit et comparé à la v1.

## Questions ouvertes

- musl à confirmer avec shairport-sync 5 et BlueALSA 5.
- Emplacement des sons embarqués (93 Mo en v1).
