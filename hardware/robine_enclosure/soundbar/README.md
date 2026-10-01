# Robine Wake wall sound bar

Robine Wake's main speaker: a bar mounted on the wall above the headboard,
wired as an ordinary stereo speaker on the HiFiBerry Amp2. Each channel is a
passive 3-way using the classic compact 3-way sizes: a 5.25" bass-reflex
woofer, a 3" midrange and a 25 mm tweeter. The drivers fire downward through a
baffle tilted 18.4° toward the ears. Spatialisation comes first: the
midrange-tweeter columns frame each sleeper (±450 mm) and are angled 20°
toward the opposite pillow.

The acoustic choices (spatialisation, bass, voice) are explained in
[ACOUSTICS.md](ACOUSTICS.md).

![View from the pillow](generated/preview-below.png)

## Layout

From the centre toward each end:

| Zone | Contents |
|---|---|
| woofer chamber | 5.25" woofer flush-mounted at ±140 mm, vent mouth, 4.61 L net |
| midrange compartment | 3" midrange and 25 mm tweeter on 20° wedges, column at ±450 mm, 1.55 L sealed |
| end compartment | 3-way crossover lying on the floor; on the left, also the Pi 3 B+ and the Amp2 |

- Overall size: 1400 × 200 × 140 mm (length × depth × height). The cross-section
  fits the 5.25" woofer despite the tilt, and leaves room to stack the
  midrange and tweeter with clearance.
- 12 mm birch plywood or MDF, glued and screwed.
- Seven airtight partitions: each channel has its own volumes, the midrange is
  isolated from the woofer, and the electronics are kept out of the acoustic
  pressure. A single pair of wires per channel runs from the crossover to the
  Amp2.
- The vent is an 88 × 22 mm duct along the front panel, under the top, from
  the woofer chamber through the end cheek: its opening is invisible from the
  bed.
- The electronics bay (left end) is closed: the Pi is installed during
  assembly, and the firmware updates over the network. It vents through slots
  in the top, wall side, behind the vent duct; the bottom face carries only
  the drivers. No hot part touches the bedding.
- The power cable comes out of the wall directly behind the bay, at the left
  end, and passes through the back panel via a Ø 12 hole: nothing is visible.
- The back sits flat against the wall, hung on two metal keyhole plates recessed
  in the back panel. Their pockets are blind (at least 3 mm of wood remains),
  so the chambers stay airtight.

![Open view](generated/preview-open.png)
![Profile](generated/preview-side.png)

## Generation

The model is fully parametric: every dimension lives in `SoundbarParameters`,
at the top of `design_soundbar.py`.

```sh
cd hardware/robine_enclosure/soundbar
/Applications/FreeCAD.app/Contents/Resources/bin/freecadcmd design_soundbar.py
python3 acoustics.py                                                 # stereo and bass
/Applications/FreeCAD.app/Contents/MacOS/FreeCAD render_previews.py   # PNG previews
```

`render_previews.py` closes FreeCAD when it finishes: do not run it in an open
FreeCAD session (go through the FreeCAD MCP in that case).

The script writes to `generated/`:

- `robine-soundbar.FCStd`: FreeCAD assembly (Enclosure and Reference groups);
- `robine-soundbar.step`: full assembly, including the reference volumes of the
  drivers and electronics;
- `parts/*.step|stl`: every part to build, in mounted position; the four
  `spacer_*` wedges are to be 3D-printed;
- `cut-list.md`: cut list, masses, chamber volumes and check results;
- `parameters.json`: parameters used, read back by `acoustics.py`.

The script checks that no driver, nor the Pi + Amp2 stack, crosses a panel, a
wedge or the vent; that each driver fits in its chamber; that the vent opens
into the woofer chamber without running over the woofer; and that the keyhole
pockets do not pierce the back. The vent length is computed from the target
tuning (`port_tuning_hz`). If a check fails, `freecadcmd` returns a non-zero
exit code.

## Before cutting

The drivers are not chosen yet. The defaults describe generic models of the
chosen sizes (5.25" woofer, 3" midrange, 25 mm dome). Copy the datasheet
dimensions into `SoundbarParameters` and the Thiele-Small parameters into
`acoustics.py`, then regenerate (selection criteria and crossover in
[ACOUSTICS.md](ACOUSTICS.md)).

To validate physically:

1. head-to-wall distance, mounting height above the ears and pillow spacing
   (`head_from_wall`, `ears_below_baffle`, `pillow_offset`); the baffle tilt
   is derived from them;
2. stereo image from each pillow (procedure in [ACOUSTICS.md](ACOUSTICS.md));
3. actual height of the Pi + Amp2 stack with its terminals (`pi_stack_depth`);
4. Amp2 temperature after 30 minutes of music, bay closed (see
   [10-002](../../../docs/specs/10/002-hardware-profile/spec.md)).

Build notes: baffle, front and back panel edges bevelled at 18.4°, midrange and
tweeter holes drilled at 20° (the wedge itself is the jig), woofer rebates,
vent duct and cheek openings with rounded edges, R9 round-over on the bottom
edge of the front and cheeks, chamber joints sealed with mastic, ~50 %
polyester fill in each chamber, acoustic fabric stretched over the baffle,
wire holes sealed after wiring, 2-3 mm pads between the back and the wall.
