# Robine Wake — Expo / TypeScript

Application universelle Robine Wake écrite en TypeScript avec Expo SDK 57 et
React Native. Elle s’organise en quatre espaces : Matin, Soir, Alarmes et
Réveil, ainsi que les transports Wi-Fi et Bluetooth du réveil.

Sur iOS 26, les cartes et la navigation utilisent `expo-glass-effect`, tandis
que les actions principales sont rendues par de vrais boutons SwiftUI
`expo/ui` en style Liquid Glass. Le même code conserve automatiquement les
styles opaques de repli sur Expo Web et sur les versions iOS plus anciennes.

L’identifiant iOS est `fr.robine.wake`. L’application Expo est la continuation
de l’ancienne application Swift, retirée du dépôt, et la remplace lors d’une
mise à jour TestFlight/App Store. Le point d’accès Wi-Fi et le volume du rituel du soir
sont migrés depuis les préférences de la version Swift au premier lancement.

## Commandes depuis la racine

Copier d’abord `.env.dist` vers `.env` à la racine du dépôt. Les identifiants
Apple et l’identifiant de l’iPhone restent ainsi locaux et non versionnés.

```sh
make expo-test
make expo-build
make expo-web
make expo-iphone
```

- `expo-test` exécute les tests TypeScript, vérifie les types et contrôle la
  configuration Expo.
- `expo-build` produit localement le bundle iOS de production dans
  `mobile/dist/ios`.
- `expo-web` produit l’application web universelle dans `priv/web`. Le
  firmware la sert comme interface par défaut sur `/` et elle utilise
  automatiquement l’API HTTP du réveil sur la même origine. L’ancienne
  interface intégrée reste accessible sur `/legacy`.
- `expo-iphone` régénère le projet natif, signe un build Release, remplace
  l’application installée sur l’iPhone défini par `IPHONE_ID`, puis la lance.

Pour viser un autre iPhone, modifier `IPHONE_ID` dans `.env` :

```sh
IPHONE_ID='00008110-XXXXXXXXXXXX'
```

## Envoyer une bêta sur TestFlight

Renseigner `FASTLANE_USER` et `APPLE_TEAM_ID` dans le `.env` racine, puis :

```sh
make ios-beta CHANGELOG="Description des changements"
```

La lane crée la fiche App Store Connect si elle n’existe pas, récupère le
certificat et le profil App Store, choisit le numéro de build suivant sur
TestFlight, régénère le projet natif avec `expo prebuild`, archive
l’application puis l’envoie. L’IPA est conservée dans `build/ios`.

Pour imposer un numéro de build :

```sh
make ios-beta BUILD_NUMBER=30
```

Pour une CI sans session interactive, définir `ASC_KEY_ID`, `ASC_ISSUER_ID` et
`ASC_KEY_FILEPATH` (ou `ASC_KEY_CONTENT`). Avec une clé API, la lane ne passe
plus par la session Apple ID et ne crée donc pas la fiche App Store Connect.

## Développement

```sh
cd mobile
npm install
npm start
```

Le Bluetooth repose sur un module natif. L’app doit donc être ouverte avec le
development build généré par Expo, pas avec Expo Go.

Les sources métier et UI sont dans `src/`. Metro compile directement le point
d’entrée `index.ts`. Les dossiers natifs `ios/` et `android/`, ainsi que les
bundles dans `dist/`, sont reconstruits localement et ignorés par Git.
