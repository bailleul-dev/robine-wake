# AUD-003 — Récepteur audio Bluetooth

## Statut

Implémenté et testé — 2026-10-17. Service bluealsa-aplay supervisé avec état initial down (PLT-004), préemption avant alarme et reprise en fin de session.

## Héritage v1

`30/005-bluetooth-audio-receiver` (fait foi), `lib/robine_wake/bluetooth_audio.ex`,
`nerves_system_rpi3/package/bluez-alsa5/`.

## Objectif

Permettre à tout téléphone, Android compris, d'utiliser Robine Wake comme
enceinte Bluetooth A2DP, sans jamais affaiblir l'alarme.

## Ce qui change

- Le paquet `bluez-alsa5` est repris dans `br-external/package/`.
- La pile (`dbus`, `bluetoothd`, `bluealsad`, agent, `bluealsa-aplay`) est
  supervisée par `runsv` ; le démon ne contrôle que `bluealsa-aplay` pour la
  préemption (PLT-004).
- L'agent `bluetoothctl --agent auto` (qui demandait un port Erlang avec stdin
  ouvert) est remplacé par un petit agent D-Bus intégré au démon (crate
  `bluer`) ou par `bt-agent` ; à trancher.

Tout le reste (contrôleur intégré sur PL011, A2DP sink seul, codecs SBC, AAC,
aptX, aptX HD, delay reporting, appairage ouvert, appairages dans
`/data/bluetooth`) reste comme en v1.

## Exigences

- `AUD-003.1` — Le réveil expose un A2DP sink « Robine Wake Bedroom » sans
  action physique.
- `AUD-003.2` — L'alarme arrête la lecture Bluetooth avant d'ouvrir ALSA ; la
  lecture reprend après la session, sans nouvel appairage.
- `AUD-003.3` — Une pile Bluetooth en panne ne retarde pas l'alarme au-delà du
  budget de latence audio.
- `AUD-003.4` — Aucun profil mains libres n'est enregistré.
- `AUD-003.5` — Désactiver la fonction retire BlueZ, BlueALSA et leurs codecs de
  l'image.

## Critères d'acceptation

Ceux de la v1 : Galaxy S24 et iPhone appairés sans toucher l'appareil, 10 min
sans coupure Wi-Fi actif, alarme audible pendant un flux, reprise de la musique
après l'arrêt, appairages conservés après redémarrage et mise à jour.

## Questions ouvertes

- Fonction conservée en v2 ? Elle ajoute D-Bus, BlueZ, FDK AAC et libopenaptx
  (licences à revoir avant toute distribution).
