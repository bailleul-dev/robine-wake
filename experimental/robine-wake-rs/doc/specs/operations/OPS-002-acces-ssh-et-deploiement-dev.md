# OPS-002 — Accès SSH et déploiement de dev

## Statut

Brouillon — 2026-10-17. Phase 1.

## Héritage v1

`config/target.exs` : `nerves_ssh` (serveur SSH Erlang) avec sous-système
`fwup`, clés autorisées prises dans `~/.ssh/id_*.pub` au build, IEx à distance.

## Objectif

Donner un accès de maintenance authentifié, un canal de mise à jour, et une
boucle de développement rapide qui ne demande pas de reconstruire l'image.

## Serveur SSH

- **dropbear**, authentification par clé uniquement, mot de passe désactivé.
- Les clés autorisées sont ajoutées au build depuis `~/.ssh/id_*.pub` (comme en
  v1) ou depuis une variable `.env`, puis stockées dans
  `/data/ssh/authorized_keys` pour pouvoir être modifiées sans reflasher.
- Les clés d'hôte sont générées au premier démarrage dans `/data/ssh/` et
  survivent aux mises à jour.

## Commandes de maintenance

Le shell BusyBox remplace la console IEx. Le démon fournit une CLI locale :

```sh
robine-wake status          # santé, heure, prochaine alarme, session
robine-wake logs [-f]       # journal en RAM
robine-wake can-update      # règle de mise à jour (OPS-001)
robine-update < fichier.fw  # vérifie la règle puis lance fwup
```

Mise à jour depuis le poste :

```sh
ssh root@robine-wake.local robine-update < robine-wake.fw
```

## Déploiement rapide de dev

Pendant le développement, remplacer seulement le binaire, sans image :

```sh
make deploy HOST=robine-wake.local
# = cargo build --release --target <cible>
#   scp target/.../robine-wake root@HOST:/data/dev/robine-wake
#   ssh root@HOST 'robine-wake-dev on && sv restart robine-wake'
```

- Le binaire de dev vit dans `/data/dev/` (le rootfs est en lecture seule).
- Le script `run` du service préfère `/data/dev/robine-wake` s'il existe et si
  le mode dev est activé ; `robine-wake-dev off` revient au binaire de l'image.
- Le mode dev est **désactivé dans les images de production** : le fichier
  `/data/dev/robine-wake` est alors ignoré.

## Exigences

- `OPS-002.1` — SSH n'accepte que l'authentification par clé.
- `OPS-002.2` — Les clés d'hôte et les clés autorisées survivent aux mises à jour.
- `OPS-002.3` — `make deploy` remplace et relance le démon en moins de 30 s sur
  le réseau local.
- `OPS-002.4` — Une image de production n'exécute jamais un binaire de `/data/dev/`.
- `OPS-002.5` — Une clé SSH peut être restreinte à la seule commande
  `robine-update` (`command=` dans `authorized_keys`).

## Critères d'acceptation

- Connexion par mot de passe refusée.
- `make deploy` puis `robine-wake status` montre la nouvelle version.
- Sur une image de production, un binaire placé dans `/data/dev/` n'est pas lancé.
