# PRD-002 — Architecture logicielle Rust

## Statut

Brouillon — 2026-10-17.

## Héritage v1

`00/001-system-architecture` (composants, événements, dégradations), arbre de
supervision de `lib/robine_wake/application.ex`.

## Objectif

Définir le découpage du code Rust, le modèle de concurrence et ce qui remplace
la supervision OTP.

## Workspace Cargo

```text
crates/
  robine-core/      domaine pur : alarmes, occurrences, session, profils,
                    validation. Aucune E/S, aucune dépendance tokio.
                    Compatible no_std + alloc à terme (PLT-005).
  robine-ports/     traits des adaptateurs : Clock, AudioOut, Store, Hue,
                    MusicReceiver, Radio, Tactile, Network.
  robine-adapters/  implémentations cible (ALSA, fichier JSON, HTTP Hue,
                    spidev, processus externes) et hôte (simulées).
  robine-daemon/    binaire `robine-wake` : runtime tokio, câblage, HTTP,
                    SSE, MCP, CLI de contrôle local.
```

Le prototype `experimental/robine-wake-rs` de la v1 sert de point de départ :
`alarm.rs` va dans `robine-core`, `store.rs` dans les adaptateurs, `http.rs`
et `events.rs` dans le démon.

## Modèle de concurrence

- Un runtime tokio multi-thread limité à 2 workers (le Pi 3 a 4 cœurs, l'audio
  a besoin des autres).
- Chaque composant de la v1 devient un **acteur** : une tâche tokio qui possède
  son état et reçoit des messages par canal `mpsc`. Pas de `Mutex` partagé
  entre composants.
- Les événements de domaine passent par un bus `broadcast` borné ; le flux SSE
  rejouable (64 événements) s'abonne à ce bus.
- La génération et la lecture audio tournent dans un **thread système dédié**
  à priorité temps réel, hors tokio (AUD-001).

## Remplacer la supervision OTP

| Besoin v1 | Solution v2 |
|---|---|
| Un accessoire qui plante ne tue pas l'horloge | Chaque acteur tourne dans une tâche ; un `panic` est capturé (`JoinHandle`), journalisé et l'acteur est relancé avec backoff exponentiel plafonné à 60 s. |
| Processus externes (shairport, bluealsa…) supervisés | Supervisés par le système d'init (PLT-004), pilotés par le démon via `sv up/down`. |
| Le démon lui-même plante | Relancé par l'init ; l'état de session persistant permet la reprise (ALM-002). |
| Watchdog | Le démon nourrit `/dev/watchdog` seulement si le planificateur et la boucle d'événements répondent (PLT-004). |

Règle : `panic = "unwind"` dans le profil release pour que la capture de
panique par acteur fonctionne. Un panic dans `robine-core` est un bug à
corriger, pas un mode de fonctionnement.

## Dépendances

- Les traits de `robine-ports` sont la seule frontière vers le matériel
  (`ARCH-002` v1).
- `robine-core` ne lit jamais l'heure système : il reçoit des instants UTC et
  monotones (`ARCH-004`, `ARCH-005` v1).
- Bibliothèques pressenties : `tokio`, `axum`, `serde`, `chrono` + `chrono-tz`,
  `alsa`, `symphonia`, `reqwest` + `rustls`, `hmac` + `sha2`, `spidev`,
  `tracing`. Pas d'OpenSSL côté Rust.

## Compilation

- Cibles : `aarch64-unknown-linux-musl` (recommandée), `armv7-unknown-linux-musleabihf`
  (même matériel en 32 bits), `x86_64` hôte.
- Profil release : `opt-level = "s"`, `lto = "fat"`, `codegen-units = 1`,
  `strip = true`.
- Les fonctions lourdes sont des features Cargo (`airplay`, `bluetooth`,
  `lora`, `mcp`, `hue`) alignées sur les options Buildroot (PRD-001.3).

## Exigences

- `PRD-002.1` — `robine-core` ne dépend d'aucune crate d'E/S ni de runtime async.
- `PRD-002.2` — La panne ou le panic d'un acteur accessoire n'interrompt ni le
  planificateur ni une session de réveil en cours.
- `PRD-002.3` — Un acteur relancé repart avec un backoff exponentiel plafonné à
  60 s et son nombre de redémarrages est visible dans la santé (OPS-003).
- `PRD-002.4` — Chaque feature Cargo optionnelle peut être désactivée sans
  casser la compilation ni les tests du cœur.
- `PRD-002.5` — Tous les événements d'une session partagent un identifiant de
  corrélation (`ARCH-006` v1).

## Questions ouvertes

- Faut-il un seul binaire (démon + CLI) ou un binaire CLI séparé, plus petit,
  pour les scripts système ?
