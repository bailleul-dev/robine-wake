# Écran d'arrêt Wi-Fi Heltec WiFi Kit 32 V1

Le firmware transforme un Heltec WiFi Kit 32 V1 (ESP32, OLED SSD1306 128×64) en commande de
chevet pour Robine Wake.

- l'écran affiche l'heure, la qualité du Wi-Fi et la disponibilité du réveil ;
- le bouton `PRG` (`GPIO0`) appelle directement le Raspberry sur le réseau local ;
- l'action envoie la commande versionnée `session.dismiss` à
  `http://robine-wake.local:4000/api/v1/command` ;
- l'écran distingue un réveil arrêté, l'absence de session active et une panne réseau ;
- l'OLED utilise la plage de contraste étendue du SSD1306, reste au minimum au repos et passe au
  contraste maximal dès qu'un réveil devient actif, avant même l'appui ;
- pendant le réveil, Robine court avec des cœurs et affiche « Je t'aime, tu me promènes » ;
- au repos, maintenir le bouton gauche pendant 3 secondes prévisualise cet écran pendant
  15 secondes ;
- aucune connexion Internet n'est nécessaire pour arrêter le réveil.

## Compiler et flasher

Copier `.env.dist` vers `.env` à la racine du dépôt, puis renseigner
`ROBINE_WIFI_SSID`, `ROBINE_WIFI_PASSPHRASE` et éventuellement
`REMOTE_BUTTON_WAKE_HOST`. Le fichier `.env` est ignoré par Git et les valeurs
sont injectées comme macros uniquement pendant la compilation. L’ancien
`include/local_config.h` reste accepté pour compatibilité, mais n’est plus
nécessaire.

```sh
make button-build
make button-upload PORT=/dev/cu.usbserial-0001
make button-monitor PORT=/dev/cu.usbserial-0001
```

Le profil utilise les broches intégrées de la révision V1 : `SDA=4`, `SCL=15`, `OLED_RST=16`.
Le second bouton est `RESET` et ne peut pas servir de commande applicative.

## Boîtier imprimable

Le modèle paramétrique Blender, les instructions d'impression et les STL générés
se trouvent dans [`enclosure/`](enclosure/README.md).
