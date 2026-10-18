# ACC-001 — Philips Hue

## Statut

Retiré du périmètre v2 — Décision d'arbitrage du 2026-10-17. Le support de Philips Hue
n'est pas implémenté dans Robine Wake 2 afin de respecter l'objectif de simplicité,
de limiter les dépendances réseau et de focaliser le produit sur le réveil autonome
hors ligne. Les appels API et commandes relatifs à Hue renvoient l'erreur
`capability_unavailable`.

## Héritage v1

Section « Connect Philips Hue » du README v1, `lib/robine_wake/hue.ex`
(1 123 lignes), `hue/driver/http.ex`, opérations `hue.*` de `docs/bluetooth/v1.md`.

## Objectif

Piloter localement un pont Philips Hue (API v2, sans cloud) pour le lever de
lumière du réveil, l'alerte lumineuse forte et la respiration (AUD-004).

## Fonctions reprises de la v1

- **Appairage** : découverte Bonjour du pont, saisie manuelle de l'adresse en
  secours, appui sur le bouton du pont, création de la clé d'application
  (`hue.pair`, `hue.refresh`, `hue.disconnect`).
- **Cibles** : pièces et zones (grouped lights) listées dans l'état.
- **Lever de lumière** par alarme : cible, luminosité initiale et finale, durée
  de transition, comportement à l'arrêt (restaurer, éteindre, laisser allumé).
- **Snooze** : éteint la cible ; la reprise relance la transition.
- **Alerte forte** : alternance de couleurs vives pendant la phase forte
  (intervalle 3 s, transition 650 ms).
- **Respiration** : voir AUD-004, mesure de latence par moyenne glissante.
- La clé d'application est stockée uniquement dans la configuration locale
  persistante et n'est jamais exportée ni renvoyée aux clients.

## Implémentation

- Client HTTPS `reqwest` + `rustls`. Le pont présente un certificat auto-signé :
  la v1 désactive la vérification (`verify_none`). La v2 vérifie au minimum que
  le certificat correspond à l'identifiant du pont (épinglage au premier
  appairage).
- Toutes les requêtes ont un délai court ; une panne Hue est un événement
  `device_degraded` et ne bloque jamais l'alarme sonore.
- Un seul propriétaire de Hue à la fois (session de réveil ou respiration).

## Exigences

- `ACC-001.1` — Une panne ou une lenteur du pont ne retarde ni l'audio ni les
  échéances de la session.
- `ACC-001.2` — La clé d'application n'est jamais renvoyée par l'API ni exportée.
- `ACC-001.3` — Le certificat du pont est épinglé à l'appairage.
- `ACC-001.4` — L'arrêt restaure l'état d'avant selon la politique de l'alarme.
- `ACC-001.5` — Le JSON `light_profile` et l'état Hue sont identiques à la v1.

## Critères d'acceptation

- Pont débranché pendant un réveil : l'alarme sonne normalement, santé `degraded`.
- Appairage depuis l'app v1 sans modification.
- Certificat différent après appairage : connexion refusée, santé `degraded`.
