# OPS-001 — Mise à jour A/B signée

## Statut

Brouillon — 2026-10-17. Phase 1.

## Héritage v1

`70/001-operations-updates`, `nerves_system_rpi3/fwup.conf` (A/B avec
`tryboot` du firmware Pi et retour automatique), `lib/robine_wake/update_policy.ex`,
`scripts/build_signed_firmware.sh`, clé Ed25519 dans `~/.config/robine-wake/`.

## Objectif

Mettre à jour l'image complète à distance, de façon atomique et signée, avec
retour automatique à la version précédente si la nouvelle ne valide pas son
démarrage. Reprendre le mécanisme v1, qui fonctionne sans Nerves.

## Disposition de la carte SD

| Partition | Type | Contenu |
|---|---|---|
| boot A | FAT | firmware Pi, noyau, DTB, `config.txt`, `cmdline.txt` → rootfs A |
| boot B | FAT | idem → rootfs B |
| rootfs A | squashfs | système A |
| rootfs B | squashfs | système B |
| data | ext4 | `/data`, conservée entre mises à jour |
| autoboot / env | FAT + zone brute | `autoboot.txt` (`tryboot`) et environnement de version |

Tailles proposées sur une carte de 16 Go : boot 2 × 64 Mo, rootfs 2 × 256 Mo,
le reste pour `/data`.

## Format et outil

- Paquet de mise à jour `.fw` produit par **fwup** (déjà utilisé en v1), signé
  Ed25519. La clé publique est embarquée dans l'image
  (`/etc/robine-wake/fwup-key.pub`), la clé privée reste hors dépôt.
- Le `fwup.conf` v1 est repris sans les variables propres à Nerves
  (`nerves_fw_*` renommées `robine_fw_*`).
- Le même fichier `.fw` sert à flasher une carte neuve (`fwup -a -t complete`)
  et à mettre à jour (`-t upgrade`).

## Séquence de mise à jour

1. Le paquet arrive par SSH (OPS-002) ou, plus tard, par l'API HTTP.
2. `robine-update` demande au démon si la mise à jour est permise (règle v1) :
   refus pendant une session de réveil, si l'heure est `untrusted`, ou à moins
   de 15 min de la prochaine alarme. Une option `--force` explicite contourne
   la règle pour la maintenance.
3. fwup vérifie la signature et la plateforme, écrit le slot inactif et prépare
   un démarrage `tryboot` sur ce slot.
4. Redémarrage. Le firmware Pi démarre une seule fois le nouveau slot.
5. Le démon valide le nouveau firmware seulement si : la configuration est
   lisible, le planificateur tourne, l'audio est initialisé ou déclaré dégradé,
   et le serveur HTTP répond (`10-001` v1). La validation rend le slot permanent.
6. Sans validation dans les 120 s (ou après un plantage), le redémarrage suivant
   revient automatiquement au slot précédent.

## Exigences

- `OPS-001.1` — Seul un paquet signé par la clé embarquée est installable (`OPS-004` v1).
- `OPS-001.2` — Une mise à jour ne démarre ni pendant une session, ni à moins de
  15 min d'une alarme, ni avec une heure non fiable, sauf `--force` (`OPS-005` v1).
- `OPS-001.3` — Un firmware qui ne passe pas les contrôles de santé n'est pas
  validé et le slot précédent redevient actif (`OPS-006` v1, `NRV-005` v1).
- `OPS-001.4` — `/data` est conservée et migrée si besoin (DAT-001).
- `OPS-001.5` — Une coupure de courant à n'importe quelle étape laisse un
  système démarrable.
- `OPS-001.6` — Une carte v1 peut passer en v2 par une mise à jour, sans
  reflasher (question ouverte, voir ci-dessous).

## Critères d'acceptation

- Paquet non signé ou signé par une autre clé : refusé.
- Mise à jour demandée à T−10 min d'une alarme : refusée avec un code clair.
- Firmware volontairement cassé (démon qui quitte au démarrage) : retour
  automatique au slot précédent sans intervention.
- Coupure de courant pendant l'écriture : redémarrage sur l'ancien slot.

## Questions ouvertes

- Migration v1 → v2 sans reflash : il faut un paquet `.fw` compatible avec la
  disposition de partitions Nerves et qui reprend `/data` (format JSON v1). À
  évaluer ; sinon, reflash une fois avec sauvegarde de `/data`.
- Mise à jour tirée par l'appareil (URL HTTPS) en plus de la mise à jour poussée
  par SSH : utile ou non ?
