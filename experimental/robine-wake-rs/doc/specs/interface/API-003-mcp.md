# API-003 — Serveur MCP HTTP

## Statut

Implémenté et testé — 2026-10-17. Endpoint POST /mcp (JSON-RPC 2.0, Streamable HTTP), GET /mcp (405), vérification Origin, limitation 120 req/min, 10 outils de domaine.

## Héritage v1

`50/002-http-mcp` (fait foi), `lib/robine_wake/mcp.ex`.

## Objectif

Permettre à un client IA du réseau local d'inspecter et de piloter le réveil
par MCP, avec les mêmes validations, plafonds et révisions que l'API.

## Profil repris de la v1

- `POST /mcp`, MCP Streamable HTTP, un message JSON-RPC 2.0 par requête,
  réponses JSON synchrones, sans session ni SSE ; `GET /mcp` → 405.
- Versions `2025-06-18` et `2025-03-26`.
- Outils : `get_state`, `list_alarms`, `list_sounds`, `preview_alarm`,
  `create_alarm`, `update_alarm`, `delete_alarm`, `trigger_alarm`,
  `snooze_session`, `dismiss_session` (soumis à la porte d'arrêt à distance).
- Vérification de `Origin`, limite de 120 requêtes par minute et par adresse.
- Erreurs métier en `isError: true`, erreurs de protocole en erreurs JSON-RPC.

## Ce qui change

- Implémentation en Rust, soit à la main (le profil est petit et sans état),
  soit avec le SDK Rust officiel MCP si son poids reste raisonnable.
- Ajouter les versions MCP publiées depuis la v1 si les clients les exigent.

## Exigences

- `API-003.1` — Les outils appellent les services de domaine et respectent les révisions.
- `API-003.2` — Aucun outil ne renvoie de secret.
- `API-003.3` — Un `Origin` non autorisé est rejeté avant l'exécution.
- `API-003.4` — Désactiver la fonction retire la route et le code du binaire.

## Critères d'acceptation

Tests repris de la v1 : initialisation, découverte, notifications, rejet
d'`Origin`, négociation, limite de débit, versions non supportées, erreurs
d'outil, conflits de révision.
