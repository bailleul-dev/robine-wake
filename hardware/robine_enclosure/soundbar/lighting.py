#!/usr/bin/env python3
"""First-order lighting checks for the sound bar (stdlib only).

    python3 lighting.py

Reads ``generated/parameters.json`` (written by ``design_soundbar.py``).
Uniform-cone approximation: a lamp puts ``beam_efficiency`` of its flux
evenly into its full beam angle; illuminance falls with the square of the
distance and the cosine of incidence.

It answers:

* breathing halo: where the spot lands on the ceiling and how large it is;
* dawn and reading lamps: flux needed for 300 lux at the eye of a sleeper
  (the top of the dawn range in spec 00-002) and for reading, and how much
  light spills onto the other pillow.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

PARAMS = json.loads((Path(__file__).resolve().parent / "generated" / "parameters.json").read_text())
MM = 0.001
BEAM_EFFICIENCY = 0.8

DAWN_LUX = 300.0  # top of the 100-300 lux range at the eye (spec 00-002)
READING_LUX = 500.0  # comfortable reading on the page


def unit(v):
    n = math.sqrt(sum(c * c for c in v))
    return tuple(c / n for c in v)


def angle_deg(a, b) -> float:
    return math.degrees(math.acos(max(-1.0, min(1.0, sum(x * y for x, y in zip(unit(a), unit(b)))))))


def cone_lux(flux_lm: float, beam_deg: float, distance_m: float, incidence_deg: float, off_axis_deg: float) -> float:
    """Illuminance from a uniform cone; zero outside the beam."""
    if off_axis_deg > beam_deg / 2:
        return 0.0
    solid = 2 * math.pi * (1 - math.cos(math.radians(beam_deg / 2)))
    intensity = flux_lm * BEAM_EFFICIENCY / solid  # candela
    return intensity * math.cos(math.radians(incidence_deg)) / distance_m**2


def halo() -> None:
    src = [c * MM for c in PARAMS["halo_position"]]
    tgt = [c * MM for c in PARAMS["halo_target"]]
    d = [t - s for s, t in zip(src, tgt)]
    dist = math.sqrt(sum(c * c for c in d))
    tilt = angle_deg(d, (0, 0, 1))
    beam = PARAMS["halo_beam_deg"]
    minor = 2 * dist * math.tan(math.radians(beam / 2))
    major = minor / math.cos(math.radians(tilt))
    print("Breathing halo")
    print(f"  spot centre on the ceiling : {tgt[0] - PARAMS['length'] * MM / 2:+.2f} m from the bar centre,"
          f" {tgt[1]:.2f} m from the wall")
    print(f"  throw {dist:.2f} m, {tilt:.0f}° from vertical, beam {beam:g}°")
    print(f"  spot ≈ {minor * 100:.0f} × {major * 100:.0f} cm (soft edge with the diffuser)")


def lamps() -> None:
    src = [c * MM for c in PARAMS["lamp_left_position"]]
    aim = PARAMS["lamp_left_axis"]
    beam = PARAMS["lamp_beam_deg"]
    centre = PARAMS["length"] * MM / 2
    head_y = PARAMS["head_from_wall"] * MM
    ears_z = src[2] - (PARAMS["ears_below_baffle"] * MM)
    pillow = PARAMS["pillow_offset"] * MM
    targets = {
        "own face (lying)": (centre - pillow, head_y, ears_z, (0, 0, 1)),
        "own book (sitting)": (
            centre - pillow,
            PARAMS["book_from_wall"] * MM,
            src[2] - PARAMS["book_below_baffle"] * MM,
            unit((0, -0.5, 1)),  # page tilted toward the reader
        ),
        "other face (lying)": (centre + pillow, head_y, ears_z, (0, 0, 1)),
    }
    print("\nDawn / reading lamp (left; the right one mirrors it)")
    print(f"  beam {beam:g}°, axis {angle_deg(aim, (0, 0, -1)):.0f}° from vertical")
    per_lumen = {}
    for name, (x, y, z, surface_normal) in targets.items():
        to_target = (x - src[0], y - src[1], z - src[2])
        dist = math.sqrt(sum(c * c for c in to_target))
        off = angle_deg(to_target, aim)
        incidence = angle_deg([-c for c in to_target], surface_normal)
        lux_per_lm = cone_lux(1.0, beam, dist, incidence, off)
        per_lumen[name] = lux_per_lm
        print(f"  {name:20s} {dist:.2f} m, {off:4.0f}° off axis, {lux_per_lm:6.2f} lux per lumen")
    need_dawn = DAWN_LUX / per_lumen["own face (lying)"]
    need_read = READING_LUX / per_lumen["own book (sitting)"]
    flux = PARAMS["lamp_flux_lm"]
    print(f"  flux for {DAWN_LUX:g} lux at the eye : {need_dawn:.0f} lm")
    print(f"  flux for {READING_LUX:g} lux on the book: {need_read:.0f} lm")
    print(
        f"  with {flux:g} lm: {flux * per_lumen['own face (lying)']:.0f} lux at the eye, "
        f"{flux * per_lumen['own book (sitting)']:.0f} lux on the book, "
        f"{flux * per_lumen['other face (lying)']:.0f} lux on the other pillow"
    )


if __name__ == "__main__":
    halo()
    lamps()
