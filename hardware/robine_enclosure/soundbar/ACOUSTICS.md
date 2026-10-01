# Sound bar acoustic design

Goal: balanced sound for podcasts and music, with **spatialisation first**
for two sleepers, one on each side of the bed. The wiring stays that of an
ordinary stereo speaker on the HiFiBerry Amp2: one left channel, one right
channel, each a passive 3-way. Everything happens in the enclosure and the
crossover.

The figures come from `acoustics.py`, which reads back the geometry generated
by `design_soundbar.py`:

```sh
python3 acoustics.py
```

## Layout

From the centre toward each end:

| Zone | Contents | Position |
|---|---|---|
| woofer chamber | flush-mounted 5.25" woofer, vent mouth, crossover | woofer at ±140 mm, either side of the centre partition |
| midrange compartment | 3" midrange and 25 mm tweeter flush on a 20° oblique facet | column at ±450 mm, just outside each pillow |
| end compartment | lamp; Pi and Amp2 on the left; light controller on the right (see [LIGHTING.md](LIGHTING.md)) | from ±522 mm to the cheek |

The vent is a duct along the front panel, under the top. It starts in the
woofer chamber, runs over the midrange and end compartments without
connecting to them, and leaves through the cheek.

## The three ways

| Way | Driver | Band | Role |
|---|---|---|---|
| bass | 5.25" woofer + vent | < ~250 Hz | foundation, music |
| midrange | 3" | ~250 Hz – 3 kHz | voice, stereo image |
| treble | 25 mm dome | > ~3 kHz | detail, stereo image |

### Why these sizes

This is the classic compact 3-way combination (5.25" / 3" / 1"), which follows
proven rules:

- **25 mm tweeter**: the standard dome size; it reaches cleanly down to
  ~2.5-3 kHz and disperses widely up to ~10 kHz.
- **3" midrange**: at the upper crossover (3 kHz, λ = 114 mm), its cone
  (~65 mm effective) stays smaller than the wavelength, so it does not beam
  before handing over to the tweeter. It reaches low enough for a crossover
  around 250 Hz, which a 2.5" does less well.
- **5.25" woofer**: the largest that fits the tilted baffle (the enclosure has
  a 200 × 150 mm cross-section for it and for the recessed midrange). It has ~70 % more
  cone area than a 4", so deeper bass and less excursion at the same level.

### Midrange and tweeter stacked

The midrange and tweeter are stacked along the slope (midrange on the wall
side, tweeter on the room side), 90 mm centre to centre, with 10 mm between
their flanges' margins and 18 mm of margin to the facet edges. That is less than a
wavelength at 3 kHz (114 mm), so they blend cleanly. Their interference
(lobing) stays in the wall-to-room plane. Side by side along the bar, it would
fall across the width of the bed.

## Spatialisation: the columns frame each sleeper

### The physical trade-off

At 50 cm from the bar, a sleeper on a pillow is closer to one column than to
the other. Two effects pull against each other:

- **stage width**: the further apart the columns, the more the sound comes
  from different directions, and the wider and more enveloping the stage;
- **precedence effect**: the near column arrives first. Beyond about 1 ms of
  lead, the ear places sounds common to both channels (a centred voice) on
  the near column.

With a single stereo pair, both cannot be had at once on each pillow. With
spatialisation as the priority, width wins.

### Chosen spacing: ±450 mm

Seen from the left pillow (angles measured from the sleeper, negative toward
their left):

| Columns | L column | R column | Stage width | Lead of the near side |
|---|---|---|---|---|
| ±160 mm | +22° | +47° | 25°, all on one side | 0.54 ms |
| ±350 mm (above the pillows) | 0° | +56° | 56° | 1.08 ms |
| **±450 mm (chosen)** | **−12°** | **+59°** | **71°** | 1.30 ms |
| ±550 mm | −23° | +62° | 85° | 1.47 ms |

- At ±160 mm, both columns were on the same side of each sleeper: a stable
  image, but a narrow stage and nothing from the outer side.
- At **±450 mm**, each sleeper is **framed**: the near column is slightly to
  the outside, almost overhead, and the other is far on the other side. The
  stage is almost three times wider.
- Trade-off: a centred voice drifts toward the near column. Since that column
  sits at −12°, almost overhead, the voice stays in front of the sleeper, only
  slightly shifted outward. For a podcast, that is acceptable.
- At ±550 mm the stage would be wider still, but the voice would move to
  −23°, clearly to the side.

The parameter is `column_half_spacing`: it can be tried between 400 and
550 mm, and the script checks that everything still fits.

### Crossfire

Each channel's midrange and tweeter are angled 20° toward the opposite
pillow. For a sleeper on the left, the nearby left column sees them at an
angle, so its treble is attenuated. The distant right column faces them more
directly. Level compensates part of the time lead.

At ±450 mm, on the left pillow:

| Crossfire | L−R 2 kHz | L−R 12 kHz | Recess depth (110 mm facet) |
|---|---|---|---|
| **20° (chosen)** | +6.2 dB | +9.3 dB | 40 mm |
| 30° | +5.9 dB | +7.0 dB | 64 mm |
| 40° | +5.5 dB | +4.6 dB | 92 mm |

Beyond 20°, the treble gain is real, but the recess becomes very deep and
eats into the compartments. 20° remains the compromise. To validate by ear:
if the near column's treble dominates too much, raise `crossfire_deg` to 30°
(the script checks that the drivers still fit).

### Flush oblique facets

The angle is given by the casing itself, so nothing protrudes. Under each
column, the bottom forms a recess across the whole depth of the bar:

- an **oblique facet**, 110 mm wide, turned 20° toward the opposite pillow.
  It is flush with the bottom on the outer side and 40 mm deep on the side
  facing the bar centre. The midrange and tweeter sit flush in rebates on
  it;
- a **return panel** at 60°, from the deep edge back to the bottom face.

Both are 12 mm plates, bevelled where they meet the baffle and each other.
The recess also notches the front and back panels, which shows as a V in the
lower edge of the front face. The drivers sit ~20 mm deeper than on the flat
baffle, which is why the bar is 150 mm tall.

### Bass near the centre, low crossover

The two woofers sit at ±140 mm, either side of the centre partition. Up to
~500 Hz, the ear still localises from the time difference between the two
ears. Woofers close to the centre reach both pillows almost at the same time,
so the bass and lower midrange stay centred and enveloping. Localisation is
left to the midrange and tweeter, thanks to a low crossover around 250 Hz.

## Bass

- **5.12 L net woofer chamber per channel**, from the centre partition to the
  midrange compartment. It is separate from the midrange and from the other
  channel: no midrange modulation, no crosstalk.
- **Vent (the "serpentine" of commercial sound bars).** An 88 × 22 mm duct
  along the front panel, under the top, formed by a shelf and a wall. It
  starts in the woofer chamber, crosses the midrange and end compartments
  without connecting to them, and leaves through the cheek. It is 336 mm
  long for a 55 Hz tuning, in a straight line with no bend. The bottom face
  carries only the three drivers per channel, and the opening is invisible
  from the bed.
- **Tuning**: 55 Hz is a starting point for a small-box 5.25" (Fs ~55 Hz,
  Vas ~7 L). The script recomputes the length from `port_tuning_hz`; set the
  tuning from the chosen woofer's datasheet (for example in WinISD), then
  check it on the measured impedance curve. Pick a low-Vas woofer: a model
  designed for 15-20 L would be overdamped here.
- **Pipe resonance** around 460 Hz, well above the woofer/midrange crossover
  (~250 Hz): the crossover attenuates it. A little foam at the duct entrance
  damps it further.
- **Port noise**: a 19.4 cm² duct is enough at bedside levels. Rounding the
  edges of the cheek opening limits turbulence at higher volume.
- **Back flat against the wall.** The wall is less than 2 cm from the drivers:
  it reinforces the bass (half-space radiation), without the interference dip
  a speaker spaced off the wall would have. The crossover will account for it
  (slight bass attenuation, set from measurement).

## Midrange

- **1.41 L sealed compartment**, isolated from the woofer by a partition.
  Without it, the woofer's pressure would move the midrange cone. A typical
  3" rolls off around 121 Hz in it, an octave below the crossover (~250 Hz).
- Fill the compartment with polyester or wool: it is small, and internal
  reflections would come back through the cone, right in the voice band.

## Passive crossover

One 3-way crossover per channel, on a board on the back panel of the woofer
chamber, between the woofer and the vent mouth (modelled). Only one pair of wires per channel runs to the Amp2.

- Starting crossover points: ~250 Hz and ~3 kHz, 4th-order Linkwitz-Riley
  (24 dB/octave) acoustic slopes.
- The exact values are computed with the chosen drivers, measured mounted in
  the bar on the wall (for example REW + VituixCAD): the actual response on
  the tilted baffle against the wall matters more than the datasheet.
- Include tweeter attenuation (L-pad) and, if needed, midrange impedance
  compensation.

## Enclosure colouration

- **Partitions as braces**: seven partitions and the vent duct stiffen the
  bar. No free panel span exceeds ~380 mm. Glued and screwed, joints sealed
  with mastic.
- **Damping**: ~50 % polyester fill or acoustic wool in the woofer chamber,
  against its length and cross-section modes. Keep the back of the woofer and
  the vent entrance clear.
- **Every driver flush-mounted** in a rebate (modelled), on the baffle or the
  facets: no step to diffract the treble. Round over the edges of the facet
  recesses slightly.
- **Edges**: R9 round-over on the bottom edge of the front and cheeks.
- **Grille**: stretched acoustic fabric, without a thick frame in front of the
  drivers.
- **Wall**: 2-3 mm felt or elastomer pads between the back and the wall,
  against rattles and transmission into the wall.

## Driver selection

- **5.25" woofer**: Fs ≤ 60 Hz, Qts 0.35-0.45, Vas ≤ 8 L, Xmax ≥ 4 mm, depth
  ≤ 70 mm.
- **3" midrange**: smooth response from 250 Hz to 5 kHz, Fs ≤ 110 Hz, good
  dispersion.
- **25 mm tweeter**: dome, Fs ≤ 1.2 kHz to cross at 3 kHz, small faceplate
  (≤ 60 mm) to sit close to the midrange.
- Impedances compatible with the Amp2 (4-8 Ω nominal per channel).

Copy the dimensions into `SoundbarParameters` (`woofer`, `midrange`,
`tweeter`) and the Thiele-Small parameters into `acoustics.py`, then
regenerate.

## To validate on the bed

1. Measure the head-to-wall distance, the mounting height and the pillow
   spacing. Enter them in `head_from_wall`, `ears_below_baffle` and
   `pillow_offset`: the baffle tilt is derived from them. Keep the columns
   ~100 mm outside each pillow.
2. Listen to wide stereo music from each pillow: the stage should extend from
   the outer side to the other column. Then a mono voice: it should stay in
   front, almost overhead. If it moves too far to the side, reduce
   `column_half_spacing`; if the near treble dominates, raise
   `crossfire_deg`.
3. Turn the volume up with bass-heavy music: no enclosure noise, port chuffing
   or wall vibration.
