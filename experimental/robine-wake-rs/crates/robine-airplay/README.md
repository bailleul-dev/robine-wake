# robine-airplay

Récepteur AirPlay 2 audio, implémentation propre au projet : `no_std + alloc`,
sans aucune entrée-sortie. La plateforme (ESP32, ou Linux plus tard) lit les
sockets et donne les octets à `Connection::feed`, qui rend les octets à
renvoyer et des événements.

Implémenté et vérifié avec un iPhone (iOS 27) :

- annonce `_airplay._tcp` (enregistrements TXT) et `GET /info` ;
- appairage temporaire (SRP-6a 3072 bits HomeKit, code `3939`), canal de
  contrôle chiffré ChaCha20-Poly1305 ;
- `fp-setup` par tables FairPlay figées (option `fairplay`, voir
  [NOTICE.md](NOTICE.md) : prototype uniquement) ;
- `SETUP` (timing puis flux), volume, `RECORD`, `SETRATEANCHORTIME`, `FLUSH`,
  `TEARDOWN` ;
- paquets audio temps réel (UDP) et mis en tampon (TCP) déchiffrés ;
- décodeur ALAC, identique au bit près à ffmpeg sur un flux réel ;
- décodeur AAC-LC (flux mis en tampon, ex. YouTube) : 100 dB de SNR face à
  ffmpeg sur un flux réel, au plus 1 LSB d'écart ;
- suivi de l'horloge PTP de l'émetteur et ancrage `SETRATEANCHORTIME` :
  lecture à l'heure, pause, saut (`FLUSHBUFFERED`).

À faire : synchro du flux temps réel, retransmissions, lissage de la sortie
du banc (petites saccades), portage ESP32-S3.

## Banc d'essai sur PC

```sh
cargo run -p robine-airplay-bench -- "Robine Wake (PC)"
```

Annonce l'enceinte sur le réseau local, journalise chaque échange et joue les
deux flux sur la sortie PipeWire par défaut. Le suivi PTP écoute les ports
319 et 320 :

```sh
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=319   # jusqu'au redémarrage
```
 Identité et captures dans
`~/.local/share/robine-airplay-bench/` (hors dépôt).
