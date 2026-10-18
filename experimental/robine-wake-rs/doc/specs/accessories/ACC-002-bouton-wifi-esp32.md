# ACC-002 — Bouton d'arrêt Wi-Fi ESP32

## Statut

Implémenté et validé — Phase 2 (2026-10-17). Vérification HMAC-SHA256 validée sur
le vecteur de compatibilité officiel, persistance atomique du compteur avant arrêt
de la session (ACC-002.3), rejet des rejeux anciens, appairage et persistance
dans le magasin JSON.

## Héritage v1

`hardware/remote_button/` (firmware Heltec WiFi Kit 32 V1), `lib/robine_wake/remote_button.ex`,
`knowledges/remote-alarm-button.md` (protocole d'association et HMAC).

## Objectif

Accepter l'arrêt du réveil depuis le bouton physique ESP32, placé loin du lit,
via le réseau local. C'est le garde-fou principal du produit : l'arrêt depuis
le téléphone est désactivé par défaut.

## Contrat repris de la v1 (inchangé)

- Le bouton joint `robine-wake.local` et envoie la commande versionnée
  `remote_button.dismiss` sur l'API locale (`/api/v1/command`, API-002).
- Association : fenêtre de 30 à 300 s (120 s par défaut) ouverte depuis l'app ou
  le web ; le réveil génère un secret de 256 bits, le renvoie une seule fois, et
  met la réponse en cache 5 min pour qu'une réémission reçoive le même secret.
- Arrêt signé HMAC-SHA256 sur :
  `rw-remote-v1 NUL identifiant NUL compteur-décimal NUL dismiss`.
- Le réveil vérifie le HMAC, **persiste le compteur avant** d'arrêter la session ;
  le dernier compteur réémis est acquitté sans rejouer, un compteur plus ancien
  est rejeté. Compteur maximal : 2^53 − 1.
- Pendant une alarme active, l'appui est traité immédiatement.
- Les réponses distinguent : réveil arrêté, aucune session active, erreur.
- Vecteur de compatibilité : secret = 32 octets `0x42`, identifiant
  `button-001122334455`, compteur `7` →
  `5afbdaf88cbe8167dd711c4492008bb956932b7351f26b60db69237639d9f995`.

## Exigences

- `ACC-002.1` — Le firmware ESP32 v1 fonctionne sans modification avec la v2.
- `ACC-002.2` — Le vecteur de compatibilité HMAC est vérifié dans les tests.
- `ACC-002.3` — Le compteur est persisté atomiquement avant l'arrêt de la session.
- `ACC-002.4` — Un rejeu d'un compteur ancien est rejeté, sans effet.
- `ACC-002.5` — L'arrêt par le bouton fonctionne même quand l'arrêt à distance
  par téléphone est désactivé.
- `ACC-002.6` — Les secrets d'association sont migrés depuis les données v1.

## Critères d'acceptation

- Bouton v1 appairé sur la v1, puis réveil migré en v2 : l'arrêt fonctionne
  sans nouvel appairage.
- Double appui : un seul arrêt, deuxième réponse « déjà silencieux ».
- Rejeu d'un paquet capturé : rejeté.
