# AUD-004 — Respiration guidée et ambiance DSP

## Statut

Retiré du périmètre v2 — Décision d'arbitrage du 2026-10-17. La fonction de respiration
guidée et d'ambiance DSP n'est pas implémentée dans Robine Wake 2 afin de concentrer
les ressources sur la mission critique d'alarme et de réveil autonome. Les appels API
et commandes associés renvoient l'erreur `capability_unavailable`.

## Héritage v1

`30/003-guided-breathing` (fait foi), `lib/robine_wake/hue.ex` (partie
respiration), `audio/meditation_dsp.ex`, `audio/rain_dsp.ex`,
`knowledges/audio-breathing-guide.md`, `knowledges/rain-on-trees-dsp.md`.

## Objectif

Séance volontaire de respiration 4 s / 6 s, dont l'horloge appartient au réveil :
lumière Hue, ambiance sonore générée et, plus tard, vibration du lit.

## Règles reprises de la v1

- Cadence exacte 4 s inspiration / 6 s expiration, échéances monotones absolues,
  sans dérive cumulée.
- Durées : 3, 5, 10, 15, 20 ou 30 min, arrêt automatique par le réveil.
- Lumière : transitions natives Hue (`dynamics.duration`), 2 % rose crépusculaire
  ↔ 30 % ambre ; compensation de la latence Hue mesurée.
- Son : paysage stéréo généré en temps réel (souffle rose, pluie fine, bourdon
  Ré/La, halo), 16 bits, 22,05 kHz ; gain en `smoothstep` recalculé toutes les
  250 ms, de 18 à 36 au volume par défaut de 60 %, pic plafonné à 60.
- Arrêt idempotent, restauration de l'état lumineux d'avant.
- Une alarme préempte la séance (lumière, son et vibration).
- La panne d'un média n'arrête pas les autres.

## Ce qui change

- Les DSP Elixir (`meditation_dsp.ex`, `rain_dsp.ex`) sont portés en Rust et
  produisent le PCM directement dans le moteur audio (AUD-001), au lieu d'un
  flux envoyé à `aplay`.
- La génération tourne dans le thread audio temps réel ; aucune allocation dans
  la boucle de génération.

## Exigences

- `AUD-004.1` — Le rythme nominal est exactement 4 s / 6 s et appartient au réveil.
- `AUD-004.2` — Aucune dérive cumulée sur 30 min (mesurée).
- `AUD-004.3` — L'audio reste continu, sans clic ni redémarrage aux changements de phase.
- `AUD-004.4` — Une alarme et une respiration ne pilotent jamais Hue ni l'audio
  en même temps.
- `AUD-004.5` — Le DSP Rust produit un signal perceptuellement équivalent à la v1
  (écoute comparée et spectre).
- `AUD-004.6` — La génération ne dépasse pas 15 % d'un cœur du Pi 3.

## Critères d'acceptation

- Tests hôte des commandes 4 000 / 6 000 ms, de l'exclusion mutuelle et de la restauration.
- Test de 30 min de dérive des échéances.
- Enregistrement simultané lumière / son pour mesurer le décalage de phase.
- Mesure CPU du DSP sur cible.
