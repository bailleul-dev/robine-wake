# Robine Wake — All-In-One Mainboard v1.0 (`robine_board`)

> **Statut : concept, non fabricable.** Plusieurs symboles et empreintes sont
> des substituts (ampli, chargeur, Ethernet, PoE, condensateurs et
> inductances de puissance) et des circuits d'accompagnement manquent. Voir
> [`DESIGN_REVIEW.md`](DESIGN_REVIEW.md) avant toute commande.

Carte électronique principale tout-en-un conçue sous **KiCad 9** via le serveur MCP `kicad` pour le réveil / barre de son **Robine Wake**.

---

## 1. Vue d'ensemble des sous-systèmes

| Sous-système | Référence(s) | Composant choisi | Caractéristiques clés |
| :--- | :--- | :--- | :--- |
| **1. MCU Principal (Wi-Fi + BLE 5.0 + DSP)** | `U1`, `SW1`, `SW2`, `J3` | `ESP32-S3-WROOM-1-N16R8` | Dual-core Xtensa LX7 @ 240 MHz, 16 Mo Flash, 8 Mo PSRAM Octal, Wi-Fi 802.11 b/g/n, BLE 5.0, USB natif (`GPIO19/20`), maître I²S / SPI / I²C |
| **2. Co-processeur Bluetooth Audio (A2DP) + BLE + Wi-Fi** | `U2`, `J9` | `ESP32-WROOM-32E` | Dual-core Xtensa LX6 avec pile **Bluetooth Classic BR/EDR (A2DP Sink / AVRCP)** + BLE + Wi-Fi, relié à `U1` en I²S numérique (`I2S_BCLK`, `I2S_LRCLK`, `I2S_BT_DOUT`) et par son UART0 (`BT_RXD0/BT_TXD0`). `U1` pilote aussi `BT_EN` et `BT_IO0` : il peut redémarrer `U2` en bootloader ROM et le reflasher. `J9` (`BT_PROG`) reste en parallèle pour la récupération manuelle |
| **3. Entrée Alimentation Externe (24V DC)** | `J1`, `D1`, `C1`, `R1`, `R2` | Bornier `24V_DC_IN_5A` + Schottky `D1` (`SS54`) | Entrée **24V DC / 5A (120 W)** dimensionnée pour fournir la pleine puissance à l'amplificateur stéréo 2×50 W (`PVDD = 24V`) avec télémétrie ADC (`ADC_VIN_SENSE`) |
| **4. Batterie de secours (UPS 4S LiFePO4) & Conversions DC/DC** | `J2`, `U3`, `D2`, `U4`, `L1`, `U5`, `R3`, `R4` | `BQ24610` + `TPS54531` (5V 5A) + `AMS1117-3.3` | Batterie **4S LiFePO4 (12,8 V nominal / 14,4 V float)** (`J2`) choisie pour sa sécurité thermique absolue en chambre et sa durée de vie en maintien de charge 24/7 (> 10 ans), aiguillage sans coupure par triple diode Schottky OR-ing (`D1` Secteur 24V / `D2` Batterie 4S / `D3` PoE+ 24V → `PVDD`), buck `U4` (`5V / 5A`) et LDO `U5` (`3.3V / 1A`) |
| **5. Amplificateur Stéréo ≥ 40W/canal (2×50W)** | `U6`, `L2..L5`, `C9..C14`, `J5` | `TAS5825M` (Texas Instruments) | Amplificateur Classe-D numérique **2×50 W @ 4 Ω sous 24V** (`PVDD`), entrée I²S directe + contrôle DSP I²C (`0x4C`), filtre LC de sortie 4 voies BTL (`L2..L5` 10 µH / 5A + `C11..C14` 680 nF) vers bornier haut-parleurs `J5` |
| **6. Module LoRa 868 MHz** | `U7`, `J6` | `RFM95W-868S2` (SX1276) + `SMA` | Transceiver LoRa 868 MHz SPI (+20 dBm) compatible avec le bouton déporté `ACC-003` (protocole HMAC-SHA256), interruptions `LORA_DIO0/DIO1`, connecteur coaxial SMA 50 Ω (`J6`) |
| **7. Ethernet 10/100Base-TX avec PoE+** | `J7`, `U8`, `U9`, `D3`, `C15` | `W5500` + `Ag9924M` (IEEE 802.3at) + `RJ45` | Connecteur RJ45 MagJack PoE (`J7`), module PD PoE+ isolé **24V / 30W** (`U9` Silvertel `Ag9924M`) injectant sur `PVDD` via `D3`, contrôleur Ethernet SPI hardware TCP/IP `W5500` (`U8`) |
| **8. Matrice NeoPixel Haute Puissance (Simulation d'Aube)** | `U10`, `R9`, `C16`, `D4..D11`, `J8` | `SN74AHCT1G125` + 8× `SK6812` + `J8` | Level-shifter 3.3V→5V (`U10`), condensateur réservoir 1000 µF (`C16`), **matrice embarquée de 8 LEDs adressables `SK6812` RGBW (`D4..D11`)** + bornier haute intensité 5V/5A (`J8`) pour l'anneau lumineux / lampes d'aube externes |

---

## 2. Mapping GPIO (`U1` — `ESP32-S3-WROOM-1-N16R8`)

| Bus / Fonction | Signal Schéma | Broche `U1` | GPIO ESP32-S3 | Cible(s) connectée(s) |
| :--- | :--- | :---: | :--- | :--- |
| **Alimentation / Reset** | `+3V3`, `GND`, `MCU_EN` | 2, 1/40/41, 3 | `3V3`, `GND`, `EN` | Pull-up `R5` (10 kΩ), `C7` (100 nF), bouton `SW1` (`RESET`) |
| **Boot Mode** | `MCU_BOOT` | 27 | `GPIO0` | Bouton `SW2` (`BOOT`) |
| **ADC Alimentation & UPS** | `ADC_VIN_SENSE` | 4 | `GPIO4` (ADC1_CH3) | Pont diviseur 24V (`R1` 100 kΩ / `R2` 15 kΩ) |
| **ADC Batterie 4S** | `ADC_VBAT_SENSE` | 5 | `GPIO5` (ADC1_CH4) | Pont diviseur VBAT (`R3` 100 kΩ / `R4` 22 kΩ) |
| **I²S Audio (50W Amp + BT)** | `I2S_BCLK` | 6 | `GPIO6` | `U6` (`TAS5825M` BCLK) + `U2` (`ESP32-WROOM-32E` IO26) |
| **I²S Audio** | `I2S_LRCLK` | 7 | `GPIO7` | `U6` (`TAS5825M` LRCLK) + `U2` (`ESP32-WROOM-32E` IO25) |
| **I²S Audio Sortie Amp** | `I2S_AMP_DIN` | 8 | `GPIO15` | `U6` (`TAS5825M` SDIN) |
| **I²S Audio Entrée BT A2DP** | `I2S_BT_DOUT` | 9 | `GPIO16` | `U2` (`ESP32-WROOM-32E` IO22 — flux A2DP entrant) |
| **Contrôle Ampli 2×50W** | `AMP_PDN` | 10 | `GPIO17` | `U6` (`TAS5825M` `/PDN`) |
| **Défaut Ampli 2×50W** | `AMP_FAULT` | 11 | `GPIO18` | `U6` (`TAS5825M` `/FAULT`) |
| **I²C Système (DSP Ampli)** | `I2C_SDA` | 12 | `GPIO8` | `U6` (`TAS5825M` SDA) + pull-up `R6` (4,7 kΩ) |
| **I²C Système (DSP Ampli)** | `I2C_SCL` | 15 | `GPIO9` | `U6` (`TAS5825M` SCL) + pull-up `R7` (4,7 kΩ) |
| **USB Natif / Debug** | `USB_DN`, `USB_DP` | 13, 14 | `GPIO19`, `GPIO20` | Connecteur `J3` (`USB_UART_DBG`) |
| **SPI Partagé (LoRa + W5500)** | `SPI_MOSI` | 17 | `GPIO11` | `U7` (`RFM95W` MOSI) + `U8` (`W5500` MOSI) |
| **SPI Partagé (LoRa + W5500)** | `SPI_SCK` | 18 | `GPIO12` | `U7` (`RFM95W` SCK) + `U8` (`W5500` SCLK) |
| **SPI Partagé (LoRa + W5500)** | `SPI_MISO` | 19 | `GPIO13` | `U7` (`RFM95W` MISO) + `U8` (`W5500` MISO) |
| **LoRa 868 MHz Control** | `LORA_CS` | 16 | `GPIO10` | `U7` (`RFM95W` NSS) |
| **LoRa 868 MHz Reset/IRQ** | `LORA_RST`, `DIO0`, `DIO1` | 20, 21, 22 | `GPIO14`, `GPIO21`, `GPIO47` | `U7` (`RFM95W` RESET, DIO0, DIO1) |
| **Ethernet W5500 Control** | `ETH_CS`, `ETH_INT`, `ETH_RST` | 23, 24, 25 | `GPIO48`, `GPIO45`, `GPIO38` | `U8` (`W5500` SCSn, INTn, RSTn) |
| **Co-processeur BT UART + flash** | `BT_RXD0`, `BT_TXD0`, `BT_EN`, `BT_IO0` | 8, 9, 24, 25 | `GPIO15`, `GPIO16`, `GPIO47`, `GPIO48` | `U2` (`ESP32-WROOM-32E` RXD0, TXD0, EN, IO0) ; `BT_EN`/`BT_IO0` pilotés en open-drain, pull-ups `R25`/`R26` ; `J9` en parallèle (laisser `GPIO15` en entrée quand un adaptateur est branché) |
| **Simulation d'Aube NeoPixel** | `NEOPIXEL_DIN_3V3` | 31 | `GPIO42` | `U10` (`SN74AHCT1G125` 3.3V→5V) → `D4..D11` (`SK6812`) → `J8` |
| **Statut Chargeur UPS** | `UPS_PG`, `UPS_STAT` | 32, 35 | `GPIO2`, `GPIO1` | `U3` (`BQ24610` `/PG`, `/STAT`) |
| **UART0 Console** | `MCU_TXD0`, `MCU_RXD0` | 37, 36 | `GPIO43`, `GPIO44` | Connecteur `J3` (`USB_UART_DBG`) |

---

## 3. Vérifications Électriques & Physique (ERC / DRC)

- ERC et DRC passent (0 erreur), mais ils vérifient la cohérence des
  symboles et empreintes **tels que dessinés** : ceux de U3, U4, U6, U8, U9,
  U10, C1, C2, C9, C16 et L1 à L5 ne correspondent pas aux composants réels.
- Dimensions 180 × 120 mm : trop grandes pour le compartiment électronique
  de la barre (environ 166 × 176 × 126 mm intérieur, lampe comprise).
- Le tableau GPIO ci-dessus ne correspond pas au schéma ; le schéma fait foi,
  et GPIO45/46 y sont mal employés (voir la revue).

---

## 4. Fichiers du Projet & Exports de Fabrication

- **Projet & Sources KiCad** :
  - [`robine_board.kicad_pro`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/robine_board.kicad_pro) — Fichier projet KiCad 9
  - [`robine_board.kicad_sch`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/robine_board.kicad_sch) — Schéma électronique complet (format A2, 6 zones fonctionnelles)
  - [`robine_board.kicad_pcb`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/robine_board.kicad_pcb) — Layout PCB routé (180 × 120 mm) avec modèles 3D VRML associés
  - [`Robine_Custom.kicad_sym`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/Robine_Custom.kicad_sym) — Bibliothèque de symboles dédiée (`TAS5825M`, `BQ24610`, `TPS54531`, `W5500`, `Ag9924M`, `SN74AHCT1G125`)
  - [`3dmodels/`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/3dmodels) — Modèles 3D VRML 2.0 (`.wrl`) de tous les composants
- **Exports Visuels & Fabrication (`exports/`)** :
  - [`robine_board_schematic.pdf`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/exports/robine_board_schematic.pdf) & [`robine_board_schematic.png`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/exports/robine_board_schematic.png) — Schéma PDF vectoriel & PNG haute résolution
  - [`robine_board_pcb.pdf`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/exports/robine_board_pcb.pdf) & [`robine_board_pcb_2d.png`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/exports/robine_board_pcb_2d.png) — Plan PCB 2D
  - [`robine_board_3d_iso.png`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/exports/robine_board_3d_iso.png), [`robine_board_3d_top.png`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/exports/robine_board_3d_top.png), [`robine_board_3d_bottom.png`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/exports/robine_board_3d_bottom.png) — Rendus 3D Raytracing (vue isométrique, dessus, dessous)
  - [`robine_board.step`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/exports/robine_board.step) — Modèle CAO 3D STEP
  - [`robine_board_bom.csv`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/exports/robine_board_bom.csv) — Nomenclature complète (BOM, 61 composants / 25 lignes groupées)
  - [`robine_board_positions.csv`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/exports/robine_board_positions.csv) — Fichier Pick-and-Place (CPL/POS)
  - [`exports/gerbers/`](file:///home/guillaume/sources/robine-wake/hardware/robine_board/exports/gerbers) — Fichiers Gerber (`F.Cu`, `B.Cu`, `F.Mask`, `B.Mask`, `F.Paste`, `B.Paste`, `F.Silkscreen`, `B.Silkscreen`, `Edge.Cuts`) + perçage Excellon (`.drl`), **à ne pas commander en l'état**
