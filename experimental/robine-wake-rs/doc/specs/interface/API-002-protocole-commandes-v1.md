# API-002 — Protocole de commandes v1

## Statut

Implémenté et validé — Phase 2 (2026-10-17). Enveloppe versionnée v1, cache
d'idempotence LRU (64 entrées, TTL 5 min), opérations d'alarmes, de sessions,
de réglage de porte smartphone et arrêt bouton ESP32 (ACC-002).

## Héritage v1

`docs/bluetooth/v1.md` (fait foi pour l'enveloppe et les opérations),
`lib/robine_wake/bluetooth/command.ex`, `command_cache.ex`, route
`POST /api/v1/command`.

## Objectif

Reprendre le petit protocole versionné qui relie l'app mobile et le bouton ESP32
au réveil. En v1 il passait par BLE puis par Wi-Fi ; en v2 il passe
**uniquement par HTTP** (`POST /api/v1/command`), le service BLE étant retiré.

## Enveloppe

```json
{"v":1,"id":"<uuid client>","op":"state.get","body":{}}
```

Réponses `{"v":1,"id":…,"status":"ok","body":{…}}` ou
`{"v":1,"id":…,"status":"error","error":{"code":"…","details":{}}}`. Les
clients se basent sur `error.code`, jamais sur un message.

Le transport BLE paginé (en-tête `RW`, CRC32) n'est pas repris.

## Opérations

- `capabilities.get`, `state.get`
- `alarm.create`, `alarm.update`, `alarm.delete`, `alarm.preview`, `alarm.trigger`
- `nap.start`, `nap.cancel` (ALM-003)
- `session.get`, `session.snooze`, `session.dismiss`
- `settings.smartphone_dismiss.set`
- `clock.confirm`
- `remote_button.dismiss` (ACC-002)
- `history.erase`, `device.factory_reset`
- Opérations retirées renvoyant `capability_unavailable` sans effet :
  - `hue.pair`, `hue.refresh`, `hue.disconnect` (ACC-001 retiré)
  - `breathing.start`, `breathing.volume`, `breathing.stop` (AUD-004 retiré)
  - `camera.calibrate` (caméra retirée)

`capabilities.get` reflète les fonctions présentes dans l'image (`hue: false`,
`guided_breathing: false`, `remote_button: true`...).

## Idempotence

Le cache de commandes v1 est repris : une commande rejouée avec le même `id`
reçoit la même réponse sans réexécution, pendant une durée bornée.

## Exigences

- `API-002.1` — L'enveloppe et les codes d'erreur sont identiques à la v1.
- `API-002.2` — Une commande rejouée avec le même `id` n'est pas réexécutée.
- `API-002.3` — `capabilities.get` ne déclare que les fonctions réellement présentes.
- `API-002.4` — Une commande est limitée à 65 536 octets.

## Critères d'acceptation

- Rejeu de chaque opération de l'app mobile v1 sur la v2 : mêmes réponses.
- Commande dupliquée : un seul effet.
