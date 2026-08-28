# Modélisation DSP de la pluie sur les arbres

État de la recherche au 22 août 2026.

## Objectif et limites

Ce document décrit les connaissances nécessaires à une synthèse crédible de pluie tombant sur
des arbres. Il sert de référence pour faire évoluer `RobineWake.Audio.MeditationDSP`.

Il n'existe pas de son universel de « pluie sur les arbres ». Le résultat dépend au minimum :

- de l'espèce, de la taille, de la masse, de la rigidité et de la mouillabilité des feuilles ;
- de la densité, de la hauteur et de la saturation de la canopée ;
- de l'intensité de pluie et de la distribution des diamètres de gouttes ;
- de la vitesse et de l'angle du vent ;
- du sol, de l'écorce et des éventuelles surfaces d'eau ;
- de la position de l'auditeur et de la distance aux impacts ;
- du microphone ou du système de restitution utilisé comme référence.

Une modélisation « parfaite » doit donc être paramétrique et validée contre un environnement de
référence précis. Pour la méditation Robine Wake, la cible recommandée est une pluie légère à
modérée, sous une canopée feuillue déjà humide, avec quelques gouttes proches et sans vent marqué.

## Décomposition du phénomène

La pluie forestière doit être représentée par plusieurs populations et non par un bruit filtré
unique.

| Couche | Origine | Propriétés perceptives attendues |
| --- | --- | --- |
| Pluie directe | Gouttes traversant les trouées de la canopée | Impacts rapides, fins et répartis |
| Impacts foliaires | Gouttes frappant directement les feuilles | Attaque large bande puis courte résonance |
| Splash | Fragmentation et rebond sur les feuilles | Crépitement léger, diffus et plutôt aigu |
| Égouttement de canopée | Eau accumulée puis détachée des feuilles et branches | Grosses gouttes rares, fortes et localisées |
| Branches et écorce | Impacts ou écoulements sur les parties ligneuses | Corps médium/grave et points spatiaux stables |
| Sol forestier | Litière, mousse, terre humide et flaques | Texture amortie ou résonances liquides selon le sol |
| Lit distant | Superposition de milliers d'impacts non résolus | Texture continue, diffuse et filtrée par la végétation |

La couche de pluie actuellement isolée dans le DSP correspond essentiellement à un bruit aigu
continu. Elle ne représente pas encore ces familles d'événements.

## Distribution des gouttes en pluie ouverte

La distribution exponentielle de Marshall–Palmer constitue un point de départ classique pour une
pluie stratiforme :

```text
N(D) = N0 exp(-ΛD)
N0 = 8 000 m⁻³ mm⁻¹
Λ  = 4,1 R⁻⁰·²¹ mm⁻¹
```

où `D` est le diamètre en millimètres et `R` l'intensité en millimètres par heure. Cette loi donne
une distribution moyenne de pluie libre ; elle ne décrit ni les événements convectifs particuliers
ni les transformations dans une canopée.

Source primaire : [Marshall et Palmer, *The Distribution of Raindrops With Size*, 1948](https://journals.ametsoc.org/view/journals/atsc/5/4/1520-0469_1948_005_0165_tdorws_2_0_co_2.xml).

La vitesse terminale peut être approchée, pour `D` en millimètres, par :

```text
v(D) = 9,65 - 10,3 exp(-0,6D)  m/s
```

Les mesures fondatrices couvrent plus de 1 500 gouttes, depuis le régime de Stokes jusqu'aux
grosses gouttes instables, avec une précision globale annoncée meilleure que 0,7 %.

Sources :

- [Gunn et Kinzer, *The Terminal Velocity of Fall for Water Droplets in Stagnant Air*, 1949](https://journals.ametsoc.org/view/journals/atsc/6/4/1520-0469_1949_006_0243_ttvoff_2_0_co_2.xml) ;
- [Atlas, Srivastava et Sekhon, *Doppler Radar Characteristics of Precipitation at Vertical Incidence*, 1973](https://agupubs.onlinelibrary.wiley.com/doi/abs/10.1029/RG011i001p00001).

La masse et l'énergie cinétique d'une goutte sphérique sont :

```text
m  = ρ πD³ / 6
Ek = 1/2 m v²
p  = mv
```

L'énergie augmente comme le cube du diamètre avant même de tenir compte de la vitesse. Les grosses
gouttes rares ne doivent donc pas être modélisées comme de simples variantes légèrement plus fortes
des petites gouttes.

Pour une surface réceptrice effective `A`, le taux théorique d'arrivée dans une classe `dD` est de
l'ordre de :

```text
λ(D)dD = A v(D) N(D)dD
```

Dans la canopée, ce flux doit être pondéré par la fraction de trouées, la probabilité d'interception
et l'état de saturation.

## Transformation par la canopée

Les études hydrologiques distinguent trois grandes composantes :

- **free throughfall** : gouttes n'ayant touché aucune surface végétale ;
- **splash throughfall** : fragments, souvent classés sous 1 à 1,5 mm ;
- **canopy drip** : eau coalescée et détachée de la végétation, généralement au-dessus de 1,5 mm.

La canopée réduit généralement le nombre total de gouttes, mais crée une population de gouttes plus
grosses et plus lentes :

- une étude classique décrit les gouttes interceptées par une distribution normale de moyenne
  4,52 à 4,95 mm et d'écart-type 0,79 à 1,30 mm ;
- des mesures sous canopée trouvent une population préférentielle de 3,25 à 5,75 mm, se déplaçant à
  1,4–5 m/s et détachée à seulement 0,1–1,05 m de hauteur ;
- une étude sous pin mesure un diamètre médian moyen de 4,28 mm pour l'égouttement ;
- au cours d'un événement, la part de splash tend à diminuer tandis que l'égouttement augmente à
  mesure que la canopée se charge en eau ;
- les chemins d'écoulement le long des branches produisent des points d'égouttement persistants.

Sources :

- [Brandt, *The Size Distribution of Throughfall Drops Under Vegetation Canopies*, 1989](https://www.sciencedirect.com/science/article/pii/0341816289900325) ;
- [Frasson et Krajewski, caractérisation diamètre–vitesse sous canopée, 2011](https://www.sciencedirect.com/science/article/pii/S0168192311001456) ;
- [Levia et al., revue des distributions de throughfall, 2017](https://wires.onlinelibrary.wiley.com/doi/10.1002/wat2.1225) ;
- [Magliano et al., évolution intra-événement sous pin, 2020](https://hess.copernicus.org/articles/24/4675/2020/index.html) ;
- [Nanko et al., épaisseur et saturation de canopée, 2008](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2007GL033010).

### État hydrique minimal

Le moteur doit maintenir une variable lente de stockage d'eau `S(t)` :

```text
dS/dt = interception(R, canopée) - égouttement(S) - évaporation(S)
```

Elle pilote la transition perceptive suivante :

```text
canopée sèche
  → impacts secs et espacés, stockage dominant
canopée humide
  → davantage de splash, résonances plus amorties
canopée saturée
  → grosses gouttes d'égouttement et chemins de branche actifs
fin de pluie
  → disparition progressive du lit distant, égouttement persistant
```

Ce stockage doit posséder plusieurs sous-réservoirs associés à des feuilles ou branches. Un unique
accumulateur global produirait des gouttes trop régulières et spatialement incohérentes.

## Interaction goutte–feuille

Le mouvement dominant d'une feuille frappée peut être approximé par un système du second ordre :

```text
I θ'' + c θ' + k θ = J δ(t)
```

où `I` représente l'inertie feuille–pétiole, `c` l'amortissement, `k` la rigidité et `J` l'impulsion
transmise par la goutte. Les mesures sur érable, chêne et orme valident une réponse impulsionnelle du
second ordre et montrent que les paramètres sont corrélés à la masse de la feuille et spécifiques à
l'espèce.

Source : [Lauderbaugh et al., *A Biomechanical Model of Leaf Inclination Angle Oscillations After Raindrop Impact*, 2021](https://www.sciencedirect.com/science/article/abs/pii/S0098847221002161).

Le mode mécanique principal des feuilles se situe typiquement autour de 4–10 Hz. Il est sous ou à la
limite de l'audition et ne doit pas devenir une tonalité. Il doit moduler :

- la position apparente de la feuille ;
- l'amplitude des impacts suivants ;
- la probabilité de libération d'une goutte stockée ;
- de faibles variations de filtrage ou de panoramique.

Le son audible vient de l'attaque, des modes structuraux plus élevés et des phénomènes liquides. Pour
un impact sur un solide, le spectre de force est approximativement plat jusqu'à une fréquence de
l'ordre de `v/D`. L'impulsion initiale doit donc être courte et large bande, puis exciter une banque
de modes amortis propre à la feuille.

Sources :

- [Petersson, *The Liquid Drop Impact as a Source of Sound and Vibration*, 1995](https://journals.sagepub.com/doi/10.1177/1351010X9500200403) ;
- [Beacham et al., *Sound Generation by Water Drop Impact on Surfaces*, 2020](https://www.sciencedirect.com/science/article/pii/S0894177719313937).

Les signatures mesurées sur différentes surfaces occupent environ 1–20 kHz. Sur de larges feuilles
de *Musa basjoo*, le caractère reconnaissable de la pluie est principalement observé autour de
2–3 kHz. Cela ne constitue pas une fréquence universelle : l'espèce, la géométrie et le montage
modifient les modes.

Source : [analyse acoustique de pluie sur *Musa basjoo*, 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9176409/).

La mouillabilité change également la réponse. Des mesures sur feuilles de pommier indiquent que
l'humidité affecte fortement les fréquences induites, tandis que la taille et la vitesse des gouttes
se traduisent surtout par des variations d'amplitude.

Source : [Aylor, *Hydrodynamics of Raindrop Impact Stimulate Ascospore Discharge*, 2010](https://www.sciencedirect.com/science/article/abs/pii/S1878614610000115).

## Organisation temporelle

Une pluie stationnaire peut localement être approchée par un processus de Poisson. Les observations
montrent toutefois que :

- les petites gouttes peuvent être sur-dispersées et groupées ;
- les gouttes qui contribuent le plus au volume suivent mieux les statistiques de Poisson pour une
  pluie modérée ;
- le taux instantané varie fortement, parfois d'un ordre de grandeur entre intervalles voisins ;
- des épisodes réellement stationnaires et non corrélés existent, mais ne représentent pas tous
  les événements.

Le modèle recommandé est donc un **processus de Cox marqué** :

```text
λglobal(t) : intensité lente et aléatoire de la pluie
événement  : temps, diamètre, vitesse, surface, distance, azimut, élévation
```

Chaque famille d'impact reçoit son propre taux conditionnel. Les points d'égouttement possèdent en
plus une mémoire de stockage et une position stable.

Sources :

- [Jameson et Kostinski, observations de pluie non corrélée, 2005](https://journals.ametsoc.org/abstract/journals/atsc/62/11/jas3583.1.xml) ;
- [Uijlenhoet et al., test de l'hypothèse de Poisson, 1999](https://www.sciencedirect.com/science/article/pii/S1464190999000763) ;
- [Lavergnat et Golé, modèle temporel stochastique, 1998](https://journals.ametsoc.org/view/journals/apme/37/8/1520-0450_1998_037_0805_asrtdm_2.0.co_2.xml) ;
- [Larsen et O'Dell, variabilité des observations de gouttes, 2016](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1002/2016JD025491).

## Propagation et espace forestier

Le champ sonore doit séparer :

- des impacts proches, individualisés et localisables ;
- des groupes d'impacts de moyenne distance ;
- un lit lointain diffus où les événements ne sont plus séparables.

Les points de branche et d'égouttement doivent conserver une position pendant plusieurs dizaines de
secondes. Un panoramique indépendant et entièrement aléatoire pour chaque goutte détruirait la
cohérence spatiale d'un arbre.

L'atténuation inclut la divergence géométrique, l'absorption atmosphérique, le sol et le feuillage.
Pour 20–200 m de feuillage dense, la méthode simplifiée de l'ISO 9613-2 donne une atténuation
croissante avec la fréquence :

| Bande d'octave | 63 Hz | 125 Hz | 250 Hz | 500 Hz | 1 kHz | 2 kHz | 4 kHz | 8 kHz |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Atténuation | 0,02 | 0,03 | 0,04 | 0,05 | 0,06 | 0,08 | 0,09 | 0,12 dB/m |

La méthode détaillée utilise également le diamètre et la densité des troncs, la surface basale, le
volume sur pied, la structuration horizontale et le sous-bois.

Source : [ISO 9613-2:2024, annexe A](https://gat04-live-1517c8a4486c41609369c68f30c8-aa81074.divio-media.org/filer_public/99/e7/99e73316-d797-4ed4-bc7f-60d0114e8c9f/cd843_british_standard_iso_9613-2_2024_acoustics__attenuation_of_sound_during_propagation_outdoors_part_2_engineering_method_for_the_prediction_of_sound_pressure_levels_outdoors_bsi.pdf).

## Références audio scientifiques

Le jeu de données *Measuring Amazon Rainfall Intensity With Sound Recorders* fournit :

- un enregistrement sans pluie ;
- un enregistrement de pluie légère ;
- un enregistrement de pluie forte ;
- les densités spectrales de puissance utilisées pour l'apprentissage ;
- le notebook d'analyse associé.

Les enregistrements font 60 secondes, en PCM 16 bits mono à 48 kHz. Le jeu est publié sous CC BY
4.0. Les chercheurs ont trouvé que la plage 1 641–2 719 Hz était la plus utile pour détecter la pluie
et estimer son intensité à travers plusieurs environnements forestiers amazoniens.

Sources :

- [jeu de données, WAV et code](https://dataverse.ird.fr/dataset.xhtml?persistentId=doi%3A10.23708%2FI0QYNM&version=2.1) ;
- [Xavier et al., publication GRL, 2024](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2024GL108210).

Ces enregistrements ont été réalisés avec des microphones omnidirectionnels sur ou près d'arbres.
Leur forte énergie grave peut inclure un couplage mécanique au tronc et ne doit pas être copiée comme
une propriété universelle de la pluie.

## Analyse comparative locale

Le 22 août 2026, les deux WAV scientifiques ont été comparés à 60 secondes de la couche `rain` du
DSP, avec la graine `0x524F4249`.

Méthode :

- PSD de Welch, fenêtre Hann de 8 192 échantillons avec recouvrement de 50 % ;
- centre spectral et fréquence contenant 95 % de l'énergie ;
- coefficient de variation du RMS par fenêtres de 100 ms ;
- détection indicative des maxima après passe-haut à 500 Hz, seuil médiane + 8 MAD et période
  réfractaire de 12 ms.

| Mesure | Pluie légère | Pluie forte | DSP `rain` actuel |
| --- | ---: | ---: | ---: |
| Fréquence d'échantillonnage | 48 kHz | 48 kHz | 22,05 kHz |
| RMS | -27,08 dBFS | -12,31 dBFS | -24,50 dBFS |
| Facteur de crête | 27,08 dB | 12,31 dB | 12,45 dB |
| Centre spectral | 531 Hz | 356 Hz | 5 475 Hz |
| Rolloff 95 % | 2 221 Hz | 2 121 Hz | 10 471 Hz |
| Variation RMS à 100 ms | 0,489 | 0,248 | 0,072 |
| Transitoires détectés par seconde | 12,45 | 5,93 | 0,08 |

Les valeurs absolues ne sont pas directement comparables à cause du microphone, du gain et du
couplage au tronc. Les différences robustes pour notre travail sont néanmoins :

- le DSP est beaucoup trop stationnaire ;
- sa pluie isolée est dominée par l'aigu ;
- elle contient presque aucun impact individualisable ;
- elle ne représente pas la plage médium 1,6–2,7 kHz identifiée dans les données de terrain ;
- 22,05 kHz limite la reproduction des attaques observées jusqu'à 20 kHz.

## Architecture DSP proposée

### 1. Contrôleur macroscopique

Maintenir :

- intensité cible `R(t)` en mm/h ;
- intensité stochastique instantanée `λ(t)` ;
- saturation globale et sous-réservoirs de canopée ;
- vent et angle d'incidence ;
- état sec, humide, saturé ou post-pluie.

### 2. Ordonnanceur d'événements

Échantillonner pour chaque événement :

```text
type         = direct | leaf | splash | drip | branch | ground
diameter     = distribution conditionnée par le type
velocity     = terminale ou chute courte depuis la canopée
energy       = fonction de D³v²
source       = feuille ou point d'égouttement persistant
position     = azimut, élévation et distance
wetness      = état local de la surface
```

Le processus de Cox contrôle la densité globale. Les réservoirs locaux déclenchent l'égouttement.

### 3. Modèle d'un impact foliaire

Chaque impact doit combiner :

1. une impulsion très courte et large bande ;
2. une banque de modes amortis propre à la feuille ;
3. un éventuel paquet de splash ;
4. une modulation mécanique lente de la feuille ;
5. une mise à jour de l'eau stockée.

Prévoir 12 à 24 profils de feuilles ou groupes modaux afin d'éviter une hauteur reconnaissable et
répétitive. Les fréquences, amortissements et gains devront être ajustés contre des enregistrements,
car la littérature ne fournit pas de fonction universelle diamètre → forme d'onde aérienne.

### 4. Égouttement

Les gouttes de 3–6 mm doivent être :

- moins fréquentes ;
- nettement plus dynamiques ;
- issues de positions stables ;
- retardées par rapport au début de pluie ;
- encore présentes après la baisse de la pluie incidente.

### 5. Lit distant

Lorsque la densité devient trop élevée pour synthétiser chaque goutte, regrouper les événements
lointains dans un lit statistique. Celui-ci doit être produit à partir des mêmes populations et
filtré selon la distance ; il ne doit pas devenir un bruit blanc autonome sans rapport avec les
événements proches.

### 6. Spatialisation

- conserver les sources proches pendant une durée longue ;
- appliquer différences interaurales et atténuation selon la distance ;
- diffuser progressivement les sources éloignées ;
- filtrer davantage l'aigu à travers une grande profondeur de feuillage ;
- ajouter des réflexions forestières faibles et irrégulières, sans réverbération de pièce.

### 7. Fréquence d'échantillonnage

Une synthèse de référence devrait fonctionner à 44,1 ou 48 kHz pour conserver les attaques jusqu'à
20 kHz. Une version 22,05 kHz peut être dérivée après validation perceptive si les contraintes CPU du
Raspberry Pi l'imposent.

## Validation recommandée

Ne pas valider uniquement à l'écoute. Pour chaque graine et intensité, mesurer :

- PSD moyenne par bandes et plage 1 641–2 719 Hz ;
- centre spectral et rolloff 95 % ;
- RMS, facteur de crête et loudness ;
- coefficient de variation sur 50, 100, 500 ms et 1 s ;
- densité et distribution d'amplitude des transitoires ;
- intervalles inter-événements et sur-dispersion ;
- autocorrélation pour détecter les périodicités artificielles ;
- corrélation gauche/droite et stabilité des positions ;
- évolution sèche → saturée → post-pluie ;
- charge CPU et absence de sous-alimentation du flux audio sur le Raspberry Pi.

Les comparaisons doivent être faites par catégorie d'intensité et environnement. Un unique WAV de
référence ne suffit pas.

## Décisions pour la prochaine itération

1. Remplacer le bruit aigu continu de la couche `rain` par un moteur d'événements.
2. Implémenter d'abord `leaf`, `splash`, `drip` et `distant_bed`.
3. Introduire un état de saturation et plusieurs points d'égouttement persistants.
4. Conserver `make dsp DSP_LAYER=rain` comme boucle d'écoute locale.
5. Ajouter des modes d'inspection séparés pour chaque sous-couche de pluie.
6. Générer des métriques automatiques à côté de chaque aperçu WAV.
7. Calibrer d'abord la pluie légère/modérée sous feuillus humides avant d'ajouter vent, sol et pluie
   forte.

## Implémentation Robine Wake

La première itération événementielle a été intégrée le 22 août 2026 dans
`RobineWake.Audio.RainDSP` et raccordée à `RobineWake.Audio.MeditationDSP`.

Elle comprend :

- un moteur de référence stéréo à 48 kHz ;
- un lit distant filtré dont l'énergie est principalement concentrée dans le médium ;
- des populations distinctes `leaf`, `splash`, `direct`, `drip` et `wood` ;
- une intensité macroscopique lentement variable ;
- un état hydrique à attaque lente et décroissance plus lente encore ;
- des diamètres conditionnés par famille et une amplitude non linéaire dérivée de leur taille ;
- deux modes amortis très discrets et une attaque bruitée filtrée pour chaque impact ;
- six points persistants pour l'égouttement et cinq positions bois/sol ;
- une graine déterministe pour comparer les réglages ;
- la génération automatique de métriques avec les aperçus conservés.

Boucle d'écoute :

```sh
make dsp
make dsp DSP_LAYER=leaf
make dsp DSP_LAYER=drip
make dsp DSP_LAYER=bed
make dsp DSP_DURATION=30 DSP_OUTPUT=artifacts/rain.wav
```

Les sous-couches disponibles sont `bed`, `leaf`, `splash`, `direct`, `drip` et `wood`. Lorsqu'un
`DSP_OUTPUT` est fourni, les métriques sont écrites dans `<sortie>.metrics.json`. Leur destination
peut être remplacée avec `DSP_METRICS=chemin.json`.

Mesure de contrôle sur 30 secondes, graine `0x524F4249`, intensité par défaut :

| Mesure | Première implémentation événementielle |
| --- | ---: |
| Fréquence d'échantillonnage | 48 kHz |
| RMS | -38,72 dBFS |
| Pic | -18,38 dBFS |
| Facteur de crête | 20,35 dB |
| Centre spectral | 1 411 Hz |
| Rolloff 95 % | 6 416 Hz |
| Variation RMS à 100 ms | 0,173 |
| Transitoires détectés par seconde | 0,00 au seuil conservateur de l'outil local |
| Corrélation stéréo | 0,935 |

Après un premier essai perceptif, les attaques sinusoïdales ont été remplacées par des bouffées de
bruit filtré et la contribution bois/sol a été abaissée d'environ 34 dB sous le lit de pluie. Cette
correction retire le caractère de brindilles frappées. Après un second essai perceptif, le lit
stéréo a été rendu majoritairement corrélé et renforcé entre 200 et 1 200 Hz : 71 % de son énergie
est désormais sous 1 kHz. Le rolloff reste supérieur aux enregistrements amazoniens couplés aux
arbres afin de conserver une faible définition aérienne. La variation à 100 ms et la détection des
transitoires sont désormais trop faibles par rapport à la référence légère : elles restent des axes
explicites de la prochaine calibration.

## Lacunes connues

La littérature disponible décrit bien la microphysique, l'hydrologie de canopée et la dynamique des
feuilles, mais beaucoup moins la fonction de transfert complète entre une goutte, une feuille
naturelle et la pression acoustique aérienne reçue à une position donnée. Une fidélité supérieure
nécessitera donc :

- des enregistrements contrôlés goutte par goutte sur plusieurs espèces ;
- une mesure simultanée du diamètre, de la vitesse et du point d'impact ;
- des microphones calibrés en champ proche et à distance ;
- une mesure sur feuilles sèches, humides et saturées ;
- l'identification des modes par déconvolution ou ajustement modal ;
- une validation perceptive en aveugle face à des enregistrements naturels.

Ces lacunes doivent être traitées comme des paramètres à calibrer, et non remplacées par des valeurs
présentées comme universelles.
