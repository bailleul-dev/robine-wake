# AUD-002 — Récepteur AirPlay

## Statut

Implémenté et testé — 2026-10-17. Service shairport-sync supervisé avec état initial down (PLT-004), génération de configuration dans /run/shairport-sync.conf, préemption avant alarme et reprise en fin de session.

## Héritage v1

`30/002-airplay-receiver` (fait foi), `lib/robine_wake/air_play.ex`,
`nerves_system_rpi3/package/shairport-sync5/` (shairport-sync 5.5.2 et ses
deux patches), `knowledges/airplay-diagnostics.md`.

## Objectif

Garder Robine Wake comme enceinte AirPlay de la chambre (« Robine Wake
Bedroom »), sans jamais affaiblir l'alarme.

## Ce qui change

- Le paquet Buildroot `shairport-sync5` et ses patches sont repris tels quels
  dans `br-external/package/`.
- La supervision passe de `MuonTrap` à `runsv` (PLT-004) ; le démon pilote
  `dbus`, `avahi`, `nqptp`, `shairport-sync` avec `sv up/down`.
- La configuration shairport (`/etc/shairport-sync.conf`) est générée par le
  démon dans `/run` au démarrage.

Tout le reste (AirPlay 2, sortie `plughw` sur l'Amp2 en 32 bits, atténuation
logicielle, volume suggéré −7,5 dB, retour au volume suggéré après 60 min
d'inactivité au-dessus de −3 dB, nom d'hôte Avahi séparé, pas de mot de passe)
reste comme en v1.

## Coût

AirPlay 2 est la fonction la plus lourde de l'image : shairport-sync, NQPTP,
Avahi, D-Bus, FFmpeg réduit (décodeurs AAC/ALAC), libgcrypt, OpenSSL. C'est elle
qui impose une carte avec ~128 Mo de RAM (PRD-001). Le surcoût exact (taille,
RAM au repos, CPU en lecture) est mesuré dans QA-002.

## Exigences

- `AUD-002.1` — Le récepteur est annoncé quand aucune alarme ne possède la sortie.
- `AUD-002.2` — L'alarme préempte AirPlay avant d'ouvrir ALSA ; AirPlay revient
  après la session.
- `AUD-002.3` — Gain plafonné indépendamment, sous la limite acoustique mesurée.
- `AUD-002.4` — Une sortie inattendue de shairport-sync est visible dans la santé
  et relancée sans redémarrer le démon.
- `AUD-002.5` — Désactiver la fonction retire tous ses paquets de l'image (PLT-001.6).

## Critères d'acceptation

Ceux de la v1 : visible depuis un iPhone et un Mac, 10 min de lecture stéréo
sans coupure, alarme audible pendant un flux dans le délai normal, récepteur
de nouveau visible après l'arrêt, `kill` de shairport sans effet sur l'alarme.

## Questions ouvertes

- AirPlay 2 est-il indispensable en v2, ou AirPlay 1 suffit-il (sans NQPTP,
  plus léger) ? La v1 est passée en AirPlay 2 pour que le récepteur propose le
  volume.
