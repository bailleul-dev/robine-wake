#!/usr/bin/env python3
"""First-order acoustic checks for the sound bar layout (stdlib only).

    python3 acoustics.py

Reads ``generated/parameters.json`` (written by ``design_soundbar.py``) so
the analysis always matches the model. Point sources with a rigid-piston
directivity, heard from a head lying on the pillow.

Each channel is a passive 3-way. The stereo image is carried by the
midrange (up to ~3 kHz) and the tweeter (above), both angled toward the
opposite pillow; the woofer only plays the non-localisable bass.

For each sleeping position it reports the stereo cues of the plain L/R pair:

* delay of the far channel: under ~1 ms the image stays between the two
  speakers (summing localisation); beyond it collapses onto the nearest one
  (precedence effect);
* level difference L-R at 1 and 2 kHz (midrange) and 4, 8 and 12 kHz
  (tweeter), where the crossfire angle trades the near speaker's proximity
  against its off-axis loss.

It also compares angle variants, gives the sealed-box alignment of a typical
midrange in its compartment, and summarises the woofer's vent duct
(tuning, length, first pipe resonance to keep above the woofer/midrange
crossover).
"""

from __future__ import annotations

import json
import math
from pathlib import Path

C = 343.0  # m/s

# (frequency Hz, effective radiating radius m): midrange 3", 25 mm dome.
BANDS = ((1000, 0.032), (2000, 0.032), (4000, 0.013), (8000, 0.013), (12000, 0.013))

# Typical Thiele-Small values (Fs Hz, Qts, Vas L): replace with datasheets.
WOOFER_TS = (55.0, 0.40, 7.0)  # 5.25" for small boxes
MIDRANGE_TS = (100.0, 0.50, 0.7)  # 3"

PARAMS = json.loads((Path(__file__).resolve().parent / "generated" / "parameters.json").read_text())
MM = 0.001
HEAD_FROM_WALL = PARAMS["head_from_wall"] * MM
EARS_BELOW_BAFFLE = PARAMS["ears_below_baffle"] * MM
BAFFLE_FROM_WALL = PARAMS["depth"] / 2 * MM
PILLOW = PARAMS["pillow_offset"] * MM
HALF_SPACING = PARAMS["column_half_spacing"] * MM
CROSSFIRE = PARAMS["crossfire_deg"]

# Distance from the baffle to the head in the plane across the bar.
REACH = math.hypot(HEAD_FROM_WALL - BAFFLE_FROM_WALL, EARS_BELOW_BAFFLE)
POSITIONS = (("left pillow", -PILLOW), ("centre", 0.0), ("right pillow", PILLOW))


def bessel_j1(x: float) -> float:
    return sum((-1) ** k * (x / 2) ** (2 * k + 1) / (math.factorial(k) * math.factorial(k + 1)) for k in range(30))


def piston_db(theta: float, freq: float, radius: float) -> float:
    x = 2 * math.pi * freq / C * radius * math.sin(theta)
    if abs(x) < 1e-6:
        return 0.0
    # A real cone never nulls like an ideal piston: floor at -20 dB.
    return max(20 * math.log10(abs(2 * bessel_j1(x) / x)), -20.0)


def cues(half_spacing: float, crossfire_deg: float, head_x: float):
    """Far-channel delay (ms) and L-R level (dB) for each band."""
    out = {}
    # L sits on the sleepers' left and is aimed toward their right (+x).
    for ch, x, aim in (("L", -half_spacing, +1), ("R", half_spacing, -1)):
        dx = head_x - x
        dist = math.hypot(dx, REACH)
        off_axis = abs(math.atan2(dx, REACH) - aim * math.radians(crossfire_deg))
        out[ch] = (dist, [piston_db(off_axis, f, r) - 20 * math.log10(dist) for f, r in BANDS])
    delay = (out["R"][0] - out["L"][0]) / C * 1000
    levels = [l - r for l, r in zip(out["L"][1], out["R"][1])]
    return delay, levels


def describe(title: str, half_spacing: float, crossfire_deg: float) -> None:
    width = math.degrees(math.atan2(half_spacing, REACH))
    print(f"\n{title} (±{half_spacing * 1000:.0f} mm, {crossfire_deg:g}°, width from the centre ±{width:.0f}°)")
    print("  position          delay   " + "".join(f"  L-R {f // 1000:>2d}k" for f, _ in BANDS))
    for label, hx in POSITIONS:
        delay, levels = cues(half_spacing, crossfire_deg, hx)
        print(f"  {label:16s} {delay:+5.2f} ms " + "".join(f"  {lv:+6.1f}" for lv in levels) + " dB")


def sealed_box(ts, vb_litres: float) -> tuple[float, float]:
    fs, qts, vas = ts
    alpha = vas / vb_litres
    return qts * math.sqrt(1 + alpha), fs * math.sqrt(1 + alpha)


def main() -> None:
    print("Delay > 0: the left channel arrives first. L-R > 0: the left channel is louder.")
    describe("Chosen", HALF_SPACING, CROSSFIRE)
    for angle in (0, 15, 25, 30):
        if angle != CROSSFIRE:
            describe("Angle variant", HALF_SPACING, angle)
    describe("Reference: pair at the ends, no angle", 0.34, 0)

    print(f"\nBaffle tilt aiming at the ears: {PARAMS['baffle_tilt_deg']:.1f}°")
    vb = PARAMS["mid_chamber_litres"]
    qtc, fc = sealed_box(MIDRANGE_TS, vb)
    print(f"Midrange (sealed)    {vb:.2f} L  Qtc = {qtc:.2f}  fc = {fc:.0f} Hz (typical driver)")

    vb = PARAMS["woofer_chamber_litres"]
    fs, qts, vas = WOOFER_TS
    length = PARAMS["port_length_mm"] * MM
    area = PARAMS["port_area_cm2"] * 1e-4
    r_eq = math.sqrt(area / math.pi)
    pipe = C / (2 * (length + 1.463 * r_eq))
    print(
        f"Woofer (bass-reflex) {vb:.2f} L  tuned to {PARAMS['port_tuning_hz']:g} Hz "
        f"(typical Fs {fs:g} Hz, Vas/Vb = {vas / vb:.1f})"
    )
    print(
        f"Vent                 {PARAMS['port_area_cm2']:.1f} cm², {PARAMS['port_length_mm']:.0f} mm, "
        f"first pipe resonance ≈ {pipe:.0f} Hz"
    )


if __name__ == "__main__":
    main()
