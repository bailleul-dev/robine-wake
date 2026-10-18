# AUD-001 — Sortie audio et arbitre ALSA

## Statut

Implémenté et testé — 2026-10-17. Moteur audio direct, courbe de gain, arbitrage de sortie avec préemption automatique des récepteurs externes (shairport-sync, bluealsa-aplay) et reprise en fin de session.

## Héritage v1

`30/001-audio-output` (fait foi pour la courbe de gain et les plafonds),
`lib/robine_wake/audio.ex`, `audio/driver/alsa.ex`, `sound_library.ex`,
`priv/sounds/` et son manifeste.

## Objectif

Produire l'alarme sur l'Amp2 de façon fiable, et arbitrer l'accès exclusif à
la carte son entre l'alarme, la respiration et les récepteurs de musique.

## Changement principal par rapport à la v1

La v1 lance `mpg123` (MP3) et `aplay` (PCM) comme processus externes et règle
le volume avec `amixer`. La v2 fait tout **dans le démon** :

- décodage MP3/WAV avec `symphonia` ;
- écriture PCM directe avec la crate `alsa` (alsa-lib) ;
- réglage du mixeur `Digital` de l'Amp2 par l'API mixeur d'alsa-lib.

Gains attendus : plus de processus à superviser ni de groupe de processus
orphelin (`AUD-009` v1 devient trivial), latence de démarrage plus faible,
`mpg123` et `alsa-utils` retirés de l'image.

## Moteur audio

- Un thread système dédié, priorité temps réel (`SCHED_FIFO` modéré), possède
  le périphérique PCM pendant qu'il est ouvert.
- Commandes par canal : `prepare`, `play(session, son)`, `set_gain`,
  `fade_out`, `stop(session)`. Chaque commande porte l'identifiant de session ;
  une commande d'une ancienne session est ignorée (`AUD-001` v1).
- Boucle sans trou audible ; fondu d'au moins 500 ms au démarrage, au snooze et
  à l'arrêt.
- Même moteur pour l'ambiance DSP de respiration (AUD-004), qui fournit un flux
  PCM généré au lieu d'un fichier.

## Courbe de gain (reprise de la v1)

- Volume logique 0–100.
- Sur Amp2 : de 1 au plafond de sécurité, linéaire de −45 dB à −15 dB ;
  0 = minimum ALSA.
- Valeurs par défaut d'alarme : départ 15, plafond 85, rampe de pré-réveil de
  20 min.
- Plafond de sécurité absolu, indépendant du réglage utilisateur.
- Entre deux alarmes, le mixeur est remis au plafond musique (`0.0 dB`) ; les
  récepteurs atténuent en logiciel.

## Arbitre de sortie

Priorité stricte : **alarme > respiration > musique (AirPlay, Bluetooth)**.

1. Avant d'ouvrir la carte pour une alarme, l'arbitre suspend tous les
   récepteurs (`sv down`, PLT-004).
2. Un récepteur qui ne répond pas dans les 500 ms est ignoré et journalisé ; il
   ne retarde jamais l'alarme.
3. À la fin de la session, les récepteurs sont relancés.

## Bibliothèque de sons

- Sons MP3 embarqués avec manifeste (id, titre, attribution, durée, intensité,
  taille, version, SHA-256), repris de `priv/sounds`.
- Import utilisateur : WAV PCM 16 bits, 44,1/48 kHz, mono ou stéréo, ≤ 5 Mo,
  copié atomiquement après validation dans `/data/sounds`.
- Le son généré `default` reste toujours disponible hors ligne.

## Erreurs

Trois nouvelles tentatives après 250 ms, 1 s et 3 s, reprise au volume courant
de la rampe. Échec final : événement critique, la session reste active pour
une action manuelle.

## Exigences

- `AUD-001.1` — Une commande d'une ancienne session n'affecte pas la session active.
- `AUD-001.2` — Le gain ne dépasse jamais le plafond matériel.
- `AUD-001.3` — Le son démarre moins de 500 ms après une commande acceptée,
  récepteurs de musique compris.
- `AUD-001.4` — Les fichiers audio sont validés avant d'être disponibles.
- `AUD-001.5` — Arrêt et changement de volume sont idempotents.
- `AUD-001.6` — Une erreur ALSA est visible et déclenche la politique de reprise.
- `AUD-001.7` — L'adaptateur hôte enregistre les commandes sans jouer de son.
- `AUD-001.8` — L'image de production n'embarque ni `mpg123` ni `aplay` pour l'alarme.

## Critères d'acceptation

- Tests automatisés de la courbe de gain et du plafond.
- Deux sessions simulées concurrentes.
- Fichier invalide, carte absente.
- Sur matériel : pas de clic, rampe lisse, niveau maximal mesuré à distance
  définie, boucle de 30 min sans trou, CPU mesuré pendant le décodage MP3.
