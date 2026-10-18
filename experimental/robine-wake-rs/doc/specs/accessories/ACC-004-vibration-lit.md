# ACC-004 — Vibration du lit

## Statut

Brouillon — 2026-10-17. Spécifié en v1 (P1), jamais implémenté.

## Héritage v1

`30/004-bed-vibration` (fait foi pour le matériel, la sécurité et les trois
usages), `knowledges/diy-bed-vibration.md`, `HW-007`, `HW-008` de
`10/002-hardware-profile`.

## Objectif

Ajouter un canal tactile, fixé au cadre du lit, pour trois usages activables
séparément : respiration guidée, basses de la musique, réveil progressif. La
vibration n'est jamais un capteur.

## Rappel des règles v1

- Actionneur (moteur à masse excentrée caréné, ou bass shaker) alimenté par un
  circuit dédié protégé, jamais par le 5 V ou les GPIO du Pi.
- Le Pi fournit seulement une consigne d'intensité ; un limiteur borne toujours
  la sortie.
- Désactivé et non calibré par défaut ; non calibré ≠ panne.
- Sa panne ne bloque jamais le son ni les commandes physiques.
- Snooze, arrêt, timeout et préemption coupent la vibration ; la reprise
  repart du niveau de départ calibré.

## Spécifique v2

- L'interface de commande (PWM matériel, I²C, ou microcontrôleur dédié sur
  liaison série) reste à choisir. Un microcontrôleur dédié en Rust embarqué
  peut porter le limiteur et la coupure de sécurité, indépendamment du Pi.
- La consigne suit les mêmes échéances monotones que la session ou la respiration.

## Exigences

- `ACC-004.1` — La panne de la sortie tactile n'interrompt ni le son ni la session.
- `ACC-004.2` — La coupure tactile intervient dans un délai borné et mesuré
  après snooze, arrêt ou timeout.
- `ACC-004.3` — Les profils de vibration persistés sont bornés et validés.

## Questions ouvertes

- Choix de l'actionneur et de l'interface (décisions `HW-DEC-007` et
  `HW-DEC-008` de la v1, toujours ouvertes).
