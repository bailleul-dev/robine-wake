# Ressources audio externes

## Orage et pluie 4 — LaSonotheque.org

| Champ | Valeur |
| --- | --- |
| Identifiant Robine Wake | `storm_rain_lasonotheque_2719` |
| Fichier source | `STORM_Orage et pluie 4 (ID 2719)_LaSonotheque.fr.aac` |
| Auteur et provenance | Joseph SARDIN — LaSonotheque.org |
| Identifiant de la source | 2719 |
| Format source | AAC ADTS, stéréo, 48 kHz, environ 133 kbit/s |
| Durée décodée | 2 092,152 secondes, soit environ 34 min 52 s |
| Format persistant sur le réveil | MP3 VBR haute qualité, stéréo, 48 kHz, environ 187 kbit/s, dans `/data/sounds` |
| SHA-256 persistant | `fe766112e8614dd14f28ab25492b9b69799044918748bc72b306cc6a8f689afb` |
| Secours embarqué | MP3 CBR, mono, 48 kHz, 64 kbit/s (adapté à la partition firmware A/B) |
| SHA-256 du secours embarqué | `b1387e121ccb2b2bd48c1257366327d57b7ef3f0729fe319d9c426c68f109af8` |

La piste sert de fond naturel à la méditation. La copie haute qualité placée dans la partition
persistante est prioritaire ; le firmware contient une copie compacte, puis le moteur procédural
demeure le dernier secours local. Le moteur reste accessible avec `make dsp` pour les essais.

La prise source conserve une très grande dynamique (environ `-40,5 dBFS` RMS pour un pic à
`-0,3 dBFS`, principalement dû à l'orage). La copie d'écoute applique jusqu'à 18 dB de compensation
avec un limiteur lié entre les canaux, une attaque par blocs de 10 ms, un relâchement de 2 secondes
et un plafond à `-3 dBFS`. Elle atteint environ `-29,2 dBFS` RMS sans écrêter les coups de tonnerre.
Le volume de méditation est transmis directement au gain audio sécurisé, sans l'ancienne seconde
atténuation à 60 %, et le plafond matériel est à `0 dB`.

La page de licence de LaSonotheque indique que les fichiers marqués « Gratuit et Libre de droits »
peuvent être utilisés, adaptés et redistribués, y compris commercialement, sans restriction, selon
des conditions apparentées à CC0 1.0. L'attribution n'est pas obligatoire mais elle est recommandée ;
Robine Wake conserve donc le crédit « Joseph SARDIN — LaSonotheque.org » dans son manifeste.

Références :

- [licences et droits d'utilisation](https://lasonotheque.org/licences.html) ;
- [LaSonotheque.org](https://lasonotheque.org/).
