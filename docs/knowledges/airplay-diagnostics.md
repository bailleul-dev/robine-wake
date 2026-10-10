# Diagnostic du récepteur AirPlay

Procédure pour comprendre un AirPlay qui « joue » sans son, sans reflasher ni
brancher quoi que ce soit. Tout est embarqué dans le firmware et se pilote
depuis le shell IEx du Pi (`ssh robine-wake.local`).

## Ce qui est embarqué

- `/usr/bin/shairport-sync-diag` : lanceur qui exécute le même Shairport Sync
  avec une configuration de diagnostic et sa sortie d'erreur (seule sortie de
  journal de Shairport 5) ajoutée à un fichier de `/tmp`.
- Dans le binaire Shairport (patch `0002` du paquet `shairport-sync5`), une
  instrumentation par bloc audio activée uniquement par l'environnement :
  `SPS_BLOCK_DIAG=1` journalise un bloc sur cinquante (taille reçue, crête
  décodée), `SPS_BLOCK_DUMP=<fichier>` conserve les 3000 premiers blocs bruts.
- `RobineWake.AirPlay.Diagnostics` : active et désactive le tout, lit les
  résultats.

Rien de cela ne tourne en fonctionnement normal : le récepteur de production
est lancé sans ces variables et sans la configuration de diagnostic.

## Session type

```elixir
alias RobineWake.AirPlay.Diagnostics
Diagnostics.enable()            # relance le récepteur en mode diagnostic (coupe la session en cours)
# lancer la lecture depuis le téléphone, attendre 20 s
Diagnostics.summary()           # verdict sur les blocs reçus
Diagnostics.log(40)             # dernières lignes du journal Shairport
Diagnostics.disable()           # retour au récepteur normal
```

Verdicts de `summary/0` :

| Verdict | Signification |
| --- | --- |
| `:source_sends_silence` | blocs minuscules et constants, crête nulle : la source envoie du silence encodé |
| `:decoded_silence` | blocs normaux mais crête nulle : chercher côté décodage |
| `:decoding_fails` | le décodeur refuse chaque bloc : mauvais codec négocié ou flux inexploitable |
| `:audio_present` | de l'audio arrive et se décode ; chercher côté ALSA ou ampli |

Options utiles :

- `Diagnostics.enable(verbosity: 3)` : journal complet des échanges RTSP (très
  verbeux, quelques Mo par quart d'heure).
- `Diagnostics.enable(dump: true)` : garde les blocs bruts dans
  `/tmp/shairport-blocks.bin` ; pour un flux AAC ils portent leur en-tête ADTS
  et se décodent tels quels (`ffmpeg -f aac -i …` sur le Pi, `afconvert` sur
  Mac).
- `Diagnostics.capture_pcm(60)` : pendant 60 s, le PCM décodé va dans
  `/tmp/shairport-pcm.raw` au lieu de l'ampli (rien n'est audible), puis le
  récepteur revient seul en mode normal. `Diagnostics.pcm_peak_dbfs()` mesure
  le résultat.

Les fichiers restent dans `/tmp` jusqu'à `Diagnostics.clear_captures()` ou au
prochain `enable/1`. Pour les rapatrier : `sftp robine-wake.local` (pas de
`scp` sur la cible).

## Garde-fous

`/tmp` est un tmpfs de 81 Mo partagé avec les fichiers d'exécution du réseau
et de D-Bus. Quand il est plein, tout ce qui y écrit échoue en silence, y
compris le journal de diagnostic. `enable/1` refuse de démarrer sous 20 Mo
libres, le dump brut est plafonné par le binaire, et la capture PCM (384 Ko/s)
doit rester courte : `capture_pcm/1` s'arrête seule.

Activer ou désactiver le mode relance Shairport : la session AirPlay en cours
est coupée et le téléphone doit re-sélectionner le récepteur.

## Cas de référence : iPhone qui « joue » sans son (octobre 2026)

Symptôme : l'iPhone (iOS 27 bêta) affiche la lecture vers le Pi, le Mac
fonctionne, aucune erreur dans les journaux, horloge PTP acquise, ALSA en
lecture, mixeur à 0 dB. Verdict `:source_sends_silence` : chaque bloc reçu
faisait 13 octets, toujours la trame AAC-LC de silence numérique
(`21 00 03 40 68 1c` après l'en-tête ADTS), décodée en zéros exacts par FFmpeg
comme par le décodeur d'Apple.

Cause : une session AirPlay figée côté iOS, dont le mixeur audio n'alimentait
plus le flux « bufferisé ». Signes dans le journal : le téléphone n'envoie pas
son volume avant de démarrer (Shairport applique son `-7.5 dB` par défaut) et
recrée son flux en boucle. Redémarrer le Pi ne change rien ; retirer la
capacité « audio bufferisé » annoncée ne mène qu'à un repli en AirPlay
classique inexploitable.

Remède : faire tomber la session côté téléphone, par exemple basculer la
sortie sur le haut-parleur de l'iPhone puis re-sélectionner le Pi, ou lancer
une lecture depuis un autre appareil puis revenir à l'iPhone. La session
reconstruite envoie des blocs de 600 octets avec de l'audio et le volume du
téléphone.
