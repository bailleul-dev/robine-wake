#!/usr/bin/env python3
"""Export the visible parts of the sound bar to a GLB for the WebGL viewer.

Run after ``design_soundbar.py``, with FreeCAD's headless interpreter:

    /Applications/FreeCAD.app/Contents/Resources/bin/freecadcmd export_gltf.py

Reads ``generated/robine-soundbar.FCStd`` and writes, in ``viewer/assets/``:

* ``robine-soundbar.glb``: one node per visible part, grouped by material
  family (``tolex``, ``driver``, ``housing``). The viewer replaces these
  placeholder materials with its own PBR materials;
* ``anchors.json``: bar dimensions and the position and beam axis of the
  halo and the lamps, so the viewer places its lights on the real model.

Frame: the viewer's, in metres. X along the bar from its centre (positive on
the sleepers' left, which is the viewer's right when facing the wall), Y up
from the lowest bottom edge, Z from the wall toward the room.
"""

from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

import FreeCAD as App

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "generated" / "robine-soundbar.FCStd"
PARAMS = json.loads((HERE / "generated" / "parameters.json").read_text())
OUT = HERE / "viewer" / "assets"

TOLERANCE_MM = 0.25

# Only what can be seen from outside: the casing, the drivers through their
# flush openings, and the lamp and halo modules behind their apertures.
FAMILIES = {
    "tolex": (
        "top", "front", "back", "end_left", "end_right", "baffle",
        "facet_L", "facet_R", "facet_return_L", "facet_return_R",
    ),
    "driver": ("woofer_L", "woofer_R", "midrange_L", "midrange_R", "tweeter_L", "tweeter_R"),
    "housing": ("lamp_L", "lamp_R", "halo", "halo_pod"),
}
PLACEHOLDER_COLOURS = {
    "tolex": (0.09, 0.16, 0.36, 1.0),
    "driver": (0.04, 0.04, 0.05, 1.0),
    "housing": (0.05, 0.05, 0.05, 1.0),
}

HALF_LENGTH_M = PARAMS["length"] / 2000


def to_viewer(v) -> tuple[float, float, float]:
    """FreeCAD mm (x along the bar, y from the wall, z up) to viewer metres."""
    return (HALF_LENGTH_M - v[0] / 1000, v[2] / 1000, v[1] / 1000)


def direction_to_viewer(v) -> tuple[float, float, float]:
    return (-v[0], v[2], v[1])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def normalise(v):
    n = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) or 1.0
    return (v[0] / n, v[1] / n, v[2] / n)


def box_uv(p, n) -> tuple[float, float]:
    """Box projection in metres: the two axes across the dominant normal."""
    ax = max(range(3), key=lambda i: abs(n[i]))
    if ax == 0:
        return p[2], p[1]
    if ax == 1:
        return p[0], p[2]
    return p[0], p[1]


def mesh_of(shape):
    """Positions, normals, UVs and indices; vertices are not shared between
    faces so creases stay sharp, and normals are smoothed within each face."""
    positions, normals, uvs, indices = [], [], [], []
    for face in shape.Faces:
        points, triangles = face.tessellate(TOLERANCE_MM)
        if not triangles:
            continue
        base = len(positions)
        pts = [to_viewer(p) for p in points]
        acc = [(0.0, 0.0, 0.0)] * len(pts)
        for a, b, c in triangles:
            n = cross(sub(pts[b], pts[a]), sub(pts[c], pts[a]))
            for i in (a, b, c):
                acc[i] = (acc[i][0] + n[0], acc[i][1] + n[1], acc[i][2] + n[2])
        face_normals = [normalise(n) for n in acc]
        positions += pts
        normals += face_normals
        uvs += [box_uv(p, n) for p, n in zip(pts, face_normals)]
        indices += [base + i for tri in triangles for i in tri]
    return positions, normals, uvs, indices


class GlbWriter:
    def __init__(self):
        self.binary = bytearray()
        self.json = {
            "asset": {"version": "2.0", "generator": "robine-wake export_gltf.py"},
            "scene": 0,
            "scenes": [{"nodes": []}],
            "nodes": [],
            "meshes": [],
            "materials": [],
            "accessors": [],
            "bufferViews": [],
            "buffers": [],
        }
        self.material_index = {}

    def _view(self, data: bytes, target: int) -> int:
        while len(self.binary) % 4:
            self.binary.append(0)
        self.json["bufferViews"].append(
            {"buffer": 0, "byteOffset": len(self.binary), "byteLength": len(data), "target": target}
        )
        self.binary += data
        return len(self.json["bufferViews"]) - 1

    def _accessor(self, view, component, count, kind, minimum=None, maximum=None) -> int:
        accessor = {"bufferView": view, "componentType": component, "count": count, "type": kind}
        if minimum is not None:
            accessor["min"], accessor["max"] = minimum, maximum
        self.json["accessors"].append(accessor)
        return len(self.json["accessors"]) - 1

    def material(self, family: str) -> int:
        if family not in self.material_index:
            self.json["materials"].append(
                {
                    "name": family,
                    "doubleSided": True,
                    "pbrMetallicRoughness": {
                        "baseColorFactor": list(PLACEHOLDER_COLOURS[family]),
                        "metallicFactor": 0.0,
                        "roughnessFactor": 0.8,
                    },
                }
            )
            self.material_index[family] = len(self.json["materials"]) - 1
        return self.material_index[family]

    def add(self, name: str, family: str, positions, normals, uvs, indices) -> None:
        flat_p = [c for p in positions for c in p]
        flat_n = [c for n in normals for c in n]
        flat_t = [c for t in uvs for c in t]
        pos_view = self._view(struct.pack(f"<{len(flat_p)}f", *flat_p), 34962)
        nrm_view = self._view(struct.pack(f"<{len(flat_n)}f", *flat_n), 34962)
        uv_view = self._view(struct.pack(f"<{len(flat_t)}f", *flat_t), 34962)
        idx_view = self._view(struct.pack(f"<{len(indices)}I", *indices), 34963)
        mins = [min(p[i] for p in positions) for i in range(3)]
        maxs = [max(p[i] for p in positions) for i in range(3)]
        primitive = {
            "attributes": {
                "POSITION": self._accessor(pos_view, 5126, len(positions), "VEC3", mins, maxs),
                "NORMAL": self._accessor(nrm_view, 5126, len(normals), "VEC3"),
                "TEXCOORD_0": self._accessor(uv_view, 5126, len(uvs), "VEC2"),
            },
            "indices": self._accessor(idx_view, 5125, len(indices), "SCALAR"),
            "material": self.material(family),
        }
        self.json["meshes"].append({"name": name, "primitives": [primitive]})
        self.json["nodes"].append({"name": name, "mesh": len(self.json["meshes"]) - 1, "extras": {"family": family}})
        self.json["scenes"][0]["nodes"].append(len(self.json["nodes"]) - 1)

    def write(self, path: Path) -> None:
        while len(self.binary) % 4:
            self.binary.append(0)
        self.json["buffers"] = [{"byteLength": len(self.binary)}]
        text = json.dumps(self.json, separators=(",", ":")).encode()
        text += b" " * (-len(text) % 4)
        chunks = struct.pack("<I4s", len(text), b"JSON") + text
        chunks += struct.pack("<I4s", len(self.binary), b"BIN\0") + bytes(self.binary)
        path.write_bytes(struct.pack("<4sII", b"glTF", 2, 12 + len(chunks)) + chunks)


def anchors() -> dict:
    mm = 0.001
    halo = to_viewer(PARAMS["halo_position"])
    halo_target = to_viewer(PARAMS["halo_target"])
    lamp_l = to_viewer(PARAMS["lamp_left_position"])
    axis_l = direction_to_viewer(PARAMS["lamp_left_axis"])
    # The right lamp mirrors the left one across the bar centre (X = 0).
    lamp_r = (-lamp_l[0], lamp_l[1], lamp_l[2])
    axis_r = (-axis_l[0], axis_l[1], axis_l[2])
    return {
        "bar": {
            "length": PARAMS["length"] * mm,
            "depth": PARAMS["depth"] * mm,
            "height": PARAMS["height"] * mm,
            "baffle_tilt_deg": PARAMS["baffle_tilt_deg"],
        },
        "listening": {
            "head_from_wall": PARAMS["head_from_wall"] * mm,
            "ears_below_baffle": PARAMS["ears_below_baffle"] * mm,
            "baffle_centre_height": math.tan(math.radians(PARAMS["baffle_tilt_deg"])) * PARAMS["depth"] / 2 * mm,
            "pillow_offset": PARAMS["pillow_offset"] * mm,
            "ceiling_above_top": PARAMS["ceiling_above_top"] * mm,
        },
        "halo": {
            "position": halo,
            "target": halo_target,
            "beam_deg": PARAMS["halo_beam_deg"],
            "aperture": (PARAMS["halo_diameter"] + 10) * mm,
        },
        "lamps": {
            "L": {"position": lamp_l, "axis": axis_l},
            "R": {"position": lamp_r, "axis": axis_r},
            "beam_deg": PARAMS["lamp_beam_deg"],
            "flux_lm": PARAMS["lamp_flux_lm"],
            "aperture": (PARAMS["lamp_diameter"] + 10) * mm,
        },
    }


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    doc = App.openDocument(str(SOURCE))
    writer = GlbWriter()
    count = 0
    for family, names in FAMILIES.items():
        for name in names:
            obj = doc.getObject(name)
            if obj is None:
                print(f"missing part: {name}")
                return 1
            positions, normals, uvs, indices = mesh_of(obj.Shape)
            writer.add(name, family, positions, normals, uvs, indices)
            count += len(indices) // 3
    writer.write(OUT / "robine-soundbar.glb")
    (OUT / "anchors.json").write_text(json.dumps(anchors(), indent=2) + "\n")
    size = (OUT / "robine-soundbar.glb").stat().st_size / 1024
    print(f"exported {len(writer.json['nodes'])} parts, {count} triangles, {size:.0f} KiB to {OUT}")
    return 0


sys.exit(main())
