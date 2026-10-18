# PLT-004 — Init, services et supervision

## Statut

Brouillon — 2026-10-17.

## Héritage v1

`erlinit` + `shoehorn` + supervision OTP, `MuonTrap.Daemon` pour shairport-sync
et BlueALSA, watchdog décrit dans `10/001-nerves-platform`.

## Objectif

Démarrer et superviser le démon et les services externes sans BEAM ni systemd,
en gardant la règle v1 : la panne d'un service accessoire n'affecte jamais
l'alarme.

## Séquence de démarrage

1. BusyBox `init` lit `/etc/inittab`.
2. Montages : `proc`, `sys`, `devtmpfs`, `tmpfs` (`/tmp`, `/run`), `/data`
   (création et formatage si absente, `fsck` automatique si nécessaire).
3. `mdev`, chargement des modules, réglage de l'heure plancher (PLT-003).
4. `runsvdir /etc/service` démarre la supervision.
5. Le service `robine-wake` démarre en premier ; réseau, SSH et services
   accessoires démarrent en parallèle.

## Services

| Service | Démarrage | Pilotage |
|---|---|---|
| `robine-wake` | toujours | relancé par `runsv` |
| `network` (udhcpc, wpa_supplicant) | toujours | `runsv` |
| `ntpd` | toujours | `runsv` |
| `dropbear` | toujours | `runsv` |
| `dbus`, `avahi`, `nqptp`, `shairport-sync` | si AirPlay | démarrés et arrêtés par le démon avec `sv up/down` |
| `bluetoothd`, `bluealsad`, `bluealsa-aplay`, agent | si Bluetooth | démarrés et arrêtés par le démon avec `sv up/down` |

Les services accessoires sont déclarés avec un fichier `down` : ils ne
démarrent pas seuls, le démon décide (préemption par l'alarme, AUD-001).

## Supervision

- `runsv` relance un service qui s'arrête, avec un délai minimal de 1 s ; le
  script `run` de chaque service accessoire ajoute un backoff plafonné à 60 s.
- Le démon lit l'état des services (`sv status`, ou le fichier `supervise/stat`)
  pour les exposer dans la santé (OPS-003).
- Arrêter la lecture d'un récepteur termine tout son groupe de processus
  (`AUD-009` v1).

## Watchdog

- Le démon ouvre `/dev/watchdog` (timeout 15 s) et le nourrit depuis une tâche
  qui vérifie que le planificateur et la boucle d'événements répondent.
- Si le démon s'arrête ou se bloque, le watchdog redémarre la carte ; au
  redémarrage, une session de réveil active est reprise (ALM-002).
- Pendant une mise à jour, le watchdog reste actif.

## Exigences

- `PLT-004.1` — Le démon est relancé en moins de 2 s après un arrêt inattendu.
- `PLT-004.2` — L'arrêt ou le plantage d'un service accessoire ne redémarre pas
  le démon.
- `PLT-004.3` — Les services accessoires ne possèdent jamais la sortie audio
  pendant une session de réveil.
- `PLT-004.4` — Un démon bloqué plus de 15 s provoque un redémarrage par le
  watchdog matériel.
- `PLT-004.5` — Le nombre de redémarrages de chaque service est visible dans la santé.

## Critères d'acceptation

- `kill -9` du démon pendant une sonnerie : relance et reprise de la sonnerie
  en moins de 5 s.
- `kill -9` de `shairport-sync` en boucle : le démon et l'alarme ne sont pas affectés.
- Gel du démon (`SIGSTOP`) : redémarrage de la carte par le watchdog.

## Questions ouvertes

- Applets runit de BusyBox ou paquet `s6` ? (recommandation : BusyBox, zéro
  paquet supplémentaire)
