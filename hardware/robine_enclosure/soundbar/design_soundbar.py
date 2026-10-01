#!/usr/bin/env python3
"""Generate the Robine Wake wall-mounted sound bar with FreeCAD.

Run with FreeCAD's headless interpreter, not the system Python:

    /Applications/FreeCAD.app/Contents/Resources/bin/freecadcmd design_soundbar.py

The bar hangs flat on the headboard wall and is wired as a plain stereo
speaker on the HiFiBerry Amp2: one left and one right set, each a passive
3-way. The bottom baffle is tilted toward the sleepers' ears. Per channel:

* tweeter and midrange stacked along the slope (wall to room) in a sealed
  compartment at ±450 mm, just outside each pillow, angled toward the
  opposite pillow (crossfire) on printed wedge spacers. Each sleeper sits
  inside a wide stereo stage (spatialisation first, see ``ACOUSTICS.md``);
* woofer, flush-mounted near the centre in a vented chamber that runs from
  the centre partition to the midrange compartment. The vent is a duct along
  the front of the top panel, from the woofer chamber over the midrange and
  end compartments to the end cheek, so the bottom face carries only the
  three drivers;
* beyond the midrange compartment, a closed end compartment holds the
  crossover; on the left it is also the electronics bay (Pi and Amp2).

The reasoning and numbers are in ``ACOUSTICS.md`` and ``acoustics.py``.

Axes: X along the bar, 0 at the end on the sleepers' left (lying on the
back, head to the wall); Y from the wall (0 = back face) toward the room;
Z up (0 = lowest bottom edge). Dimensions are millimetres and collected in
``SoundbarParameters``.
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
class Driver:
    cutout: float
    flange: float
    flange_thickness: float
    body_diameter: float
    mount_depth: float


@dataclass(frozen=True)
class SoundbarParameters:
    # Overall envelope.
    length: float = 1400.0
    depth: float = 200.0
    height: float = 140.0

    # Birch plywood or MDF panels.
    panel: float = 12.0
    density_g_cm3: float = 0.68

    # Listening geometry. The baffle is aimed at the ears of a head lying on
    # the pillow; measure both on the real bed before cutting.
    head_from_wall: float = 250.0
    ears_below_baffle: float = 450.0
    pillow_offset: float = 350.0  # pillow centre to bed centre

    # Tweeter and midrange column at ±column_half_spacing from the bar
    # centre, angled by crossfire_deg toward the opposite side of the bed.
    # Along the slope, the midrange sits toward the wall, the tweeter toward
    # the room (offsets from the baffle centreline).
    column_half_spacing: float = 450.0
    crossfire_deg: float = 20.0
    mid_offset_v: float = -39.0
    tweeter_offset_v: float = 53.0
    # Woofer centre from the bar centre.
    woofer_x: float = 140.0

    # Sealed midrange compartment centred on each column, inner length along
    # X. The electronics live in the end compartment on ``bay_side``.
    mid_chamber_length: float = 120.0
    bay_side: int = -1

    # Classic compact 3-way sizes (5.25" / 3" / 1"). Generic dimensions:
    # replace with the datasheets before cutting.
    woofer: Driver = Driver(118.0, 146.0, 6.0, 114.0, 70.0)  # 5.25" woofer
    midrange: Driver = Driver(72.0, 88.0, 4.0, 70.0, 48.0)  # 3" midrange
    tweeter: Driver = Driver(50.0, 60.0, 4.0, 48.0, 30.0)  # 25 mm dome

    # Printed wedge spacers giving the crossfire angle.
    spacer_margin: float = 3.0
    spacer_min_thickness: float = 3.0
    wire_hole: float = 8.0

    # Passive 3-way crossover board, lying on the baffle in the closed end
    # compartment, toward the room (x length, width along the slope, height).
    crossover_board: tuple[float, float, float] = (120.0, 80.0, 30.0)
    crossover_offset_v: float = 15.0

    # Bass-reflex vent: a duct along the front of the top panel (a shelf and
    # a side wall), open into the woofer chamber, crossing the midrange and
    # end compartments sealed from them, out through the end cheek. Its
    # length is computed from the tuning.
    port_tuning_hz: float = 55.0
    port_width: float = 88.0
    port_slot_height: float = 22.0
    port_shelf: float = 9.0

    # The bay is closed (the firmware updates over the network) and vents
    # through slots in the top, behind the bass duct; the bottom face carries
    # drivers only.
    vent_slot_width: float = 5.0
    vent_slot_length: float = 60.0
    vent_slot_pitch: float = 14.0
    vent_slot_count: int = 7
    # Power cable: comes out of the wall behind the bay, straight through the
    # back panel.
    power_cable_hole: float = 12.0
    power_cable_hole_z: float = 70.0

    # Raspberry Pi 3 B+ with HiFiBerry Amp2 on top, mounted on the back panel.
    pi_board_x: float = 85.0
    pi_board_z: float = 56.0
    pi_hole_pitch_x: float = 58.0
    pi_hole_pitch_z: float = 49.0
    pi_standoff: float = 6.0
    pi_stack_depth: float = 34.0

    # Two recessed keyhole hanger plates on the back panel. The pockets are
    # blind, so the speaker chambers stay airtight.
    keyhole_offset_from_end: float = 150.0
    keyhole_from_top: float = 40.0
    keyhole_plate_w: float = 25.0
    keyhole_plate_h: float = 65.0
    keyhole_plate_depth: float = 3.0
    keyhole_cavity_w: float = 12.0
    keyhole_cavity_h: float = 40.0
    keyhole_cavity_depth: float = 9.0

    @property
    def tilt(self) -> float:
        dy = self.head_from_wall - self.depth / 2
        return math.atan2(dy, self.ears_below_baffle)

    @property
    def baffle_tilt_deg(self) -> float:
        return math.degrees(self.tilt)

    def spacer_od(self, driver: Driver) -> float:
        return driver.flange + 2 * self.spacer_margin

    def bay_span(self) -> tuple[float, float]:
        return self.chambers(self.bay_side)["end"]

    def chambers(self, side: int) -> dict[str, tuple[float, float]]:
        """Inner X spans of the woofer, midrange and end compartments."""
        t = self.panel
        mid = self.length / 2
        col = self.column_half_spacing
        half = self.mid_chamber_length / 2
        spans = {
            "woofer": (t / 2, col - half - t),
            "mid": (col - half, col + half),
            "end": (col + half + t, mid - t),
        }
        return {
            k: tuple(sorted((mid + side * a, mid + side * b))) for k, (a, b) in spans.items()
        }

    def bottom_z(self, y: float) -> float:
        """Z of the outer baffle surface at distance y from the wall."""
        return y * math.tan(self.tilt)


P = SoundbarParameters()

PANEL_COLOR = (0.82, 0.68, 0.48)
SPACER_COLOR = (0.30, 0.30, 0.32)
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


SIDES = (("L", -1), ("R", +1))  # sleepers' left is toward X = 0


def angled_drivers(p: SoundbarParameters):
    """(name, spec, x, v, aim): tweeter and midrange on wedges.

    ``aim`` = +1 when the driver points toward +X (the opposite pillow).
    """
    mid = p.length / 2
    out = []
    for ch, side in SIDES:
        x = mid + side * p.column_half_spacing
        out.append((f"midrange_{ch}", p.midrange, x, p.mid_offset_v, -side))
        out.append((f"tweeter_{ch}", p.tweeter, x, p.tweeter_offset_v, -side))
    return out


def flush_drivers(p: SoundbarParameters):
    """(name, spec, x): woofers in flange rebates."""
    mid = p.length / 2
    return [(f"woofer_{ch}", p.woofer, mid + side * p.woofer_x) for ch, side in SIDES]


def port_area(p: SoundbarParameters) -> float:
    """Vent duct cross-section in mm²."""
    return p.port_width * p.port_slot_height


def port_y(p: SoundbarParameters) -> tuple[float, float]:
    """Front and back limits of the duct (against the front panel)."""
    y1 = p.depth - p.panel
    return y1 - p.port_width, y1


def port_z(p: SoundbarParameters) -> tuple[float, float]:
    """Bottom and top of the vent slot."""
    top = p.height - p.panel
    return top - p.port_slot_height, top


def vent_bottom(p: SoundbarParameters) -> float:
    """Underside of the vent shelf."""
    return port_z(p)[0] - p.port_shelf


def vent_reach(p: SoundbarParameters) -> float:
    """Length from the cheek's outer face to the woofer chamber (mm)."""
    return p.chambers(-1)["woofer"][0]


def port_length(p: SoundbarParameters, gross_litres: float) -> float:
    """Physical slot length (mm) tuning the woofer chamber to ``port_tuning_hz``.

    Helmholtz resonator with the end correction of a flanged and a free end
    (1.463 equivalent radii). Only the part of the vent inside the woofer
    chamber takes volume from it, so the length is iterated.
    """
    area_m2 = port_area(p) * 1e-6
    r_eq = math.sqrt(area_m2 / math.pi)
    k = (343.0 / (2 * math.pi * p.port_tuning_hz)) ** 2
    # Cross-section the duct (air, shelf and side wall) takes from the box.
    shelf_area = (p.port_width + p.port_shelf) * (p.port_slot_height + p.port_shelf) * 1e-6
    reach = vent_reach(p) * 1e-3
    length = reach
    for _ in range(20):
        inside = max(0.0, length - reach)
        vb = gross_litres * 1e-3 - shelf_area * inside
        length = area_m2 * k / vb - 1.463 * r_eq
    return length * 1000


def driver_mount(p: SoundbarParameters, spec: Driver, x: float, v: float, aim: int):
    """Mounting point (driver flange face) and axis of an angled driver.

    The axis is the baffle normal turned by ``crossfire_deg`` toward the
    side given by ``aim``; the wedge is thinnest on that side.
    """
    centre, normal, _ = baffle_frame(p, x, v)
    a = math.radians(p.crossfire_deg)
    axis = normal * math.cos(a) + V(aim, 0, 0) * math.sin(a)
    rise = p.spacer_min_thickness + (p.spacer_od(spec) / 2) * math.tan(a)
    return centre + normal * rise, axis


def axial_cylinder(point, axis, diameter, start, length) -> Part.Shape:
    """Cylinder along ``axis``, from ``start`` mm outside ``point`` inward."""
    return Part.makeCylinder(diameter / 2, length, point + axis * start, axis * -1)


# --------------------------------------------------------------------------
# Parts


def build_panels(p: SoundbarParameters) -> dict[str, Part.Shape]:
    t = p.panel
    outer = outer_profile(p)
    inner = inner_profile(p)
    big = 10 * max(p.length, p.depth, p.height)
    mid = p.length / 2

    shell = profile_prism(outer, t, p.length - t).cut(profile_prism(inner, t - 1, p.length - t + 1))

    top = shell.common(box(-1, big, -big, big, p.height - t, big))
    back = shell.common(box(-1, big, -big, t, -big, p.height - t))
    front = shell.common(box(-1, big, p.depth - t, big, -big, p.height - t))
    baffle = shell.cut(top).cut(back).cut(front)

    # End cheeks carry the vent mouths.
    z0, z1 = port_z(p)
    y0, y1 = port_y(p)
    end_l = profile_prism(outer, 0, t).cut(box(-1, t + 1, y0, y1, z0, z1))
    end_r = profile_prism(outer, p.length - t, p.length).cut(box(p.length - t - 1, p.length + 1, y0, y1, z0, z1))

    # Partitions: bay | woofer | midrange | end compartment, each side. The
    # vent slot passes through the two midrange partitions above its shelf.
    # Wire holes are sealed with mastic after wiring.
    wire_z = vent_bottom(p) - 15
    vz0, vz1 = port_z(p)
    partitions = {}
    py0, py1 = port_y(p)

    def wall(x0: float, duct: bool) -> Part.Shape:
        part = profile_prism(inner, x0, x0 + t)
        part = part.cut(Part.makeCylinder(p.wire_hole / 2, t + 2, V(x0 - 1, t + 25, wire_z), V(1, 0, 0)))
        if duct:
            part = part.cut(box(x0 - 1, x0 + t + 1, py0, py1, vz0, vz1 + 1))
        return part

    partitions["partition_centre"] = wall(mid - t / 2, False)
    for ch, side in SIDES:
        spans = p.chambers(side)
        if side < 0:
            walls = {"mid_in": spans["mid"][1], "mid_out": spans["mid"][0] - t}
        else:
            walls = {"mid_in": spans["mid"][0] - t, "mid_out": spans["mid"][1]}
        for key, x0 in walls.items():
            partitions[f"partition_{key}_{ch}"] = wall(x0, True)

    # Angled drivers: hole along the axis, slightly oversized so the wedge,
    # not the baffle edge, frames the cone.
    for _, spec, x, v, aim in angled_drivers(p):
        point, axis = driver_mount(p, spec, x, v, aim)
        baffle = baffle.cut(axial_cylinder(point, axis, spec.cutout + 2, 5, 120))
    # Woofers: flush in a flange rebate.
    for _, spec, x in flush_drivers(p):
        baffle = baffle.cut(baffle_cylinder(p, x, spec.cutout, 5, t + 30))
        baffle = baffle.cut(baffle_cylinder(p, x, spec.flange + 1, 5, 5 + spec.flange_thickness))

    # Bay: vent slots in the top.
    bay_mid = sum(p.bay_span()) / 2
    for i in range(p.vent_slot_count):
        x = bay_mid + (i - (p.vent_slot_count - 1) / 2) * p.vent_slot_pitch
        slot_y0 = t + 10
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
    # Power cable: hole through the back panel beside the Pi, facing the
    # wall outlet.
    b0, b1 = p.bay_span()
    cable_x = b1 - p.power_cable_hole / 2 - 8 if p.bay_side < 0 else b0 + p.power_cable_hole / 2 + 8
    back = back.cut(
        Part.makeCylinder(p.power_cable_hole / 2, t + 2, V(cable_x, -1, p.power_cable_hole_z), V(0, 1, 0))
    )

    # Keyhole hangers: a shallow recess for the plate and a deeper cavity
    # behind it for the screw head, both blind from the wall side.
    zc = p.height - p.keyhole_from_top
    for x in (p.keyhole_offset_from_end, p.length - p.keyhole_offset_from_end):
        for w, h, depth in (
            (p.keyhole_plate_w, p.keyhole_plate_h, p.keyhole_plate_depth),
            (p.keyhole_cavity_w, p.keyhole_cavity_h, p.keyhole_cavity_depth),
        ):
            back = back.cut(box(x - w / 2, x + w / 2, -1, depth, zc - h / 2, zc + h / 2))

    return {
        "top": top,
        "back": back,
        "front": front,
        "baffle": baffle,
        "end_left": end_l,
        "end_right": end_r,
        **partitions,
    }


def build_vent_shelves(p: SoundbarParameters, length: float) -> dict[str, Part.Shape]:
    """Shelf forming the vent slot, from the cheek to its mouth in the woofer chamber.

    ``length`` is measured from the cheek's outer face.
    """
    t = p.panel
    z1 = port_z(p)[0]
    z0 = z1 - p.port_shelf
    top = p.height - t
    y0, y1 = port_y(p)
    out = {}
    for ch, (x0, x1) in (("L", (t, length)), ("R", (p.length - length, p.length - t))):
        shelf = box(x0, x1, y0 - p.port_shelf, y1, z0, z1)
        wall = box(x0, x1, y0 - p.port_shelf, y0, z1, top)
        out[f"port_duct_{ch}"] = shelf.fuse(wall).removeSplitter()
    return out


def build_spacers(p: SoundbarParameters) -> dict[str, Part.Shape]:
    """Printed wedge rings: flat on the baffle, angled face for the driver."""
    spacers = {}
    for name, spec, x, v, aim in angled_drivers(p):
        point, axis = driver_mount(p, spec, x, v, aim)
        ring = axial_cylinder(point, axis, p.spacer_od(spec), 0, 120)
        ring = ring.cut(baffle_slab(p, x, 400, 400, 0, 300, v))  # keep only outside the baffle
        ring = ring.cut(axial_cylinder(point, axis, spec.cutout, 5, 130))
        spacers[f"spacer_{name}"] = ring
    return spacers


def build_speakers(p: SoundbarParameters) -> dict[str, Part.Shape]:
    shapes = {}
    for name, spec, x, v, aim in angled_drivers(p):
        point, axis = driver_mount(p, spec, x, v, aim)
        ring = axial_cylinder(point, axis, spec.flange, spec.flange_thickness, spec.flange_thickness)
        body = axial_cylinder(point, axis, spec.body_diameter, 0, spec.mount_depth)
        shapes[name] = ring.fuse(body).removeSplitter()
    for name, spec, x in flush_drivers(p):
        # Flush: the flange face lies in the baffle's outer plane.
        ring = baffle_cylinder(p, x, spec.flange, 0, spec.flange_thickness)
        body = baffle_cylinder(p, x, spec.body_diameter, 0, spec.mount_depth)
        shapes[name] = ring.fuse(body).removeSplitter()
    return shapes


def build_electronics(p: SoundbarParameters) -> dict[str, Part.Shape]:
    t = p.panel
    mid = sum(p.bay_span()) / 2
    zc = vent_bottom(p) - 4 - p.pi_board_z / 2
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
    shapes = {"pi_standoffs": Part.makeCompound(standoffs), "pi3_amp2_stack": stack}
    # Crossover boards lying on the baffle in the end compartments.
    bx, bw, bh = p.crossover_board
    for ch, side in SIDES:
        e0, e1 = p.chambers(side)["end"]
        board = baffle_slab(p, (e0 + e1) / 2, bx, bw, -p.panel - 2, bh, p.crossover_offset_v)
        shapes[f"crossover_{ch}"] = board
    return shapes


# --------------------------------------------------------------------------
# Checks and reports


def run_checks(p, panels, spacers, speakers, electronics) -> list[str]:
    errors = []
    solids = {**panels, **spacers}
    for sname, sshape in {**speakers, **electronics}.items():
        for pname, pshape in solids.items():
            if sname.endswith("standoffs") and pname == "back":
                continue
            common = sshape.common(pshape)
            if common.Volume > 1.0:
                errors.append(f"{sname} intersects {pname} ({common.Volume:.0f} mm3)")
    # Footprints on the baffle (x, v, radius) must not overlap.
    prints = [(n, x, v, p.spacer_od(spec) / 2) for n, spec, x, v, _ in angled_drivers(p)]
    prints += [(n, x, 0.0, spec.flange / 2 + 1) for n, spec, x in flush_drivers(p)]
    for i, (na, xa, va, ra) in enumerate(prints):
        for nb, xb, vb, rb in prints[i + 1 :]:
            if math.hypot(xa - xb, va - vb) < ra + rb + 2:
                errors.append(f"{na} and {nb} overlap on the baffle")
    # Each driver within its chamber along X, clear of the partitions.
    for ch, side in SIDES:
        spans = p.chambers(side)
        for name, spec, x, *_ in angled_drivers(p) + [(n, s_, x_) for n, s_, x_ in flush_drivers(p)]:
            if not name.endswith(ch):
                continue
            room = "mid" if name.startswith(("midrange", "tweeter")) else "woofer"
            r = (p.spacer_od(spec) if room == "mid" else spec.flange) / 2
            x0, x1 = spans[room]
            if not (x0 + r <= x <= x1 - r):
                errors.append(f"{name} at x={x:.0f} does not fit in its {room} chamber {x0:.0f}-{x1:.0f}")
    # Footprints within the baffle face along the slope.
    half_w = p.depth / math.cos(p.tilt) / 2
    for name, x, v, r in prints:
        if abs(v) + r > half_w:
            errors.append(f"{name} runs off the baffle face")
    if p.keyhole_cavity_depth > p.panel - 2:
        errors.append("keyhole cavity leaves less than 2 mm of back panel: chamber not airtight")
    return errors


def check_vent(p: SoundbarParameters, length: float) -> list[str]:
    """The vent must open inside the woofer chamber, clear of the woofer."""
    reach = vent_reach(p)
    errors = []
    # The mouth faces the woofer chamber along X: it only has to clear the
    # midrange partition; the free space in front of it is checked below.
    if length < reach + 10:
        errors.append(
            f"vent of {length:.0f} mm does not reach into the woofer chamber (starts at {reach:.0f} mm): "
            "lower port_tuning_hz or enlarge the slot"
        )
    woofer_edge = p.length / 2 - p.woofer_x - p.woofer.flange / 2  # from the left end
    if length > woofer_edge:
        errors.append(f"vent mouth at {length:.0f} mm from the end runs over the woofer ({woofer_edge:.0f} mm)")
    _, w1 = p.chambers(-1)["woofer"]
    if w1 - length < 3 * p.port_slot_height:
        errors.append("no free space in front of the vent mouth")
    return errors


def chamber_litres(p: SoundbarParameters, solids: dict[str, Part.Shape]) -> dict[str, float]:
    """Net volume of the left midrange and woofer chambers (the right mirrors).

    ``solids`` are the parts taking room inside (drivers, boards, shelves);
    the air inside the vent slot is not counted as box volume.
    """
    litres = {}
    z0, z1 = port_z(p)
    for room, (x0, x1) in p.chambers(-1).items():
        space = profile_prism(inner_profile(p), x0, x1)
        displaced = sum(s.common(space).Volume for n, s in solids.items() if n.endswith("_L"))
        if room == "woofer" and "port_duct_L" in solids:
            # Air in the duct belongs to the vent, not to the box.
            duct = solids["port_duct_L"].common(space).BoundBox
            if duct.isValid():
                displaced += duct.XLength * p.port_width * p.port_slot_height
        litres[room] = (space.Volume - displaced) / 1e6
    return litres


def panel_rows(p, parts):
    rows = []
    for name, shape in parts.items():
        bb = shape.BoundBox
        rows.append(
            {
                "part": name,
                "x": round(bb.XLength, 1),
                "y": round(bb.YLength, 1),
                "z": round(bb.ZLength, 1),
                "mass_g": round(shape.Volume / 1000 * p.density_g_cm3),
            }
        )
    return rows


CUT_NOTES = {
    "top": "Plain top, 7 ventilation slots above the bay (left end), wall side.",
    "back": (
        f"Bottom edge bevelled at {P.baffle_tilt_deg:.1f}°, 2 blind pockets for keyhole hanger plates "
        f"({P.keyhole_plate_w:g}×{P.keyhole_plate_h:g}, {P.keyhole_cavity_depth:g} mm deep max), "
        f"Ø{P.power_cable_hole:g} cable hole in the bay, facing the wall outlet."
    ),
    "front": f"Bottom edge bevelled at {P.baffle_tilt_deg:.1f}°, R9 round-over on the outer edge.",
    "baffle": (
        f"Tilted baffle, edges bevelled at {P.baffle_tilt_deg:.1f}°. Midrange Ø{P.midrange.cutout + 2:g} and "
        f"tweeter Ø{P.tweeter.cutout + 2:g} holes drilled at {P.crossfire_deg:g}°. Woofers "
        f"Ø{P.woofer.cutout:g} with a Ø{P.woofer.flange + 1:g} rebate."
    ),
    "end_left": (
        f"Trapezoidal cheek (full profile), R9 round-over on the bottom edge, "
        f"{P.port_width:g}×{P.port_slot_height:g} vent opening at the top, room side (rounded edges)."
    ),
    "end_right": (
        f"Trapezoidal cheek (full profile), R9 round-over on the bottom edge, "
        f"{P.port_width:g}×{P.port_slot_height:g} vent opening at the top, room side (rounded edges)."
    ),
    "partition_centre": f"Airtight partition between the two woofer chambers, Ø{P.wire_hole:g} wire hole to seal.",
}
for _ch in ("L", "R"):
    CUT_NOTES[f"port_duct_{_ch}"] = (
        f"Vent duct {P.port_width:g}×{P.port_slot_height:g} mm ({P.port_shelf:g} mm plywood shelf + wall) "
        "against the front panel, from the cheek into the woofer chamber; glued airtight."
    )
    CUT_NOTES[f"partition_mid_in_{_ch}"] = (
        f"Airtight woofer / midrange partition, vent duct passage at the top, Ø{P.wire_hole:g} wire hole."
    )
    CUT_NOTES[f"partition_mid_out_{_ch}"] = (
        f"Airtight midrange / end compartment partition, vent duct passage at the top, "
        f"Ø{P.wire_hole:g} wire hole."
    )
    for _d in ("midrange", "tweeter"):
        CUT_NOTES[f"spacer_{_d}_{_ch}"] = f"3D-printed wedge spacer (PETG), {P.crossfire_deg:g}°, glued and screwed."


def write_cut_list(path: Path, p, rows, litres, errors) -> None:
    total = sum(r["mass_g"] for r in rows if not r["part"].startswith("spacer"))
    lines = [
        "# Cut list — Robine Wake sound bar",
        "",
        "Generated by `design_soundbar.py`; do not edit by hand.",
        "",
        f"- Overall size: {p.length:g} × {p.depth:g} × {p.height:g} mm (L × D × H)",
        f"- Panels: {p.panel:g} mm, baffle tilted {p.baffle_tilt_deg:.1f}° toward the ears",
        f"- 3-way per channel. Tweeter and midrange at ±{p.column_half_spacing:g} mm from the centre, angled"
        f" {p.crossfire_deg:g}° toward the opposite pillow",
        f"- Net volumes per channel: midrange {litres['mid']:.2f} L, woofer {litres['woofer']:.2f} L",
        f"- Vent: {p.port_width:g}×{p.port_slot_height:g} mm duct, {litres['port_mm']:.0f} mm long,"
        f" from the woofer chamber to the cheek, tuned to {p.port_tuning_hz:g} Hz",
        f"- Estimated mass (bar only, ρ = {p.density_g_cm3:g}): {total / 1000:.2f} kg"
        " without drivers and electronics",
        f"- Geometry checks: {'OK' if not errors else 'FAILED'}",
        "",
        "Dimensions = bounding box in mounted position (X along the bar, Y from the wall, Z vertical).",
        "",
        "| Part | X | Y | Z | Mass (g) | Notes |",
        "|---|---:|---:|---:|---:|---|",
    ]
    for r in rows:
        lines.append(
            f"| `{r['part']}` | {r['x']:g} | {r['y']:g} | {r['z']:g} | {r['mass_g']} | {CUT_NOTES.get(r['part'], '')} |"
        )
    if errors:
        lines += ["", "## Errors", ""] + [f"- {e}" for e in errors]
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
    parts_dir = out_dir / "parts"
    parts_dir.mkdir(parents=True, exist_ok=True)

    panels = build_panels(P)
    spacers = build_spacers(P)
    speakers = build_speakers(P)
    electronics = build_electronics(P)

    gross = chamber_litres(P, {**speakers, **electronics})["woofer"]
    vent = port_length(P, gross)
    shelves = build_vent_shelves(P, vent)
    panels |= shelves

    errors = run_checks(P, panels, spacers, speakers, electronics) + check_vent(P, vent)
    litres = chamber_litres(P, {**speakers, **electronics, **shelves}) | {"port_mm": vent}
    rows = panel_rows(P, {**panels, **spacers})

    doc = App.newDocument("RobineSoundbar")
    g_body = doc.addObject("App::DocumentObjectGroup", "Enclosure")
    g_ref = doc.addObject("App::DocumentObjectGroup", "Reference")
    fabricated = []
    for name, shape in panels.items():
        fabricated.append(add(doc, g_body, name, shape, PANEL_COLOR))
    for name, shape in spacers.items():
        fabricated.append(add(doc, g_body, name, shape, SPACER_COLOR))
    for name, shape in speakers.items():
        add(doc, g_ref, name, shape, DRIVER_COLOR)
    for name, shape in electronics.items():
        add(doc, g_ref, name, shape, ELECTRONICS_COLOR)
    doc.recompute()

    fcstd = out_dir / "robine-soundbar.FCStd"
    fcstd.unlink(missing_ok=True)  # avoid FreeCAD's timestamped .FCBak copies
    doc.saveAs(str(fcstd))
    Part.export(doc.Objects, str(out_dir / "robine-soundbar.step"))
    for stale in parts_dir.glob("*"):
        stale.unlink()
    for obj in fabricated:
        obj.Shape.exportStep(str(parts_dir / f"{obj.Name}.step"))
        obj.Shape.exportStl(str(parts_dir / f"{obj.Name}.stl"))

    write_cut_list(out_dir / "cut-list.md", P, rows, litres, errors)
    params = asdict(P) | {
        "baffle_tilt_deg": round(P.baffle_tilt_deg, 2),
        "mid_chamber_litres": round(litres["mid"], 3),
        "woofer_chamber_litres": round(litres["woofer"], 3),
        "port_length_mm": round(vent, 1),
        "port_area_cm2": round(port_area(P) / 100, 2),
    }
    (out_dir / "parameters.json").write_text(json.dumps(params, indent=2) + "\n")

    print(
        f"chambers: midrange {litres['mid']:.2f} L, woofer {litres['woofer']:.2f} L per side; "
        f"vent {vent:.0f} mm for {P.port_tuning_hz:g} Hz"
    )
    for e in errors:
        print(f"CHECK FAILED: {e}")
    print(f"written to {out_dir}")
    return 1 if errors else 0


# freecadcmd executes the file under its module name, not "__main__".
_code = main()
if not App.GuiUp:
    sys.exit(_code)
