# robine-wake-rs — prototype EXPÉRIMENTAL

> ⚠️ **Ceci n'est pas le produit.** Robine Wake est l'application Elixir/Nerves
> à la racine du dépôt. Ce crate est un prototype d'évaluation, hors de tout
> pipeline, sans engagement de maintenance. Il peut être supprimé à tout moment.

## Pourquoi

Évaluer concrètement ce que coûterait un port de l'API locale en Rust, dans
l'optique d'un futur système Buildroot sur une carte Linux exotique ou un
design custom que Nerves ne couvre pas, et à terme un seul langage du réveil
jusqu'aux MCU (télécommande ESP32, driver de vibration).

Conclusion de l'évaluation (octobre 2026) : la BEAM n'est pas ce qui impose un
Raspberry Pi. AirPlay 2 (shairport-sync, nqptp), BlueZ et ffmpeg imposent un
Linux avec Wi-Fi/BT et ~128 Mo de RAM quel que soit le langage. Le port Rust
se justifie par la liberté de design hardware, pas par le prix du compute.

## Périmètre du prototype

Porté fidèlement depuis Elixir, avec le même contrat JSON :

- `RobineWake.Alarm` → `alarm.rs` : validation permissive, bornes de sécurité,
  profils volume/lumière/snooze, occurrences avec fuseaux IANA et gestion DST
  (heure inexistante → premier instant valide, heure ambiguë → première).
- `RobineWake.Settings` (partie alarmes) + `Persistence` → `store.rs` :
  fichier JSON `schema_version: 1`, écriture atomique (tmp + fsync + rename,
  mode 0600), révisions optimistes, clés inconnues du fichier préservées.
- `RobineWake.EventStream` → `events.rs` : flux rejouable de 64 événements,
  `Last-Event-ID`.
- Routeur → `http.rs` (axum) : `/health`, `/api/state`, `/api/alarms` CRUD,
  `/api/alarms/preview`, `/api/sounds`, `/api/v1/events` (SSE) et le bundle
  web Expo de `priv/web` servi en statique.

Volontairement absent : sessions de réveil, scheduler, audio, Hue, AirPlay,
Bluetooth, LoRa, MCP, auth, télécommande, firmware. `/health` le dit
explicitement dans son JSON.

## Lancer

```sh
cd experimental/robine-wake-rs
cargo test
cargo run
open http://localhost:4120
```

Variables : `ROBINE_RS_PORT` (4120), `ROBINE_RS_DATA` (`./data/robine_wake_rs.json`,
jamais le fichier de l'app Elixir par défaut), `ROBINE_RS_WEB` (`../../priv/web`,
lancer `make expo-web` à la racine si absent), `ROBINE_RS_SOUNDS` (`../../priv/sounds`).

Le fichier de données est au même format que celui de l'app Elixir : on peut
pointer `ROBINE_RS_DATA` sur une copie de `data/robine_wake_dev.json` pour
vérifier l'interopérabilité.

## Ce que le proto mesure

| Question | Réponse donnée par ce crate |
|---|---|
| Coût de port d'un agrégat Elixir validé | `alarm.rs` ≈ 1,2× les lignes Elixir, tests inclus |
| Perte d'OTP | un `Mutex` + `broadcast` suffisent ici ; la supervision des processus externes (aplay, shairport) n'est pas couverte |
| Empreinte | binaire release statique, RSS à mesurer sur cible avec `ROBINE_RS_WEB` |
| Compat API | le front Expo existant doit fonctionner sans modification sur les écrans alarmes |
