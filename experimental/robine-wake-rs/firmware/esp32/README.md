# Firmware ESP32

Firmware Rust sans OS (`esp-hal`, `esp-radio`, `embassy`) qui sert l'API v1
de l'app mobile et du bouton déporté, sur le port 4000 comme le Raspberry Pi :

- alarmes de sommeil (création, modification, suppression, test, révisions) ;
- sieste (`nap.start`, `nap.cancel`) ;
- arrêt par le bouton déporté (`remote_button.*`, HMAC-SHA256 et compteur
  anti-rejeu) ; le téléphone n'arrête qu'une alarme de test ;
- flux temps réel `GET /api/v1/events` ;
- app web embarquée (`priv/web`, gzip) sur `http://<ip>:4000/`.

Le protocole vient de [`robine-api`](../../crates/robine-api), testé sur PC
(`cargo test -p robine-api` à la racine du workspace).

Sans ampli pour l'instant, la LED blanche (GPIO 25) clignote tant qu'une
alarme sonne. Hue, respiration guidée et caméra répondent
`unsupported_operation`.

## AirPlay 2

Le firmware embarque le récepteur [`robine-airplay`](../../crates/robine-airplay)
sous le nom « Robine Wake » : annonce mDNS `_airplay._tcp`, contrôle sur le
port 7000, événements 7001, audio 7002 (TCP mis en tampon, UDP temps réel),
retransmissions 7003, horloge PTP 319 et 320.

Sans ampli, le son décodé est seulement mesuré ; toutes les 5 s le journal
donne les trames décodées, le temps de décodage par trame, le niveau crête et
la mémoire libre.

État au 2026-10-18 sur Heltec V1 (ESP32 rév. 1.0, sans PSRAM) : démarrage,
vérificateur SRP en 1,6 s, annonce mDNS visible sur le réseau. **Pas encore
essayé avec un iPhone.** Limites de cette carte : tampon du flux mis en
tampon annoncé à 48 Kio, décodeur AAC créé seulement s'il reste 90 Kio de tas,
pile principale réduite à 21 Kio.

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
cargo run --release      # compile, flashe (table partitions.csv) et ouvre le moniteur
```

L'adresse s'affiche au démarrage (`Robine Wake ready: http://…:4000/`).
L'heure vient de `pool.ntp.org` ; tant qu'elle n'est pas réglée, aucune alarme
ne se déclenche.

## Stockage

`partitions.csv` réserve une partition `robine` de 64 Kio : deux emplacements
de 32 Kio écrits en alternance, avec en-tête et CRC-32, pour qu'une coupure
pendant une écriture laisse la sauvegarde précédente intacte. Une sonnerie en
cours au moment d'une coupure reprend au redémarrage.

## Révision de puce

`esp-hal` ne prend officiellement en charge que l'ESP32 révision 3.0 et plus.
`.cargo/esp-config.toml` abaisse le minimum à 1.0
(`ESP_HAL_CONFIG_MIN_CHIP_REVISION="100"`) pour la Heltec V1 sans PSRAM.
