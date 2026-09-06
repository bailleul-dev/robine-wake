# Vibration DIY du lit — note de conception

Date : 6 septembre 2026. La [spécification 30-004](../specs/30/004-bed-vibration/spec.md)
prévaut. Fonction retenue, matériel et implémentation à valider. Caméra et
présence sont retirées du produit.

## Besoin clarifié

L'utilisateur recherche surtout une vibration ressentie, à intensité progressive.
Une fréquence grossière convient ; produire un son ou reproduire fidèlement les
basses n'est pas une exigence. Le montage est DIY à partir de composants adaptés.
Le lit a un sommier à lattes ; exciter son cadre rigide ou le coffrage seulement
s'il est solidaire du cadre porteur.

## Choix à essayer

- Moteur vibrant DC à masse excentrée carénée, alimenté par un driver dédié :
  première piste pour une vibration simple. Valider la force sur le lit chargé,
  le démarrage à faible consigne, la progressivité, le bruit et l'inertie.
- Transducteur tactile électrodynamique : alternative si le moteur manque de
  douceur. Un oscillateur mono simple et un ampli peuvent produire la vibration ;
  aucune piste audio ni carte son haute fidélité n'est nécessaire.

Sur un moteur à masse excentrée, force et fréquence varient avec la vitesse.
La fréquence PWM électrique ne donne pas directement la fréquence mécanique.
La [note constructeur ERM](https://www.precisionmicrodrives.com/ab-029) explique
ces limites. Aucun petit moteur n'est présumé capable d'exciter un lit entier.
Choisir une masse captive et un moteur dimensionné pour ses charges, sans masse
improvisée exposée. La puissance nominale seule ne valide pas le montage.

Pour un shaker, le [BST-1](https://www.daytonaudio.com/product/1245/bst-1-high-power-pro-tactile-bass-shaker-50-watts)
reste un candidat. Son [manuel de montage](https://www.daytonaudio.com/images/resources/295-244--dayton-audio-bst-1-user-manual.pdf)
préconise un contact rigide avec la structure. Le bruit du cadre doit être évalué
pour les deux technologies ; aucune n'est supposée silencieuse.

## Commande et alimentation

```text
Pi → consigne d'intensité → driver/générateur et étage de puissance → vibreur du cadre
                                    ↑
                         alimentation basse tension dédiée
```

Le GPIO est une commande logique, pas une alimentation moteur. Prévoir protection
inductive pour le driver moteur, surintensité, limitation, coupure accessible et
alimentation externe fermée et certifiée. L'Amp2 reste sur ses enceintes. Un DAC
USB est une variante possible pour un shaker, pas une contrainte de conception.

## Trois usages

| Usage | Commande nécessaire |
| --- | --- |
| Respiration | sensation croissante sur 4 s, décroissante sur 6 s, même horloge que la séance |
| Musique | intensité suivant grossièrement l'énergie des graves ou les accents, avec lissage |
| Réveil | vagues d'intensité croissante indépendantes du morceau, plafond personnel |

Le contrôle musical doit encore accéder au signal pour extraire une enveloppe,
même si l'actionneur ne reçoit pas de flux audio. L'inertie d'un moteur limite sa
réponse aux attaques rapides. Pause, sourdine et arrêt de la musique arrêtent
également la commande tactile. Un morceau sans graves ne supprime pas le motif
synthétique du réveil.

## Essai décisif

Commencer avec un actionneur fixé de façon démontable sur une traverse rigide.
Tester en position allongée avant de sélectionner puissance et quantité. Mesurer
répartition, bruit, démarrage, montée/descente, température, coupure électrique et
arrêt mécanique résiduel. Un deuxième actionneur dépend des résultats.
La calibration doit rendre lisible le cycle respiratoire et permettre une montée
confortable ; fréquence exacte et synchronisation musicale de studio ne sont pas
des critères. Voir la spécification pour arbitrage, limites et essais de panne.
