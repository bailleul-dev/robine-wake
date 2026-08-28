# Bouton déporté d'arrêt du réveil en LoRa

## Architecture retenue

Le bouton et le Raspberry Pi communiquent directement en LoRa point-à-point. Il ne s'agit pas de
LoRaWAN : il n'y a ni passerelle Internet, ni compte cloud, ni serveur externe. Le Raspberry est le
récepteur permanent (« serveur ») et le bouton Arduino est un émetteur qui attend un accusé de
réception.

La première implémentation cible deux modules RFM95/SX1276 en 868 MHz : un sur le Raspberry Pi 3
et un sur l'Arduino Pro Mini 3,3 V / 8 MHz. Les deux radios doivent employer exactement les mêmes
paramètres :

| Paramètre | Valeur |
| --- | --- |
| Fréquence | 868,1 MHz |
| Bande passante | 125 kHz |
| Facteur d'étalement | SF9 |
| Taux de codage | 4/5 |
| Préambule | 8 symboles |
| CRC de charge utile | activé |
| En-tête | explicite |
| Mot de synchronisation | `0x12` (réseau privé) |
| Puissance Raspberry | 14 dBm |

Le processus `RobineWake.LoRa.Server` ouvre `spidev0.0`, configure le SX1276 puis écoute en
réception continue. Il interroge les drapeaux d'interruption toutes les 25 ms ; la broche DIO0
n'est donc pas requise. Après chaque paquet valide, il repasse brièvement en émission pour envoyer
la réponse, puis revient automatiquement en écoute.

## Câblage RFM95 vers Raspberry Pi 3

Le module est strictement en 3,3 V. Ne jamais relier VCC à 5 V et ne jamais émettre sans antenne.

| RFM95 / SX1276 | Raspberry Pi | Broche physique |
| --- | --- | --- |
| `3.3V` | 3,3 V | 1 ou 17 |
| `GND` | masse | 6 |
| `SCK` | GPIO11 / SPI0 SCLK | 23 |
| `MISO` | GPIO9 / SPI0 MISO | 21 |
| `MOSI` | GPIO10 / SPI0 MOSI | 19 |
| `NSS` / `CS` | GPIO8 / SPI0 CE0 | 24 |
| `RESET` | tirage 10 kΩ vers 3,3 V | — |
| `DIO0` | non connecté pour cette version | — |

Placer au minimum un condensateur de 100 nF et un de 10 µF entre 3,3 V et GND au plus près du
module. Utiliser une antenne 868 MHz adaptée ; un simple fil quart d'onde mesure environ 86 mm.

Le SPI est déjà activé dans l'image Nerves avec `dtparam=spi=on`. Au démarrage, le pilote lit
`RegVersion` et exige `0x12`. Une autre valeur fait passer le service en état indisponible plutôt
que d'écouter avec une radio mal câblée.

## Association et authentification

L'utilisateur ouvre une fenêtre d'association de 30 à 300 secondes depuis l'app mobile ou web.
Le bouton envoie alors un paquet `pair`. Le Raspberry crée un secret aléatoire de 256 bits, le
conserve dans ses paramètres privés et le retourne une seule fois au bouton. La réponse est mise
en cache pendant cinq minutes : si l'accusé est perdu, la même demande reçoit exactement le même
secret au lieu de créer une nouvelle association.

Chaque arrêt signe avec HMAC-SHA256 les octets suivants :

```text
rw-remote-v1 NUL identifiant NUL compteur-décimal NUL dismiss
```

Le compteur doit être persisté dans l'EEPROM du bouton avant l'émission. Le Raspberry vérifie le
HMAC puis persiste le compteur avant d'arrêter la session. Une retransmission du dernier compteur
est acquittée sans rejouer l'action ; un compteur plus ancien est rejeté.

Vecteur de compatibilité : secret composé de 32 octets `42`, identifiant
`button-001122334455`, compteur `7`, résultat
`5afbdaf88cbe8167dd711c4492008bb956932b7351f26b60db69237639d9f995`.

## Protocole radio

Chaque charge utile est un document JSON UTF-8 de 255 octets maximum.

Association :

```json
{"v":1,"id":"p1","op":"pair","body":{"button_id":"button-a1b2","name":"Bouton chevet"}}
```

Arrêt :

```json
{"v":1,"id":"d7","op":"dismiss","body":{"button_id":"button-a1b2","counter":7,"mac":"<64 caractères hexadécimaux>"}}
```

Le champ `id` sert à reconnaître l'accusé. Le bouton peut retransmettre le même paquet en cas de
silence ; le Raspberry conserve les 32 dernières réponses pendant cinq minutes.

## Configuration et diagnostic

La configuration se trouve dans `config/target.exs`. Le service démarre automatiquement sur le
Raspberry et réessaie d'ouvrir la radio toutes les cinq secondes si le module est absent.

Dans une console IEx du réveil :

```elixir
RobineWake.LoRa.Server.status()
```

Un état normal ressemble à :

```elixir
%{state: :listening, packets_received: 3, packets_rejected: 0, last_error: nil}
```

La référence exacte du module doit être vérifiée avant câblage. Un E32/E220 ou un module SX126x
n'utilise pas ce pilote SPI SX1276 et nécessite un adaptateur différent.
