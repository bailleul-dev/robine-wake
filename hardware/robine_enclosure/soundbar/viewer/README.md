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

Views: `room`, `pillow` (looking up from the pillow), `bar` (close-up),
`decor` (dresser and reading corner). The demo controls are hidden by
default: press **H** to show or hide them.

## Bedside remote

The card at the bottom right emulates the bedside remote (Heltec WiFi Kit 32
V1: ESP32 and 128×64 OLED). It is drawn as a device on a separate card, not
in the 3D room: in real life it sits in the hand or on the nightstand.

`remote.js` reproduces `hardware/remote_button/src/main.cpp`:

- idle screen: "ROBINe WAKE", Wi-Fi bars, the time, "PRET REVEIL", the
  "PRG ARRETER" banner, dim (SSD1306 low contrast);
- alarm screen, at full contrast: Robine running with hearts, "JE T'AIME,
  TU ME PROMÈNES", an arrow pointing at the button;
- a short PRG press stops the alarm ("Reveil arrete") or reports that there
  is nothing to stop ("Aucun reveil"); feedback for 3 s, screen bright 5 s;
- holding PRG for 3 s previews the alarm screen for 15 s.

The alarm rings when the dawn reaches the wake time (30 minutes); during
the dawn the remote's clock runs from 06:30 to 07:00. The Robine frames in
`remote_sprites.js` are generated from
`hardware/remote_button/include/robine_sprites.h`; regenerate them if the
firmware sprites change.

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

- **Room**: generated in `room.js` (walls, window, curtains, bed and bedding,
  nightstands), with procedural canvas textures (plaster, oak, linen weave,
  Tolex levant grain). No image files.
- **Decor** (`decor.js`): a warm Japandi room echoing the bar's navy and the
  terracotta throw. Olive tree in a terracotta pot, Berber rug, cushions laid
  flat (they never hide the lamps' light on the pillows), walnut dresser with
  stoneware, pampas and an abstract arch print, bouclé reading chair with a
  side table, floating oak shelf with books, a small crescent-moon frame, and
  a carafe and bud vase on the nightstands.
- **Light**: physical units. Spot lights in candela computed from the lamp
  flux and beam (same model as `../lighting.py`), soft shadows. Outdoor light
  only enters through the window: the moon or sun is a directional light
  whose shadows cover the whole room (walls and ceiling block it), and the
  sky is an area light filling the window opening, so daylight comes from
  the window and fades with distance. A faint image-based environment gives
  reflections, a bounce light stands in for global illumination, ambient occlusion (GTAO), bloom on the emitters, AgX
  tone mapping. Exposure follows the reference illuminance of each scene,
  like the eye adapting, so a 1-lux halo and a 900-lux reading lamp both
  read correctly.
- **Materials**: navy blue Tolex for the casing, satin black drivers, plaster
  walls, varnished oak floor, linen bedding with sheen, walnut furniture.

## Performance

The image at rest is unchanged by these; they remove work, not quality:

- **Render on demand**: static scenes (night, reading, day) draw a frame
  only when the camera, the scene or the window changes; breathing and a
  playing dawn animate continuously.
- **Shadows computed once**: nothing in the room moves, so the shadow maps
  are rendered a single time.
- **Static batching**: meshes sharing a material are merged into one draw
  call (141 meshes → 61); the olive leaves are one instanced mesh.
- **No transmission**: curtains and glassware use plain transparency, which
  avoids a full extra render of the room each frame.
- **MSAA on the post-processing target**, not on the canvas, where it was
  paid for without effect.
- **Ambient occlusion at half resolution**, upsampled when blended (it is
  soft and low-frequency).
- **Lower resolution while the camera moves**, back to full as soon as it
  stops.
- **Procedural textures written directly into pixel buffers**: loading went
  from ~8 s to ~0.5 s.

To measure in the console (the tab must be visible):

```js
const f0 = robineRoom.frames; await new Promise(r => setTimeout(r, 4000));
(robineRoom.frames - f0) / 4 // frames per second
```

## Next steps

- Drive the scenes from the emulator state (breathing session, wake session)
  through the Hardware Lab, instead of the demo buttons.
- Play the breathing soundscape and the alarm in the page.
