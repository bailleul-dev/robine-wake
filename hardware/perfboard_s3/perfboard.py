#!/usr/bin/env python3
"""Perfboard layout of the Robine Wake ESP32-S3 prototype.

One source of truth for the placement and the wires. Running it checks the
layout (no hole used twice, every wire end on a real hole) and writes:

  website/src/assets/perfboard/top.svg     component side
  website/src/assets/perfboard/bottom.svg  solder side (mirrored left-right)
  hardware/perfboard_s3/layout.md          wire and component tables

Holes are (column, row), column 1 at the left edge and row 1 at the top edge
of the board seen from the component side. 2.54 mm pitch.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COLS, ROWS = 58, 35

# --- Devkit headers ---------------------------------------------------------
# Pin names in header order (pin 1 first), from the Espressif pin layouts.
S3_J1 = ["3V3", "3V3", "RST", "IO4", "IO5", "IO6", "IO7", "IO15", "IO16", "IO17", "IO18",
         "IO8", "IO3", "IO46", "IO9", "IO10", "IO11", "IO12", "IO13", "IO14", "5V0", "G"]
S3_J3 = ["G", "TX", "RX", "IO1", "IO2", "IO42", "IO41", "IO40", "IO39", "IO38", "IO37",
         "IO36", "IO35", "IO0", "IO45", "IO48", "IO47", "IO21", "IO20", "IO19", "G", "G"]
E32_J3 = ["GND", "IO23", "IO22", "TX", "RX", "IO21", "GND", "IO19", "IO18", "IO5", "IO17",
          "IO16", "IO4", "IO0", "IO2", "IO15", "SD1", "SD0", "CLK"]
E32_J2 = ["3V3", "EN", "VP", "VN", "IO34", "IO35", "IO32", "IO33", "IO25", "IO26", "IO27",
          "IO14", "IO12", "GND", "IO13", "SD2", "SD3", "CMD", "5V"]

# Turned so that the USB ports face the board edges and the antennas face each
# other, over the free middle of the board.
S3_X0, S3_ROW_J1, S3_ROW_J3 = 3, 4, 13          # row spacing 9 holes = 22.86 mm
E32_X0, E32_ROW_J3, E32_ROW_J2 = 38, 4, 14      # row spacing 10 holes = 25.4 mm
HAT_X0, HAT_EVEN_ROW, HAT_ODD_ROW = 5, 21, 22   # 2x20 header, pin 1 on the left, under the S3


def s3(header, pin):
    """Hole of an S3 devkit pin. USB end on the left, so pin 22 is leftmost."""
    row = S3_ROW_J1 if header == "J1" else S3_ROW_J3
    return (S3_X0 + 22 - pin, row)


def e32(header, pin):
    """Hole of an ESP32 devkit pin. USB end on the right, pin 1 leftmost."""
    row = E32_ROW_J3 if header == "J3" else E32_ROW_J2
    return (E32_X0 + pin - 1, row)


def hat(pin):
    """Hole of a pin of the amplifier's 40-pin header."""
    if pin % 2 == 0:
        return (HAT_X0 + pin // 2 - 1, HAT_EVEN_ROW)
    return (HAT_X0 + (pin - 1) // 2, HAT_ODD_ROW)


def find(names, wanted, nth=0):
    return [i + 1 for i, name in enumerate(names) if name == wanted][nth]


def S3(name, nth=0):
    if name in S3_J1:
        return s3("J1", find(S3_J1, name, nth))
    return s3("J3", find(S3_J3, name, nth))


def E32(name, nth=0):
    if name in E32_J3:
        return e32("J3", find(E32_J3, name, nth))
    return e32("J2", find(E32_J2, name, nth))


# --- Free-standing parts ----------------------------------------------------
# The I2C pull-ups sit beside the amplifier, below the wire channels.
R1 = ((30, 20), (30, 24))   # 2.2 kOhm, SDA pull-up: lead 1 to 3V3, lead 2 to SDA
R2 = ((32, 20), (32, 24))   # 2.2 kOhm, SCL pull-up
JP3 = ((52, 16), (53, 16))  # ESP32 5 V from the S3, jumper cap (open it to power the ESP32 by its own USB)
JP4 = ((53, 26), (54, 26))  # single-supply link: strip 5 V rail to the S3 5 V, jumper cap (open it whenever a USB cable is plugged)
JP1 = ((41, 16), (42, 16))  # UART S3 TX -> ESP32 RX, jumper cap
JP2 = ((44, 16), (45, 16))  # UART ESP32 TX -> S3 RX, jumper cap
R3 = ((38, 25), (38, 29))   # 330 Ohm, strip data
# 74AHCT1G125 on a SOT23-6 to DIP-6 adapter (rows 3 holes apart), buffer for the strip data:
# it runs on the strip's 5 V so its output is a true 5 V level. Pin 5 is not connected.
U1 = {"OE": (45, 25), "A": (45, 26), "GND": (45, 27), "VCC": (48, 25), "NC": (48, 26), "Y": (48, 27)}
C2 = {"VCC": (50, 27), "GND": (50, 25)}   # 100 nF ceramic across the buffer supply
J4 = {"+5V": (36, 31), "DATA": (38, 31), "GND": (40, 31)}  # 5.08 mm screw terminal
C1 = {"+": (36, 33), "-": (38, 33)}                         # 1000 uF radial, 5 mm
GND_BUS = [(x, 18) for x in range(7, 52)]                   # bare tinned wire, row 18
CHANNELS = (15, 16, 17)  # rows where long wires run, under neither antenna

# --- Wires: (id, from, to, colour, what) ------------------------------------
HAT_SDA, HAT_SCL, HAT_GND = hat(3), hat(5), hat(6)
WIRES = [
    # Amplifier, I2S
    ("W1", S3("IO6"), hat(12), "yellow", "I2S bit clock"),
    ("W2", S3("IO7"), hat(35), "yellow", "I2S word clock"),
    ("W3", S3("IO8"), hat(40), "yellow", "I2S data to the amplifier"),
    # Amplifier, I2C and control
    ("W4", S3("IO17"), HAT_SDA, "green", "I2C SDA"),
    ("W5", S3("IO18"), HAT_SCL, "green", "I2C SCL"),
    ("W6", R1[1], HAT_SDA, "green", "SDA pull-up (R1 lead 2 to amplifier pin 3)"),
    ("W7", R2[1], HAT_SCL, "green", "SCL pull-up (R2 lead 2 to amplifier pin 5)"),
    ("W8", S3("IO21"), hat(8), "blue", "amplifier enable"),
    ("W9", S3("IO41"), hat(10), "blue", "amplifier mute"),
    ("W10", S3("IO38"), hat(16), "blue", "amplifier error"),
    # 3.3 V of the S3 to the two pull-ups
    ("W11", S3("3V3", 1), R1[0], "orange", "S3 3V3 to R1 lead 1"),
    ("W12", R1[0], R2[0], "orange", "R1 lead 1 to R2 lead 1 (3V3 link)"),
    # Bluetooth companion: I2S clocks and return audio
    ("W13", S3("IO6"), E32("IO26"), "yellow", "I2S bit clock to the ESP32"),
    ("W14", S3("IO7"), E32("IO25"), "yellow", "I2S word clock to the ESP32"),
    ("W15", S3("IO40"), E32("IO22"), "yellow", "Bluetooth audio back to the S3"),
    # Bluetooth companion: UART through the jumpers, reset and boot
    ("W16", S3("IO15"), JP1[0], "white", "S3 TX to the jumper"),
    ("W17", JP1[1], E32("RX"), "white", "jumper to ESP32 RX"),
    ("W18", E32("TX"), JP2[0], "white", "ESP32 TX to the jumper"),
    ("W19", JP2[1], S3("IO16"), "white", "jumper to S3 RX"),
    ("W20", S3("IO47"), E32("EN"), "purple", "ESP32 reset (EN)"),
    ("W21", S3("IO48"), E32("IO0"), "purple", "ESP32 boot (IO0)"),
    # ESP32 power from the S3's USB through a jumper
    ("W22", S3("5V0"), JP3[0], "red", "5 V from the S3 to the jumper"),
    ("W23", JP3[1], E32("5V"), "red", "jumper to the ESP32 5 V"),
    # Light strip, through the 5 V buffer
    ("W24", S3("IO9"), U1["A"], "gray", "strip data to the buffer input"),
    ("W25", U1["Y"], R3[0], "gray", "buffer output to the resistor"),
    ("W26", R3[1], J4["DATA"], "gray", "resistor to the terminal"),
    ("W27", J4["+5V"], C1["+"], "red", "terminal +5 V to the capacitor"),
    ("W28", J4["GND"], C1["-"], "black", "terminal GND to the capacitor"),
    ("W29", U1["VCC"], C2["VCC"], "red", "buffer supply to C2"),
    ("W30", C2["VCC"], J4["+5V"], "red", "C2 to the terminal +5 V"),
    ("W31", U1["OE"], U1["GND"], "black", "buffer output enable to ground"),
    # Single supply: the strip's 5 V also feeds both devkits, through a jumper
    ("W32", C2["VCC"], JP4[0], "red", "5 V rail to the single-supply jumper"),
    ("W33", JP4[1], JP3[0], "red", "jumper to the S3 5 V (same node as JP3 lead 1)"),
]
# Wires that do not follow the default routing.
ROUTES = {
    "W24": [(10, 16), (46, 16), (46, 26)],
    "W25": [(48, 28), (40, 28), (40, 24), (38, 24)],
    "W28": [(40, 33)],
    "W29": [(49, 25), (49, 27)],
    "W30": [(50, 30), (36, 30)],
    "W31": [(44, 25), (44, 27)],
    "W32": [(53, 27)],
    "W33": [(54, 17), (52, 17)],
}
WIRES = [(f"W{i + 1}", *w[1:]) for i, w in enumerate(WIRES)]

# Ground: each tap goes to the bare bus on row 18, straight below the pin.
GND_TAPS = [
    ("G1", s3("J3", 1), "S3 GND"),
    ("G2", e32("J2", 14), "ESP32 GND"),
    ("G3", HAT_GND, "amplifier pin 6"),
    ("G4", J4["GND"], "terminal GND"),
    ("G5", U1["OE"], "buffer OE"),
    ("G6", C2["GND"], "C2 ground lead"),
]
COLOURS = {"yellow": "#d4a900", "green": "#2e9e4a", "blue": "#2f6fdb", "orange": "#e07b00",
           "white": "#7d8590", "purple": "#8e44ad", "red": "#d62f2f", "gray": "#555b66",
           "black": "#111111"}

# Holes that carry a lead or a pin (checked for duplicates).
def occupied():
    holes = {}

    def put(hole, what):
        assert 1 <= hole[0] <= COLS and 1 <= hole[1] <= ROWS, (what, hole)
        assert hole not in holes, f"hole {hole} used by {holes[hole]} and {what}"
        holes[hole] = what

    for i in range(1, 23):
        put(s3("J1", i), f"S3 J1.{i}")
        put(s3("J3", i), f"S3 J3.{i}")
    for i in range(1, 20):
        put(e32("J3", i), f"ESP32 J3.{i}")
        put(e32("J2", i), f"ESP32 J2.{i}")
    for p in range(1, 41):
        if p not in (2, 4):  # pins 2 and 4 (5 V) are removed from the header
            put(hat(p), f"HAT {p}")
    for name, pair in (("R1", R1), ("R2", R2), ("R3", R3), ("JP3", JP3), ("JP4", JP4), ("JP1", JP1), ("JP2", JP2)):
        put(pair[0], f"{name}.1")
        put(pair[1], f"{name}.2")
    for k, v in U1.items():
        put(v, f"U1 {k}")
    for k, v in C2.items():
        put(v, f"C2 {k}")
    for k, v in J4.items():
        put(v, f"J4 {k}")
    for k, v in C1.items():
        put(v, f"C1 {k}")
    for h in GND_BUS:
        put(h, "GND bus")
    return holes


def check():
    holes = occupied()
    def is_hole(h):
        return h in holes
    for wid, a, b, _, _ in WIRES:
        assert is_hole(a), f"{wid}: start {a} is not a pin or a lead"
        assert is_hole(b), f"{wid}: end {b} is not a pin or a lead"
    for gid, pin, _ in GND_TAPS:
        assert is_hole(pin), gid
    # Pins used by several wires must be the same electrical node on purpose.
    return holes


def route(index, a, b, wid=None):
    """Polyline of a wire on the solder side. Short wires run in an L; long ones
    drop to a channel row under both devkits, so no wire crosses an antenna zone."""
    if wid in ROUTES:
        return [a, *ROUTES[wid], b]
    if abs(a[0] - b[0]) + abs(a[1] - b[1]) <= 6:
        return [a, (b[0], a[1]), b]
    if min(a[1], b[1]) >= 19:  # both below the GND bus: no channel needed
        return [a, (b[0], a[1]), b]
    row = CHANNELS[index % len(CHANNELS)]
    return [a, (a[0], row), (b[0], row), b]


def path_len(points):
    return sum(abs(p[0] - q[0]) + abs(p[1] - q[1]) for p, q in zip(points, points[1:]))


def length_mm(points):
    """Insulated wire to cut: the run plus 20 mm to strip and tin both ends."""
    return round(path_len(points) * 2.54 + 20)


def routed():
    return [(wid, route(i, a, b, wid), colour, role) for i, (wid, a, b, colour, role) in enumerate(WIRES)]


def drawn(index, points):
    """Same polyline, channel segments nudged apart so wires sharing a row stay readable."""
    if len(points) != 4:
        return points
    nudge = ((index // len(CHANNELS)) % 5 - 2) * 0.2
    return [points[0], (points[1][0], points[1][1] + nudge), (points[2][0], points[2][1] + nudge), points[3]]


# --- Drawing ----------------------------------------------------------------
STEP, MARGIN = 14, 30


def render(mirror, wires=(), gnd=False, title="", highlight_all=False):
    width = COLS * STEP + 2 * MARGIN
    height = ROWS * STEP + 2 * MARGIN + 60

    def px(h):
        x = (COLS + 1 - h[0]) if mirror else h[0]
        return MARGIN + (x - 0.5) * STEP, MARGIN + (h[1] - 0.5) * STEP

    def rect(x0, y0, x1, y1):
        corners = [px((x0, y0)), px((x1, y1))]
        xs = sorted(c[0] for c in corners)
        ys = sorted(c[1] for c in corners)
        return xs[0], ys[0], xs[1] - xs[0], ys[1] - ys[0]

    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
         f'font-family="system-ui, sans-serif" role="img" aria-label="Perfboard layout, '
         f'{"solder side" if mirror else "component side"}">',
         f'<rect width="{width}" height="{height}" fill="#ffffff"/>']
    bx, by, bw, bh = rect(0.5, 0.5, COLS + 0.5, ROWS + 0.5)
    o.append(f'<rect x="{bx}" y="{by}" width="{bw}" height="{bh}" rx="6" fill="#e9f0e4" stroke="#6b7f63" stroke-width="2"/>')

    # Antenna keep-outs, then the board outlines.
    def box(x0, y0, x1, y1, fill, stroke, label=None, dash=False, lx=None, ly=None, color="#333"):
        x, y, w, h = rect(x0, y0, x1, y1)
        d = ' stroke-dasharray="6 4"' if dash else ""
        o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="{stroke}" stroke-width="1.5"{d} opacity="{0.45 if mirror else 1}"/>')
        if label:
            tx, ty = px((lx, ly))
            o.append(f'<text x="{tx}" y="{ty}" font-size="11" fill="{color}" text-anchor="middle">{label}</text>')

    box(0.2, 3.5, 27.4, 13.5, "#dbe7f5", "#2f6fdb", "ESP32-S3-DevKitC-1 (N16R8)", lx=13, ly=8.5)
    box(24.4, 3.5, 27.4, 13.5, "#f6c6c6", "#c0392b", None, dash=True)
    box(34.5, 3.5, 58.7, 14.5, "#e8dff2", "#8e44ad", "ESP32-DevKitC (Bluetooth)", lx=48, ly=9)
    box(34.5, 3.5, 37.4, 14.5, "#f6c6c6", "#c0392b", None, dash=True)
    box(2.2, 19.6, 27.8, 31.4, "#fdf1d6", "#c58b00", "InnoMaker amplifier HAT (plugs on top)", dash=True, lx=15, ly=29.5)

    # Holes
    for y in range(1, ROWS + 1):
        for x in range(1, COLS + 1):
            cx, cy = px((x, y))
            o.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="1.7" fill="#b9c4b2"/>')
    # Axis labels: real column numbers, so the solder side reads backwards.
    for x in range(1, COLS + 1):
        if x % 5 == 0 or x == 1:
            cx, _ = px((x, 1))
            o.append(f'<text x="{cx:.1f}" y="{MARGIN - 12}" font-size="10" fill="#555" text-anchor="middle">{x}</text>')
    for y in range(1, ROWS + 1):
        if y % 5 == 0 or y == 1:
            _, cy = px((1, y))
            o.append(f'<text x="{MARGIN - 14}" y="{cy + 3:.1f}" font-size="10" fill="#555" text-anchor="middle">{y}</text>')

    # GND bus
    (x0, y0), (x1, y1) = px(GND_BUS[0]), px(GND_BUS[-1])
    o.append(f'<line x1="{x0}" y1="{y0}" x2="{x1}" y2="{y1}" stroke="#111" stroke-width="4" stroke-linecap="round"/>')
    tx, ty = px((34, 18))
    o.append(f'<text x="{tx}" y="{ty + 15}" font-size="10" fill="#111" text-anchor="middle">GND bus: bare tinned wire along row 18 (holes 7 to 51)</text>')

    def pad(h, fill, label=None, size=4.2, dy=-7, rotate=False):
        cx, cy = px(h)
        o.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{size}" fill="{fill}" stroke="#222" stroke-width="0.8"/>')
        if label and rotate:
            # Vertical labels: neighbouring pins would overlap side by side.
            angle = -90 if dy < 0 else 90
            o.append(f'<text transform="translate({cx:.1f} {cy + dy:.1f}) rotate({angle})" font-size="9" fill="#222" '
                     f'text-anchor="start" dominant-baseline="central">{label}</text>')
        elif label:
            o.append(f'<text x="{cx:.1f}" y="{cy + dy:.1f}" font-size="8" fill="#222" text-anchor="middle">{label}</text>')

    # Pins of the devkits and the HAT header
    used = {}
    for index, (_, a, b, _, _) in enumerate(WIRES):
        if highlight_all or index in wires:
            used.setdefault(a, 0); used.setdefault(b, 0)
    if highlight_all or gnd:
        for _, pin, _ in GND_TAPS:
            used.setdefault(pin, 0)
    for i in range(1, 23):
        for header, names in (("J1", S3_J1), ("J3", S3_J3)):
            h = s3(header, i)
            pad(h, "#2f6fdb" if h in used else "#9db7de", names[i - 1] if h in used else None,
                dy=-8 if header == "J1" else 8, rotate=True)
    for i in range(1, 20):
        for header, names in (("J3", E32_J3), ("J2", E32_J2)):
            h = e32(header, i)
            pad(h, "#8e44ad" if h in used else "#c9b3dc", names[i - 1] if h in used else None,
                dy=-8 if header == "J3" else 8, rotate=True)
    for p in range(1, 41):
        h = hat(p)
        if p in (2, 4):
            cx, cy = px(h)
            o.append(f'<text x="{cx:.1f}" y="{cy + 4:.1f}" font-size="11" fill="#c0392b" text-anchor="middle">×</text>')
            continue
        pad(h, "#c58b00" if h in used else "#e2c77a", str(p) if h in used or p == 1 else None,
            dy=-7 if p % 2 == 0 else 13)

    # Parts
    def part(pair, fill, label, vertical=True, left=False):
        (xa, ya), (xb, yb) = px(pair[0]), px(pair[1])
        o.append(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}" stroke="#444" stroke-width="7" stroke-linecap="round"/>')
        o.append(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}" stroke="{fill}" stroke-width="4" stroke-linecap="round"/>')
        pad(pair[0], "#fff"); pad(pair[1], "#fff")
        mx, my = (xa + xb) / 2, (ya + yb) / 2
        o.append(f'<text x="{mx + ((-10 if left else 10) if vertical else 0):.1f}" y="{my + (3 if vertical else 20):.1f}" font-size="10" fill="#222" '
                 f'text-anchor="{("end" if left else "start") if vertical else "middle"}">{label}</text>')

    part(R1, "#e8c08a", "R1 2.2k")
    part(R2, "#e8c08a", "R2 2.2k", left=mirror)
    part(R3, "#e8c08a", "R3 330")
    part(JP3, "#222", "JP3", vertical=False)
    part(JP4, "#222", "JP4", vertical=False)
    box(44.6, 24.4, 48.4, 27.6, "#e4e4e4", "#555", None)
    for name, h in U1.items():
        pad(h, "#fff", name if name != "NC" else None, size=3.6, dy=-6)
    tx, ty = px((46.5, 28.6))
    o.append(f'<text x="{tx}" y="{ty}" font-size="9" fill="#222" text-anchor="middle">U1 74AHCT1G125</text>')
    part((C2["GND"], C2["VCC"]), "#d9a066", "C2 100n", left=mirror)
    part(JP1, "#222", "JP1", vertical=False)
    part(JP2, "#222", "JP2", vertical=False)
    for name, h in J4.items():
        pad(h, "#2a9d8f", name, size=6, dy=-10)
    tx, ty = px((38, 32.4))
    o.append(f'<text x="{tx}" y="{ty}" font-size="10" fill="#1f6f66" text-anchor="middle">J4 screw terminal 5.08 mm</text>')
    for name, h in C1.items():
        pad(h, "#fff", name, size=5, dy=14)
    tx, ty = px((42, 33))
    o.append(f'<text x="{tx}" y="{ty + 3}" font-size="10" fill="#222" text-anchor="start">C1 1000 µF</text>')

    # Wires (dashed on the component side: they run on the solder side)
    dash = "" if mirror else 'stroke-dasharray="5 3" '
    for index, (wid, points, colour, _) in enumerate(routed()):
        if index not in wires:
            continue
        points = drawn(index, points)
        coords = " ".join(f"{px(p)[0]:.1f},{px(p)[1]:.1f}" for p in points)
        o.append(f'<polyline points="{coords}" fill="none" stroke="{COLOURS[colour]}" stroke-width="2.2" '
                 f'{dash}opacity="0.9" stroke-linejoin="round"/>')
        # Label on the longest segment.
        seg = max(zip(points, points[1:]), key=lambda s: abs(s[0][0] - s[1][0]) + abs(s[0][1] - s[1][1]))
        (xa, ya), (xb, yb) = px(seg[0]), px(seg[1])
        o.append(f'<text x="{(xa + xb) / 2:.1f}" y="{(ya + yb) / 2 - 3:.1f}" font-size="9" font-weight="600" fill="{COLOURS[colour]}" '
                 f'stroke="#fff" stroke-width="2.5" paint-order="stroke" text-anchor="middle">{wid}</text>')
    for gid, pin, _ in (GND_TAPS if gnd else []):
        (xa, ya), (xb, yb) = px(pin), px((pin[0], 18))
        o.append(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}" stroke="#111" stroke-width="2" {dash}/>')
        o.append(f'<text x="{xa + 7:.1f}" y="{(ya + yb) / 2:.1f}" font-size="9" font-weight="600" fill="#111" '
                 f'stroke="#fff" stroke-width="2.5" paint-order="stroke">{gid}</text>')

    # Legend
    ly = ROWS * STEP + 2 * MARGIN + 6
    side = "SOLDER SIDE: board flipped left to right, columns count down" if mirror else "COMPONENT SIDE"
    o.append(f'<text x="{MARGIN}" y="{ly + 6}" font-size="13" font-weight="700" fill="#222">{title}</text>')
    o.append(f'<text x="{MARGIN}" y="{ly + 26}" font-size="11" fill="#333">{side} · hole = 2.54 mm · '
             f'red hatched = antenna zone, keep it free · × = header pin removed</text>')
    o.append('</svg>')
    return "\n".join(o)


def hole_names():
    names = {}
    for i in range(1, 23):
        names[s3("J1", i)] = f"S3 {S3_J1[i - 1]}"
        names[s3("J3", i)] = f"S3 {S3_J3[i - 1]}"
    for i in range(1, 20):
        names[e32("J3", i)] = f"ESP32 {E32_J3[i - 1]}"
        names[e32("J2", i)] = f"ESP32 {E32_J2[i - 1]}"
    for p in range(1, 41):
        names[hat(p)] = f"HAT pin {p}"
    for n, pair in (("R1", R1), ("R2", R2), ("R3", R3), ("JP1", JP1), ("JP2", JP2), ("JP3", JP3), ("JP4", JP4)):
        names[pair[0]] = f"{n} lead 1"; names[pair[1]] = f"{n} lead 2"
    for k, v in U1.items():
        names[v] = f"U1 {k}"
    for k, v in C2.items():
        names[v] = f"C2 {k}"
    for k, v in J4.items():
        names[v] = f"J4 {k}"
    for k, v in C1.items():
        names[v] = f"C1 {k}"
    return names


def wire_table(indexes):
    names = hole_names()
    out = ["| # | Colour | From (col, row) | To (col, row) | Runs | Cut |", "|---|---|---|---|---|---|"]
    for index, (wid, points, colour, role) in enumerate(routed()):
        if index not in indexes:
            continue
        a, b = points[0], points[-1]
        via = f"row {points[1][1]}" if len(points) == 4 and points[1][1] in CHANNELS else "direct"
        out.append(f"| **{wid}** {role} | {colour} | {names[a]} ({a[0]}, {a[1]}) | {names[b]} ({b[0]}, {b[1]}) | {via} | {length_mm(points)} mm |")
    return "\n".join(out)


def gnd_table():
    names = hole_names()
    out = ["| # | From (col, row) | Bus hole | Cut |", "|---|---|---|---|"]
    for gid, pin, role in GND_TAPS:
        out.append(f"| **{gid}** | {role} ({pin[0]}, {pin[1]}) | ({pin[0]}, 18) | {length_mm([pin, (pin[0], 18)])} mm |")
    return "\n".join(out)


def parts_table():
    rows = [
        ("S3 sockets", "2 × 1×22 female header", f"row {S3_ROW_J1} and row {S3_ROW_J3}, columns 3 to 24", "pin 1 (3V3) on the right, USB on the left edge"),
        ("ESP32 sockets", "2 × 1×19 female header", f"row {E32_ROW_J3} and row {E32_ROW_J2}, columns 38 to 56", "pin 1 on the left, USB on the right edge"),
        ("HAT header", "1 × 2×20 male header, 11 mm", f"rows {HAT_EVEN_ROW} and {HAT_ODD_ROW}, columns {HAT_X0} to {HAT_X0 + 19}", "pin 1 at (5, 22); pins 2 and 4 pulled out"),
        ("R1", "2.2 kΩ", f"({R1[0][0]}, {R1[0][1]}) and ({R1[1][0]}, {R1[1][1]})", "lead 1 = 3V3, lead 2 = SDA"),
        ("R2", "2.2 kΩ", f"({R2[0][0]}, {R2[0][1]}) and ({R2[1][0]}, {R2[1][1]})", "lead 1 = 3V3, lead 2 = SCL"),
        ("R3", "330 Ω", f"({R3[0][0]}, {R3[0][1]}) and ({R3[1][0]}, {R3[1][1]})", "strip data"),
        ("JP3", "1×2 male header + jumper cap", f"({JP3[0][0]}, {JP3[0][1]}) and ({JP3[1][0]}, {JP3[1][1]})", "5 V of the ESP32; remove the cap to power it by its own USB"),
        ("JP4", "1×2 male header + jumper cap", f"({JP4[0][0]}, {JP4[0][1]}) and ({JP4[1][0]}, {JP4[1][1]})", "power mode: **cap off = mode A** (three supplies, USB on each devkit), **cap on = mode B** (single supply, no USB cable at all)"),
        ("U1", "74AHCT1G125 on a SOT23-6 to DIP-6 adapter", f"OE ({U1['OE'][0]}, {U1['OE'][1]}), A ({U1['A'][0]}, {U1['A'][1]}), GND ({U1['GND'][0]}, {U1['GND'][1]}), Y ({U1['Y'][0]}, {U1['Y'][1]}), VCC ({U1['VCC'][0]}, {U1['VCC'][1]})", "adapter pin 5 stays free; pins 1-3 on the left column"),
        ("C2", "100 nF ceramic", f"VCC ({C2['VCC'][0]}, {C2['VCC'][1]}), GND ({C2['GND'][0]}, {C2['GND'][1]})", "buffer supply decoupling"),
        ("JP1, JP2", "2 × 1×2 male header + jumper caps", f"JP1 ({JP1[0][0]}, {JP1[0][1]}) ({JP1[1][0]}, {JP1[1][1]}), JP2 ({JP2[0][0]}, {JP2[0][1]}) ({JP2[1][0]}, {JP2[1][1]})", "UART link, remove to use the ESP32's own USB console"),
        ("J4", "3-position screw terminal, 5.08 mm", f"+5V ({J4['+5V'][0]}, {J4['+5V'][1]}), DATA ({J4['DATA'][0]}, {J4['DATA'][1]}), GND ({J4['GND'][0]}, {J4['GND'][1]})", "strip and 5 V supply"),
        ("C1", "1000 µF 10 V radial, 5 mm pitch", f"+ ({C1['+'][0]}, {C1['+'][1]}), − ({C1['-'][0]}, {C1['-'][1]})", "long lead is +"),
        ("GND bus", "bare tinned wire 0.8 mm", "row 18, columns 7 to 51", "nothing else in row 18"),
    ]
    out = ["| Part | Value | Holes (col, row) | Note |", "|---|---|---|---|"]
    out += [f"| {a} | {b} | {c} | {d} |" for a, b, c, d in rows]
    return "\n".join(out)


def total_wire():
    return sum(length_mm(pts) for _, pts, _, _ in routed()) + sum(length_mm([p, (p[0], 18)]) for _, p, _ in GND_TAPS)


def tables():
    return "\n\n".join(["# Perfboard layout, generated by perfboard.py", "## Parts", parts_table(),
                         "## Wires", wire_table(set(range(len(WIRES)))), "## Ground taps", gnd_table(),
                         f"Total insulated wire: about {total_wire() / 1000:.1f} m.\n"])


STEPS = {
    "step1-ground": (range(10, 12), True, "Step 1: GND bus, pull-up resistors and the 3V3 wire"),
    "step2-amplifier": (range(0, 10), False, "Step 2: amplifier (I2S, I2C, enable, mute, error)"),
    "step3-bluetooth": (range(12, 23), False, "Step 3: Bluetooth ESP32 (I2S, UART, reset, boot, 5 V)"),
    "step4-strip": (range(23, 33), True, "Step 4: light strip (buffer, data, terminal, capacitor, JP4)"),
}

if __name__ == "__main__":
    check()
    assets = ROOT / "website/src/assets/perfboard"
    assets.mkdir(parents=True, exist_ok=True)
    for old in assets.glob("*.svg"):
        old.unlink()
    (assets / "placement.svg").write_text(render(False, title="Placement of the parts", highlight_all=True))
    for name, (indexes, gnd, title) in STEPS.items():
        (assets / f"{name}.svg").write_text(render(True, wires=set(indexes), gnd=gnd, title=title))
    (Path(__file__).parent / "layout.md").write_text(tables())
    template = (Path(__file__).parent / "page.mdx.in").read_text()
    fill = {
        "PARTS": parts_table(), "GND": gnd_table(), "TOTAL": f"{total_wire() / 1000:.1f}",
        "WIRES1": wire_table(set(STEPS["step1-ground"][0])), "WIRES2": wire_table(set(STEPS["step2-amplifier"][0])),
        "WIRES3": wire_table(set(STEPS["step3-bluetooth"][0])), "WIRES4": wire_table(set(STEPS["step4-strip"][0])),
    }
    for key, value in fill.items():
        template = template.replace("{{" + key + "}}", value)
    (ROOT / "website/src/content/docs/docs/guides/wiring-s3-perfboard.mdx").write_text(template)
    print("layout ok:", len(WIRES), "wires,", len(GND_TAPS), "ground taps")
