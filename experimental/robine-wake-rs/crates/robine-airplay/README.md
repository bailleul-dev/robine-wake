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
- décodeur ALAC, identique au bit près à ffmpeg sur un flux réel.

À faire : décodeur AAC-LC (flux mis en tampon, ex. YouTube), tampon de
réordonnancement et synchro PTP, portage ESP32-S3.

## Banc d'essai sur PC

```sh
cargo run -p robine-airplay-bench -- "Robine Wake (PC)"
```

Annonce l'enceinte sur le réseau local, journalise chaque échange et joue le
flux temps réel sur la sortie PipeWire par défaut. Identité et captures dans
`~/.local/share/robine-airplay-bench/` (hors dépôt).
