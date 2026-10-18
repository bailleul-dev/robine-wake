# esp32-hello

Firmware Rust sans OS (`esp-hal`, `esp-radio`, `embassy`) sur Heltec WiFi Kit 32
V1 (ESP32 révision 1.0) : connexion Wi-Fi, adresse par DHCP, et serveur HTTP
sur le port 80 qui répond `robine esp32`.

## Wi-Fi

Créer `wifi.ini` (ignoré par git), lu par `build.rs` à la compilation :

```ini
ssid=MonReseau
password=MonMotDePasse
```

Le format nu est aussi accepté : SSID sur la première ligne, mot de passe sur
la deuxième.

## Utilisation

```sh
. ~/export-esp.sh
cargo run --release      # compile, flashe et ouvre le moniteur série
curl http://<ip>/        # IP affichée dans le moniteur
```

## Révision de puce

`esp-hal` ne prend officiellement en charge que l'ESP32 révision 3.0 et plus.
`.cargo/esp-config.toml` abaisse le minimum à 1.0
(`ESP_HAL_CONFIG_MIN_CHIP_REVISION="100"`) pour cette carte sans PSRAM.
