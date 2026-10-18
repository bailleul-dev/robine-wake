# API-001 — API HTTP locale et interface web

## Statut

Brouillon — 2026-10-17. Partiellement porté par le prototype
`experimental/robine-wake-rs/src/http.rs` (`/health`, `/api/state`,
`/api/alarms`, `/api/alarms/preview`, `/api/sounds`, `/api/v1/events`, bundle
web statique).

## Héritage v1

`50/001-local-interface`, `lib/robine_wake_web/router.ex` (Bandit + Plug).

## Objectif

Servir l'interface web Expo existante (`priv/web`) et l'API JSON dont dépendent
le web, l'app mobile et le bouton, avec un contrat identique à la v1.

## Serveur

- `axum` sur `tokio`, port 4000 sur l'appareil (comme la v1), configurable.
- Écoute uniquement sur les interfaces configurées.
- Sans mot de passe sur le réseau local de confiance, comme la v1 ; les
  mutations depuis un navigateur gardent une protection CSRF.

## Routes à reprendre

| Route | V2 Rust |
|---|---|
| `GET /health` | ✅ |
| `GET /api/state` | ✅ |
| `GET /api/v1/events` (SSE, `Last-Event-ID`, 64 événements rejouables) | ✅ |
| `POST /api/v1/command` (API-002, cache d'idempotence 64 entrées, TTL 5 min) | ✅ |
| `GET/POST /api/alarms`, `PATCH/DELETE /api/alarms/:id`, `POST /api/alarms/preview` | ✅ |
| `POST /api/alarms/:id/trigger`, `/trigger-strong` | ✅ |
| `POST /api/nap/start`, `/api/nap/cancel` | ✅ |
| `POST /api/session/snooze`, `/dismiss` | ✅ |
| `PATCH /api/settings/smartphone-dismiss` | ✅ |
| `GET/POST /api/sounds` (import WAV) | ✅ |
| `POST /api/time/confirm` | ✅ |
| `POST /api/remote-button/pairing`, `DELETE /api/remote-button/:id` | ✅ (via `/api/v1/command`) |
| `DELETE /api/history` | ✅ |
| `POST /api/factory-reset` | ✅ |
| `POST /api/breathing/start`, `/volume`, `/stop` | Retiré (renvoie 503 `capability_unavailable`) |
| `GET /api/export`, `GET /api/diagnostics` | ✅ |
| `GET /setup`, `POST /api/setup` | ❌ (Phase 3) |
| Pages `/`, `/matin`, `/soir`, `/alarmes`, `/reveil` (bundle Expo) | ✅ |
| `/mcp` (API-003) | ❌ (Phase 4) |

Non repris / retirés : `/api/camera/calibrate`, `/api/simulation/observation` (caméra
retirée), `/api/breathing/*` (respiration guidée retirée du périmètre v2),
`/legacy`, `/beta` (à confirmer).

## Erreurs

Codes stables repris de la v1 : `validation_failed`, `revision_conflict`,
`capability_unavailable`, `not_found`, `rate_limited`, `internal_error`, plus
les codes métier (`smartphone_dismiss_disabled`, etc.).

## Exigences

- `API-001.1` — L'app mobile et le web v1 fonctionnent sans modification.
- `API-001.2` — Les écritures concurrentes utilisent `revision`.
- `API-001.3` — Aucun secret n'est renvoyé par l'API.
- `API-001.4` — Snooze et arrêt répondent en moins de 500 ms.
- `API-001.5` — Une commande ou route retirée (caméra, respiration guidée, Hue)
  renvoie `capability_unavailable` sans effet.
- `API-001.6` — Le bundle web est embarqué dans l'image, pas téléchargé.

## Critères d'acceptation

- Tests de contrat : les réponses JSON de la v2 sont comparées à celles de la
  v1 sur les mêmes données (fichier d'or produit depuis la v1).
- Parcours de l'app mobile sur un appareil v2 : alarmes, réveil actif, soir.
