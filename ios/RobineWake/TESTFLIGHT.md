# Déployer Robine Wake sur TestFlight

Les commandes Fastlane manuelles se lancent depuis `ios/RobineWake`. La cible
`make testflight` se lance depuis la racine du dépôt.

## Première installation

```sh
cp ../../.env.dist ../../.env
# Renseigner FASTLANE_USER et APPLE_TEAM_ID dans ../../.env.
bundle config set --local path vendor/bundle
bundle install
../../scripts/with-env bundle exec fastlane ios bootstrap
```

Fastlane réutilise les identifiants et certificats présents dans le trousseau
macOS. Le compte et l’équipe Apple viennent du `.env` local ; aucune valeur
personnelle n’est versionnée.

## Vérifier le build

```sh
../../scripts/with-env bundle exec fastlane ios verify
```

## Envoyer une bêta

```sh
make testflight CHANGELOG="Description des changements"
```

Cette commande se lance depuis la racine du dépôt. Elle installe les dépendances
Ruby manquantes puis exécute la lane Fastlane.

La lane crée la fiche App Store Connect si elle n'existe pas, récupère le profil
App Store, choisit le numéro suivant sur TestFlight, archive l'application puis
l'envoie. L'IPA est également conservée dans `build/ios`.

Pour imposer un numéro de build :

```sh
make testflight BUILD_NUMBER=21
```

## Authentification par clé API (optionnelle)

Pour une CI sans session interactive, définir `ASC_KEY_ID`, `ASC_ISSUER_ID` et
`ASC_KEY_FILEPATH` dans le gestionnaire de secrets de la CI. En local, ces
champs sont disponibles dans le `.env` racine. La clé `.p8` doit rester hors
Git.
