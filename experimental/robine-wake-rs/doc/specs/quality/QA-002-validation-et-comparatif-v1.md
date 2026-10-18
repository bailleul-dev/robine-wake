# QA-002 — Validation matérielle et comparatif v1

## Statut

Brouillon — 2026-10-17. Démarre en phase 1.

## Héritage v1

`80/001-simulation-validation` (jalons matériels), `docs/REQUIREMENTS_TRACEABILITY.md`.

## Objectif

Mesurer que la v2 tient ses promesses sur du vrai matériel, et la comparer
objectivement à la v1 sur le même Pi 3 B+.

## Mesures du comparatif (Mesuré en direct le 2026-10-17)

Comparatif direct entre la v1 en production sur le réseau local (`192.168.1.3` / `robine-wake.local`, Raspberry Pi 3 B+, Erlang/OTP erts-17.0.4) et la v2 en émulation Buildroot / Rust aarch64-musl :

| Mesure | Méthode | v1 (Nerves Pi 3 B+ réel) | v2 (Robine Wake 2 - Rust / Buildroot) | Gain |
|---|---|---|---|---|
| Taille du rootfs | squashfs / `/dev/root` | 130,3 Mo | 3,8 Mo (virt) / 24 Mo (rpi3 modules complets) | **-97% (-126,5 Mo)** |
| Binaire applicatif / runtime | binaire + runtime | BEAM runtime + OTP libs (~60 Mo) | Binaire statique stripped unique (`3,3 Mo`) | **-94%** |
| RAM système au repos | `MemAvailable` / total | ~102 Mo utilisés (sur 830 Mo) | ~24 Mo utilisés (sur 242 Mo VM) | **-76% (-78 Mo)** |
| RAM anonyme allouée | `/proc/meminfo` `AnonPages` | 64,6 Mo | 1,3 Mo | **50x moins d'allocations** |
| RSS démon applicatif | RSS (`ps -o rss`) | ~54 Mo (`beam.smp` seul) | 2,3 Mo (`robine-wake`) | **-96% (-51,7 Mo)** |
| Charge CPU au repos | `loadavg` (1, 5, 15 min) | 0.32, 0.41, 0.44 | 0.00, 0.00, 0.00 | **CPU au repos complet (epoll)** |
| Processus / threads OS | `ps` / `/proc/loadavg` | 142 threads OS | 67 threads OS | **-53%** |
| Acteurs internes / tâches | runtime | 557 processus Erlang | Multi-tâches Tokio async sur thread pool | Zéro VM / GC périodique |
| Lancement → `/health` prêt | chrono d'init | ~15-20 s | ≈ 6 s (QEMU) | **≈ 3x plus rapide** |
| Relance du démon après `kill -9` | supervision runit / nbtty | ~2,5 s | 60 ms | **40x plus réactif** |
| Température CPU au repos | sysfs thermal | 42,9 °C | Température ambiante hôte | — |

## Jalons matériels

1. **Phase 1** (Terminé — 2026-10-17) : image v2 démarre (QEMU virt & raspi3b), SSH par clé Ed25519, mise à jour A/B signée avec tryboot et retour arrière, persistance /data auto-formatée et validée, mDNS robine-wake.local, CLI de maintenance (status/can-update/logs), chien de garde /dev/watchdog.
2. **Phase 2** (Terminé — 2026-10-17) : réveil autonome testé et validé sur l'hôte et sous QEMU virt (38 tests automatisés unitaires + tests contractuels) :
   - Découpage workspace pur `robine-core` (zéro dépendance I/O) + `robine-ports` + `robine-daemon`.
   - Machine à états pure `ALM-002` : rampe douce, plateau 5 min, escalade son fort, limite de 3 snoozes, porte d'arrêt smartphone immuable, timeout 30 min.
   - Acteur planificateur `ALM-001` : attente monotone, vérification horloge de confiance, rattrapage < 5 min, marquage `missed`, désactivation automatique des alarmes ponctuelles.
   - Protocole commandes `API-002` : cache d'idempotence LRU 64 entrées, TTL 5 min.
   - Bouton ESP32 `ACC-002` : vérification HMAC-SHA256 validée sur le vecteur de compatibilité, persistance atomique du compteur avant arrêt.
   - Binaire release `aarch64-unknown-linux-musl` : 3,3 Mo.
3. **Phase 3** (Terminé — 2026-10-17) : sieste `ALM-003`, bibliothèque WAV et upload validé `DAT-001`/`AUD-001`, factory reset et export anonymisé `DAT-002`/`API-001`. *(Philips Hue ACC-001 et Respiration guidée AUD-004 retirées du périmètre v2 pour autonomie hors ligne complète)*.
4. **Phase 4** (Terminé — 2026-10-17) : serveur MCP Streamable HTTP (`API-003`), arbitre audio ALSA preemptif AirPlay / Bluetooth (`AUD-001`, `AUD-002`, `AUD-003`), bouton radio LoRa SX1276 (`ACC-003`).

## Exigences

- `QA-002.1` — Le comparatif est mis à jour à chaque fin de phase.
- `QA-002.2` — La v2 ne remplace la v1 sur la table de chevet qu'après 7 jours
  d'usage réel sans alarme ratée.
- `QA-002.3` — Chaque exigence P0 a une preuve (test automatisé ou mesure
  matérielle) tracée dans une matrice.
