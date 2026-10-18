# QA-001 — Simulation sur hôte

## Statut

Brouillon — 2026-10-17.

## Héritage v1

`80/001-simulation-validation`, `80/002-host-hardware-emulator`, `mix verify`,
`lib_host/` (laboratoire matériel LiveView, mode démo).

## Objectif

Tester tout le comportement métier sur la machine de développement, sans Pi
ni attente réelle, comme `MIX_TARGET=host` en v1.

## Pyramide de tests

1. **Unitaires** (`robine-core`) : occurrences, DST, machine à états de session,
   validation, courbe de gain.
2. **Propriétés** (`proptest`) : pas de double session, bornes de gain,
   idempotence, propriété de session.
3. **Intégration hôte** : démon complet avec adaptateurs simulés (horloge
   virtuelle, audio enregistreur, Hue simulé, stockage avec pannes injectées).
4. **Contrat** : réponses JSON comparées à des fichiers d'or produits depuis la v1.
5. **Fumée firmware** : image démarrée dans QEMU pour l'init, les services,
   `/data` et la mise à jour (QA-003).
6. **Matériel** : QA-002.

## Adaptateurs simulés

- **Horloge** : UTC, fuseau et monotone avancés manuellement ; simule NTP, sauts,
  redémarrage, DST.
- **Audio** : enregistre commandes, horodatages, gain et session propriétaire ;
  injecte indisponibilité, latence, pannes transitoires.
- **Stockage** : écritures partielles, disque plein, anciennes versions de schéma.
- **Réseau / Hue** : absence, reconnexion, latence, erreurs.

## Catalogue minimal de scénarios

Repris de la v1 (`SIM-006` à `SIM-017`, sans les scénarios caméra retirés) :
trois snoozes puis un quatrième refusé, redémarrage pendant la sonnerie, saut
d'horloge de 10 min, panne audio, vibration en panne, arrêt / snooze / timeout,
anciennes politiques de présence, 20 cycles de respiration avec téléphone
déconnecté, préemption de la musique par l'alarme. Ajout v2 : `kill -9` du
démon pendant la sonnerie.

## Commande unique

`make verify` (équivalent de `mix verify`) : `cargo fmt --check`,
`cargo clippy -- -D warnings`, tests, `cargo deny` (licences et vulnérabilités),
couverture avec seuil, compilation `no_std` de `robine-core` (PLT-005.1).

## Exigences

- `QA-001.1` — `make verify` ne demande aucun outil Raspberry Pi ni Buildroot.
- `QA-001.2` — Aucun test n'attend en temps réel ; tout passe par l'horloge virtuelle.
- `QA-001.3` — Les scénarios du catalogue passent en CI.
- `QA-001.4` — La couverture du code de production est au moins celle de la v1 (67 %).

## Questions ouvertes

- Faut-il porter le laboratoire matériel (LiveView, en v1) en page web servie
  par le démon en mode hôte ?
- Le mode démo public doit-il être porté (voir PRD-001) ?
