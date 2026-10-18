# ALM-001 — Planification des alarmes

## Statut

Implémenté et validé — Phase 2 (2026-10-17). Modèle pur et calcul d'occurrences
dans `robine-core::alarm`, acteur planificateur dans `robine-daemon::scheduler`
avec réveil monotone, vérification d'horloge de confiance, rattrapage < 5 min et
désactivation automatique des alarmes ponctuelles.

## Héritage v1

`20/001-alarm-scheduling` (fait foi pour le modèle et les règles),
`lib/robine_wake/alarm.ex`, `scheduler.ex`, `session_recovery.ex`.

## Objectif

Créer, modifier et déclencher les alarmes de façon fiable dans un fuseau IANA
explicite, avec le même modèle et le même contrat JSON que la v1.

## Modèle

Identique à la v1 : `id`, `label`, `enabled`, `local_time`, `days_of_week`,
`one_shot_date`, `timezone`, `sound_id`, `strong_sound_id`, `prewake_seconds`,
`volume_profile`, `light_profile`, `vibration_profile`, `snooze`,
`dismiss_policy` (`manual` uniquement), `revision`.

Les champs inconnus présents dans le fichier de données sont préservés à
l'écriture (comportement du prototype).

## Règles reprises de la v1

- Heure locale inexistante (passage à l'heure d'été) : première minute valide.
- Heure locale répétée (passage à l'heure d'hiver) : une seule fois, à la
  première occurrence.
- La phase douce démarre `prewake_seconds` avant l'heure cible ; l'occurrence
  cible sert à la déduplication et à l'historique.
- Toute modification annule atomiquement le minuteur précédent.
- Rattrapage après redémarrage : moins de 5 min de retard (réglable de 0 à
  15 min) → déclenchement unique ; au-delà → `missed` dans l'historique.
- Heure `untrusted` → pas d'armement silencieux (PLT-003).
- Une alarme ponctuelle est désactivée dès que sa session est créée.

## Implémentation

- Le calcul d'occurrence est une fonction pure de `robine-core`
  (règle, instant UTC) → prochaine occurrence.
- L'acteur planificateur garde un seul minuteur sur la prochaine échéance
  toutes alarmes confondues, recalculé à chaque modification, saut d'horloge
  ou changement de qualité de l'heure.
- Attente sur l'horloge monotone avec réveil de contrôle au plus toutes les
  60 s pour détecter les sauts d'horloge murale.

## Exigences

Les exigences `ALM-001` à `ALM-011` de la v1 s'appliquent, renumérotées :

- `ALM-001.1` — Une alarme active a exactement une prochaine occurrence.
- `ALM-001.2` — Une occurrence crée au plus une session.
- `ALM-001.3` — Le calcul suit le fuseau IANA et ses règles DST.
- `ALM-001.4` — Modifier une alarme annule atomiquement son minuteur précédent.
- `ALM-001.5` — Une alarme ponctuelle est désactivée après création de sa session.
- `ALM-001.6` — Un démarrage tardif applique la fenêtre de rattrapage.
- `ALM-001.7` — Une heure non fiable empêche l'armement silencieux.
- `ALM-001.8` — Une alarme référence un son doux et un son fort disponibles.
- `ALM-001.9` — Les écritures concurrentes sont protégées par `revision`.
- `ALM-001.10` — Le JSON des alarmes est identique à celui de la v1
  (même client Expo).

## Critères d'acceptation

- Tests déterministes avant, pendant et après deux transitions DST (repris des
  tests v1 et du prototype).
- Redémarrage à +2 min et +10 min de l'heure prévue.
- Conflit de révision rejeté.
- Test de propriété : 10 000 recalculs sans double déclenchement.
- Fichier de données v1 réel chargé sans perte (DAT-001).
