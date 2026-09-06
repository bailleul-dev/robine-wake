# 30-004 — Vibration DIY du lit

## Statut et objectif

Fonction P1 retenue le 2026-09-06 ; conception matérielle et implémentation à faire.
Ajouter un canal tactile aux séances de respiration, à la musique et au réveil
progressif. Chaque usage est activable et réglable séparément. La caméra et toute
détection de présence sont retirées du produit ; les vibrations ne sont pas un
capteur et ne confirment ni réveil effectif ni sortie du lit.

Le DIY couvre fixation, câblage basse tension, boîtier et logiciel, à partir de
transducteurs et modules du commerce. Le matériel précis reste à choisir après
essai du lit. Aucun bénéfice thérapeutique ni diminution de l'inertie du sommeil
n'est revendiqué.

Précision utilisateur : la priorité est une vibration corporelle progressive ;
aucune restitution sonore, note juste ou fidélité aux fréquences musicales n'est
requise. Une fréquence mécanique approximative convient. Le bruit du montage
est un effet secondaire à minimiser, pas un objectif.

## Montage mécanique

Le lit possède un sommier à lattes. La fixation préférée est le coffrage lorsqu'il
est solidaire du cadre porteur, ou une traverse rigide de ce cadre. Une paroi
décorative désolidarisée ne constitue pas une fixation validée. Ne pas fixer le
transducteur sur une latte souple isolée.

Commencer par un seul actionneur vibratoire sur une platine rigide
démontable, en contact complet. Tester la transmission jusqu'au corps avec le
matelas et le lit occupé. Ajouter un second transducteur uniquement si les essais
de répartition le justifient, avec une commande de puissance par actionneur.
La vibration du lit entier est un objectif à vérifier, sans garantie d'uniformité
ni d'isolation d'une place. Dimensions, assemblage du cadre et places visées
restent à relever.

Les fixations doivent résister aux vibrations sans fragiliser le sommier. Écarter
tissu et rembourrage des éléments chauds, protéger et retenir les câbles. Des
patins sous les pieds peuvent limiter la transmission au sol, sous réserve de
stabilité et de capacité de charge adaptées.

## Architecture matérielle simplifiée

```text
Raspberry Pi : horloge des sessions et consigne d'intensité
  ├── HiFiBerry Amp2 ── enceintes existantes
  └── commande dédiée ── étage de puissance ── vibreur fixé au cadre
                              └── alimentation basse tension dédiée
```

Deux options restent ouvertes avant essai sur le lit :

| Option | Commande | Limite à vérifier |
| --- | --- | --- |
| moteur vibrant DC à masse excentrée, caréné | commande de vitesse via un driver moteur adapté | fréquence et force varient ensemble ; démarrage, inertie et bruit mécanique |
| transducteur tactile électrodynamique (« bass shaker ») | oscillateur mono simple et ampli dédié, amplitude variable | couplage au lit, puissance et bruit de structure |

Évaluer d'abord un moteur vibrant caréné si une vibration grossière suffit. Ne
pas valider un modèle sur sa seule tension : vérifier force sous charge, courant
de démarrage/blocage, service prolongé et réponse aux variations lentes. Les petits
vibreurs de téléphone ne constituent pas une sélection pour un lit entier.
La masse tournante doit être captive et inaccessible ; ne pas ajouter une masse
improvisée sur un moteur non dimensionné pour cet effort.

Pour un moteur à masse excentrée, vitesse, fréquence et force sont liées : une
faible consigne peut ne pas démarrer le moteur et la réponse doit être calibrée.
La fréquence PWM de sa commande électrique n'est pas la fréquence mécanique du
lit. Ces propriétés sont décrites dans la
[note constructeur ERM](https://www.precisionmicrodrives.com/ab-029).

Le bass shaker reste une alternative si le moteur est trop bruyant ou manque de
progressivité. C'est un actionneur mécanique ; il peut recevoir un simple signal
périodique sans jouer un morceau ni reproduire précisément ses basses. Une source
mono approximative convient si son signal est adapté à l'ampli et sans composante
continue dommageable. Le BST-1 est un candidat d'essai, pas un achat figé.

Aucun DAC USB, flux PCM tactile, stéréo ou seconde horloge audio n'est imposé au
prototype. Un petit contrôleur ou générateur matériel peut produire la commande
locale ; sélectionner son interface après vérification des broches déjà utilisées.
Si une sortie audio USB est finalement choisie pour le shaker, elle reste une
variante et doit être adressée de façon stable.

L'étage de puissance reçoit une alimentation externe fermée et certifiée, adaptée
à l'actionneur, avec protection basse tension, plafond matériel et coupure
accessible. Le GPIO transporte uniquement une commande logique vers un driver
compatible, jamais le courant du vibreur. Le driver moteur doit gérer la charge
inductive, la surintensité et les surtensions de commutation. L'Amp2 garde ses
enceintes : aucune connexion du vibreur en parallèle ni pontage de ses sorties.

## Profils d'usage

### Respiration

Reprendre l'horloge monotone et les échéances absolues 4 s / 6 s du service de
respiration. Faire monter la sensation à l'inspiration et la diminuer à
l'expiration, avec transitions douces. La consigne peut faire varier la vitesse
d'un moteur ou l'amplitude d'un signal périodique ; aucune porteuse exacte n'est
imposée. Mesurer seuil de démarrage, retard et inertie de l'actionneur pour que la
sensation reste lisible sur le cycle 4/6, sans grands déplacements du sommier.

La durée est celle de la séance (3, 5, 10, 15, 20 ou 30 minutes). La déconnexion de
l'iPhone ne change ni rythme ni arrêt automatique. Le niveau est indépendant du
volume sonore. Une panne tactile laisse continuer les autres médias disponibles.

### Musique

Le minimum attendu est une vibration qui suit grossièrement l'énergie des graves
ou les accents de la musique, avec une enveloppe lissée et bornée. Extraire une
consigne d'intensité depuis le signal musical décodé ou une détection d'enveloppe
adaptée ; l'accès à ce signal reste à implémenter dans le chemin AirPlay actuel.
Il n'est pas nécessaire de transmettre le son complet au vibreur ni de reproduire
ses fréquences. Un moteur lent ne reproduit pas chaque attaque de basse ; cette
limite est acceptable si la sensation accompagne le morceau sans retard gênant.
Aucune amplification automatique illimitée ne compense un morceau pauvre en graves.
La restitution directe des basses sur shaker est une variante facultative.

Le gain tactile suit le volume de lecture et possède un réglage relatif séparé,
tous deux bornés par la calibration. Pause, volume de lecture nul, arrêt et perte
du flux mettent aussi la vibration au silence. Le prototype utilise une mise en
sourdine générale commune aux enceintes et au tactile.

### Réveil

Produire un motif synthétique indépendant du contenu musical. Au début de la
phase sonore douce, partir du seuil tactile perceptible calibré. L'amplitude des
vagues monte progressivement jusqu'au plafond personnel ; transitions et
frontières de vagues sont continues. La fréquence, le motif, la durée de montée
et la courbe définitive restent des paramètres de calibration expérimentaux.

Le profil sauvegarde activation, niveau initial, plafond et durée de montée. Les
niveaux logiques vont de 0 à 100, avec `0 ≤ initial ≤ plafond ≤ limite calibrée` ;
ils ne sont pas des unités physiques. Sans calibration valide, la vibration est
désactivée. Une fois le plafond atteint, le motif reste borné jusqu'à une commande
ou à la durée maximale. La montée tactile ne prolonge jamais une session.

Le calendrier sonore de [la session](../../20/002-wake-session/spec.md) reste
autoritaire : la vibration ne change ni l'heure cible ni le passage au son fort.
Snooze arrête la vibration ; la reprise repart du niveau initial. L'arrêt physique
et le timeout la coupent également. Aucune décision n'attend un mouvement ou une
sortie du lit.

## Service, arbitrage et arrêt

Un service `Vibration` possède la sortie, expose capacités/état et reçoit commandes
de préparation, démarrage, intensité et arrêt avec identifiant du propriétaire.
L'adaptateur hôte enregistre signaux logiques et échéances sans périphérique réel.
L'adaptateur cible possède la commande moteur ou le générateur périodique,
ainsi que la coupure de l'étage de puissance.

Priorité : réveil, puis respiration volontaire, puis musique. Un réveil arrête la
respiration et préempte AirPlay avant de prendre les sorties. Une respiration est
refusée pendant un réveil et suspend la musique. À sa fin, le récepteur musical
peut redevenir disponible, sans rejouer une ancienne commande tactile. Un seul
propriétaire peut produire un signal ; une commande périmée ne peut arrêter ou
relancer le propriétaire suivant.

Au démarrage et après panne, l'étage de puissance reste inactif jusqu'à une
commande valide. Un limiteur logiciel et un plafond matériel bornent la sortie.
Un arrêt normal fait décroître la commande en au plus 500 ms puis coupe la
puissance ; une coupure physique agit directement. La perte du générateur ou du
contrôle impose une coupure électrique sous une seconde via une surveillance à
choisir et à tester, même si le processus est bloqué. Pour un moteur, mesurer
séparément l'arrêt mécanique résiduel et prévoir un freinage si la persistance
est gênante ; une alimentation coupée ne prouve pas une vibration instantanément
nulle. Après reboot, la restauration d'un réveil repart seulement du niveau initial,
dans la fenêtre restante. Un défaut thermique ou une surintensité coupe le tactile.

La durée tactile d'une séance de respiration est bornée par son minuteur ; celle
d'un réveil par le timeout de session (30 minutes par défaut). La musique ne
dispose pas d'un minuteur de séance : son fonctionnement prolongé doit être
validé thermiquement et conserver limiteur et coupure sur perte de flux.

## Interface et état

Présenter activation/intensité par usage, test court avec arrêt accessible et
calibration du lit. Afficher `disabled`, `uncalibrated`, `ready`, `active` ou
`unavailable`, le mode, le propriétaire, le niveau et le dernier défaut. Une option
désactivée ou non configurée n'est pas une panne ; une sortie demandée mais absente
est dégradée. Ni présence, ni confiance visuelle, ni écran caméra ne sont exposés.

## Exigences

- `VIB-001` — Les trois usages doivent être activables et réglables indépendamment.
- `VIB-002` — La fixation doit exciter le cadre porteur du sommier à lattes et être
  validée avec le lit occupé ; le nombre de transducteurs suit les essais.
- `VIB-003` — La chaîne tactile doit avoir un étage de puissance et une alimentation adaptés,
  indépendants de l'Amp2 et des rails de puissance du Pi.
- `VIB-004` — La commande tactile doit utiliser une interface stable compatible avec Nerves ;
  une sortie audio ou un DAC USB ne sont pas requis.
- `VIB-005` — La respiration tactile doit suivre l'horloge 4/6 et le minuteur du Pi.
- `VIB-006` — La vibration musicale doit suivre une enveloppe d'énergie ou d'accents
  bornée, sans exigence de fidélité fréquentielle, et respecter pause, sourdine
  et perte de flux.
- `VIB-007` — Le réveil tactile doit utiliser un motif autonome à intensité
  progressive, bornée par une calibration personnelle.
- `VIB-008` — Le tactile ne doit pas retarder l'audio, son escalade ou les contrôles.
- `VIB-009` — L'arbitrage doit garantir un propriétaire unique et rejeter les
  commandes périmées, avec priorité au réveil.
- `VIB-010` — Snooze, arrêt et timeout doivent mettre le tactile au silence ; toute
  reprise doit repartir du niveau initial dans les délais restants de la session.
- `VIB-011` — Démarrage, panne et perte de contrôle doivent respecter la mise en
  sourdine, les délais de coupure et les limites logicielles/matérielles décrits ici.
- `VIB-012` — Les défauts doivent être visibles sans dégrader l'état d'une option désactivée.
- `VIB-013` — Un adaptateur hôte doit permettre tests déterministes et injection de pannes.
- `VIB-014` — La calibration doit borner les niveaux et empêcher l'activation avant validation.
- `VIB-015` — La réception du matériel doit vérifier répartition, fixation, bruit
  transmis au sol, stabilité du lit, puissance et température en usage prolongé.

## Critères d'acceptation

- Simulation : 20 cycles respiratoires sans dérive des échéances ; priorité et
  commandes périmées ; morceau sans graves avec réveil tactile maintenu ; profils
  invalides refusés ; snooze/arrêt/timeout et perte de contrôle dans les délais.
- Migration : alarmes existantes conservées avec tactile désactivé ; aucune
  observation de présence ne modifie la session.
- Cible : mesurer seuil de démarrage, montée/descente, arrêt résiduel et retard
  ressenti sur 20 cycles 4/6 puis 30 minutes de musique. Une progression confortable
  et un accompagnement lisible sont requis ; aucun seuil de synchronisation audio
  de 20 ms ni fréquence exacte n'est imposé. Tester l'adressage USB seulement si
  cette variante est choisie.
- Lit : essai à faible niveau puis calibration aux positions d'usage, contrôle
  thermique sur 30 minutes respiration/réveil et huit heures de musique, inspection
  des fixations et du bruit transmis ; pas d'acceptation sur la seule puissance nominale.
- Pannes : débrancher l'interface retenue, bloquer le générateur, couper le contrôle
  et redémarrer le Pi ; mesurer coupure électrique et décroissance mécanique,
  vérifier arrêt physique et maintien de l'alarme sonore.

## Références de conception

- [Note de conception DIY](../../../knowledges/diy-bed-vibration.md)
- [BST-1 — constructeur](https://www.daytonaudio.com/product/1245/bst-1-high-power-pro-tactile-bass-shaker-50-watts)
- [BST-1 — montage](https://www.daytonaudio.com/images/resources/295-244--dayton-audio-bst-1-user-manual.pdf)
- [Amp2 — interfaces](https://www.hifiberry.com/docs/data-sheets/datasheet-amp2/)
