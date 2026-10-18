# ACC-003 — Bouton d'arrêt LoRa SX1276

## Statut

Implémenté et testé — 2026-10-17. Pilote radio SX1276 (868.1 MHz, BW 125 kHz, SF9, Sync 0x12, 14 dBm), scrutation périodique, vérification RegVersion 0x12, authentification HMAC-SHA256 et anti-rejeu ACC-002, cache LRU 32 réponses 5 min.

## Héritage v1

`knowledges/remote-alarm-button.md`, `lib/robine_wake/lora/server.ex`,
`lora/protocol.ex`, `lib_target/robine_wake/lora/driver/sx1276.ex`.

## Objectif

Variante radio du bouton d'arrêt, en LoRa point à point (pas LoRaWAN), pour un
bouton sur pile sans Wi-Fi.

## Contrat repris de la v1

- Module RFM95/SX1276 868 MHz sur `spidev0.0`, sans DIO0 (scrutation des
  drapeaux toutes les 25 ms).
- 868,1 MHz, BW 125 kHz, SF9, CR 4/5, préambule 8, CRC, en-tête explicite,
  mot de synchronisation `0x12`, 14 dBm.
- `RegVersion` doit valoir `0x12`, sinon service indisponible ; nouvel essai
  toutes les 5 s si le module est absent.
- Charges utiles JSON ≤ 255 octets, opérations `pair` et `dismiss`, même HMAC et
  même compteur que ACC-002 ; cache des 32 dernières réponses pendant 5 min.

## Implémentation

Pilote SX1276 en Rust sur `spidev` (crate `spidev` ou `linux-embedded-hal`).
Le pilote peut être partagé avec un futur firmware de bouton en Rust embarqué
(PLT-005).

## Exigences

- `ACC-003.1` — Les paramètres radio sont identiques à la v1.
- `ACC-003.2` — Un module absent ou mal câblé met le service en indisponible
  sans affecter le démon.
- `ACC-003.3` — L'authentification et l'anti-rejeu sont ceux d'ACC-002.

## Critères d'acceptation

- Bouton Arduino v1 associé et fonctionnel avec la v2.
- Module débranché : santé `degraded`, alarme inchangée.

## Questions ouvertes

- Ce bouton est-il encore utilisé, le bouton ESP32 Wi-Fi l'ayant remplacé ?
