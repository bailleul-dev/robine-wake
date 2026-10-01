# Sound bar lighting

The bar carries two very different light sources:

- a **breathing halo** for falling asleep: a narrow beam aimed at the ceiling,
  pulsing with the 4 s / 6 s guided breathing of
  [30-003](../../../docs/specs/30/003-guided-breathing/spec.md);
- two **dawn / reading lamps**, one per sleeper: a 30-minute artificial dawn
  in the morning ([00-002](../../../docs/specs/00/002-gentle-awakening-mechanisms/spec.md):
  100–300 lux at the eye), and a reading light in the evening.

The figures come from `lighting.py`, which reads back the geometry generated
by `design_soundbar.py`:

```sh
python3 lighting.py
```

## Breathing halo

| Item | Value |
|---|---|
| Position | centre of the top panel, wall side |
| Aim | ceiling above the middle of the bed, 0.75 m from the wall (both sleepers see it) |
| Throw | 1.38 m, 30° from vertical, tilted toward the room only (1.2 m from the top of the bar to the ceiling) |
| Optic | 10° TIR collimator + light diffuser film for a soft edge |
| Spot | ≈ 24 × 28 cm on the ceiling |
| Emitter | RGB(A) LED, 1-3 W, on a star board |

- **Narrow and indirect.** Nobody looks into the emitter. The spot on the
  ceiling is the only thing visible, which is what you look at lying on your
  back.
- **Colours** follow 30-003: dusk pink on the exhale, amber gold on the
  inhale. Both are poor in blue, which suits falling asleep. A red + green +
  blue LED reproduces them; adding an amber die gives warmer, purer ambers.
- **Low level**: a few lumens are enough in a dark room. The controller
  limits the halo to a dim range. The breathing goes from ~2 % to 30 % of
  that range, as on Hue.
- **Mounting**: the centre of the bar is the partition between the two
  woofer chambers. The module sits in a sealed 3D-printed housing (PETG,
  `halo_pod`), glued into an angled hole in the top and through a cut-out in
  the centre partition (modelled). Both woofer chambers stay airtight; seen
  from above, only a small ring shows at the centre of the top.
- To validate: the ceiling height above the bar (`ceiling_above_top`) and
  the spot position (`halo_target_from_wall`).

## Dawn / reading lamps

| Item | Value |
|---|---|
| Position | bottom face of each end compartment, outside the speakers |
| Aim | between the sleeper's face (lying) and book (sitting up), 42° from vertical, from above and outside the shoulder |
| Beam | 60° |
| Flux | 400 lm (≈ 4-5 W) per lamp |
| Emitter | warm white 2700 K + cool white 5000 K (CRI ≥ 90) + amber |

Illuminance with 400 lm (uniform-cone estimate):

| Target | Distance | Illuminance |
|---|---|---|
| own face, lying | 0.51 m | ≈ 1280 lux at full power |
| own book, sitting up | 0.60 m | ≈ 900 lux at full power |
| the other sleeper's face | 1.01 m, 43° off axis | outside the beam |

- **Dawn**: 300 lux at the eye needs only ~95 lm, a quarter of the lamp. The
  dawn starts in amber at a fraction of a lux, moves to warm white, then
  ends around 4000 K at 300 lux after 30 minutes. The software caps the dawn
  at the 00-002 target; the headroom is for reading and room light.
- **Reading**: 500 lux on the page needs ~220 lm. Warm white with high CRI
  in the evening.
- **Each sleeper has their own lamp**: the beam of one lamp does not reach
  the other pillow. Each lamp is recessed in its angled hole, which acts as
  a glare shield. A real beam has a soft edge, so a small spill remains; to
  check at night.
- **Why the bottom face**: a reading light has to come from above and
  outside the shoulder, like a bedside wall lamp. The front face is
  vertical and too short to aim down at the bed. The lamps sit at the very
  ends, away from the speakers.
- **Heat**: ~5 W per lamp at full power, on a small heatsink inside the end
  compartment, which has vent slots in the top. Check the lamp temperature
  after 30 minutes of reading.
- To validate: book position (`book_from_wall`, `book_below_baffle`) and the
  absence of glare when lying down.

## Electronics

- **Light controller**: an RP2040 board and constant-current LED drivers, on
  the inner face of the right cheek (modelled). Channels:
  halo R, G, B (A); each lamp warm white, cool white, amber. That makes 9 to
  10 channels, within the 16 PWM channels of the RP2040.
- **Dimming**: a dawn starts from almost nothing, so the controller uses
  16-bit PWM at ≥ 2 kHz (no visible flicker) with a perceptual curve. It
  runs the fades itself, from absolute deadlines sent by the Pi, which keeps
  owning the clock as required by 30-003.
- **Link to the Pi**: USB, addressed by a stable path (`/dev/serial/by-id`),
  per HW-009. No GPIO is taken from the HiFiBerry.
- **Power**: the lights add up to ~15 W (two lamps at full power plus the
  halo). The power supply has to be re-sized with the Amp2, the Pi and this
  load, with a 25 % margin (HW-006).
- **Wiring**: the left lamp and the halo are wired across the bar to the
  controller, through the sealed wire holes of the partitions.

## Specs to update

This hardware adds to the project scope:

- [10-002](../../../docs/specs/10/002-hardware-profile/spec.md): bill of
  materials (halo, lamps, light controller), power budget, decision
  register;
- [30-003](../../../docs/specs/30/003-guided-breathing/spec.md): the
  built-in halo as a breathing light, alongside or instead of Philips Hue;
- [00-002](../../../docs/specs/00/002-gentle-awakening-mechanisms/spec.md):
  the 30-minute dawn becomes possible with built-in light (rule GWA-008).
