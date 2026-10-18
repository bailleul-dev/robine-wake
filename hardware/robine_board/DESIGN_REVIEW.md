# Revue de la carte `robine_board` v1.0 — 2026-10-18

Verdict : **concept d'architecture, pas une carte fabricable.** Le choix des
blocs est bon (ESP32-S3 N16R8 + ESP32 classique pour l'A2DP en I²S,
ampli I²S, NeoPixel), et il est validé par le firmware Rust actuel. Mais les
symboles et empreintes de la plupart des circuits de puissance sont des
substituts, et les circuits d'accompagnement manquent. Les contrôles « 0 ERC,
0 DRC » ne portent que sur la cohérence de ces substituts.

## 1. Bloquants

### Boîtiers et symboles faux

| Réf. | Composant | Dessiné | Réel |
|---|---|---|---|
| U6 | TAS5825M | SOIC-16, 16 broches | HTSSOP-32 avec PowerPAD (vias thermiques) |
| U3 | BQ24610 | SOIC-8, 8 broches | VQFN-24 ; contrôleur à **MOSFET externes**, inductance et résistances de mesure absentes |
| U8 | W5500 | SOIC-14, 14 broches | LQFP-48 ; quartz 25 MHz et découplage absents |
| U9 | Ag9924M (PoE) | SOIC-8 | module SIL traversant ; pont de redressement, TVS et isolation absents |
| U4 | TPS54531 | SOIC-8 sans pad | SO-8 PowerPAD ; boucle de régulation (pont de retour, compensation, bootstrap) absente |
| U10 | SN74AHCT1G125 | valeur « 74AHCT125 », SOIC-8 | porte unique SOT-23-5 |
| C1, C2, C9, C16 | 470 µF/35 V, 100 µF/25 V, 1000 µF/10 V | 0805 | électrolytiques CMS (≥ 8×10 mm) ou traversants |
| L1–L5 | 4,7 µH/6 A, 10 µH/5 A | 1210 | inductances de puissance blindées ≥ 7×7 mm (saturation > 6 A) |
| J3 | « USB_PORT » | barrette 4 broches | USB-C avec protection ESD (l'ESP32-S3 se flashe par USB natif) |

### Circuits manquants

- **Stockage des sons** : 93 Mo de sons embarqués, la flash du module fait
  16 Mo. Ajouter une NAND SPI 1 Gbit (W25N01GV) ou un lecteur microSD.
- **Ampli** : condensateurs de bootstrap, découplage DVDD/AVDD/PVDD au plus
  près, pull-up de `FAULTZ`.
- **ESP32-WROOM-32E** : circuit RC de `EN`, broches de démarrage (IO0, IO2,
  IO12) fixées, découplage complet, accès de flashage (UART ou USB).
- **3,3 V** : un AMS1117 depuis 5 V pour deux modules Wi-Fi (pointes ~1 A)
  dissipe ~1,7 W en SOT-223. Remplacer par un buck 3,3 V / 2 A.

### Broches de démarrage de l'ESP32-S3

| Broche | Usage dessiné | Problème |
|---|---|---|
| GPIO46 | `AMP_FAULT` (tiré au niveau haut) | GPIO0 bas + GPIO46 haut est une combinaison invalide : le bouton BOOT ne permettrait plus de flasher |
| GPIO45 | `HALO_3V3` | doit rester bas au démarrage (tension de la flash) ; à éviter |
| GPIO3 | `POE_OK` | broche de sélection JTAG ; acceptable en entrée, mieux ailleurs |

GPIO35 à 37 (PSRAM octale) sont bien laissés libres. GPIO1 et GPIO19/20
(USB) sont disponibles. Le tableau GPIO du README ne correspond pas au
schéma (ex. I²S) : le schéma fait foi.

### Encombrement

180 × 120 mm ne rentre pas dans la barre : le compartiment d'extrémité fait
environ 166 × 176 × 126 mm intérieur (panneaux de 12 mm), lampe comprise.
Viser ≤ 120 × 90 mm.

## 2. Décisions pour la v1.1

| Sujet | Décision (2026-10-18) |
|---|---|
| Ethernet W5500 + PoE Ag9924M + MagJack | **supprimés** |
| LoRa 868 MHz | **conservé** pour le bouton déporté, avec un **Ai-Thinker Ra-01H** (SX1276 868 MHz, ~3–4 €) au lieu du RFM95W : même puce, pilote existant compatible ; brochage et stock à vérifier |
| Onduleur | **pour l'alarme sonore seulement, à plein volume** : pack LiFePO4 4S externe, chargeur BQ24610 (avec MOSFET, inductance, mesure), **élévateur 12,8 V → 24 V** (ex. TPS55340) activé sur coupure pour garder la pleine puissance de l'ampli ; lumière sur une ligne secteur seule, coupée matériellement sur batterie ; RTC à pile bouton pour l'heure ; signal secteur lu par le firmware (Wi-Fi coupé sur batterie jusqu'à l'alarme) |
| Éclairage | **pilotes LED à courant constant** (`LIGHTING.md`) : 10 canaux (2 lampes blanc chaud / blanc froid / ambre, halo RGBA), abaisseurs type PT4115/AL8860 sur la ligne 24 V secteur seule ; **PWM produits par l'ESP32-WROOM-32E** (16 canaux LEDC, broches libres) sur consignes de l'ESP32-S3 par l'UART existant ; les 8 SK6812 sont retirées (une LED d'état reste) ; LED de puissance hors carte |

## 3. Points relevés

- **Ethernet + PoE** (W5500, Ag9924M, MagJack) : ~25 € et une grande surface
  pour un réveil en Wi-Fi ; 30 W de PoE ne suffisent pas à l'ampli ; la
  conception PoE (isolation 1500 V) est la partie la plus risquée.
- **Onduleur LiFePO4 4S** : la v1.0 dessinait le chargeur sans ses MOSFET,
  son inductance ni sa mesure de courant, et sans élévateur : sur batterie,
  l'ampli aurait perdu environ 5,5 dB. Voir la décision ci-dessus.
- **Éclairage** : huit SK6812 (≈ 2 W) ne faisaient ni l'aube à 300 lux ni la
  lumière de lecture prévues par `LIGHTING.md`. Les dix canaux PWM
  nécessaires n'entrent pas dans les broches de l'ESP32-S3 (≈ 34 broches
  demandées pour ≈ 25 sûres) : voir la décision ci-dessus.
- **Ampli** : condensateurs de bootstrap, découplage DVDD/AVDD/PVDD au plus
  près, pull-up de `FAULTZ`.
- **ESP32-WROOM-32E** : circuit RC de `EN`, broches de démarrage (IO0, IO2,
  IO12) fixées, découplage complet, accès de flashage (UART ou USB).
- **3,3 V** : un AMS1117 depuis 5 V pour deux modules Wi-Fi (pointes ~1 A)
  dissipe ~1,7 W en SOT-223. Remplacer par un buck 3,3 V / 2 A.

### Broches de démarrage de l'ESP32-S3

| Broche | Usage dessiné | Problème |
|---|---|---|
| GPIO46 | `AMP_FAULT` (tiré au niveau haut) | GPIO0 bas + GPIO46 haut est une combinaison invalide : le bouton BOOT ne permettrait plus de flasher |
| GPIO45 | `HALO_3V3` | doit rester bas au démarrage (tension de la flash) ; à éviter |
| GPIO3 | `POE_OK` | broche de sélection JTAG ; acceptable en entrée, mieux ailleurs |

GPIO35 à 37 (PSRAM octale) sont bien laissés libres. GPIO1 et GPIO19/20
(USB) sont disponibles. Le tableau GPIO du README ne correspond pas au
schéma (ex. I²S) : le schéma fait foi.

### Encombrement

180 × 120 mm ne rentre pas dans la barre : le compartiment d'extrémité fait
environ 166 × 176 × 126 mm intérieur (panneaux de 12 mm), lampe comprise.
Viser ≤ 120 × 90 mm.

## 2. Décisions pour la v1.1

| Sujet | Décision (2026-10-18) |
|---|---|
| Ethernet W5500 + PoE Ag9924M + MagJack | **supprimés** |
| LoRa 868 MHz | **conservé** pour le bouton déporté, avec un **Ai-Thinker Ra-01H** (SX1276 868 MHz, ~3–4 €) au lieu du RFM95W : même puce, pilote existant compatible ; brochage et stock à vérifier |
| Onduleur | **pour l'alarme sonore seulement, à plein volume** : pack LiFePO4 4S externe, chargeur BQ24610 (avec MOSFET, inductance, mesure), **élévateur 12,8 V → 24 V** (ex. TPS55340) activé sur coupure pour garder la pleine puissance de l'ampli ; lumière sur une ligne secteur seule, coupée matériellement sur batterie ; RTC à pile bouton pour l'heure ; signal secteur lu par le firmware (Wi-Fi coupé sur batterie jusqu'à l'alarme) |
| Éclairage | **pilotes LED à courant constant** (`LIGHTING.md`) : 10 canaux (2 lampes blanc chaud / blanc froid / ambre, halo RGBA), abaisseurs type PT4115/AL8860 sur la ligne 24 V secteur seule ; **PWM produits par l'ESP32-WROOM-32E** (16 canaux LEDC, broches libres) sur consignes de l'ESP32-S3 par l'UART existant ; les 8 SK6812 sont retirées (une LED d'état reste) ; LED de puissance hors carte |

## 3. Points relevés

- **Ethernet + PoE** (W5500, Ag9924M, MagJack) : ~25 € et une grande surface
  pour un réveil en Wi-Fi ; 30 W de PoE ne suffisent pas à l'ampli ; la
  conception PoE (isolation 1500 V) est la partie la plus risquée.
- **Onduleur LiFePO4 4S** : la v1.0 dessinait le chargeur sans ses MOSFET,
  son inductance ni sa mesure de courant, et sans élévateur : sur batterie,
  l'ampli aurait perdu environ 5,5 dB. Voir la décision ci-dessus.
- **Éclairage** : `LIGHTING.md` prévoit deux lampes de ~5 W (blanc chaud,
  blanc froid, ambre) à courant constant et un halo RGB(A). Huit SK6812 sur
  la carte (≈ 2 W) ne font ni l'aube à 300 lux ni la lumière de lecture.
  Prévoir des sorties pour pilotes LED à courant constant (PWM) ou des rubans
  NeoPixel externes puissants, et garder seulement une LED d'état sur la
  carte.
- **Ampli** : « 2 × 50 W » est optimiste pour un TAS5825M ; compter environ
  2 × 30 à 40 W sur 4 Ω sous 24 V selon la distorsion acceptée (fiche technique
  à confirmer pour les haut-parleurs choisis).
- **PCB 4 couches** : deux radios, un Class-D et un buck 5 A sur 2 couches
  risquent des problèmes de CEM ; le surcoût est faible.

## 4. Estimation de coût (ordres de grandeur, prix catalogue 2026 non vérifiés)

Hors alimentation 24 V (≈ 12–15 €), haut-parleurs, batterie et boîtier.
Le pack LiFePO4 4S avec sa protection (≈ 2 Ah, ≈ 20–25 €) et les LED de
puissance hors carte (≈ 5–8 €) sont en plus.

| Bloc | v1.0 telle que dessinée (corrigée) | v1.1 (décisions ci-dessus) |
|---|---|---|
| ESP32-S3-WROOM-1-N16R8 | 4,0 | 4,0 |
| ESP32-WROOM-32E (A2DP) | 2,8 | 2,8 |
| Ampli TAS5825M + filtre LC + découplage | 7,3 | 7,3 |
| Buck 5 V / 5 A (TPS54531 + inductance + boucle) | 2,6 | 2,6 |
| 3,3 V | 0,1 (LDO, à remplacer) | 0,6 (buck) |
| Onduleur BQ24610 + MOSFET + inductance | 6,1 | 6,1 |
| Élévateur 24 V (TPS55340 + inductance + diodes) | 0 | 3,5 |
| RTC + support pile | 0 | 0,5 |
| LoRa SX1276 + SMA | 7,8 | 4,5 (Ra-01H) |
| Ethernet W5500 + quartz + MagJack PoE | 6,2 | 0 |
| Module PoE Ag9924M + pont/TVS | ~19 | 0 |
| Stockage sons (NAND 1 Gbit) | 0 (absent) | 1,5 |
| USB-C + ESD | 0 (absent) | 0,6 |
| Lumière | 1,1 (8 SK6812) | 6,0 (10 pilotes à courant constant + connecteurs) |
| Connecteurs, boutons, passifs | 2,7 | 2,5 |
| **Composants (€, à l'unité, petites quantités)** | **≈ 60** | **≈ 42** |
| PCB 4 couches (lot de 5) | ≈ 8 (180 × 120) | ≈ 4 (120 × 90) |
| Assemblage CMS en ligne (lot de 5, frais répartis) | ≈ 13 | ≈ 9 |
| **Prototype, par carte (lot de 5)** | **≈ 80 €** | **≈ 58 €** |
| **Série de 1000** | **≈ 45 €** | **≈ 32–34 €** |

Le poste dominant de la v1.0 est le bloc Ethernet + PoE (~25 €). Le surcoût
FairPlay/AirPlay est nul côté matériel ; la décision MFi (voir
`experimental/robine-wake-rs/crates/robine-airplay/NOTICE.md`) changerait la
carte (puce d'authentification Apple) et le coût.
