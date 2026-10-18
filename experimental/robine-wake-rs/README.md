# Robine Wake (Rust + Buildroot)

Implémentation en Rust de Robine Wake sur un système Buildroot minimal (sans Nerves ni BEAM), intégrée dans `experimental/robine-wake-rs/`. L'application Elixir à la racine du dépôt reste la référence de production pour le moment.

Cibles Buildroot : QEMU (`qemu`), Raspberry Pi 3 (`rpi3`) et Raspberry Pi Zero / Zero 2W (`rpi0`).

Les spécifications v2 sont dans [`doc/specs`](doc/specs/README.md).

## Prérequis

- Les dépendances hôtes de Buildroot (`gcc`, `g++`, `make`, `patch`, `perl`,
  `python3`, `rsync`, `bc`, `cpio`, `unzip`, `file`, `wget`).
- `rustup` : la toolchain Rust est figée par `rust-toolchain.toml` et
  s'installe seule au premier `cargo`.
- QEMU n'est pas requis : Buildroot construit le sien (`output/<carte>/host`).

## Construire et lancer

```sh
make image                 # image QEMU virt (BOARD=qemu par défaut)
make qemu                  # démarre ; Ctrl-A X pour quitter

make image BOARD=rpi3      # image carte SD Raspberry Pi 3
make qemu BOARD=rpi3       # la même image dans QEMU raspi3b
```

Le premier build télécharge Buildroot 2026.02.3 (vérifié par SHA-256) dans
`.cache/`, la toolchain Bootlin et le noyau.

Sous QEMU, le réveil est joignable sur l'hôte :

- interface web : <http://localhost:4000>
- SSH : `ssh -p 2222 root@localhost` (clés `~/.ssh/id_*.pub` copiées au build)

## Développer le démon

```sh
make test                                   # tests du workspace sur l'hôte
cargo run -p robine-daemon                  # lance le démon sur l'hôte (:4000)
make deploy HOST=localhost SSH_PORT=2222    # remplace le démon sans reconstruire l'image
```

`make deploy` ne fonctionne qu'avec une image en mode développement
(`BR2_PACKAGE_ROBINE_WAKE_DEV_MODE`, actif dans les defconfigs actuels).

## Organisation

```text
crates/robine-core/     domaine pur sans I/O (`no_std + alloc`, `std` par défaut)
crates/robine-ports/    traits d'interface matérielle / système
crates/robine-daemon/   démon Rust complet (HTTP, SSE, MCP, mDNS, audio, LoRa, CLI)
crates/robine-api/      protocole de commandes v1 de l'app (no_std), partagé par les firmwares
crates/robine-airplay/  récepteur AirPlay 2 audio (no_std, sans E/S)
crates/robine-airplay-bench/  banc d'essai AirPlay sur PC (développement)
firmware/esp32/         firmware ESP32 sans OS (hors workspace, chaîne Xtensa)
br-external/            arbre BR2_EXTERNAL : defconfigs, cartes, paquets
doc/specs/              spécifications et comparatif v1/v2
../../priv/web/         bundle web partagé avec l'application Elixir
../../priv/sounds/      sons intégrés partagés avec l'application Elixir
Makefile                point d'entrée unique (Buildroot, QEMU, tests, déploiement)
```
