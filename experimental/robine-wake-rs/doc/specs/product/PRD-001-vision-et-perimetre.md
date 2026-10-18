# PRD-001 — Vision et périmètre v2

## Statut

Brouillon — 2026-10-17.

## Héritage v1

`docs/specs/README.md`, `00/001-system-architecture`, et la conclusion de
`experimental/robine-wake-rs/README.md` du dépôt v1.

## Objectif

Reconstruire Robine Wake en Rust sur un système Buildroot maison, sans Nerves
ni BEAM, pour :

1. **réduire l'empreinte** (taille d'image, RAM, temps de démarrage) ;
2. **libérer le choix du matériel** : ne plus dépendre des systèmes Nerves
   disponibles, pouvoir viser des cartes plus petites ou un design custom ;
3. **un seul langage** du réveil jusqu'aux microcontrôleurs (bouton, vibration).

## Constat de départ

L'évaluation menée dans la v1 (octobre 2026) montre que la BEAM n'est pas ce
qui impose un Raspberry Pi. AirPlay 2 (shairport-sync + NQPTP + FFmpeg) et
l'audio Bluetooth (BlueZ + BlueALSA) imposent à eux seuls un Linux avec Wi-Fi,
Bluetooth et ~128 Mo de RAM. Le gain réel sur le choix de la carte dépend donc
d'abord du **périmètre conservé**, ensuite du langage.

Le prototype Rust v1 (alarmes, stockage, événements, HTTP) compile en un
binaire statique aarch64-musl de 3,1 Mo.

## Périmètre

### Repris de la v1

| Fonction | Spec v2 |
|---|---|
| Alarmes récurrentes et ponctuelles, fuseaux IANA, DST | ALM-001 |
| Session de réveil deux phases (douce puis forte), snooze, timeout | ALM-002 |
| Sieste | ALM-003 |
| Sortie HiFiBerry, bibliothèque de sons, import WAV | AUD-001 |
| Récepteur AirPlay 2 | AUD-002 |
| Récepteur Bluetooth A2DP | AUD-003 |
| Bouton d'arrêt ESP32 Wi-Fi signé HMAC | ACC-002 |
| Bouton d'arrêt LoRa SX1276 | ACC-003 |
| API locale, SSE, interface web Expo, app mobile | API-001, API-002 |
| MCP | API-003 |
| Mise à jour A/B signée, refus près d'une alarme | OPS-001 |

### Hérité de la v1 mais non implémenté là-bas

- Vibration du lit (ACC-004), spécifiée en v1 et jamais livrée.

### Abandonné / Retiré du périmètre v2

- **Philips Hue** (ACC-001) : non implémenté en v2 (autonomie réseau complète, zéro dépendance extérieure).
- **Respiration guidée et ambiance DSP** (AUD-004) : non implémentée en v2 (recentrage sur le réveil autonome).
- Caméra, infrarouge, détection de présence et de sortie du lit (déjà retirés du périmètre v1).
- Service de contrôle BLE BlueHeron (déjà désactivé en v1).
- Laboratoire matériel Phoenix LiveView et mode démo 3D : pas porté (voir QA-001).

### Clients inchangés

L'app mobile Expo, le bundle web `priv/web` et le firmware du bouton ESP32
restent ceux de la v1. La v2 doit leur présenter le même contrat (API-001,
API-002, ACC-002) pour pouvoir remplacer la v1 sans les modifier.

## Non-objectifs

- Cloud, comptes utilisateurs, accès depuis Internet.
- Diagnostic médical, analyse du sommeil.
- Commande vocale.
- Support de plusieurs lits ou plusieurs pièces.

## Exigences

- `PRD-001.1` — La v2 remplace la v1 sur le même matériel (Pi 3 B+, Amp2) sans
  modification des clients existants.
- `PRD-001.2` — Les données d'une installation v1 sont reprises sans perte
  d'alarme (voir DAT-001).
- `PRD-001.3` — Chaque fonction lourde (AirPlay, Bluetooth, LoRa, MCP) est
  activable à la compilation de l'image, pour pouvoir construire des images
  réduites.
- `PRD-001.4` — L'empreinte de la v2 est mesurée et comparée à la v1 (QA-002).

## Questions ouvertes

- AirPlay 2 et Bluetooth sont-ils indispensables en v2 ? La réponse fixe la
  carte minimale (PLT-005).
- Le mode démo public (`robine-wake-demo.bailleul.dev`) doit-il être porté ?
