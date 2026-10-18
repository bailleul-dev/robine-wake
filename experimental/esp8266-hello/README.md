# esp8266-hello

Premier firmware Rust sans OS sur la NodeMCU DevKit v0.9 (ESP8266, ESP-12) :
la LED bleue du module clignote et la carte écrit `robine esp8266: tick N` sur
le port série toutes les 500 ms.

L'ESP8266 n'est plus maintenu dans l'écosystème Rust (`esp8266-hal` 0.5.1,
2022). Ce projet sert à apprendre la chaîne Rust embarquée avant l'arrivée de
l'ESP32-S3, pas de base au produit.

## Outils

```sh
cargo install espup --locked && espup install --targets esp32s3   # compilateur Rust « esp »
# éditeur de liens GCC ESP8266 d'Espressif
mkdir -p ~/.local/opt && curl -fsSL https://dl.espressif.com/dl/xtensa-lx106-elf-gcc8_4_0-esp-2020r3-linux-amd64.tar.gz | tar xz -C ~/.local/opt
uv tool install esptool                                           # espflash ne gère plus l'ESP8266
```

## Utilisation

```sh
make flash            # compile, convertit l'ELF en image ESP8266 et flashe /dev/ttyUSB0
make monitor          # port série à 115200
```

## Correctif de `xtensa-lx-rt`

`patches/xtensa-lx-rt` est la version 0.12.0, dernière à gérer l'ESP8266,
corrigée pour les compilateurs récents :

- `#[naked]` devient `#[unsafe(naked)]` et `asm!` devient `naked_asm!` ;
- `src/exception/assembly_esp8266.rs` est regroupé en un seul `global_asm!`,
  car les fonctions naked sont maintenant émises séparément des macros
  assembleur `SAVE_CONTEXT` / `RESTORE_CONTEXT` qu'elles utilisent.
