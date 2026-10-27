#!/usr/bin/env python3
"""Perfboard HAT for the Raspberry Pi 3: the light ESP32 and the strip connector.

The board (65 x 51 mm, 25 x 20 holes) plugs on the 40 pins of the HiFiBerry
Amp2 by a narrow strip along the header only: the Amp2 has components too tall
for a full-size HAT. The rest of the board hangs beyond the edge of the Pi, in
the air, and carries the 30-pin ESP32 devkit that runs `pi_light`, a diode for
its 5 V, the strip data resistor, the strip terminal and a capacitor, and J5, the
connector of the LoRa module (SX1276 / RFM95W) of the bedside button. One source
of truth: running this checks the layout (no hole used twice, every wire end on a
real hole, no link crossing another) and writes

  website/src/assets/perfboard-pi3/*.svg
  hardware/perfboard_pi3/layout.md
  website/src/content/docs/docs/guides/wiring-pi3-hat.mdx  (from page.mdx.in)

Holes are (column, row), column 1 at the left edge and row 1 at the top edge
of the board seen from the component side, 2.54 mm pitch. The 2x20 socket
hangs under the board, along the bottom edge, and is soldered from the
component side: its pins are on the component side, its body on the solder
side, where the wires run. The Pi's outer row (even pins) is the upper one. The
ESP32 uses four outer pins; the LoRa module needs the SPI0 pins, which are on the
inner row (row 20, the bottom edge of the board): their links hop over the outer row.
"""

import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COLS, ROWS = 25, 20

# ESP32 DevKit 30 pins (CP2102): pin names in header order, pin 1 first.
E32_LEFT = ["EN", "VP", "VN", "D34", "D35", "D32", "D33", "D25", "D26", "D27", "D14", "D12",
            "D13", "GND", "VIN"]
E32_RIGHT = ["D23", "D22", "TX0", "RX0", "D21", "D19", "D18", "D5", "TX2", "RX2", "D4", "D2",
             "D15", "GND", "3V3"]

# Turned so that the USB port faces the left edge (the SD card side of the Pi)
# and the antenna faces the middle of the board.
E32_ROW_LEFT, E32_ROW_RIGHT = 6, 15     # rows 9 holes apart = 22.86 mm
E32_PIN15_X = 4                         # the USB end; pin n is at column 19 - n
HAT_X0, HAT_EVEN_ROW, HAT_ODD_ROW = 3, 19, 20   # Pi header, pin 1 at (3, 20)
PI_EDGE_ROW = 17.6                              # edge of the Pi (3.5 mm above the outer row)


def e32(side, pin):
    """Hole of an ESP32 devkit pin: side 'L' (EN ... VIN) or 'R' (D23 ... 3V3)."""
    row = E32_ROW_LEFT if side == "L" else E32_ROW_RIGHT
    return (E32_PIN15_X + 15 - pin, row)


def E32(name, nth=0):
    if name in E32_LEFT and (name not in E32_RIGHT or nth == 0):
        return e32("L", E32_LEFT.index(name) + 1)
    return e32("R", E32_RIGHT.index(name) + 1)


def pi(pin):
    """Hole of a pin of the Pi's 40-pin header (the socket's pins on the top face)."""
    if pin % 2 == 0:
        return (HAT_X0 + pin // 2 - 1, HAT_EVEN_ROW)
    return (HAT_X0 + (pin - 1) // 2, HAT_ODD_ROW)


# Feed-through holes: the socket body covers the pads of its two rows on the
# solder side, so each header pin used is linked on the component side to a
# free hole just above the body (row 18), from where the wire goes straight up.
FEED = {2: (3, 18), 6: (5, 18), 8: (6, 18), 10: (7, 18),
        # LoRa: three straight hops over an unused pad (pins 18, 20, 22), one
        # straight link (pin 24, outer row) and two diagonals through the gap
        # between two pads (pins 23 and 25, inner row).
        17: (11, 18), 19: (12, 18), 21: (13, 18), 24: (14, 18), 23: (15, 18), 25: (16, 18)}
BODY = [(x, y) for x in range(3, 23) for y in (HAT_EVEN_ROW, HAT_ODD_ROW)]   # socket body, solder side

D1 = ((2, 16), (2, 12))      # Schottky 1N5819, anode (2, 16), cathode band (2, 12)
R3 = ((6, 4), (6, 1))        # 330 Ohm, strip data, above the devkit
J4 = {"DATA": (8, 1), "+5V": (10, 1), "GND": (12, 1)}   # 5.08 mm screw terminal, top edge
C1 = {"+": (10, 3), "-": (12, 3)}                        # 1000 uF radial, 5 mm
# J5: 1x6 male header, LoRa module (3.3 V logic). Row 17, just above the feed holes.
J5 = {"3V3": (11, 17), "MOSI": (12, 17), "MISO": (13, 17), "NSS": (14, 17), "SCLK": (15, 17), "GND": (16, 17)}

# Links on the component side: header pin pad to its feed-through hole.
LINKS = [(f"L{i + 1}", pi(p), FEED[p], role) for i, (p, role) in enumerate(
    [(2, "5 V"), (6, "GND"), (8, "TXD"), (10, "RXD"),
     (17, "3V3 (LoRa)"), (19, "MOSI (LoRa)"), (21, "MISO (LoRa)"), (24, "NSS = CE0 (LoRa)"),
     (23, "SCLK (LoRa)"), (25, "GND (LoRa)")])]

# Wires on the solder side: (id, from, to, colour, role)
WIRES = [
    ("W1", FEED[2], D1[0], "red", "Pi 5 V to the diode"),
    ("W2", D1[1], E32("VIN"), "red", "diode to the ESP32 VIN"),
    ("W3", FEED[6], e32("R", 14), "black", "Pi GND to the ESP32 GND"),
    ("W4", FEED[8], E32("D18"), "white", "Pi TXD to the ESP32 RX (D18)"),
    ("W5", E32("TX2"), FEED[10], "white", "ESP32 TX (TX2) to the Pi RXD"),
    ("W6", E32("D13"), R3[0], "gray", "strip data to the resistor"),
    ("W7", R3[1], J4["DATA"], "gray", "resistor to the terminal"),
    ("W8", C1["+"], J4["+5V"], "red", "capacitor + to the terminal +5 V"),
    ("W9", C1["-"], J4["GND"], "black", "capacitor − to the terminal GND"),
    ("W10", C1["-"], e32("L", 14), "black", "capacitor − (ground) to the ESP32 GND"),
    ("W11", FEED[17], J5["3V3"], "orange", "Pi 3.3 V to J5"),
    ("W12", FEED[19], J5["MOSI"], "green", "Pi MOSI to J5"),
    ("W13", FEED[21], J5["MISO"], "green", "Pi MISO to J5"),
    ("W14", FEED[24], J5["NSS"], "green", "Pi CE0 to J5 NSS"),
    ("W15", FEED[23], J5["SCLK"], "green", "Pi SCLK to J5"),
    ("W16", FEED[25], J5["GND"], "black", "Pi GND to J5"),
]
# Corners of each path. Every wire runs in the rows between the header and the
# devkit (16 to 18) or in the rows above it (1 to 5), or down the free columns
# 1 to 3 on the left: nothing runs over a pad or under the socket body. W4 and W5
# cross at (10, 16) (W4 and W5) and at (6, 5) (W10 over W6): insulated wires lie
# one over the other.
ROUTES = {
    "W1": [(3, 16)],
    "W2": [(2, 6), (3, 6)],
    "W3": [],
    "W4": [(6, 16), (12, 16)],
    "W5": [(10, 17), (7, 17)],
    "W6": [],
    "W7": [],
    "W8": [],
    "W9": [],
    "W10": [(12, 5), (5, 5)],
    "W11": [], "W12": [], "W13": [], "W14": [], "W15": [], "W16": [],
}
LANES = {}
LANE_PX = 5


def lane_points(wid, points):
    k = LANES.get(wid, 0) * LANE_PX
    return [points[0], *[(x, y) for x, y in points[1:-1]], points[-1]] if not k else points


COLOURS = {"green": "#2e9e4a", "orange": "#e07b00", "white": "#7d8590", "red": "#d62f2f",
           "gray": "#555b66", "black": "#111111"}


def occupied():
    holes = {}

    def put(hole, what):
        assert 1 <= hole[0] <= COLS and 1 <= hole[1] <= ROWS, (what, hole)
        assert hole not in holes, f"hole {hole} used by {holes[hole]} and {what}"
        holes[hole] = what

    for i in range(1, 16):
        put(e32("L", i), f"ESP32 L{i}")
        put(e32("R", i), f"ESP32 R{i}")
    for p in range(1, 41):
        put(pi(p), f"Pi header {p}")
    for p, hole in FEED.items():
        put(hole, f"feed {p}")
    for name, pair in (("D1", D1), ("R3", R3)):
        put(pair[0], f"{name}.1")
        put(pair[1], f"{name}.2")
    for k, v in J4.items():
        put(v, f"J4 {k}")
    for k, v in C1.items():
        put(v, f"C1 {k}")
    for k, v in J5.items():
        put(v, f"J5 {k}")
    return holes


def check():
    holes = occupied()
    for wid, a, b, _, _ in WIRES:
        assert a in holes, f"{wid}: start {a} is not a pin or a lead"
        assert b in holes, f"{wid}: end {b} is not a pin or a lead"
    check_links(holes)
    # No wire may run over another net's pad, nor under the socket body.
    for wid, a, b, _, _ in WIRES:
        points = route(wid, a, b)
        for p, q in zip(points, points[1:]):
            assert p[0] == q[0] or p[1] == q[1], f"{wid}: segment {p}->{q} is not straight"
            n = max(abs(p[0] - q[0]), abs(p[1] - q[1]))
            for i in range(n + 1):
                hole = (p[0] + (q[0] - p[0]) * i // max(n, 1), p[1] + (q[1] - p[1]) * i // max(n, 1))
                assert hole not in BODY, f"{wid} runs under the socket body at {hole}"
                if hole in holes and hole not in (a, b) and holes[hole] != holes.get(a) and holes[hole] != holes.get(b):
                    raise AssertionError(f"{wid} runs over {holes[hole]} at {hole}")
    assert E32("D18") == e32("R", 7) and E32("TX2") == e32("R", 9)
    assert pi(2)[1] == pi(6)[1] == pi(8)[1] == pi(10)[1] == HAT_EVEN_ROW, "the four ESP32 pins are on the outer row"
    spi = {"3V3": 17, "MOSI": 19, "MISO": 21, "SCLK": 23, "NSS": 24, "GND": 25}   # SPI0 + CE0 of the Pi
    for name, pin in spi.items():
        assert FEED[pin] == (J5[name][0], J5[name][1] + 1), f"J5 {name} is not fed by header pin {pin}"
    assert E32("VIN") == e32("L", 15) and E32("D13") == e32("L", 13)
    return holes


def link_cut_mm(a, b):
    """Insulated wire of a link: the run plus 9 mm to strip and tin both ends."""
    return math.ceil(math.hypot(a[0] - b[0], a[1] - b[1]) * 2.54 + 9)


def check_links(holes):
    """A link joins a header pad to a free hole: adjacent, diagonal, or two rows up. It may pass
    over an unused pad of the socket, never over a linked pad, and never cross another link."""
    pads = {a for _, a, _, _ in LINKS}
    for lid, a, b, _ in LINKS:
        assert a in holes and b in holes, lid
        dx, dy = abs(a[0] - b[0]), a[1] - b[1]
        assert dx <= 1 and dy in (1, 2), f"{lid}: link too long"
        if dx == 0 and dy == 2:
            middle = (a[0], a[1] - 1)
            assert middle in holes and middle not in pads, f"{lid} passes over a linked pad {middle}"

    def side(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])

    for i, (l1, a1, b1, _) in enumerate(LINKS):
        for l2, a2, b2, _ in LINKS[i + 1:]:
            if {a1, b1} & {a2, b2}:
                continue
            crossing = side(a1, b1, a2) * side(a1, b1, b2) < 0 and side(a2, b2, a1) * side(a2, b2, b1) < 0
            assert not crossing, f"{l1} crosses {l2}"


def route(wid, a, b):
    """Solder-side polyline of a wire: its start, the corners of ROUTES, its end."""
    return [a, *ROUTES[wid], b]


def path_len(points):
    return sum(abs(p[0] - q[0]) + abs(p[1] - q[1]) for p, q in zip(points, points[1:]))


def length_mm(points):
    """Insulated wire to cut: the run plus 20 mm to strip and tin both ends."""
    return round(path_len(points) * 2.54 + 20)


def routed():
    return [(wid, route(wid, a, b), colour, role) for wid, a, b, colour, role in WIRES]


def hole_names():
    names = {}
    for i in range(1, 16):
        names[e32("L", i)] = f"ESP32 {E32_LEFT[i - 1]}"
        names[e32("R", i)] = f"ESP32 {E32_RIGHT[i - 1]}"
    for p in range(1, 41):
        names[pi(p)] = f"Pi pin {p}"
    for p, hole in FEED.items():
        names[hole] = f"feed hole of Pi pin {p}"
    for k, v in J5.items():
        names[v] = f"J5 {k}"
    names[D1[0]] = "D1 anode"; names[D1[1]] = "D1 cathode (band)"
    names[R3[0]] = "R3 lead 1"; names[R3[1]] = "R3 lead 2"
    for k, v in J4.items():
        names[v] = f"J4 {k}"
    for k, v in C1.items():
        names[v] = f"C1 {k}"
    return names


def wire_table(indexes):
    names = hole_names()
    out = ["| # | Colour | From (col, row) | To (col, row) | Cut |", "|---|---|---|---|---|"]
    for index, (wid, points, colour, role) in enumerate(routed()):
        if index in indexes:
            a, b = points[0], points[-1]
            out.append(f"| **{wid}** {role} | {colour} | {names[a]} ({a[0]}, {a[1]}) | {names[b]} ({b[0]}, {b[1]}) | {length_mm(points)} mm |")
    return "\n".join(out)


def link_table():
    names = hole_names()
    out = ["| # | Joins (component side) | Wire |", "|---|---|---|"]
    for lid, a, b, role in LINKS:
        out.append(f"| **{lid}** {role} | {names[a]} ({a[0]}, {a[1]}) and its feed hole ({b[0]}, {b[1]}) | {link_cut_mm(a, b)} mm insulated, soldered on the component side |")
    return "\n".join(out)


def parts_table():
    rows = [
        ("Pi socket", "1 × 2×20 female header, 2.54 mm", f"rows {HAT_EVEN_ROW} and {HAT_ODD_ROW}, columns {HAT_X0} to {HAT_X0 + 19}", f"body under the board, pin 1 at ({pi(1)[0]}, {pi(1)[1]})"),
        ("ESP32 sockets", "2 × 1×15 female header", f"row {E32_ROW_LEFT} and row {E32_ROW_RIGHT}, columns 4 to 18", "pin 1 on the right, USB on the left edge, antenna end hangs in the air"),
        ("D1", "Schottky 1N5819", f"anode ({D1[0][0]}, {D1[0][1]}), cathode ({D1[1][0]}, {D1[1][1]})", "band on the cathode side"),
        ("R3", "330 Ω", f"({R3[0][0]}, {R3[0][1]}) and ({R3[1][0]}, {R3[1][1]})", "strip data"),
        ("J4", "3-position screw terminal, 5.08 mm", f"DATA ({J4['DATA'][0]}, {J4['DATA'][1]}), +5V ({J4['+5V'][0]}, {J4['+5V'][1]}), GND ({J4['GND'][0]}, {J4['GND'][1]})", "strip and 5 V supply, wires toward the top edge"),
        ("C1", "1000 µF 10 V radial, 5 mm pitch", f"+ ({C1['+'][0]}, {C1['+'][1]}), − ({C1['-'][0]}, {C1['-'][1]})", "long lead is +"),
        ("J5", "1 × 6 male pin header, 2.54 mm", "row 17, columns 11 to 16: " + ", ".join(f"{k} ({v[0]}, {v[1]})" for k, v in J5.items()), "LoRa module, 3.3 V only; plastic on the component side"),
    ]
    out = ["| Part | Value | Holes (col, row) | Note |", "|---|---|---|---|"]
    out += [f"| {a} | {b} | {c} | {d} |" for a, b, c, d in rows]
    return "\n".join(out)


def total_wire():
    return sum(length_mm(pts) for _, pts, _, _ in routed()) + sum(link_cut_mm(a, b) for _, a, b, _ in LINKS)


def tables():
    return "\n\n".join(["# Perfboard HAT layout, generated by perfboard.py", "## Parts", parts_table(),
                        "## Links (component side)", link_table(), "## Wires (solder side)",
                        wire_table(set(range(len(WIRES)))), f"Total wire: about {total_wire() / 1000:.2f} m.\n"])


# --- Drawing ----------------------------------------------------------------
STEP, MARGIN = 26, 34


def render(mirror, wires=(), links=False, title="", highlight_all=False):
    width = COLS * STEP + 2 * MARGIN
    height = ROWS * STEP + 2 * MARGIN + 80

    def px(h):
        x = (COLS + 1 - h[0]) if mirror else h[0]
        return MARGIN + (x - 0.5) * STEP, MARGIN + (h[1] - 0.5) * STEP

    def rect(x0, y0, x1, y1):
        a, b = px((x0, y0)), px((x1, y1))
        return min(a[0], b[0]), min(a[1], b[1]), abs(a[0] - b[0]), abs(a[1] - b[1])

    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
         f'font-family="system-ui, sans-serif" role="img" aria-label="Pi 3 HAT layout, '
         f'{"solder side" if mirror else "component side"}">',
         f'<rect width="{width}" height="{height}" fill="#ffffff"/>']
    x, y, w, h = rect(0.5, 0.5, COLS + 0.5, ROWS + 0.5)
    o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="#e9f0e4" stroke="#6b7f63" stroke-width="2"/>')

    def box(x0, y0, x1, y1, fill, stroke, label=None, lx=None, ly=None, dash=False):
        x, y, w, h = rect(x0, y0, x1, y1)
        d = ' stroke-dasharray="6 4"' if dash else ""
        o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="{stroke}" stroke-width="1.5"{d} opacity="{0.45 if mirror else 1}"/>')
        if label:
            tx, ty = px((lx, ly))
            o.append(f'<text x="{tx}" y="{ty}" font-size="12" fill="#333" text-anchor="middle">{label}</text>')

    box(1.5, E32_ROW_LEFT - 0.5, 22.3, E32_ROW_RIGHT + 0.5, "#fde9d2", "#d9822b", "ESP32 DevKit 30 pins (CP2102)", lx=14, ly=10.5)
    box(19.9, E32_ROW_LEFT - 0.5, 22.3, E32_ROW_RIGHT + 0.5, "#f6c6c6", "#c0392b", None, dash=True)
    box(HAT_X0 - 0.5, HAT_EVEN_ROW - 0.5, HAT_X0 + 19.5, HAT_ODD_ROW + 0.5, "#dfe3ea", "#6b7684", None, dash=True)  # socket body, underneath

    ex0, ey = px((0.5, PI_EDGE_ROW))
    ex1, _ = px((COLS + 0.5, PI_EDGE_ROW))
    o.append(f'<line x1="{ex0:.1f}" y1="{ey:.1f}" x2="{ex1:.1f}" y2="{ey:.1f}" stroke="#444" stroke-width="2" stroke-dasharray="10 5"/>')
    o.append(f'<text x="{(ex1 - 6) if not mirror else (ex1 + 6):.1f}" y="{ey + 14:.1f}" font-size="11" fill="#444" '
             f'text-anchor="{"end" if not mirror else "start"}">edge of the Pi</text>')

    for yy in range(1, ROWS + 1):
        for xx in range(1, COLS + 1):
            cx, cy = px((xx, yy))
            o.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="2" fill="#b9c4b2"/>')
    for xx in range(1, COLS + 1):
        if xx % 5 == 0 or xx == 1:
            cx, _ = px((xx, 1))
            o.append(f'<text x="{cx:.1f}" y="{MARGIN - 14}" font-size="11" fill="#555" text-anchor="middle">{xx}</text>')
    for yy in range(1, ROWS + 1):
        if yy % 5 == 0 or yy == 1:
            _, cy = px((1, yy))
            o.append(f'<text x="{MARGIN - 16}" y="{cy + 4:.1f}" font-size="11" fill="#555" text-anchor="middle">{yy}</text>')

    used = set()
    for index, (_, a, b, _, _) in enumerate(WIRES):
        if highlight_all or index in wires:
            used.update((a, b))
    if highlight_all or links:
        for _, a, b, _ in LINKS:
            used.update((a, b))

    def pad(hole, fill, label=None, size=5.5, dy=-9, rotate=False):
        cx, cy = px(hole)
        o.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{size}" fill="{fill}" stroke="#222" stroke-width="0.9"/>')
        if label and rotate:
            angle = -90 if dy < 0 else 90
            o.append(f'<text transform="translate({cx:.1f} {cy + dy:.1f}) rotate({angle})" font-size="10" fill="#222" '
                     f'text-anchor="start" dominant-baseline="central">{label}</text>')
        elif label:
            o.append(f'<text x="{cx:.1f}" y="{cy + dy:.1f}" font-size="10" fill="#222" text-anchor="middle">{label}</text>')

    for p in range(1, 41):
        hole = pi(p)
        on = hole in used
        pad(hole, "#c58b00" if on else "#e2c77a", str(p) if on else None, size=5.5, dy=-9 if p % 2 == 0 else 17)
    for i in range(1, 16):
        for side, names, row in (("L", E32_LEFT, E32_ROW_LEFT), ("R", E32_RIGHT, E32_ROW_RIGHT)):
            hole = e32(side, i)
            pad(hole, "#d9822b" if hole in used else "#efc9a0", names[i - 1] if hole in used else None,
                dy=-10 if side == "L" else 10, rotate=True)
    for p, hole in FEED.items():
        pad(hole, "#fff", None, size=5)
        cx, cy = px(hole)
        o.append(f'<text x="{cx:.1f}" y="{cy - 9:.1f}" font-size="9" fill="#555" text-anchor="middle">F{p}</text>')

    def part(pair, fill, label, side="r"):
        (xa, ya), (xb, yb) = px(pair[0]), px(pair[1])
        o.append(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}" stroke="#444" stroke-width="9" stroke-linecap="round"/>')
        o.append(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}" stroke="{fill}" stroke-width="5" stroke-linecap="round"/>')
        pad(pair[0], "#fff", size=5); pad(pair[1], "#fff", size=5)
        mx, my = (xa + xb) / 2, (ya + yb) / 2
        if xa == xb:
            o.append(f'<text x="{mx + (12 if side == "r" else -12):.1f}" y="{my + 4:.1f}" font-size="11" fill="#222" text-anchor="{"start" if side == "r" else "end"}">{label}</text>')
        else:
            o.append(f'<text x="{mx:.1f}" y="{my - 10:.1f}" font-size="11" fill="#222" text-anchor="middle">{label}</text>')

    part(D1, "#9aa", "D1", side="l")
    part(R3, "#e8c08a", "R3 330")
    for name, hole in J4.items():
        pad(hole, "#2a9d8f", name, size=7, dy=-12)
    tx, ty = px((14, 1))
    o.append(f'<text x="{tx}" y="{ty + 4}" font-size="11" fill="#1f6f66" text-anchor="{"end" if mirror else "start"}">J4 screw terminal 5.08 mm (wires leave by the top edge)</text>')
    for name, hole in C1.items():
        pad(hole, "#fff", name, size=6, dy=-10)
    tx, ty = px((14, 3))
    o.append(f'<text x="{tx}" y="{ty + 4}" font-size="11" fill="#222" text-anchor="{"end" if mirror else "start"}">C1 1000 µF</text>')
    # Rotated pin names above J5 when a step shows it alone; on the placement plan they would
    # print over the ESP32 pin names, so the order goes in a caption instead.
    named = not highlight_all and any(index >= 10 for index in wires)
    for name, hole in J5.items():
        pad(hole, "#2a9d8f", name if named else None, size=6, dy=-10, rotate=True)
    anchor = "end" if mirror else "start"
    tx, ty = px((17.2, 16.4 if highlight_all else 17))
    o.append(f'<text x="{tx:.1f}" y="{ty + 4:.1f}" font-size="11" fill="#1f6f66" text-anchor="{anchor}">J5 LoRa (3.3 V)</text>')
    if highlight_all:
        tx, ty = px((17.2, 17.0))
        o.append(f'<text x="{tx:.1f}" y="{ty:.1f}" font-size="10" fill="#1f6f66" text-anchor="start">'
                 f'3V3 · MOSI · MISO · NSS · SCLK · GND</text>')

    dash = "" if mirror else 'stroke-dasharray="6 4" '
    for index, (wid, points, colour, _) in enumerate(routed()):
        if index not in wires:
            continue
        k = LANES.get(wid, 0) * LANE_PX * (-1 if mirror else 1)
        pts = [px(p) for p in points]
        # push the corners (not the ends) of the path into their lane
        pts = [pts[0], *[(x + k, y + abs(k)) for x, y in pts[1:-1]], pts[-1]] if k else pts
        coords = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
        o.append(f'<polyline points="{coords}" fill="none" stroke="{COLOURS[colour]}" stroke-width="3" {dash}opacity="0.92" stroke-linejoin="round"/>')
        seg = max(zip(pts, pts[1:]), key=lambda s: abs(s[0][0] - s[1][0]) + abs(s[0][1] - s[1][1]))
        (xa, ya), (xb, yb) = seg
        o.append(f'<text x="{(xa + xb) / 2:.1f}" y="{(ya + yb) / 2 - 4:.1f}" font-size="11" font-weight="700" fill="{COLOURS[colour]}" '
                 f'stroke="#fff" stroke-width="3" paint-order="stroke" text-anchor="middle">{wid}</text>')
    if links:
        for lid, a, b, _ in LINKS:
            (xa, ya), (xb, yb) = px(a), px(b)
            o.append(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}" stroke="#e07b00" stroke-width="4" stroke-linecap="round"/>')
            o.append(f'<text x="{xb:.1f}" y="{yb - 16:.1f}" font-size="10" font-weight="700" fill="#e07b00" text-anchor="middle">{lid}</text>')

    ly = ROWS * STEP + 2 * MARGIN + 6
    side = "SOLDER SIDE (flipped), columns count down" if mirror else "COMPONENT SIDE"
    o.append(f'<text x="{MARGIN}" y="{ly + 8}" font-size="14" font-weight="700" fill="#222">{title}</text>')
    o.append(f'<text x="{MARGIN}" y="{ly + 30}" font-size="12" fill="#333">{side} · hole = 2.54 mm · '
             f'red hatched = antenna zone, keep it free</text>')
    o.append(f'<text x="{MARGIN}" y="{ly + 48}" font-size="12" fill="#333">grey dashed = Pi socket body (solder side) · '
             f'dashed line = edge of the Pi and the Amp2: above it the board hangs in the air</text>')
    o.append("</svg>")
    return "\n".join(o)


STEPS = {
    "step1-links": (range(0), True, False, "Step 1: link the ten header pins to their feed holes (component side)"),
    "step2-power-uart": (range(0, 5), False, True, "Step 2: 5 V, GND and UART to the Pi"),
    "step3-strip": (range(5, 10), False, True, "Step 3: light strip (data, terminal, capacitor, ground)"),
    "step4-lora": (range(10, 16), False, True, "Step 4: LoRa connector J5 (3.3 V, SPI0, CE0, ground)"),
}

if __name__ == "__main__":
    check()
    assets = ROOT / "website/src/assets/perfboard-pi3"
    assets.mkdir(parents=True, exist_ok=True)
    for old in assets.glob("*.svg"):
        old.unlink()
    (assets / "placement.svg").write_text(render(False, title="Placement of the parts", highlight_all=True))
    for name, (indexes, links, mirror, title) in STEPS.items():
        (assets / f"{name}.svg").write_text(render(mirror, wires=set(indexes), links=links, title=title))
    (Path(__file__).parent / "layout.md").write_text(tables())
    template = (Path(__file__).parent / "page.mdx.in").read_text()
    fill = {"PARTS": parts_table(), "LINKS": link_table(), "TOTAL": f"{total_wire() / 1000:.1f}",
            "WIRES2": wire_table(set(STEPS["step2-power-uart"][0])), "WIRES3": wire_table(set(STEPS["step3-strip"][0])),
            "WIRES4": wire_table(set(STEPS["step4-lora"][0]))}
    for key, value in fill.items():
        template = template.replace("{{" + key + "}}", value)
    (ROOT / "website/src/content/docs/docs/guides/wiring-pi3-hat.mdx").write_text(template)
    print("layout ok:", len(WIRES), "wires,", len(LINKS), "links")
