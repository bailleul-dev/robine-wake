# Experimental

> **Rien dans ce dossier ne fait partie du produit.**
>
> Ce sont des prototypes jetables. Ils ne sont pas compilés par `mix verify`,
> pas inclus dans le firmware Nerves, pas déployés dans la démo, pas couverts
> par la traçabilité des exigences. Ils peuvent être supprimés sans préavis.

| Dossier | Objet | Statut |
|---|---|---|
| [`robine-wake-rs/`](robine-wake-rs/README.md) | Implémentation complète Rust + Buildroot (`robine-core`, `robine-ports`, `robine-daemon`, `br-external`, specs v2) | expérimental — l'app Elixir reste la référence de prod |
| [`esp8266-hello/`](esp8266-hello/README.md) | Premier firmware Rust sans OS sur NodeMCU ESP8266 (LED + série) | essai de chaîne d'outils avant l'ESP32-S3 |

La référence de production reste l'application Elixir dans `lib/` et le système
Nerves dans `nerves_system_rpi3/`.
