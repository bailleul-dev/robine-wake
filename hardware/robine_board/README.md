# Robine Wake — All-In-One Mainboard v1.1 (`robine_board`)

> **Statut : schéma v1.1 terminé, PCB placé mais non routé.** Les exports de
> fabrication (`exports/gerbers/`) reflètent cet état et **ne sont pas
> commandables**. La revue [`DESIGN_REVIEW.md`](DESIGN_REVIEW.md) porte sur la
> v1.0 ; une partie de ses points a été traitée par la v1.1.

Carte électronique principale tout-en-un du réveil / barre de son **Robine
Wake**, conçue sous **KiCad 9** via le serveur MCP `kicad`. Carte 2 couches,
120 × 90 mm, 145 composants.

Pour prototyper sans cette carte, voir le banc de dev sur breadboard :
[`../dev_bench/banc-de-dev.pdf`](../dev_bench/banc-de-dev.pdf).

---

## 1. Vue d'ensemble des sous-systèmes

| Sous-système | Référence(s) | Composant choisi | Caractéristiques clés |
| :--- | :--- | :--- | :--- |
| **MCU principal** | `U1`, `SW1`, `SW2`, `J3`, `U11`, `J4` | `ESP32-S3-WROOM-1-N16R8` | Dual-core LX7 240 MHz, 16 Mo flash, 8 Mo PSRAM octale, Wi-Fi + BLE 5. AirPlay 2, maître I²S, SPI et I²C. USB-C natif (`J3`, protection ESD `U11` `USBLC6-2SC6`, CC 5,1 kΩ `R22`/`R23`), console UART0 sur `J4` |
| **Co-processeur Bluetooth audio + aube** | `U2`, `J9`, `R25`, `R26`, `C29` | `ESP32-WROOM-32E` | Bluetooth Classic BR/EDR (A2DP sink, AVRCP), absent du S3. Esclave I²S de `U1` (`I2S_BCLK`, `I2S_LRCLK`), renvoie le flux A2DP sur `I2S_BT_DOUT`. Relié à `U1` par son UART0 ; `U1` pilote `BT_EN` et `BT_IO0` et peut le reflasher via le bootloader ROM. `J9` (`BT_PROG`) en parallèle pour la récupération manuelle. Génère aussi les 10 PWM de l'aube |
| **Entrée secteur 24 V** | `J1`, `D1`, `C1` | Bornier 2 points + `SS54` | Entrée `+24V_MAINS`, OR-ing vers `PVDD_24V` par `D1` |
| **UPS batterie 4S LiFePO4** | `J2`, `U3`, `Q1`, `L7`, `R15`, `R1`/`R2` | `BQ24610` + `CSD87350Q5D` | Chargeur buck synchrone depuis `+24V_MAINS`, shunt 10 mΩ, tension de fin de charge fixée par `R1`/`R2` (110 k / 20 k ≈ 13,6 V). `MAINS_OK` (/PG) et `CHG_STAT` (STAT1) vers `U1` |
| **Boost batterie → PVDD** | `U10`, `L8`, `D2`, `R16`/`R17`, `D3` | `TPS55340` | Remonte `+VBAT` vers ≈ 23,4 V sur `PVDD_24V` (OR-ing `D2`), activé par `BOOST_EN`. `D3` relie directement `+VBAT` à `PVDD_24V` en dernier recours |
| **Rails logiques** | `U4`, `L1`, `D5`, `U5`, `L6`, `D6` | `TPS54531` + `TPS54331` | Buck `PVDD_24V` → `+5V` (5 A, `R18`/`R19`), puis buck `+5V` → `+3V3` (3 A, `R20`/`R21`) |
| **Ampli stéréo** | `U6`, `L2..L5`, `C11..C14`, `C9`, `J5`, `R10` | `TAS5825M` (HTSSOP-32) | Classe D sur `PVDD_24V`, entrée I²S (`I2S_DOUT`), contrôle I²C, adresse fixée par `R10` (4,7 kΩ sur `ADR`). Filtre LC BTL vers `J5` (4 points) |
| **LoRa 868 MHz** | `U7`, `J6` | `Ai-Thinker Ra-01H` (SX1276) + SMA | Sur le SPI partagé, `LORA_CS`, `LORA_RST`, `LORA_DIO0`. Lien avec le bouton déporté `ACC-003` |
| **Stockage** | `U8` | `W25N01GVZEIG` | NAND SPI 1 Gbit sur le SPI partagé (`NAND_CS`) |
| **Horloge temps réel** | `U9`, `BT1` | `DS3231MZ` + CR1220 | I²C partagé avec l'ampli, alarme `RTC_INT_N` vers `U1`, sauvegarde par pile |
| **Lampes d'aube (10 canaux)** | `U12..U21`, `L11..L20`, `D11..D20`, `R31..R40`, `J7`, `J8`, `J10` | 10 × `PT4115` | Drivers LED à courant constant (shunt 0,2 Ω ≈ 0,5 A) alimentés par `+24V_MAINS`, gradation par `PWM_CH1..10` depuis `U2`. Lampe 1 (`J7`) et lampe 2 (`J8`) : blanc chaud, blanc froid, ambre. Halo (`J10`) : R, G, B, ambre |
| **LED de statut** | `D4`, `R9` | `SK6812` | Une LED adressable sur `+5V`, données `STATUS_LED_3V3` via 330 Ω |

---

## 2. Mapping GPIO de `U1` (`ESP32-S3-WROOM-1-N16R8`)

Généré à partir du netlist du schéma v1.1. Broches non listées : non connectées
(IO3, IO45, IO46 ; IO35..IO37 sont réservées à la PSRAM octale).

| Fonction | Net | Broche `U1` | GPIO | Cible(s) |
| :--- | :--- | :---: | :--- | :--- |
| Reset | `MCU_EN` | 3 | `EN` | `R24` 10 kΩ, `C7` 1 µF, bouton `SW1` |
| Boot | `MCU_BOOT` | 27 | `GPIO0` | `R12` 10 kΩ, bouton `SW2` |
| Présence secteur | `MAINS_OK` | 4 | `GPIO4` | `U3` /PG, pull-up `R8` |
| Commande boost | `BOOST_EN` | 5 | `GPIO5` | `U10` EN, pull-down `R13` |
| ADC batterie | `ADC_VBAT_SENSE` | 39 | `GPIO1` (ADC1_CH0) | Pont `R3` 100 kΩ / `R4` 15 kΩ sur `+VBAT` |
| État charge | `CHG_STAT` | 38 | `GPIO2` | `U3` STAT1, pull-up `R5` |
| I²S horloge bit | `I2S_BCLK` | 6 | `GPIO6` | `U6` SCLK + `U2` IO26 |
| I²S horloge mot | `I2S_LRCLK` | 7 | `GPIO7` | `U6` LRCLK + `U2` IO25 |
| I²S vers ampli | `I2S_DOUT` | 12 | `GPIO8` | `U6` SDIN |
| I²S depuis BT | `I2S_BT_DOUT` | 33 | `GPIO40` | `U2` IO22 (flux A2DP) |
| I²C données | `I2C_SDA` | 10 | `GPIO17` | `U6`, `U9`, pull-up `R6` 4,7 kΩ |
| I²C horloge | `I2C_SCL` | 11 | `GPIO18` | `U6`, `U9`, pull-up `R7` 4,7 kΩ |
| Ampli marche | `AMP_PDN` | 23 | `GPIO21` | `U6` /PDN |
| Ampli défaut | `AMP_FAULT` | 31 | `GPIO38` | `U6` /FAULT, pull-up `R11` |
| SPI horloge | `SPI_SCK` | 20 | `GPIO12` | `U7`, `U8` |
| SPI MOSI | `SPI_MOSI` | 19 | `GPIO11` | `U7`, `U8` |
| SPI MISO | `SPI_MISO` | 21 | `GPIO13` | `U7`, `U8` |
| LoRa sélection | `LORA_CS` | 18 | `GPIO10` | `U7` NSS, pull-up `R27` |
| LoRa reset | `LORA_RST` | 22 | `GPIO14` | `U7` RESET |
| LoRa interruption | `LORA_DIO0` | 32 | `GPIO39` | `U7` DIO0 |
| NAND sélection | `NAND_CS` | 17 | `GPIO9` | `U8` /CS, pull-up `R28` |
| RTC alarme | `RTC_INT_N` | 34 | `GPIO41` | `U9` /INT, pull-up `R14` |
| LED statut | `STATUS_LED_3V3` | 35 | `GPIO42` | `R9` 330 Ω → `D4` DIN |
| Liaison BT (TX de `U1`) | `BT_RXD0` | 8 | `GPIO15` | `U2` RXD0, `J9` broche 3 |
| Liaison BT (RX de `U1`) | `BT_TXD0` | 9 | `GPIO16` | `U2` TXD0, `J9` broche 2 |
| Reset de `U2` | `BT_EN` | 24 | `GPIO47` | `U2` EN, `R25`, `C29`, `J9` broche 5 — en open-drain |
| Boot de `U2` | `BT_IO0` | 25 | `GPIO48` | `U2` IO0, `R26`, `J9` broche 4 — en open-drain |
| USB natif | `USB_DN`, `USB_DP` | 13, 14 | `GPIO19`, `GPIO20` | `U11` → `J3` |
| Console | `UART0_TX`, `UART0_RX` | 37, 36 | `GPIO43`, `GPIO44` | `J4` |

Quand un adaptateur est branché sur `J9`, laisser `GPIO15` en entrée : il est
en parallèle de la sortie TX de l'adaptateur.

## 3. Mapping GPIO de `U2` (`ESP32-WROOM-32E`)

| Fonction | Net | GPIO | Cible |
| :--- | :--- | :--- | :--- |
| Liaison avec `U1` | `BT_RXD0`, `BT_TXD0` | `GPIO3`, `GPIO1` (UART0) | `U1` GPIO15, GPIO16 |
| Reset, boot | `BT_EN`, `BT_IO0` | `EN`, `GPIO0` | `U1` GPIO47, GPIO48 |
| I²S esclave | `I2S_BCLK`, `I2S_LRCLK` | `GPIO26`, `GPIO25` | horloges générées par `U1` |
| Sortie A2DP | `I2S_BT_DOUT` | `GPIO22` | `U1` GPIO40 |
| Lampe 1 blanc chaud, froid, ambre | `PWM_CH1..3` | `GPIO4`, `GPIO13`, `GPIO14` | `U12..U14` DIM |
| Lampe 2 blanc chaud, froid, ambre | `PWM_CH4..6` | `GPIO18`, `GPIO19`, `GPIO21` | `U15..U17` DIM |
| Halo R, G, B, ambre | `PWM_CH7..10` | `GPIO23`, `GPIO27`, `GPIO32`, `GPIO33` | `U18..U21` DIM |

---

## 4. Vérifications

- **ERC** : 0 violation. **DRC** : 0 violation, parité schéma ↔ PCB sans
  écart ; 402 connexions restent à router.
- ERC et DRC ne contrôlent que la cohérence des symboles et empreintes tels
  que dessinés, pas leur conformité aux composants réels.

### Points ouverts

- **Routage** du PCB à faire, puis plans de masse et vias thermiques
  (`U6` PowerPAD, buck, boost).
- **Placement** : sur la vue 2D, des borniers et la zone d'antenne de `U1`
  débordent du contour de la carte.
- **Aube sur batterie** : les `PT4115` sont alimentés par `+24V_MAINS`, donc
  les lampes s'éteignent en cas de coupure secteur. À confirmer si c'est
  voulu.
- **LED de statut** : la `SK6812` est en 5 V et reçoit des données en 3,3 V
  sans level shifter ; le seuil haut (0,7 × VDD = 3,5 V) n'est pas garanti.

---

## 5. Fichiers

- **Sources KiCad**
  - [`robine_board.kicad_pro`](robine_board.kicad_pro) — projet KiCad 9
  - [`robine_board.kicad_sch`](robine_board.kicad_sch) — schéma
  - [`robine_board.kicad_pcb`](robine_board.kicad_pcb) — PCB 120 × 90 mm, placé, non routé
  - [`Robine_Custom.kicad_sym`](Robine_Custom.kicad_sym) — symboles dédiés
  - [`3dmodels/`](3dmodels) — modèles 3D des composants
- **Exports** (`exports/`, régénérés avec `kicad-cli` 9.0.8)
  - [`robine_board_schematic.pdf`](exports/robine_board_schematic.pdf), [`robine_board_schematic.png`](exports/robine_board_schematic.png) — schéma
  - [`robine_board_pcb.pdf`](exports/robine_board_pcb.pdf), [`robine_board_pcb.svg`](exports/robine_board_pcb.svg), [`robine_board_pcb_2d.png`](exports/robine_board_pcb_2d.png) — vue 2D (F.Cu, B.Cu, F.Silkscreen, Edge.Cuts)
  - [`robine_board_3d_iso.png`](exports/robine_board_3d_iso.png), [`robine_board_3d_top.png`](exports/robine_board_3d_top.png), [`robine_board_3d_bottom.png`](exports/robine_board_3d_bottom.png) — rendus 3D
  - [`robine_board.step`](exports/robine_board.step) — modèle 3D STEP
  - [`robine_board_bom.csv`](exports/robine_board_bom.csv) — nomenclature (145 composants, 68 lignes groupées)
  - [`robine_board_positions.csv`](exports/robine_board_positions.csv) — pick-and-place
  - [`drc_report.json`](exports/drc_report.json) — rapport DRC avec parité schéma
  - [`gerbers/`](exports/gerbers) — Gerber (cuivre, masque, pâte, sérigraphie, contour) et perçage Excellon, **non commandables tant que le PCB n'est pas routé**
