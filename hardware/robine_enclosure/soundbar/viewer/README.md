# Demo room (WebGL)

A real-time, physically based view of the sound bar above a bed, for demos:
the breathing halo on the ceiling, the dawn and the reading lamps, in a
furnished bedroom. three.js, no build step.

## Open it

From the Hardware Lab (host build):

```sh
MIX_TARGET=host mix run --no-halt
open http://127.0.0.1:4111/room
```

Or with any static server, without Elixir:

```sh
cd hardware/robine_enclosure/soundbar/viewer
python3 -m http.server 8765
open http://127.0.0.1:8765/
```

three.js is loaded from jsDelivr (pinned to 0.170.0): the page needs
internet access the first time.

The URL can pick a scene, a view and a dawn time, for scripted demos:
`?scene=breathing&view=pillow`, `?scene=dawn&minutes=20`.

| Scene | What it shows |
|---|---|
| `night` | dark room, moonlight through the window |
| `breathing` | halo on the ceiling, 4 s in / 6 s out, dusk pink to amber gold (spec 30-003) |
| `dawn` | both lamps from amber to ~4000 K, up to 300 lux at the eye; the 30 minutes play in one minute (spec 00-002) |
| `readingLeft`, `readingRight` | one lamp at full power, warm white; the other pillow stays dark |
| `day` | daylight through the window |

Views: `room`, `pillow` (looking up from the pillow), `bar` (close-up).

## How it is built

- **Bar**: `robine-soundbar.glb` is exported from the FreeCAD model by
  `../export_gltf.py` (visible parts only, metres, Y up, box-projected UVs).
  `anchors.json` gives the halo and lamp positions and beam axes, so the
  lights sit exactly where the model puts them. After changing the model:

  ```sh
  cd hardware/robine_enclosure/soundbar
  /Applications/FreeCAD.app/Contents/Resources/bin/freecadcmd design_soundbar.py
  /Applications/FreeCAD.app/Contents/Resources/bin/freecadcmd export_gltf.py
  ```

- **Room**: generated in `room.js` (bed, bedding, nightstands, rug, window,
  curtains), with procedural canvas textures (plaster, oak, linen weave,
  Tolex levant grain). No image files.
- **Light**: physical units. Spot lights in candela computed from the lamp
  flux and beam (same model as `../lighting.py`), soft shadows, an
  image-based environment for reflections, a bounce light standing in for
  global illumination, ambient occlusion (GTAO), bloom on the emitters, AgX
  tone mapping. Exposure follows the reference illuminance of each scene,
  like the eye adapting, so a 1-lux halo and a 900-lux reading lamp both
  read correctly.
- **Materials**: navy blue Tolex for the casing, satin black drivers, plaster
  walls, varnished oak floor, linen bedding with sheen, walnut furniture.

## Next steps

- Drive the scenes from the emulator state (breathing session, wake session)
  through the Hardware Lab, instead of the demo buttons.
- Play the breathing soundscape and the alarm in the page.
