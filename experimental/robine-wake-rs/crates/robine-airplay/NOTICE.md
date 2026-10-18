# NOTICE

Ceci n'est pas un avis juridique.

## Tables FairPlay `fp-setup` (`src/fairplay.rs`, option `fairplay`)

Les quatre tables de 142 octets et l'en-tête de 12 octets ne sont pas
originales. Ce sont des constantes d'interopérabilité rétro-conçues à partir
du FairPlay d'Apple, présentes dans de nombreux récepteurs AirPlay
(shairport-sync, UxPlay, RPiPlay, openairplay). Elles sont reprises de
openairplay2 0.3.0 :

> MIT License — Copyright (c) 2026 Stefan Arentz

La licence MIT de openairplay2 ne couvre pas ces données dérivées d'Apple :
leur statut relève du droit d'auteur d'Apple et des règles sur le
contournement des mesures techniques de protection (DMCA aux États-Unis,
directive 2001/29/CE en Europe).

Décision du projet (2026-10-18) : utilisées pour le prototype uniquement,
derrière l'option `fairplay`, désactivée par défaut. Avant toute
commercialisation, choisir entre le programme MFi d'Apple, l'abandon
d'AirPlay, ou une analyse juridique. Le nom « AirPlay » ne peut pas figurer
sur un produit vendu sans licence Apple.

## Référence du protocole

Le comportement du récepteur (enregistrements TXT, `/info`, SRP HomeKit,
canal de contrôle) a été vérifié en lisant openairplay2 0.3.0 (MIT) et
shairport-sync (MIT, © James Laird et Mike Brady). Le reste du code est
original.

## Tables de Huffman AAC (`src/aac/tables.rs`)

Extraites de Symphonia (symphonia-codec-aac 0.6.1), sous licence
**MPL-2.0** : ce fichier reste sous MPL-2.0 (copyleft au niveau du fichier,
compatible avec un produit commercial tant que ses modifications éventuelles
sont publiées). Le reste du décodeur AAC est original.
