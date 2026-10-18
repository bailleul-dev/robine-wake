# OPS-003 — Santé, logs et diagnostics

## Statut

Brouillon — 2026-10-17.

## Héritage v1

`70/001-operations-updates`, `lib/robine_wake/health.ex`, `event_log.ex`,
`ring_logger`, `air_play/diagnostics.ex`, `knowledges/airplay-diagnostics.md`.

## Objectif

Rendre l'appareil observable sans cloud : santé par capacité, logs bornés,
paquet de diagnostic exportable.

## Santé

- État global `healthy`, `degraded` ou `unhealthy`, calculé à partir de :
  heure, planificateur, stockage, audio, réseau, firmware, Hue, AirPlay,
  Bluetooth, radio LoRa, vibration (selon les fonctions présentes).
- Chaque capacité expose : état, dernier succès, dernière erreur expurgée,
  nombre de redémarrages.
- Seuls un planificateur indisponible, une panne de stockage critique ou une
  boucle de plantage rendent l'appareil `unhealthy`. Une fonction absente de
  l'image ou désactivée n'est pas une panne.
- Exposé par `GET /health` (minimal, sans authentification) et dans `/api/state`.

## Logs

- `tracing` vers un tampon circulaire en RAM (taille bornée, ex. 2 Mo).
- Événements critiques (alarme ratée, échec audio, retour arrière de firmware)
  également écrits dans `/data/log/critical.jsonl`, borné en taille et à 7 jours
  (`OPS-007` v1).
- Les sorties des services externes (`runsv` + `svlogd`) vont dans `/tmp`,
  bornées.
- Contenu interdit : mots de passe, clés, SSID marqué sensible, corps de
  requêtes d'authentification.

## Métriques minimales

Uptime, RSS du démon, mémoire système, redémarrages d'acteurs et de services,
qualité et dérive de l'heure, alarmes planifiées / déclenchées / ratées,
latence de démarrage audio, snooze, arrêts, timeouts, erreurs.

## Paquet de diagnostic

Export local (`GET /api/diagnostics`) : versions, configuration non secrète,
santé, métriques, logs récents, manifeste SHA-256 de chaque fichier. Les outils
de diagnostic AirPlay de la v1 (lanceur `shairport-sync-diag`) sont repris si
AUD-002 est activé.

## Exigences

- `OPS-003.1` — Chaque capacité publie un état explicable (`OPS-001` v1).
- `OPS-003.2` — Logs et métriques sont bornés en taille et en durée.
- `OPS-003.3` — Le paquet de diagnostic ne contient aucun secret.
- `OPS-003.4` — Les événements critiques survivent à un redémarrage.
- `OPS-003.5` — Une fonction absente de l'image n'apparaît pas comme une panne.

## Critères d'acceptation

- Saturation des logs : la mémoire reste bornée.
- Recherche automatique de secrets dans un paquet de diagnostic : aucun résultat.
- Table de santé cohérente pour chaque périphérique débranché.
