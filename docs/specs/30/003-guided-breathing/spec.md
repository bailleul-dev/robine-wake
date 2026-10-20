# 30-003 — Respiration guidée : ruban, son et vibration

## Objectif

Proposer une session volontaire de respiration à cadence fixe : inspiration de
4 secondes, expiration de 6 secondes. L’iPhone démarre ou arrête la session,
mais le Raspberry Pi en possède l’horloge afin que le rythme continue lorsque
l’app est verrouillée ou déconnectée.

Cette fonction est un guide de détente et ne formule aucune allégation médicale.

## Ruban lumineux de l’ESP32

Le ruban WS2812B de 60 LED, relié à l’ESP32, porte la lumière de la séance
(Philips Hue a été retiré le 2026-10-20). Au démarrage, le Raspberry Pi envoie
une seule commande `light.program` :

```json
{"program":"breathing","cadence":"0-4-0-6","duration_ms":600000}
```

La cadence donne, en secondes, la pause poumons vides, l’inspiration, la pause
poumons pleins et l’expiration (0 à 60 s chacune, inspiration et expiration
non nulles). L’ESP32 calcule chaque image à partir de son horloge locale : la
séance dure un nombre entier de respirations, `ceil(durée / respiration)`, et
le ruban s’éteint seul après la dernière.

Le transport est un driver : UART sur les GPIO 14/15 du Pi (lignes JSON,
enveloppe API-002) par défaut, HTTP possible. Une panne du ruban est
journalisée une fois (`guide_light_failed`) et la séance continue avec le son
(BRTH-007).

L’arrêt est idempotent et éteint le ruban. Le lancement d’une alarme arrête
d’abord la respiration et laisse le ruban à l’aube du réveil. Une respiration
est refusée tant qu’une session de réveil sonne.

La durée va de 1 à 60 minutes. Un minuteur détenu par le Raspberry Pi arrête
l’ambiance à la fin de la dernière respiration, même lorsque l’app n’est plus
connectée.

## Contrôle iOS

L’écran `Soir` permet de choisir la cadence, la durée et le volume, de démarrer
la session et de l’arrêter. L’animation affichée est une aide visuelle seulement : l’autorité
temporelle reste le réveil. L’état exposé contient la phase, son heure de début,
l’heure de fin, le temps restant et les durées des quatre phases. Les commandes v1 sont :

- `breathing.start` avec `{"cadence":"0-4-0-6","duration_minutes":10,"volume_percent":60}` ;
- `breathing.volume` avec `{"volume_percent":60}` pendant une séance ;
- `breathing.stop` avec un corps vide.

## Ambiance sonore — jardin nocturne

Le Raspberry Pi synthétise en temps réel un paysage stéréo sans fichier ni
raccord de boucle. Deux générateurs roses indépendants sont filtrés et modulés
très lentement pour former un souffle naturel non stationnaire. Son amplitude
propre suit une enveloppe `smoothstep` 4/6 profonde, tandis que le bourdon reste
plus stable pour rendre la consigne respiratoire nettement audible. Une pluie
fine combine une nappe large bande décorrélée et de rares gouttes résonantes.
Un bourdon consonant Ré/La, sans tierce majeure ou mineure, ajoute un ancrage
harmonique sans imposer de mélodie. Un halo très discret évolue sur près d’une
minute.

Le DSP produit du PCM stéréo signé 16 bits à 22,05 kHz, envoyé directement à
`aplay`. Le gain matériel utilise la horloge monotone du réveil. À la valeur
par défaut de 60 %, il monte de 18 à 36 pendant l’inspiration et redescend de 36
à 18 pendant l'expiration. Le curseur iOS règle l’échelle globale de 0 à 100 %
sans supprimer ce contraste et le firmware plafonne le pic à 60, sous le plafond
audio général de 80. L’interpolation
`smoothstep` est recalculée toutes les 250 ms.

Le moteur ne modifie pas la cadence et ne relance aucun lecteur aux frontières
de phase :

- source : souffle rose stéréo, pluie fine, bourdon Ré/La et halo procédural continus ;
- inspiration (4 s) : montée du tiers au maximum choisi ;
- expiration (6 s) : retour du maximum choisi à son tiers ;
- courbe : `smoothstep`, sans rupture de gain ;
- arrêt : fondu jusqu’au silence avant de libérer HiFiBerry ;
- plafond indépendant du volume d’alarme et valeur sûre par défaut ;
- synchronisation : cadence transmise au ruban ;
- défaillance audio : la lumière continue et l’erreur est journalisée ;
- défaillance du ruban : le son continue et l’app signale l’état dégradé.

Le design évite volontairement les paroles, les percussions, les événements
sonores soudains et toute revendication liée à une « fréquence thérapeutique ».
Il constitue une ambiance de relaxation personnalisable, pas un traitement de
santé ni une séance de musicothérapie conduite par un professionnel.

Une alarme arrête d’abord l’ambiance respiratoire et récupère ensuite la sortie
HiFiBerry, même si son profil lumineux est désactivé.

## Vibration du lit — extension spécifiée

La séance peut activer le canal tactile décrit dans
[la spécification du lit](../004-bed-vibration/spec.md). Son intensité est réglée
séparément du son. Il reprend exactement les phases et échéances monotones 4/6
existantes : montée douce à l'inspiration, descente à l'expiration et arrêt
automatique à la fin de la durée choisie. Une fréquence approximative convient ;
la commande compense autant que nécessaire le seuil et l'inertie de l'actionneur.

La vibration n'impose aucun suivi de présence ni capteur respiratoire. Une panne
de l'un des médias laisse continuer les autres médias disponibles. Une alarme
préempte aussi la vibration respiratoire ; l'arrêt de séance libère toutes les
sorties. La configuration tactile est désactivée par défaut tant que le lit n'a
pas été calibré. Les commandes devront transporter cette option et son intensité
sans modifier la cadence ni casser les clients existants qui omettent ces champs.

## Exigences

- `BRTH-001` — Le rythme nominal est exactement 4 s / 6 s et appartient au
  réveil, pas à l’app iOS.
- `BRTH-002` — Le ruban calcule ses fondus lui-même à partir d’une seule
  commande par séance.
- `BRTH-003` — Les échéances monotones ne doivent pas accumuler de dérive
  logicielle d’un cycle au suivant.
- `BRTH-004` — L’arrêt éteint le ruban et reste idempotent.
- `BRTH-005` — Une alarme et une respiration ne doivent jamais piloter le
  ruban en concurrence.
- `BRTH-006` — L’audio reste continu, sans clic ni redémarrage aux
  frontières de phase.
- `BRTH-007` — La panne d’un média ne doit pas arrêter l’autre.
- `BRTH-008` — Une durée de 1 à 60 minutes doit être imposée par le Raspberry
  Pi, avec arrêt automatique après la dernière respiration complète.

- `BRTH-009` — La vibration optionnelle doit partager la phase 4/6 et la durée
  de séance, avec intensité indépendante et absence de dérive cumulée.
- `BRTH-010` — Arrêt, fin de durée et préemption par une alarme doivent libérer
  aussi la sortie tactile ; sa panne ne doit pas interrompre lumière et son.

## Validation

- Tests hôte des commandes 4 000/6 000 ms, de l’exclusion mutuelle et de la
  restauration.
- Test de 30 minutes mesurant la dérive des deadlines monotones.
- Sur le ruban réel : capture vidéo à haute fréquence ou capteur de
  lumière pendant au moins 20 cycles.
- Avec l’audio : enregistrement simultané lumière/audio pour mesurer le
  décalage de phase et vérifier l’absence de clic.
