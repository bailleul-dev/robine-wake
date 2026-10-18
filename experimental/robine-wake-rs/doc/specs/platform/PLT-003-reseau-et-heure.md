# PLT-003 — Réseau, mDNS et qualité de l'heure

## Statut

Brouillon — 2026-10-17.

## Héritage v1

`10/001-nerves-platform` (réseau et heure), `lib/robine_wake/clock_quality.ex`,
`lib/robine_wake/network.ex`, `nerves_pack` / `vintage_net` / `mdns_lite`.

## Objectif

Remplacer ce que fournissaient `vintage_net`, `nerves_time` et `mdns_lite` :
connexion réseau, annonce locale et heure fiable.

## Réseau

- Ethernet en DHCP par défaut, prioritaire pour la maintenance.
- Wi-Fi via `wpa_supplicant` ; les identifiants viennent du provisioning de
  l'image (`.env`, comme en v1) puis de `/data/network/wpa_supplicant.conf`.
- `udhcpc` (BusyBox) gère le DHCP sur les deux interfaces.
- Le démon observe l'état des interfaces (netlink) et l'expose dans la santé.
- La perte du réseau n'a aucun effet sur les alarmes enregistrées (`ARCH-001` v1).

## Annonce locale (mDNS)

- Le réveil s'annonce `robine-wake.local` ; le bouton ESP32 et l'app en dépendent.
- Services annoncés : HTTP (port de l'interface web), SSH.
- Implémentation proposée : répondeur mDNS intégré au démon (crate
  `mdns-sd`), pour ne pas exiger Avahi ni D-Bus dans l'image réduite.
- Si AirPlay est activé, Avahi annonce AirPlay sous un autre nom d'hôte
  (`robine-wake-airplay.local`), comme en v1, pour éviter deux répondeurs sur
  le même nom.

## Heure

- NTP par `ntpd` de BusyBox (client seul) dès qu'un réseau est disponible.
- Le démon suit la qualité de l'heure : `untrusted` au démarrage, `trusted`
  après une synchronisation NTP réussie, une lecture RTC valide, ou une
  confirmation explicite par l'utilisateur (`clock.confirm`).
- Sans RTC, l'heure de la dernière extinction est restaurée depuis `/data`
  comme plancher (évite de démarrer en 1970), mais reste `untrusted`.
- Un saut d'horloge détecté (écart entre horloge murale et monotone) est publié
  au planificateur, qui applique la règle de rattrapage (ALM-001).
- Fuseaux : base IANA embarquée dans le binaire (`chrono-tz`), pas de
  dépendance à `/usr/share/zoneinfo`.

## Exigences

- `PLT-003.1` — Le réveil est joignable sur `robine-wake.local` en Ethernet et
  en Wi-Fi.
- `PLT-003.2` — Aucun mot de passe Wi-Fi n'apparaît dans les logs, la santé ou
  les exports.
- `PLT-003.3` — La qualité de l'heure est observable par le domaine et par l'API.
- `PLT-003.4` — Une alarme ne s'arme pas silencieusement tant que l'heure est
  `untrusted` (`ALM-007` v1).
- `PLT-003.5` — La base de fuseaux utilisée par le démon ne dépend pas de
  fichiers du rootfs.
- `PLT-003.6` — L'image réduite n'embarque ni Avahi ni D-Bus.

## Critères d'acceptation

- Démarrage sans réseau : santé `degraded`, heure `untrusted`, alarmes visibles,
  aucune alarme rejouée à tort.
- Branchement du réseau : passage à `trusted` après NTP en moins de 30 s.
- L'ESP32 v1 trouve et joint `robine-wake.local` sans modification.

## Questions ouvertes

- Provisioning Wi-Fi après installation : écran de setup en point d'accès,
  configuration via l'app, ou uniquement au build ?
