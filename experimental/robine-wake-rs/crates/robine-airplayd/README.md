# robine-airplayd

Récepteur AirPlay 2 pour le Raspberry Pi, sur le cœur
[`robine-airplay`](../robine-airplay) qui tourne aussi sur l'ESP32. Il vise à
remplacer Shairport Sync, NQPTP et Avahi par un binaire statique de 1,4 Mio
que l'app Elixir pilote directement.

```sh
robine-airplayd --name "Robine Wake Bedroom" --device plughw:0 --data-dir /data/airplay
```

| Option | Défaut | |
|---|---|---|
| `--name` | `Robine Wake Bedroom` | nom dans le sélecteur AirPlay |
| `--device` | `plughw:0` | sortie ALSA, ouverte par `aplay` en S32_LE |
| `--data-dir` | `/data/airplay` | identité persistante (`identity`, 54 octets) |
| `--host` | `robine-wake-airplay` | nom d'hôte mDNS, distinct de celui du Pi |

Le binaire annonce lui-même `_airplay._tcp` et suit l'horloge PTP de
l'émetteur sur les ports 319 et 320 : NQPTP ne doit pas tourner en même temps.

## Protocole avec Elixir

Une ligne JSON par message. Les journaux vont sur stderr.

Événements (stdout) : `ready`, `client` (`connected` / `disconnected`),
`stream` (`buffered` / `realtime`), `session` (`playing` / `paused` /
`stopped`), `volume` (`db`), `output` (`open` / `closed`), `suspended`,
`resumed`, `stats` (toutes les 5 s pendant la lecture : trames reçues,
en retard, corrections, retransmissions), `error` (`reason`).

Commandes (stdin) : `{"cmd":"suspend"}` libère la carte son, puis répond
`suspended` une fois `aplay` fermé, et jette l'audio tant que dure la
suspension (une alarme prend le haut-parleur) ; `{"cmd":"resume"}`. Le processus se
termine quand stdin se ferme, donc jamais après le port Erlang.

## Sortie

Une seule sortie ALSA pour les deux flux, car la HiFiBerry ne s'ouvre qu'une
fois. Le volume AirPlay s'applique en logiciel sur 32 bits, comme Shairport
Sync ; le mixeur matériel reste à l'app Elixir. La carte est libérée après
2 s sans audio, à la fin de session et pendant une suspension.

## Synchronisation

Chaque échantillon est joué à l'heure que lui donne l'horloge PTP de
l'émetteur : le flux bufferisé (AAC) depuis l'ancre de `SETRATEANCHORTIME`,
le flux temps réel (ALAC) depuis les paquets de synchro `0xD7` du port de
contrôle, envoyés chaque seconde. Les paquets temps réel sont remis dans
l'ordre ; un trou dans les numéros de séquence est redemandé à l'émetteur
(`0xD5`, réponses `0xD6`) et joué en silence s'il ne revient pas à temps.

Tant qu'elle est ouverte, la sortie est écrite en continu (du silence s'il
n'y a rien à jouer) à travers un pipe réduit à une page : chaque écriture
attend que la DAC ait fait de la place, donc le prochain échantillon écrit
sera entendu dans « buffer ALSA + pipe + demi-période », relevés dans la
sortie `-v` d'`aplay` (environ 115 ms). L'écart avec l'heure prévue est
corrigé d'un coup au-delà de 50 ms (trames sautées ou silence) ; en deçà,
l'écart lissé fait sauter ou répéter de temps en temps une trame, au plus
une toutes les 256 (0,4 %), ce qui absorbe la dérive entre l'horloge de
l'émetteur et le quartz de la DAC.

## Volume proposé

`/info` propose aux nouvelles sessions (`initialVolume`) le dernier volume
reçu, `-7.5 dB` au démarrage. Après une heure sans audio à `-3.0 dB` ou
plus, il revient à `-7.5 dB` (événement `volume` avec `reason:
"idle_reset"`), comme `high_volume_idle_timeout_in_minutes` de Shairport
Sync : le réveil ne démarre pas la musique du lendemain à fond.

## Compilation pour le Pi 3

```sh
cargo build --release --target arm-unknown-linux-musleabihf -p robine-airplayd
```

`make airplayd`, à la racine du dépôt, fait de même et le copie dans
`rootfs_overlay/usr/bin` ; `make firmware` l'appelle. Il est choisi par
`config :robine_wake, airplay_receiver: :robine` (Shairport Sync par défaut).

## À faire avant de remplacer Shairport Sync

Une écoute longue sur le Pi, qui doit aussi valider :

- la correction de l'ancre temps réel (`realtime::ANCHOR_CORRECTION`,
  11 035 trames reprises de Shairport Sync), à comparer à une enceinte
  AirPlay de référence ;
- l'estimation de la latence de sortie, et les compteurs `stuffed`,
  `resyncs` et `underruns` de l'événement `stats`.
