# ALM-003 — Sieste

## Statut

Implémenté et testé — Phase 3 (2026-10-17). Module domaine pur `robine_core::nap`,
persistance dans `Store`, commandes `nap.start` et `nap.cancel` dans `CommandHandler`
(API-002), routes HTTP `POST /api/nap/start` et `POST /api/nap/cancel` (API-001).

## Héritage v1

`lib/robine_wake/nap.ex`, opérations `nap.start` / `nap.cancel` de
`docs/bluetooth/v1.md`.

## Objectif

Lancer une alarme ponctuelle qui sonne dans N minutes, en reprenant les sons,
le volume et la lumière de l'alarme habituelle de l'utilisateur.

## Règles reprises de la v1

- Durée de 1 à 180 minutes.
- Alarme ponctuelle à l'identifiant réservé `nap`, libellé « Sieste ».
- Modèle : la première alarme de l'utilisateur ; fuseau `Europe/Paris` à défaut.
- Rampe douce au plus de 2 minutes, jamais plus longue que la sieste.
- `nap.cancel` supprime l'alarme `nap` ; idempotent.
- Une sieste crée une session de réveil normale (ALM-002).

## Exigences

- `ALM-003.1` — Une sieste démarre une session identique à une alarme planifiée.
- `ALM-003.2` — La rampe de la sieste est `min(120 s, durée)`.
- `ALM-003.3` — Une seule sieste existe à la fois ; en relancer une remplace la précédente.

## Critères d'acceptation

- Sieste de 1 min : rampe de 60 s, sonne à l'heure.
- Sieste de 20 min : rampe de 120 s.
- Annulation puis nouvelle sieste : une seule alarme `nap`.
