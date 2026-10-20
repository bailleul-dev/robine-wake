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

Sans ampli pour l'instant, le GPIO 25 (la LED blanche de la Heltec V1,
`D25` sans LED sur une DevKit) clignote tant qu'une alarme sonne. Hue et caméra répondent `unsupported_operation`.

## Veilleuse NeoPixel

Une Adafruit Flora RGB Smart NeoPixel sert de guide lumineux pour la
respiration 4/6. Le Raspberry Pi, maître de l'audio, garde l'horloge de la
séance ([30-003](../../../../docs/specs/30/003-guided-breathing/spec.md)) et
pilote la LED par une commande bas niveau, une par phase, comme les
transitions natives Hue. Elle passe par la liaison série avec le Pi (voir
plus bas) ou par HTTP, avec la même enveloppe API-002 :

```json
{"v":1,"id":"guide-light-42","op":"light.set","body":{
  "color":{"r":255,"g":120,"b":12},"brightness":30,
  "transition_ms":4000,"easing":"smoothstep"}}
```

| Champ | |
|---|---|
| `brightness` | obligatoire, 0 à 100 % (rapport cyclique PWM, pas de gamma) |
| `color` | `{"r","g","b"}` de 0 à 255 ; garde la couleur actuelle s'il est omis |
| `transition_ms` | 0 (immédiat, par défaut) à 60 000 |
| `easing` | `linear` (par défaut) ou `smoothstep` |

La transition part toujours de la couleur affichée à la réception, même
si la précédente n'était pas finie. `light.get` renvoie la couleur actuelle,
la cible et le temps de transition restant. L'ESP32 calcule les images à
50 Hz et ne garde aucun rythme propre : la LED reste sur la dernière
consigne jusqu'à la suivante. Elle est éteinte au démarrage et n'est pas
persistée.

| Flora NeoPixel | Heltec WiFi Kit 32 V1 |
|---|---|
| `+` | 3V3 |
| `−` | GND |
| `→` (entrée, flèche vers le pixel) | GPIO 13, via 330 Ω |

Alimentée en 3,3 V, la WS2812B accepte directement les données 3,3 V de
l'ESP32 : pas de level shifter. Elle éclaire un peu moins fort qu'en 5 V,
sans importance la nuit. Le signal sort du SPI2 par DMA (3 bits SPI à
2,5 MHz par bit WS2812B) : toute la trame part sans le CPU, et ni le Wi-Fi
ni une tâche occupée ne peuvent déformer ou rejouer des bits. Avec le RMT,
rechargé par la tâche async, 60 LED flashaient dès que le Wi-Fi tournait.

## Ruban LED et aube

`light.program` lance un programme que l'ESP32 joue seul jusqu'à la
commande suivante ; le Raspberry Pi le relaie depuis l'app web (onglet
Soir, carte « Ruban lumineux ») :

```json
{"v":1,"id":"1","op":"light.program","body":{"program":"dawn","duration_ms":1800000}}
{"v":1,"id":"2","op":"light.program","body":{"program":"sunset","duration_ms":1800000}}
{"v":1,"id":"3","op":"light.program","body":{"program":"breathing","cadence":"0-4-0-6","duration_ms":300000}}
{"v":1,"id":"4","op":"light.program","body":{"program":"off"}}
```

Durées de 1 ms à 2 h ; erreurs `invalid_program`, `invalid_duration`,
`invalid_cadence`. Un `light.set` remplace le programme en cours.

La même sortie (GPIO 13) pilote un ruban WS2812B de 60 LED : une
transition `light.set` met tout le ruban de la même couleur.
`guide_light::start_dawn(duree_ms)` lance une aube artificielle
([00-002](../../../../docs/specs/00/002-gentle-awakening-mechanisms/spec.md)),
calculée LED par LED par `robine_api::Dawn` : une LED orange faible au
centre (≈ 1800 K) qui s'étend en dégradé, monte et se refroidit, puis tout
le ruban en blanc de jour uniforme (≈ 5500 K), plafonné à 60 % pour une
petite alimentation 5 V. Elle reste allumée jusqu'à la commande suivante.

| Ruban | |
|---|---|
| `Din` (côté des flèches qui partent vers le ruban) | GPIO 13, via 330 Ω |
| `+5V`, `GND` (fils d'injection) | alimentation 5 V séparée |
| `GND` | GND de la carte : sans masse commune, le signal se brouille |

`guide_light::start_sunset(duree_ms)` lance un coucher de soleil pour
s'endormir, calculé par `robine_api::Sunset` : tout le ruban s'allume d'un
coup en ambre (≈ 2200 K, 40 % du plafond), puis baisse sur la courbe de
l'aube à l'envers et rougit, les bords s'éteignant en premier, jusqu'à une
LED rouge faible au centre qui s'éteint. Jamais plus froid que 2200 K.

`guide_light::start_breathing(Cadence::parse("0-4-0-6"), duree_ms)` lance une
respiration guidée ([30-003](../../../../docs/specs/30/003-guided-breathing/spec.md)),
calculée par `robine_api::Breathing`. La cadence s'écrit `pause poumons
vides-inspiration-pause poumons pleins-expiration`, en secondes (`0-4-0-6` :
cohérence cardiaque). Poumons vides, seule la LED du centre luit en rouge
très faible ; à l'inspiration, une fenêtre glisse du centre vers chaque bout
en s'élargissant linéairement jusqu'à 10 LED par côté, et revient à
l'expiration. Au bout de la durée, elle finit le souffle en cours (poumons
vides) et le ruban s'éteint.

Démos de banc, sans Wi-Fi ni Pi :

```sh
cargo run --release --bin dawn_demo     # aube compressée à 1 minute
cargo run --release --bin sunset_demo   # coucher compressé à 1 minute
cargo run --release --bin breathing_demo  # respiration 0-4-0-6 d'une minute
cargo run --release --bin strip_probe   # identifie le protocole d'un ruban inconnu
```

## Liaison série avec le Raspberry Pi

Sur le réveil, l'ESP32 tourne `pi_light` : le ruban et cette liaison,
sans Wi-Fi, HTTP ni AirPlay (le firmware `robine-esp32` complet reste
l'expérience autonome). Le Pi relaie les commandes de l'app web.

UART2 à 115 200 bauds, 8N1. Une requête JSON par ligne (`\n`), une réponse
par ligne avec le même `id`, traitée comme `POST /api/v1/command`. Les
lignes qui ne commencent pas par `{` sont ignorées sans réponse : la console
noyau du Pi écrit sur le même UART.

| Raspberry Pi 3 (sous la HiFiBerry Amp2) | ESP32 DevKit 30 broches |
|---|---|
| GPIO 14 TXD (broche 8, 4ᵉ de la rangée extérieure) | `D18` (GPIO 18, RX) |
| GPIO 15 RXD (broche 10, 5ᵉ de la rangée extérieure) | `TX2` (GPIO 17, TX) |
| GND (broche 6, 3ᵉ de la rangée extérieure) | `GND` |
| port USB | USB-C : alimentation, et flashage si le câble porte les données |

Les deux cartes sont en 3,3 V : fils directs. Sur la DevKit, le GPIO 17 est
marqué `TX2` ; `RX2` (GPIO 16) n'est pas utilisé. Côté Pi, c'est le mini UART
`ttyS0` (le PL011 sert au Bluetooth), réglé par
`config :robine_wake, guide_light: [driver: RobineWake.GuideLight.Driver.UART, device: "ttyS0"]`
dans `config/target.exs`. Pour passer par le Wi-Fi à la place :
`ROBINE_GUIDE_LIGHT_URL=http://robine-wake-xxxxxx.local:4000`.

## AirPlay 2

Le firmware embarque le récepteur [`robine-airplay`](../../crates/robine-airplay)
sous le nom « Robine Wake » : annonce mDNS `_airplay._tcp`, contrôle sur le
port 7000, événements 7001, audio 7002 (TCP mis en tampon, UDP temps réel),
retransmissions 7003, horloge PTP 319 et 320.

Sans ampli, le son décodé est seulement mesuré ; toutes les 5 s le journal
donne les trames décodées, le temps de décodage par trame, le niveau crête et
la mémoire libre.

État au 2026-10-18 sur Heltec V1 (ESP32 rév. 1.0, sans PSRAM), essayé avec
un iPhone sous iOS 27 :

| | Résultat |
|---|---|
| Appairage SRP 3072 bits | environ 3,5 s (vérificateur préparé en 1,6 s au démarrage) |
| FairPlay, `SETUP`, `RECORD`, volume, PTP | fonctionnent |
| Flux temps réel ALAC | 124 trames/s, aucune rejetée ni corrompue |
| Décodage ALAC | 3,6 ms par trame de 8 ms (environ 45 % d'un cœur) |
| Tas libre pendant la lecture | 69 Kio |

Le flux mis en tampon (AAC, ex. YouTube) demande 90 Kio de tas pour son
décodeur : la Heltec ne les a pas, ce sera pour l'ESP32-S3 N16R8. Autres
limites de cette carte : tampon annoncé de 48 Kio, pile principale de 21 Kio.

Le nom d'hôte mDNS est propre à chaque carte (`robine-wake-xxxxxx.local`) :
le Raspberry Pi répond déjà à `robine-wake.local`, et un iPhone qui résout
ce nom vers le Pi ne joint jamais l'ESP32.

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
