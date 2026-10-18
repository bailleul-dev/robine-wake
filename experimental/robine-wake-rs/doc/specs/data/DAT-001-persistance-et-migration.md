# DAT-001 — Persistance et reprise des données v1

## Statut

Implémenté et testé — Phase 2 & 3 (2026-10-17). Porté dans `crates/robine-daemon/src/store.rs`
et `sounds.rs` : document JSON versionné, écriture atomique (.tmp + fsync + rename + 0600),
révisions optimistes, préservation des clés inconnues, rétention des sessions sur 30 jours,
import WAV avec validation PCM stricte et SHA-256, factory-reset (`POST /api/factory-reset`).

## Héritage v1

`60/001-data-privacy` (schémas, migrations), `lib/robine_wake/settings.ex`,
fichier `/data/robine_wake*.json` (`schema_version: 1`).

## Objectif

Stocker la configuration, l'historique des sessions et les secrets locaux de
façon atomique, et reprendre une installation v1 sans perte.

## Stockage

- Même format que la v1 : document JSON avec `schema_version`, `created_at`,
  `updated_at`, sur `/data`.
- Écriture atomique : fichier temporaire, `fsync`, `rename`, `fsync` du dossier,
  mode `0600` (déjà dans le prototype).
- Révisions optimistes par ressource.
- Les clés inconnues sont préservées à la réécriture (compatibilité ascendante
  et descendante avec la v1 pendant la transition).
- Une sauvegarde valide précédente est conservée avant chaque migration.
- Fichier illisible : démarrage avec des valeurs sûres par défaut, état
  `degraded`, fichier corrompu conservé à part pour diagnostic.

## Reprise de la v1

- La v2 lit directement le fichier de données v1 (format identique).
- Sont repris : alarmes, réglages audio, réglages Hue (clé comprise), boutons
  appairés (secrets et compteurs), préférences, historique des sessions
  (30 jours), sons WAV importés de `/data/sounds`.
- Les données caméra résiduelles et les politiques `bed_exit` / `either` sont
  normalisées comme en v1 (`manual`).
- Les appairages Bluetooth (`/data/bluetooth`) sont repris tels quels si AUD-003
  est activé.

## Rétention

- Sessions : 30 jours. Logs critiques : 7 jours.
- Purge au démarrage puis quotidienne.

## Exigences

- `DAT-001.1` — Les écritures sont atomiques ; une coupure de courant à
  n'importe quelle étape laisse un fichier valide (ancien ou nouveau).
- `DAT-001.2` — Un fichier de données v1 réel est chargé sans perte d'alarme,
  de secret ni de compteur.
- `DAT-001.3` — Les clés inconnues sont préservées.
- `DAT-001.4` — Une migration échouée laisse les anciennes données intactes.
- `DAT-001.5` — Un fichier corrompu n'empêche pas le démarrage.
- `DAT-001.6` — La rétention s'applique au démarrage puis chaque jour.

## Critères d'acceptation

- Coupure simulée à chaque étape d'écriture et de migration.
- Chargement d'une copie anonymisée du fichier de la carte v1 actuelle.
- Purge avec horloge avancée de 31 jours.
