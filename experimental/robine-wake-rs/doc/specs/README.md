# Spécifications Robine Wake 2

Robine Wake 2 est la réécriture en Rust de [Robine Wake](../../../robine-wake)
(Elixir / Nerves), sur un système Buildroot maison minimal. La première cible
reste le Raspberry Pi 3 B+ avec HiFiBerry Amp2 ; l'objectif est de pouvoir
descendre ensuite sur du matériel plus léger.

Ce dossier est la source de vérité fonctionnelle et technique de la v2. Le
code et les tests référencent les identifiants d'exigence définis ici.

## Convention

```text
doc/specs/<domaine>/<feature-id>-<feature-name>.md
```

- `feature-id` = préfixe du domaine + numéro sur 3 chiffres (`PLT-001`).
- Les exigences d'une feature sont numérotées `<feature-id>.<n>` (`PLT-001.4`).
- Les identifiants sont stables : renommer une feature ne change pas son ID, un
  ID retiré n'est jamais réutilisé.
- Chaque spec indique la spec v1 dont elle hérite. Quand la v2 ne dit rien de
  contraire, le comportement v1 fait foi.

| Domaine | Préfixe | Responsabilité |
|---|---|---|
| `product` | `PRD` | vision, périmètre, architecture logicielle |
| `platform` | `PLT` | Buildroot, carte, réseau, heure, services système |
| `operations` | `OPS` | mises à jour, accès de maintenance, santé |
| `alarm` | `ALM` | alarmes, sessions de réveil, sieste |
| `audio` | `AUD` | sortie audio, récepteurs AirPlay/Bluetooth, respiration |
| `accessories` | `ACC` | Hue, boutons déportés, vibration du lit |
| `interface` | `API` | API HTTP, protocole de commandes, MCP |
| `data` | `DAT` | persistance, migrations, sécurité |
| `quality` | `QA` | simulation hôte, validation matérielle, comparatif v1 |

## Priorités

- **P0** : indispensable pour un réveil fiable hors ligne.
- **P1** : indispensable pour remplacer la v1 au quotidien.
- **P2** : amélioration ou fonction reportable après remplacement de la v1.

## Index

La colonne *Priorité* est une **proposition à valider**. L'ordre retenu à ce
stade : Buildroot d'abord.

| ID | Feature | Priorité proposée | Phase proposée |
|---|---|---|---|
| [PRD-001](product/PRD-001-vision-et-perimetre.md) | Vision et périmètre v2 | P0 | 0 |
| [PRD-002](product/PRD-002-architecture-logicielle.md) | Architecture logicielle Rust | P0 | 0 |
| [PLT-001](platform/PLT-001-systeme-buildroot.md) | Système Buildroot minimal | P0 | **1** |
| [PLT-002](platform/PLT-002-carte-rpi3.md) | Support carte Raspberry Pi 3 | P0 | **1** |
| [PLT-003](platform/PLT-003-reseau-et-heure.md) | Réseau, mDNS et qualité de l'heure | P0 | **1** |
| [PLT-004](platform/PLT-004-services-et-supervision.md) | Init, services et supervision | P0 | **1** |
| [PLT-005](platform/PLT-005-cibles-legeres.md) | Portage vers des cibles plus légères | P2 | 5 |
| [OPS-001](operations/OPS-001-mise-a-jour-ab.md) | Mise à jour A/B signée | P0 | **1** |
| [OPS-002](operations/OPS-002-acces-ssh-et-deploiement-dev.md) | Accès SSH et déploiement de dev | P0 | **1** |
| [OPS-003](operations/OPS-003-sante-logs-diagnostics.md) | Santé, logs et diagnostics | P1 | 2 |
| [ALM-001](alarm/ALM-001-planification.md) | Planification des alarmes | P0 | 2 |
| [ALM-002](alarm/ALM-002-session-de-reveil.md) | Session de réveil | P0 | 2 |
| [ALM-003](alarm/ALM-003-sieste.md) | Sieste | P1 | 3 |
| [AUD-001](audio/AUD-001-sortie-audio.md) | Sortie audio et arbitre ALSA | P0 | 2 |
| [AUD-002](audio/AUD-002-recepteur-airplay.md) | Récepteur AirPlay | P1 | 4 |
| [AUD-003](audio/AUD-003-recepteur-bluetooth.md) | Récepteur audio Bluetooth | P2 | 4 |
| [AUD-004](audio/AUD-004-respiration-guidee.md) | Respiration guidée et ambiance DSP | Retiré | — |
| [ACC-001](accessories/ACC-001-philips-hue.md) | Philips Hue | Retiré | — |
| [ACC-002](accessories/ACC-002-bouton-wifi-esp32.md) | Bouton d'arrêt Wi-Fi ESP32 | P0 | 2 |
| [ACC-003](accessories/ACC-003-bouton-lora.md) | Bouton d'arrêt LoRa SX1276 | P2 | 4 |
| [ACC-004](accessories/ACC-004-vibration-lit.md) | Vibration du lit | P2 | 5 |
| [API-001](interface/API-001-api-http-locale.md) | API HTTP locale et interface web | P0 | 2 |
| [API-002](interface/API-002-protocole-commandes-v1.md) | Protocole de commandes v1 | P1 | 2 |
| [API-003](interface/API-003-mcp.md) | Serveur MCP HTTP | P2 | 4 |
| [DAT-001](data/DAT-001-persistance-et-migration.md) | Persistance et reprise des données v1 | P0 | 2 |
| [DAT-002](data/DAT-002-securite-et-confidentialite.md) | Sécurité et confidentialité | P1 | 3 |
| [QA-001](quality/QA-001-simulation-hote.md) | Simulation sur hôte | P0 | 2 |
| [QA-002](quality/QA-002-validation-et-comparatif-v1.md) | Validation matérielle et comparatif v1 | P0 | 1 → 4 |
| [QA-003](quality/QA-003-emulation-qemu.md) | Émulation QEMU | P0 | **1** |

Phases :

1. **Plateforme** (Terminée — 2026-10-17) : image Buildroot minimale, SSH par clé, mise à jour A/B signée avec tryboot et fw-validate, autoformatage `/data`, mDNS `robine-wake.local`, CLI de maintenance (`status`, `can-update`, `logs`), watchdog matériel, suivi qualité horloge, validation QEMU virt & raspi3b.
2. **Réveil autonome** (Terminée — 2026-10-17) : découpage workspace Cargo (robine-core, robine-ports, robine-daemon), machine à états de session ALM-002, planificateur actif ALM-001, bouton ESP32 ACC-002 avec HMAC/compteur anti-rejeu, API commandes v1 API-001/002, sortie audio AUD-001, validation end-to-end QEMU (QA-003).
3. **Parité quotidienne** (Terminée — 2026-10-17) : sieste (ALM-003), import sons WAV et bibliothèque (DAT-001/AUD-001), factory-reset, sécurité et diagnostics (DAT-002, API-001). *(Philips Hue ACC-001 et Respiration guidée AUD-004 retirées du périmètre v2 pour autonomie hors ligne complète)*.
4. **Confort** (Terminée — 2026-10-17) : Serveur MCP Streamable HTTP (API-003), arbitre audio avec préemption et reprise AirPlay / Bluetooth (AUD-001, AUD-002, AUD-003), bouton d'arrêt radio LoRa SX1276 (ACC-003).
5. **Au-delà de la v1** : vibration du lit, cibles plus légères.

## Principes non négociables (repris de la v1)

1. Le réveil fonctionne sans réseau, sans application et sans accessoire.
2. La panne d'un accessoire (Hue, AirPlay, Bluetooth, vibration, radio) ne
   retarde, n'atténue et n'empêche jamais l'alarme sonore ni son arrêt.
3. Le cœur métier est testable sur la machine de développement, sans matériel.
4. Une configuration invalide n'empêche jamais le démarrage.
5. L'heure, le fuseau et les changements d'heure sont traités explicitement.
6. Aucune caméra, aucune détection de présence (retirées le 2026-09-06).
