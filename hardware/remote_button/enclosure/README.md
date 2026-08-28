# Boîtier Heltec WiFi Kit 32 V1

Ce dossier contient un boîtier paramétrique en deux parties pour la commande de
chevet Robine Wake : coque arrière, façade et poussoir `PRG` captif.

Deux profondeurs sont générées :

- `slim` pour une carte sans barrettes de broches soudées ;
- `headers` pour la géométrie complète de 27 mm fournie par Heltec.

Les deux variantes mesurent 60 × 33 mm de face. Leur profondeur totale est de
16,8 mm (`slim`) ou 32,8 mm (`headers`). La façade laisse accessibles l'OLED et
le bouton `PRG`; le côté gauche reçoit le connecteur micro-USB. Le bouton `RST`
reste volontairement protégé.

## Génération

Blender 5.2 LTS est installé sur la machine et son module BlenderMCP est présent.
Le script fonctionne aussi directement en ligne de commande, ce qui permet de
reproduire les exports sans interaction dans l'interface :

```sh
cd hardware/remote_button/enclosure
blender --background --python design_enclosure.py -- --variant all --render
```

Les STL, aperçus PNG et scènes Blender de contrôle sont écrits dans `generated/`.
Les dimensions ajustables sont regroupées dans `EnclosureParameters` au début
du script.

## Impression conseillée

- PLA ou PETG, buse 0,4 mm, couches de 0,20 mm ;
- 3 périmètres, 15 à 25 % de remplissage ;
- coque imprimée dos contre le plateau, ouverture vers le haut ;
- façade imprimée face visible contre le plateau ;
- poussoir imprimé avec son axe vertical si le slicer l'autorise, ou couché avec
  une petite bordure.

### Ultimaker 2 Go

Dans Cura, sélectionner le profil intégré `Ultimaker 2 Go`, puis utiliser ces
réglages de départ pour du PLA 2,85 mm et la buse d'origine de 0,4 mm :

- hauteur de couche : 0,20 mm ;
- largeur de ligne : 0,40 mm ;
- parois : 1,20 mm, soit 3 lignes ;
- dessus/dessous : 0,80 mm ;
- remplissage : 20 % ;
- vitesse : 40 mm/s ;
- température de buse : 205 à 210 °C selon le filament ;
- plateau : non chauffé, avec ruban bleu propre et correctement nivelé ;
- ventilation : 100 % à partir de la deuxième couche ;
- supports : désactivés ;
- adhérence : jupe pour la coque et la façade, bordure de 5 mm pour le poussoir.

Le volume utile de 120 × 120 × 115 mm accepte largement les pièces de 60 ×
33 mm. Imprimer d'abord uniquement la façade `slim` permet de contrôler les
ouvertures en consommant peu de matière. Le G-code doit être généré dans Cura
avec le profil de la machine, puis transféré par carte SD.

Insérer le poussoir depuis l'intérieur de la façade, placer la carte derrière la
façade, puis emboîter l'ensemble dans la coque. Pour le premier prototype, ne pas
coller : vérifier l'alignement de l'OLED, du bouton et du micro-USB.

## Validation physique encore nécessaire

Le contour 52 × 25 mm vient du modèle de référence officiel Heltec. La position
de l'écran et du bouton a été estimée à partir de la photographie de la révision
V1, car le fichier constructeur ne modélise pas ces composants. Avant une
impression finale, faire un test de façade peu coûteux ou relever au pied à
coulisse :

1. centre et dimensions visibles de l'OLED ;
2. centre du bouton `PRG` ;
3. épaisseur totale réelle de la carte, avec ou sans barrettes ;
4. position verticale et encombrement du connecteur micro-USB.

Ces quatre mesures suffisent pour corriger automatiquement le modèle et régénérer
les STL.
