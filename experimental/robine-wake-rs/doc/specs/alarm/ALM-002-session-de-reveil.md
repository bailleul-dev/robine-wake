# ALM-002 — Session de réveil

## Statut

Implémenté et validé — Phase 2 (2026-10-17). Machine à états pure dans
`robine-core::session`, gestionnaire d'effets dans `robine-daemon::session_manager`,
rampe douce, plateau de 5 min, escalade son fort, limite de snooze, porte d'arrêt
à distance figée au démarrage, timeout de sécurité de 30 min, persistance des sessions.

## Héritage v1

`20/002-wake-session` (fait foi), `00/002-gentle-awakening-mechanisms`,
`lib/robine_wake/wake_session.ex` (711 lignes), `session_recovery.ex`.

## Objectif

Orchestrer une occurrence d'alarme du déclenchement à la fin : son en deux
phases, lumière, vibration optionnelle et commandes explicites de l'utilisateur.
C'est le cœur de la fiabilité du produit.

## Machine à états

```text
scheduled -> starting -> ringing -> dismissed
                            +-> snoozed -> ringing
                            +-> failed_safe -> dismissed / snoozed / timed_out
                            +-> timed_out
```

La machine à états est une fonction pure de `robine-core` :
`(état, événement, instant monotone) -> (nouvel état, effets)`. L'acteur de
session exécute les effets (audio, Hue, vibration, persistance). Cela rend
toutes les transitions testables sans matériel ni attente réelle.

## Règles reprises de la v1

- La session est **persistée avant** tout effet sonore.
- L'audio démarre sans attendre la lumière ni la vibration.
- Phase douce : le gain monte du niveau de départ au plafond exactement à
  l'heure cible, puis plateau de 5 min.
- Sans arrêt ni snooze après le plateau : bascule unique vers le son fort, au
  niveau `volume_profile.strong` ; événement `gentle_wake_escalated`.
- Snooze : fondu de sortie, redémarrage monotone, reprise toujours en phase
  douce avec une rampe neuve. Par défaut 3 snoozes de 8 min ; le compteur
  survit à un redémarrage.
- Arrêt idempotent. L'arrêt depuis le téléphone, le web ou MCP est refusé tant
  que la porte firmware `remote_dismiss_enabled` est fermée (par défaut) ; la
  permission est figée au démarrage de la session.
- Durée sonore maximale : 30 min, puis `timed_out`, volume réduit, vibration
  coupée, alerte visible.
- Reprise après redémarrage si la session est encore dans sa fenêtre active,
  avec ses échéances d'origine ; une session terminée n'est jamais rouverte.
- Une panne de lumière ou de vibration ne déplace aucune échéance audio.

## Exigences

- `ALM-002.1` — La création de session précède tout effet audio (`SES-001` v1).
- `ALM-002.2` — Toutes les commandes utilisateur sont idempotentes.
- `ALM-002.3` — La limite de snooze survit à un redémarrage.
- `ALM-002.4` — Une session a exactement une raison de fin horodatée.
- `ALM-002.5` — La phase douce bascule une seule fois vers le son fort après
  le plateau de 5 min.
- `ALM-002.6` — La rampe atteint son plafond à l'heure cible quel que soit
  `prewake_seconds`.
- `ALM-002.7` — La permission d'arrêt à distance est immuable pendant la session.
- `ALM-002.8` — Seuls une commande autorisée ou le timeout de sécurité terminent
  la sonnerie.
- `ALM-002.9` — Snooze, arrêt et timeout coupent la vibration ; la reprise
  repart du niveau de départ calibré.
- `ALM-002.10` — Après un plantage du démon pendant la sonnerie, le son reprend
  en moins de 5 s (PLT-004).

## Critères d'acceptation

Scénarios Given/When/Then obligatoires (repris de la v1) : arrêt physique,
refus de l'arrêt à distance désactivé, nombre maximal de snoozes, commandes
répétées, redémarrage pendant la sonnerie, bascule douce → forte avec
vibration en panne, timeout de 30 min. Plus, spécifique v2 : `kill -9` du
démon pendant la sonnerie.
