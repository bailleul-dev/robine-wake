# DAT-002 — Sécurité et confidentialité

## Statut

Implémenté et testé — Phase 3 (2026-10-17). `GET /api/export` et `GET /api/diagnostics`
excluent strictement tous les secrets (secrets des boutons, compteurs sensibles,
données résiduelles). Remise à zéro usine complète via `POST /api/factory-reset` et
commande v1 `device.factory_reset`. Zéro caméra, zéro donnée biométrique.

## Héritage v1

`60/001-data-privacy` (sécurité, minimisation, commandes utilisateur),
`lib/robine_wake/auth.ex`.

## Objectif

Garder les données minimales, les secrets protégés et les accès d'administration
authentifiés.

## Règles reprises de la v1

- Aucune image, aucune donnée de présence, aucune donnée biométrique.
- Interface web et API sans mot de passe sur le réseau local de confiance ;
  SSH et mises à jour restent authentifiés (clé SSH, signature Ed25519).
- Secrets (Wi-Fi, clé Hue, secrets des boutons) exclus des logs, de l'API et des
  exports.
- Jetons générés par une source aléatoire cryptographique (`getrandom`).
- Limitation de débit sur les points sensibles (association, MCP).
- Export de la configuration non secrète, effacement de l'historique, remise à
  zéro usine.
- Le chiffrement de la carte SD n'est pas garanti : limite physique documentée.

## Spécifique v2

- Le démon tourne sous un utilisateur dédié non root, avec seulement les
  capacités nécessaires (accès audio, `CAP_NET_BIND_SERVICE` si port < 1024,
  `CAP_SYS_NICE` pour le thread audio) ; `sv` est appelé via une règle dédiée.
- `/data/robine-wake` appartient à cet utilisateur, mode `0700`.
- Le provisioning (mot de passe initial de la v1, s'il est conservé) utilise
  Argon2id ou PBKDF2 réglé pour le Pi.

## Exigences

- `DAT-002.1` — Les exports et diagnostics ne contiennent aucun secret.
- `DAT-002.2` — La remise à zéro usine rend les données applicatives inaccessibles.
- `DAT-002.3` — Le démon ne tourne pas en root.
- `DAT-002.4` — Aucune donnée de présence ou d'image n'est collectée ni exposée.

## Critères d'acceptation

- Recherche automatique de secrets dans une image, un export et un paquet de diagnostic.
- `ps` sur la cible : le démon tourne sous son utilisateur dédié.

## Questions ouvertes

- Le parcours `/setup` (mot de passe initial) de la v1 est-il encore utile,
  l'interface étant sans mot de passe ?
