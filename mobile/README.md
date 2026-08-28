# Robine Wake — Expo / ClojureScript

Réécriture de l’application iOS Robine Wake avec Expo SDK 57, React Native et
ClojureScript (`shadow-cljs`). Elle conserve les quatre espaces de l’app Swift :
Matin, Soir, Alarmes et Réveil, ainsi que les transports Wi-Fi et Bluetooth du
réveil.

Sur iOS 26, les cartes et la navigation utilisent `expo-glass-effect`, tandis
que les actions principales sont rendues par de vrais boutons SwiftUI
`expo/ui` en style Liquid Glass. Le même code conserve automatiquement les
styles opaques de repli sur Expo Web et sur les versions iOS plus anciennes.

L’identifiant iOS est `fr.robine.wake`. L’application Expo est la continuation
de l’application Swift et la remplace lors de l’installation ou d’une mise à
jour TestFlight/App Store. Le point d’accès Wi-Fi et le volume du rituel du soir
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

- `expo-test` compile les tests ClojureScript et vérifie la configuration Expo.
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

## Développement

```sh
cd mobile
npm install
npm run cljs:watch
```

Dans un second terminal :

```sh
cd mobile
npx expo start --dev-client
```

Le Bluetooth repose sur un module natif. L’app doit donc être ouverte avec le
development build généré par Expo, pas avec Expo Go.

Les sources métier et UI sont dans `src/robine_wake`. Le JavaScript généré dans
`app/`, les dossiers natifs `ios/` et `android/`, ainsi que les bundles dans
`dist/` sont reconstruits localement et ignorés par Git.
