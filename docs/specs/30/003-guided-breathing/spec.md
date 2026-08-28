# 30-003 — Respiration guidée Hue et ambiance sonore

## Objectif

Proposer une session volontaire de respiration à cadence fixe : inspiration de
4 secondes, expiration de 6 secondes. L’iPhone démarre ou arrête la session,
mais le Raspberry Pi en possède l’horloge afin que le rythme continue lorsque
l’app est verrouillée ou déconnectée.

Cette fonction est un guide de détente et ne formule aucune allégation médicale.

## Lumière Philips Hue

La pièce ou zone Hue est choisie dans l’app iOS. Au démarrage, Robine Wake lit
et mémorise son état, applique immédiatement une luminosité basse de 2 % en
rose crépusculaire, puis
alterne les commandes Hue v2 suivantes :

| Phase | Durée native Hue | Destination |
|---|---:|---:|
| inspiration | 4 000 ms | 30 %, ambre doré (`xy 0,56 / 0,42`) |
| expiration | 6 000 ms | 2 %, rose crépusculaire (`xy 0,50 / 0,30`) |

Chaque destination utilise `dynamics.duration`; aucun fondu image par image
n’est envoyé par l’iPhone. Les échéances reposent sur l’horloge monotone du
réveil et sur des deadlines absolues pour empêcher l’accumulation de dérive
logicielle. La latence du réseau local à la réception d’une commande reste à
mesurer sur le matériel réel.

L’arrêt est idempotent, annule la prochaine échéance et restaure l’état `on`, la
luminosité et la température de couleur observés avant la session. Le lancement
d’une alarme lumineuse arrête d’abord la respiration et restaure la lampe. Une
respiration est refusée si une session de réveil possède déjà Hue.

La durée est choisie parmi 3, 5, 10, 15, 20 ou 30 minutes. Un minuteur monotone détenu
par le Raspberry Pi arrête automatiquement la session, effectue le fondu audio
et restaure la lumière, même lorsque l’app iOS n’est plus connectée.

## Contrôle iOS

L’écran `Soir` permet de choisir une pièce ou zone, la durée, de démarrer la session et
de l’arrêter. L’animation affichée est une aide visuelle seulement : l’autorité
temporelle reste le réveil. L’état exposé contient la phase, son heure de début,
le nombre de cycles, l’heure de fin, le temps restant et les paramètres 4/6. Les commandes v1 sont :

- `breathing.start` avec `{"target_id":"<grouped-light-id>","duration_minutes":10,"volume_percent":60}` ;
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
`aplay`. Le gain matériel utilise la même horloge monotone que Hue. À la valeur
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
- synchronisation : même deadline monotone de phase que la transition Hue ;
- défaillance audio : la lumière continue et l’erreur est journalisée ;
- défaillance Hue : le son continue et l’app signale l’état dégradé.

Le design évite volontairement les paroles, les percussions, les événements
sonores soudains et toute revendication liée à une « fréquence thérapeutique ».
Il constitue une ambiance de relaxation personnalisable, pas un traitement de
santé ni une séance de musicothérapie conduite par un professionnel.

Une alarme arrête d’abord l’ambiance respiratoire et récupère ensuite la sortie
HiFiBerry, même si son profil lumineux est désactivé.

## Exigences

- `BRTH-001` — Le rythme nominal est exactement 4 s / 6 s et appartient au
  réveil, pas à l’app iOS.
- `BRTH-002` — Chaque fondu lumineux utilise une transition native Hue.
- `BRTH-003` — Les échéances monotones ne doivent pas accumuler de dérive
  logicielle d’un cycle au suivant.
- `BRTH-004` — L’arrêt restaure l’état lumineux antérieur et reste idempotent.
- `BRTH-005` — Une alarme et une respiration ne doivent jamais piloter Hue en
  concurrence.
- `BRTH-006` — L’audio reste continu, sans clic ni redémarrage aux
  frontières de phase.
- `BRTH-007` — La panne d’un média ne doit pas arrêter l’autre.
- `BRTH-008` — Une durée parmi 3, 5, 10, 15, 20 ou 30 minutes doit être imposée par le
  Raspberry Pi, avec arrêt automatique et restauration complète.

## Validation

- Tests hôte des commandes 4 000/6 000 ms, de l’exclusion mutuelle et de la
  restauration.
- Test de 30 minutes mesurant la dérive des deadlines monotones.
- Sur pont et ampoule réels : capture vidéo à haute fréquence ou capteur de
  lumière pendant au moins 20 cycles.
- Avec l’audio : enregistrement simultané lumière/audio pour mesurer le
  décalage de phase et vérifier l’absence de clic.
