#!/usr/bin/env python3
"""Generate a printable enclosure for the Heltec WiFi Kit 32 V1.

Run with Blender, not the system Python:

    blender --background --python design_enclosure.py -- --variant all --render

The dimensions are intentionally collected in ``EnclosureParameters`` so a fit
test can be adjusted without remodeling the case by hand.
"""

from __future__ import annotations

import argparse
import math
import sys
from dataclasses import dataclass, replace
from pathlib import Path

import bpy
from mathutils import Vector


@dataclass(frozen=True)
class EnclosureParameters:
    # Manufacturer nominal board dimensions. The official reference mesh is
    # 52 x 25 mm in its front plane.
    board_width: float = 52.0
    board_height: float = 25.0
    board_depth: float = 11.0

    # FDM-friendly defaults for a 0.4 mm nozzle.
    fit_clearance: float = 0.30
    wall: float = 2.0
    back: float = 2.4
    face_thickness: float = 2.2
    corner_radius: float = 3.2

    # Front features, measured from the center of the PCB. These values are
    # based on the V1 product photo and remain easy to tune after a paper fit.
    screen_center_x: float = 10.5
    screen_center_z: float = 3.7
    screen_width: float = 27.5
    screen_height: float = 15.0
    button_center_x: float = -18.6
    button_center_z: float = 6.7
    button_hole_diameter: float = 5.2

    # The micro-USB socket exits through the left-hand short edge.
    usb_center_z: float = 0.0
    usb_height: float = 8.0
    usb_depth: float = 10.5

    @property
    def outer_width(self) -> float:
        return self.board_width + 2 * (self.wall + 2.0)

    @property
    def outer_height(self) -> float:
        return self.board_height + 2 * (self.wall + 2.0)

    @property
    def inner_width(self) -> float:
        return self.outer_width - 2 * self.wall

    @property
    def inner_height(self) -> float:
        return self.outer_height - 2 * self.wall

    @property
    def inner_depth(self) -> float:
        return self.board_depth + 1.2

    @property
    def outer_depth(self) -> float:
        return self.inner_depth + self.back


SLIM = EnclosureParameters()
HEADERS = replace(SLIM, board_depth=27.0)


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", choices=("slim", "headers", "all"), default="all")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path(__file__).resolve().parent / "generated",
    )
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--board-stl", type=Path)
    return parser.parse_args(argv)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def apply_transform(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def rounded_box(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    radius: float,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    apply_transform(obj)
    if radius > 0:
        modifier = obj.modifiers.new("printable_rounding", "BEVEL")
        modifier.width = min(radius, min(size) / 2 - 0.01)
        modifier.segments = 4
        modifier.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


def cylinder_y(
    name: str,
    diameter: float,
    length: float,
    location: tuple[float, float, float],
    vertices: int = 48,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=diameter / 2,
        depth=length,
        location=location,
        rotation=(math.pi / 2, 0, 0),
    )
    obj = bpy.context.object
    obj.name = name
    return obj


def boolean(target: bpy.types.Object, cutter: bpy.types.Object, operation: str) -> None:
    modifier = target.modifiers.new(f"{operation.lower()}_{cutter.name}", "BOOLEAN")
    modifier.operation = operation
    modifier.solver = "EXACT"
    modifier.object = cutter
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def join(name: str, objects: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    return objects[0]


def clean_mesh(obj: bpy.types.Object, merge_distance: float = 0.001) -> None:
    """Remove coincident boolean vertices and zero-area fragments."""
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=merge_distance)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=merge_distance)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def prepare_print_mesh(obj: bpy.types.Object) -> None:
    """Triangulate and remove duplicate faces before STL serialization."""
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.001)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.verts.index_update()

    seen: set[tuple[int, ...]] = set()
    duplicates = []
    for face in bm.faces:
        key = tuple(sorted(vertex.index for vertex in face.verts))
        if key in seen:
            duplicates.append(face)
        else:
            seen.add(key)
    if duplicates:
        bmesh.ops.delete(bm, geom=duplicates, context="FACES")

    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def build_base(p: EnclosureParameters) -> bpy.types.Object:
    base = rounded_box(
        "base",
        (p.outer_width, p.outer_depth, p.outer_height),
        (0, p.outer_depth / 2, 0),
        p.corner_radius,
    )

    # Open cavity, extending slightly beyond the front to avoid coplanar faces.
    cavity_depth = p.outer_depth - p.back + 0.6
    cavity = rounded_box(
        "cavity",
        (p.inner_width, cavity_depth, p.inner_height),
        (0, -0.3 + cavity_depth / 2, 0),
        max(1.0, p.corner_radius - p.wall),
    )
    boolean(base, cavity, "DIFFERENCE")

    # Left-side micro-USB opening. Its generous height accommodates connector
    # shell and common molded cables.
    usb = rounded_box(
        "usb_cutout",
        # Deliberately overlap the inner cavity by 0.4 mm. A merely tangent
        # boolean surface can leave non-manifold edges in the shallow variant.
        (p.wall + 2.8, p.usb_depth, p.usb_height),
        (-p.outer_width / 2, p.usb_depth / 2 + 0.5, p.usb_center_z),
        1.2,
    )
    boolean(base, usb, "DIFFERENCE")

    # Narrow rear vents keep the ESP32 comfortable while remaining bridgeable.
    for index, z in enumerate((-6.0, -2.0, 2.0, 6.0)):
        vent = rounded_box(
            f"rear_vent_{index}",
            (24.0, p.back + 1.0, 1.6),
            (7.0, p.outer_depth - p.back / 2, z),
            0.7,
        )
        boolean(base, vent, "DIFFERENCE")

    clean_mesh(base)
    return base


def build_face(p: EnclosureParameters) -> bpy.types.Object:
    face = rounded_box(
        "face",
        (p.outer_width - 0.25, p.face_thickness, p.outer_height - 0.25),
        (0, -p.face_thickness / 2, 0),
        p.corner_radius - 0.15,
    )

    screen = rounded_box(
        "screen_window",
        (p.screen_width, p.face_thickness + 2.0, p.screen_height),
        (p.screen_center_x, -p.face_thickness / 2, p.screen_center_z),
        1.4,
    )
    boolean(face, screen, "DIFFERENCE")

    button_hole = cylinder_y(
        "button_hole",
        p.button_hole_diameter,
        p.face_thickness + 2.0,
        (p.button_center_x, -p.face_thickness / 2, p.button_center_z),
    )
    boolean(face, button_hole, "DIFFERENCE")

    # A shallow tongue centers the cover in the rear shell and also locates the
    # PCB. The 0.30 mm per-side clearance is suitable for a first FDM fit test.
    tongue_depth = 2.6
    tongue_wall = 0.9
    tongue_outer_w = p.inner_width - 2 * p.fit_clearance
    tongue_outer_h = p.inner_height - 2 * p.fit_clearance
    tongue_parts = [
            rounded_box(
                "tongue_top",
                (tongue_outer_w, tongue_depth, tongue_wall),
                (0, tongue_depth / 2 - 0.2, tongue_outer_h / 2 - tongue_wall / 2),
                0.35,
            ),
            rounded_box(
                "tongue_bottom",
                (tongue_outer_w, tongue_depth, tongue_wall),
                (0, tongue_depth / 2 - 0.2, -tongue_outer_h / 2 + tongue_wall / 2),
                0.35,
            ),
            rounded_box(
                "tongue_left",
                (tongue_wall, tongue_depth, tongue_outer_h - 2 * tongue_wall),
                (-tongue_outer_w / 2 + tongue_wall / 2, tongue_depth / 2 - 0.2, 0),
                0.35,
            ),
            rounded_box(
                "tongue_right",
                (tongue_wall, tongue_depth, tongue_outer_h - 2 * tongue_wall),
                (tongue_outer_w / 2 - tongue_wall / 2, tongue_depth / 2 - 0.2, 0),
                0.35,
            ),
        ]
    for tongue_part in tongue_parts:
        boolean(face, tongue_part, "UNION")
    clean_mesh(face)
    return face


def build_button(p: EnclosureParameters) -> bpy.types.Object:
    # Insert from inside the faceplate. The flange retains the plunger; the
    # narrow stem protrudes 0.9 mm at the front and contacts the PRG switch.
    stem_length = p.face_thickness + 2.0
    stem = cylinder_y(
        "button_stem",
        p.button_hole_diameter - 0.55,
        stem_length,
        (p.button_center_x, -p.face_thickness + stem_length / 2 - 0.9, p.button_center_z),
    )
    flange = cylinder_y(
        "button_flange",
        8.2,
        1.0,
        (p.button_center_x, 0.5, p.button_center_z),
    )
    boolean(stem, flange, "UNION")
    stem.name = "button"
    clean_mesh(stem)
    return stem


def mock_board(p: EnclosureParameters) -> list[bpy.types.Object]:
    pcb = rounded_box(
        "board_reference",
        (p.board_width, 1.6, p.board_height),
        (0, 3.4, 0),
        0.6,
    )
    screen = rounded_box(
        "oled_reference",
        (26.0, 2.6, 14.0),
        (p.screen_center_x, 1.7, p.screen_center_z),
        0.8,
    )
    switch = rounded_box(
        "prg_reference",
        (4.2, 2.8, 4.2),
        (p.button_center_x, 1.6, p.button_center_z),
        0.5,
    )
    return [pcb, screen, switch]


def set_material(obj: bpy.types.Object, name: str, color: tuple[float, float, float, float]) -> None:
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.diffuse_color = color
    obj.data.materials.clear()
    obj.data.materials.append(material)


def export_stl(obj: bpy.types.Object, path: Path) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.wm.stl_export(
        filepath=str(path),
        export_selected_objects=True,
        ascii_format=False,
        apply_modifiers=True,
    )


def mesh_report(obj: bpy.types.Object) -> tuple[int, int]:
    mesh = obj.data
    # Blender's bmesh API provides a reliable manifold check after modifiers.
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(mesh)
    non_manifold = sum(1 for edge in bm.edges if not edge.is_manifold)
    loose = sum(1 for edge in bm.edges if len(edge.link_faces) == 0)
    bm.free()
    return non_manifold, loose


def render_preview(
    p: EnclosureParameters,
    objects: dict[str, bpy.types.Object],
    path: Path,
) -> None:
    # Slightly exploded assembly: the relationship between face, button, PCB,
    # and shell is easier to inspect than in a fully closed product render.
    objects["base"].location.y += 7.0
    objects["face"].location.y -= 5.0
    objects["button"].location.y -= 5.0

    for obj in objects.values():
        if obj.name.startswith("board"):
            set_material(obj, "pcb", (0.06, 0.33, 0.16, 1.0))
        elif obj.name.startswith("oled"):
            set_material(obj, "oled", (0.02, 0.05, 0.08, 1.0))
        elif obj.name.startswith("prg"):
            set_material(obj, "switch", (0.65, 0.65, 0.62, 1.0))
        elif obj.name == "button":
            set_material(obj, "button", (0.95, 0.43, 0.48, 1.0))
        else:
            set_material(obj, "case", (0.11, 0.16, 0.28, 1.0))

    bpy.ops.object.camera_add(location=(82, -105, 68))
    camera = bpy.context.object
    target = Vector((0, p.outer_depth / 2, 0))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 83

    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shading.cavity_type = "WORLD"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.background_type = "VIEWPORT"
    scene.display.shading.background_color = (0.025, 0.032, 0.055)
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def generate_variant(
    name: str,
    p: EnclosureParameters,
    out_dir: Path,
    render: bool,
) -> None:
    clear_scene()
    variant_dir = out_dir / name
    variant_dir.mkdir(parents=True, exist_ok=True)

    base = build_base(p)
    face = build_face(p)
    button = build_button(p)
    printable = {"base": base, "face": face, "button": button}

    for part_name, obj in printable.items():
        prepare_print_mesh(obj)
        export_stl(obj, variant_dir / f"heltec-v1-{name}-{part_name}.stl")
        non_manifold, loose = mesh_report(obj)
        print(
            f"VALIDATION {name}/{part_name}: "
            f"non_manifold_edges={non_manifold} loose_edges={loose}"
        )

    if render:
        references = mock_board(p)
        preview_objects = dict(printable)
        for ref in references:
            preview_objects[ref.name] = ref
        render_preview(p, preview_objects, variant_dir / f"heltec-v1-{name}-preview.png")
        bpy.ops.wm.save_as_mainfile(filepath=str(variant_dir / f"heltec-v1-{name}-preview.blend"))

    print(
        f"DIMENSIONS {name}: "
        f"{p.outer_width:.1f} x {p.outer_height:.1f} x {p.outer_depth + p.face_thickness:.1f} mm"
    )


def main() -> None:
    args = parse_args()
    # Generated preview scenes are reproducible, so Blender backup copies only
    # add noise to the deliverables.
    bpy.context.preferences.filepaths.save_version = 0
    args.out_dir.mkdir(parents=True, exist_ok=True)
    variants = {
        "slim": SLIM,
        "headers": HEADERS,
    }
    selected = variants.items() if args.variant == "all" else [(args.variant, variants[args.variant])]
    for name, params in selected:
        generate_variant(name, params, args.out_dir, args.render)


if __name__ == "__main__":
    main()
