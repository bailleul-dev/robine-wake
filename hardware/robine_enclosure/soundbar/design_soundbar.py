#!/usr/bin/env python3
"""Generate the Robine Wake wall-mounted sound bar with FreeCAD.

Run with FreeCAD's headless interpreter, not the system Python:

    /Applications/FreeCAD.app/Contents/Resources/bin/freecadcmd design_soundbar.py

The bar hangs on the headboard wall above the bed. Both speaker sets fire
through the bottom baffle, tilted by ``baffle_tilt_deg`` toward the pillow.
A central electronics bay holds the Raspberry Pi 3 B+ and HiFiBerry Amp2,
acoustically sealed from the two speaker chambers by partitions.

Axes: X along the bar (0 = left end seen from the bed), Y from the wall
(0 = back face of the bar) toward the room, Z up (0 = lowest bottom edge).
All dimensions are millimetres and collected in ``SoundbarParameters``.
"""

from __future__ import annotations

import json
import math
import os
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

import FreeCAD as App
import Part

V = App.Vector


@dataclass(frozen=True)
class SoundbarParameters:
    # Overall envelope. 900 mm spans the pillows of a 140-160 cm bed.
    length: float = 900.0
    depth: float = 120.0
    height: float = 110.0

    # Birch plywood or MDF panels.
    panel: float = 12.0
    density_g_cm3: float = 0.68

    # Bottom baffle faces down and toward the bed by this angle.
    baffle_tilt_deg: float = 15.0

    # Central electronics bay, inner length along X.
    bay_inner_length: float = 160.0

    # One speaker set per channel: a 3" class full-range driver plus a passive
    # radiator, front-mounted on the outside of the baffle. Replace with the
    # datasheet values of the chosen parts before cutting.
    driver_cutout: float = 72.0
    driver_flange: float = 88.0
    driver_flange_thickness: float = 5.0
    driver_body_diameter: float = 70.0
    driver_mount_depth: float = 48.0
    radiator_cutout: float = 72.0
    radiator_flange: float = 88.0
    radiator_mount_depth: float = 28.0
    # Driver centres measured from the outer end of the bar along X.
    driver_offset_from_end: float = 110.0
    radiator_offset_from_end: float = 280.0
    wire_hole: float = 8.0

    # Removable hatch under the electronics bay (microSD and wiring access).
    hatch_opening_x: float = 140.0
    hatch_opening_w: float = 66.0
    hatch_cover_x: float = 172.0
    hatch_cover_w: float = 98.0
    hatch_cover_thickness: float = 6.0
    hatch_screw: float = 3.5

    # Convection: slots in the hatch cover (in) and the top panel (out).
    vent_slot_width: float = 5.0
    vent_slot_length: float = 60.0
    vent_slot_pitch: float = 14.0
    vent_slot_count: int = 7

    # Raspberry Pi 3 B+ with HiFiBerry Amp2 on top, mounted on the back panel.
    pi_board_x: float = 85.0
    pi_board_z: float = 56.0
    pi_hole_pitch_x: float = 58.0
    pi_hole_pitch_z: float = 49.0
    pi_hole_inset: float = 3.5
    pi_standoff: float = 6.0
    pi_stack_depth: float = 34.0
    power_cable_hole: float = 12.0

    # French cleat for the wall.
    cleat_thickness: float = 18.0
    cleat_height: float = 55.0
    cleat_margin_x: float = 100.0
    spacer_height: float = 30.0

    @property
    def tilt(self) -> float:
        return math.radians(self.baffle_tilt_deg)

    @property
    def bay_x0(self) -> float:
        return self.length / 2 - self.bay_inner_length / 2

    @property
    def bay_x1(self) -> float:
        return self.length / 2 + self.bay_inner_length / 2

    def bottom_z(self, y: float) -> float:
        """Z of the outer baffle surface at distance y from the wall."""
        return y * math.tan(self.tilt)


P = SoundbarParameters()

PANEL_COLOR = (0.82, 0.68, 0.48)
HATCH_COLOR = (0.55, 0.42, 0.30)
CLEAT_COLOR = (0.70, 0.55, 0.38)
DRIVER_COLOR = (0.12, 0.12, 0.13)
ELECTRONICS_COLOR = (0.10, 0.45, 0.20)


# --------------------------------------------------------------------------
# Geometry helpers


def profile_prism(points_yz: list[tuple[float, float]], x0: float, x1: float) -> Part.Shape:
    pts = [V(x0, y, z) for y, z in points_yz]
    face = Part.Face(Part.makePolygon(pts + [pts[0]]))
    return face.extrude(V(x1 - x0, 0, 0))


def outer_profile(p: SoundbarParameters) -> list[tuple[float, float]]:
    return [
        (0.0, 0.0),
        (p.depth, p.bottom_z(p.depth)),
        (p.depth, p.height),
        (0.0, p.height),
    ]


def inner_profile(p: SoundbarParameters) -> list[tuple[float, float]]:
    t = p.panel
    lift = t / math.cos(p.tilt)
    return [
        (t, p.bottom_z(t) + lift),
        (p.depth - t, p.bottom_z(p.depth - t) + lift),
        (p.depth - t, p.height - t),
        (t, p.height - t),
    ]


def profile_area(points: list[tuple[float, float]]) -> float:
    return 0.5 * abs(
        sum(
            a[0] * b[1] - b[0] * a[1]
            for a, b in zip(points, points[1:] + points[:1])
        )
    )


def box(x0, x1, y0, y1, z0, z1) -> Part.Shape:
    return Part.makeBox(x1 - x0, y1 - y0, z1 - z0, V(x0, y0, z0))


def baffle_frame(p: SoundbarParameters, x: float, v: float = 0.0):
    """Point on the outer baffle at (x, v) plus the outward normal and slope.

    ``v`` is measured along the baffle slope from its centreline.
    """
    slope = V(0, math.cos(p.tilt), math.sin(p.tilt))
    normal = V(0, math.sin(p.tilt), -math.cos(p.tilt))
    y_mid = p.depth / 2
    centre = V(x, y_mid, p.bottom_z(y_mid)) + slope * v
    return centre, normal, slope


def baffle_cylinder(p, x, diameter, start, length, v=0.0) -> Part.Shape:
    """Cylinder normal to the baffle, starting ``start`` mm outside it."""
    centre, normal, _ = baffle_frame(p, x, v)
    base = centre + normal * start
    return Part.makeCylinder(diameter / 2, length, base, normal * -1)


def baffle_slab(p, x, size_x, size_w, start, thickness, v=0.0) -> Part.Shape:
    """Rectangular slab lying on the baffle plane."""
    centre, normal, slope = baffle_frame(p, x, v)
    origin = centre + normal * start - slope * (size_w / 2)
    origin.x -= size_x / 2
    u = V(size_x, 0, 0)
    w = slope * size_w
    face = Part.Face(Part.makePolygon([origin, origin + u, origin + u + w, origin + w, origin]))
    return face.extrude(normal * -thickness)


def speaker_positions(p: SoundbarParameters):
    left = [("driver_l", p.driver_offset_from_end), ("radiator_l", p.radiator_offset_from_end)]
    right = [
        ("driver_r", p.length - p.driver_offset_from_end),
        ("radiator_r", p.length - p.radiator_offset_from_end),
    ]
    return left + right


# --------------------------------------------------------------------------
# Parts


def build_panels(p: SoundbarParameters) -> dict[str, Part.Shape]:
    t = p.panel
    outer = outer_profile(p)
    inner = inner_profile(p)
    big = 10 * max(p.length, p.depth, p.height)

    shell = profile_prism(outer, t, p.length - t).cut(profile_prism(inner, t - 1, p.length - t + 1))

    top = shell.common(box(-1, big, -big, big, p.height - t, big))
    back = shell.common(box(-1, big, -big, t, -big, p.height - t))
    front = shell.common(box(-1, big, p.depth - t, big, -big, p.height - t))
    baffle = shell.cut(top).cut(back).cut(front)

    end_l = profile_prism(outer, 0, t)
    end_r = profile_prism(outer, p.length - t, p.length)

    part_l = profile_prism(inner, p.bay_x0 - t, p.bay_x0)
    part_r = profile_prism(inner, p.bay_x1, p.bay_x1 + t)
    wire_z = p.height - t - 20
    for name in ("l", "r"):
        x0 = p.bay_x0 - t if name == "l" else p.bay_x1
        hole = Part.makeCylinder(p.wire_hole / 2, t + 2, V(x0 - 1, p.depth / 2, wire_z), V(1, 0, 0))
        if name == "l":
            part_l = part_l.cut(hole)
        else:
            part_r = part_r.cut(hole)

    # Speaker cutouts.
    for name, x in speaker_positions(p):
        d = p.driver_cutout if name.startswith("driver") else p.radiator_cutout
        baffle = baffle.cut(baffle_cylinder(p, x, d, 5, t + 30))

    # Hatch opening and pilot holes for the cover screws.
    mid = p.length / 2
    baffle = baffle.cut(baffle_slab(p, mid, p.hatch_opening_x, p.hatch_opening_w, 5, t + 30))
    for sx, sv in hatch_screw_positions(p):
        baffle = baffle.cut(baffle_cylinder(p, mid + sx, 2.5, 5, 5 + t - 2, sv))

    # Top vents above the bay.
    for i in range(p.vent_slot_count):
        x = mid + (i - (p.vent_slot_count - 1) / 2) * p.vent_slot_pitch
        slot_y0 = p.depth / 2 - p.vent_slot_length / 2
        top = top.cut(
            box(
                x - p.vent_slot_width / 2,
                x + p.vent_slot_width / 2,
                slot_y0,
                slot_y0 + p.vent_slot_length,
                p.height - t - 1,
                p.height + 1,
            )
        )

    # Power cable through the back panel, inside the bay, below the boards.
    back = back.cut(
        Part.makeCylinder(p.power_cable_hole / 2, t + 2, V(mid + 55, -1, 32), V(0, 1, 0))
    )

    return {
        "top": top,
        "back": back,
        "front": front,
        "baffle": baffle,
        "end_left": end_l,
        "end_right": end_r,
        "partition_left": part_l,
        "partition_right": part_r,
    }


def hatch_screw_positions(p: SoundbarParameters):
    sx = p.hatch_cover_x / 2 - 8
    sv = p.hatch_cover_w / 2 - 8
    return [(-sx, -sv), (sx, -sv), (sx, sv), (-sx, sv)]


def build_hatch(p: SoundbarParameters) -> Part.Shape:
    mid = p.length / 2
    cover = baffle_slab(p, mid, p.hatch_cover_x, p.hatch_cover_w, p.hatch_cover_thickness, p.hatch_cover_thickness)
    for i in range(p.vent_slot_count):
        x = mid + (i - (p.vent_slot_count - 1) / 2) * p.vent_slot_pitch
        cover = cover.cut(
            baffle_slab(p, x, p.vent_slot_width, min(p.vent_slot_length, p.hatch_opening_w - 10), 10, 20)
        )
    for sx, sv in hatch_screw_positions(p):
        cover = cover.cut(baffle_cylinder(p, mid + sx, p.hatch_screw, 10, 20, sv))
    return cover


def build_cleats(p: SoundbarParameters) -> dict[str, Part.Shape]:
    c = p.cleat_thickness
    top = p.height - 5
    cut = top - p.cleat_height
    x0, x1 = p.cleat_margin_x, p.length - p.cleat_margin_x
    # The wall cleat bevel rises away from the wall, so the bar cleat's lip
    # drops into the pocket against the wall and its weight pulls it inward.
    bar_cleat = profile_prism([(0, cut + c), (0, top), (-c, top), (-c, cut)], x0, x1)
    wall_cleat = profile_prism([(0, cut - 35), (0, cut + c), (-c, cut), (-c, cut - 35)], x0, x1)
    spacer = box(x0, x1, -c, 0, 5, 5 + p.spacer_height)
    return {"cleat_bar": bar_cleat, "cleat_wall": wall_cleat, "spacer": spacer}


def build_speakers(p: SoundbarParameters) -> dict[str, Part.Shape]:
    shapes = {}
    for name, x in speaker_positions(p):
        is_driver = name.startswith("driver")
        flange = p.driver_flange if is_driver else p.radiator_flange
        depth = p.driver_mount_depth if is_driver else p.radiator_mount_depth
        body_d = p.driver_body_diameter if is_driver else p.radiator_cutout - 4
        ring = baffle_cylinder(p, x, flange, p.driver_flange_thickness, p.driver_flange_thickness)
        body = baffle_cylinder(p, x, body_d, 0, depth)
        shapes[name] = ring.fuse(body).removeSplitter()
    return shapes


def build_electronics(p: SoundbarParameters) -> dict[str, Part.Shape]:
    t = p.panel
    mid = p.length / 2
    zc = p.height - t - p.pi_board_z / 2 - 6
    y_board = t + p.pi_standoff
    standoffs = []
    for dx in (-p.pi_hole_pitch_x / 2, p.pi_hole_pitch_x / 2):
        for dz in (-p.pi_hole_pitch_z / 2, p.pi_hole_pitch_z / 2):
            standoffs.append(Part.makeCylinder(3, p.pi_standoff, V(mid + dx, t, zc + dz), V(0, 1, 0)))
    stack = box(
        mid - p.pi_board_x / 2,
        mid + p.pi_board_x / 2,
        y_board,
        y_board + p.pi_stack_depth,
        zc - p.pi_board_z / 2,
        zc + p.pi_board_z / 2,
    )
    return {"pi_standoffs": Part.makeCompound(standoffs), "pi3_amp2_stack": stack}


# --------------------------------------------------------------------------
# Checks and reports


def run_checks(p, panels, hatch, speakers, electronics) -> list[str]:
    errors = []
    solid_panels = {**panels, "hatch": hatch}
    for sname, sshape in {**speakers, **electronics}.items():
        for pname, pshape in solid_panels.items():
            if sname.endswith("standoffs") and pname == "back":
                continue
            common = sshape.common(pshape)
            if common.Volume > 1.0:
                errors.append(f"{sname} intersects {pname} ({common.Volume:.0f} mm3)")
    for name, x in speaker_positions(p):
        in_bay = p.bay_x0 - p.panel - p.driver_flange / 2 < x < p.bay_x1 + p.panel + p.driver_flange / 2
        if in_bay:
            errors.append(f"{name} overlaps the electronics bay")
    centres = sorted(x for _, x in speaker_positions(p))
    for a, b in zip(centres, centres[1:]):
        if b - a < max(p.driver_flange, p.radiator_flange) + 4:
            errors.append(f"speaker flanges at x={a:.0f} and x={b:.0f} overlap")
    return errors


def chamber_litres(p: SoundbarParameters, speakers) -> float:
    inner_len = p.bay_x0 - p.panel - p.panel
    gross = profile_area(inner_profile(p)) * inner_len
    displacement = sum(
        s.Volume for n, s in speakers.items() if n.endswith("_l")
    )
    return (gross - displacement) / 1e6


def panel_rows(p, panels, hatch, cleats):
    rows = []
    for name, shape in {**panels, "hatch": hatch, **cleats}.items():
        bb = shape.BoundBox
        rows.append(
            {
                "part": name,
                "x": round(bb.XLength, 1),
                "y": round(bb.YLength, 1),
                "z": round(bb.ZLength, 1),
                "volume_cm3": round(shape.Volume / 1000, 1),
                "mass_g": round(shape.Volume / 1000 * p.density_g_cm3),
            }
        )
    return rows


CUT_NOTES = {
    "top": "Plein dessus, 7 fentes d'aération au-dessus de la baie.",
    "back": f"Arête basse biseautée à {P.baffle_tilt_deg:g}°, perçage passe-câble Ø{P.power_cable_hole:g}.",
    "front": f"Arête basse biseautée à {P.baffle_tilt_deg:g}°.",
    "baffle": (
        f"Baffle incliné, chants biseautés à {P.baffle_tilt_deg:g}°, 4 découpes Ø{P.driver_cutout:g}, "
        f"trappe {P.hatch_opening_x:g}×{P.hatch_opening_w:g}."
    ),
    "end_left": "Joue trapézoïdale (profil complet).",
    "end_right": "Joue trapézoïdale (profil complet).",
    "partition_left": f"Cloison étanche, passe-fil Ø{P.wire_hole:g} à reboucher au mastic.",
    "partition_right": f"Cloison étanche, passe-fil Ø{P.wire_hole:g} à reboucher au mastic.",
    "hatch": f"Contreplaqué {P.hatch_cover_thickness:g} mm, 7 fentes, 4 vis Ø{P.hatch_screw:g}.",
    "cleat_bar": "Tasseau français côté barre, biseau 45°.",
    "cleat_wall": "Tasseau français côté mur, biseau 45°.",
    "spacer": "Cale basse, même épaisseur que le tasseau.",
}


def write_cut_list(path: Path, p, rows, litres, errors) -> None:
    total = sum(r["mass_g"] for r in rows if r["part"] != "cleat_wall")
    lines = [
        "# Liste de débit — barre de son Robine Wake",
        "",
        "Fichier généré par `design_soundbar.py`; ne pas éditer à la main.",
        "",
        f"- Encombrement : {p.length:g} × {p.depth:g} × {p.height:g} mm (L × P × H)",
        f"- Panneaux : {p.panel:g} mm, baffle incliné de {p.baffle_tilt_deg:g}° vers le lit",
        f"- Volume net par chambre : {litres:.2f} L",
        f"- Masse estimée (barre seule, ρ = {p.density_g_cm3:g}) : {total / 1000:.2f} kg"
        " hors haut-parleurs et électronique",
        f"- Vérifications géométriques : {'OK' if not errors else 'ÉCHEC'}",
        "",
        "Cotes = boîte englobante en position montée (X le long de la barre, Y depuis le mur, Z vertical).",
        "",
        "| Pièce | X | Y | Z | Masse (g) | Notes |",
        "|---|---:|---:|---:|---:|---|",
    ]
    for r in rows:
        lines.append(
            f"| `{r['part']}` | {r['x']:g} | {r['y']:g} | {r['z']:g} | {r['mass_g']} | {CUT_NOTES.get(r['part'], '')} |"
        )
    if errors:
        lines += ["", "## Erreurs", ""] + [f"- {e}" for e in errors]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# --------------------------------------------------------------------------
# Document


def add(doc, group, name, shape, color, transparency=0):
    obj = doc.addObject("Part::Feature", name)
    obj.Shape = shape
    group.addObject(obj)
    if App.GuiUp:
        obj.ViewObject.ShapeColor = color
        obj.ViewObject.Transparency = transparency
    else:
        # Stored so a later GUI session can restore the palette.
        obj.addProperty("App::PropertyColor", "DesignColor", "Robine")
        obj.DesignColor = color
    return obj


def main() -> int:
    out_dir = Path(os.environ.get("ROBINE_OUT", Path(__file__).resolve().parent / "generated"))
    (out_dir / "parts").mkdir(parents=True, exist_ok=True)

    panels = build_panels(P)
    hatch = build_hatch(P)
    cleats = build_cleats(P)
    speakers = build_speakers(P)
    electronics = build_electronics(P)

    errors = run_checks(P, panels, hatch, speakers, electronics)
    litres = chamber_litres(P, speakers)
    rows = panel_rows(P, panels, hatch, cleats)

    doc = App.newDocument("RobineSoundbar")
    g_body = doc.addObject("App::DocumentObjectGroup", "Enclosure")
    g_mount = doc.addObject("App::DocumentObjectGroup", "WallMount")
    g_ref = doc.addObject("App::DocumentObjectGroup", "Reference")
    fabricated = []
    for name, shape in panels.items():
        fabricated.append(add(doc, g_body, name, shape, PANEL_COLOR))
    fabricated.append(add(doc, g_body, "hatch", hatch, HATCH_COLOR))
    for name, shape in cleats.items():
        fabricated.append(add(doc, g_mount, name, shape, CLEAT_COLOR))
    for name, shape in speakers.items():
        add(doc, g_ref, name, shape, DRIVER_COLOR)
    for name, shape in electronics.items():
        add(doc, g_ref, name, shape, ELECTRONICS_COLOR)
    doc.recompute()

    fcstd = out_dir / "robine-soundbar.FCStd"
    fcstd.unlink(missing_ok=True)  # avoid FreeCAD's timestamped .FCBak copies
    doc.saveAs(str(fcstd))
    Part.export(doc.Objects, str(out_dir / "robine-soundbar.step"))
    for obj in fabricated:
        obj.Shape.exportStep(str(out_dir / "parts" / f"{obj.Name}.step"))
        obj.Shape.exportStl(str(out_dir / "parts" / f"{obj.Name}.stl"))

    write_cut_list(out_dir / "cut-list.md", P, rows, litres, errors)
    (out_dir / "parameters.json").write_text(json.dumps(asdict(P), indent=2) + "\n")

    print(f"chamber volume: {litres:.2f} L per side")
    for e in errors:
        print(f"CHECK FAILED: {e}")
    print(f"written to {out_dir}")
    return 1 if errors else 0


# freecadcmd executes the file under its module name, not "__main__".
_code = main()
if not App.GuiUp:
    sys.exit(_code)
