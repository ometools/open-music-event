"""Generate a simple Blender starter model for the Open Music Event mark.

Run from the repo root with:

    /Applications/Blender.app/Contents/MacOS/Blender --background --python Docs/design/blender/ome_logo_starter_model.py

The scene is intentionally simple: separated named parts, editable materials, a
reference image plane, and a short animation pass for TouchDesigner experiments.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


SCRIPT_PATH = Path(__file__).resolve()
ROOT = SCRIPT_PATH.parent
ASSET_PATH = ROOT.parent / "assets" / "ome-logo-final-mark-2026-06.png"
BLEND_PATH = ROOT / "ome-logo-starter-model.blend"
GLB_PATH = ROOT / "ome-logo-starter-model.glb"
PREVIEW_PATH = ROOT / "ome-logo-starter-preview.png"


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for collection in list(bpy.data.collections):
        if collection.users == 0:
            bpy.data.collections.remove(collection)


def collection(name: str) -> bpy.types.Collection:
    existing = bpy.data.collections.get(name)
    if existing is not None:
        return existing
    new_collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(new_collection)
    return new_collection


def put_in_collection(obj: bpy.types.Object, target: bpy.types.Collection) -> bpy.types.Object:
    for user_collection in list(obj.users_collection):
        user_collection.objects.unlink(obj)
    target.objects.link(obj)
    return obj


def make_material(
    name: str,
    color: tuple[float, float, float, float],
    emission_strength: float = 0.0,
    roughness: float = 0.3,
    metallic: float = 0.0,
    alpha: float | None = None,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    if alpha is not None or color[3] < 1:
        material.blend_method = "BLEND"
        material.show_transparent_back = True

    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        if "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = color[3] if alpha is None else alpha
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = color
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return material


def make_image_material(name: str, image_path: Path, alpha: float) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.blend_method = "BLEND"
    material.show_transparent_back = True

    tree = material.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    texture = tree.nodes.new("ShaderNodeTexImage")
    texture.image = bpy.data.images.load(str(image_path))
    if bsdf is not None:
        tree.links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
        if "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = alpha
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = 0.8
    material.diffuse_color = (1, 1, 1, alpha)
    return material


def rounded_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material: bpy.types.Material,
    target: bpy.types.Collection,
    bevel_width: float = 0.08,
    bevel_segments: int = 12,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    bevel = obj.modifiers.new("soft rounded edge", "BEVEL")
    bevel.width = bevel_width
    bevel.segments = bevel_segments
    bevel.affect = "EDGES"

    normals = obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")
    normals.keep_sharp = True

    obj.data.materials.append(material)
    return put_in_collection(obj, target)


def curve_path(
    name: str,
    points: list[tuple[float, float]],
    material: bpy.types.Material,
    target: bpy.types.Collection,
    bevel_depth: float = 0.07,
    resolution: int = 24,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = resolution
    curve.bevel_depth = bevel_depth
    curve.bevel_resolution = 8

    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, (x, y) in zip(spline.bezier_points, points):
        point.co = (x, y, 0)
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"

    obj = bpy.data.objects.new(name, curve)
    obj.data.materials.append(material)
    target.objects.link(obj)
    return obj


def torus(
    name: str,
    location: tuple[float, float, float],
    major_radius: float,
    minor_radius: float,
    material: bpy.types.Material,
    target: bpy.types.Collection,
    scale: tuple[float, float, float] = (1, 1, 1),
    segments: int = 128,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_segments=segments,
        minor_segments=18,
        location=location,
        major_radius=major_radius,
        minor_radius=minor_radius,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(material)
    return put_in_collection(obj, target)


def cylinder_beam(
    name: str,
    location: tuple[float, float, float],
    length: float,
    radius: float,
    material: bpy.types.Material,
    target: bpy.types.Collection,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=48,
        radius=radius,
        depth=length,
        location=location,
        rotation=(0, math.radians(90), 0),
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    return put_in_collection(obj, target)


def add_text(
    name: str,
    body: str,
    location: tuple[float, float, float],
    material: bpy.types.Material,
    target: bpy.types.Collection,
) -> bpy.types.Object:
    bpy.ops.object.text_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.body = body
    obj.data.align_x = "CENTER"
    obj.data.align_y = "CENTER"
    obj.data.size = 0.2
    obj.data.space_character = 2.1
    obj.data.extrude = 0.018
    obj.data.bevel_depth = 0.002
    obj.data.materials.append(material)
    return put_in_collection(obj, target)


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def animate_scale(obj: bpy.types.Object, keys: list[tuple[int, tuple[float, float, float]]]) -> None:
    for frame, scale in keys:
        bpy.context.scene.frame_set(frame)
        obj.scale = scale
        obj.keyframe_insert(data_path="scale", frame=frame)


def build_scene() -> None:
    clear_scene()

    reference = collection("00_reference")
    geometry = collection("10_logo_geometry")
    controls = collection("20_controls")
    lighting = collection("30_lights_camera")

    dark_glass = make_material("deep black glass", (0.01, 0.01, 0.025, 1), 0.0, 0.18, 0.2)
    teal = make_material("spectral teal", (0.25, 0.92, 0.82, 1), 0.25, 0.22, 0.1)
    blue = make_material("spectral blue", (0.17, 0.38, 1.0, 1), 0.35, 0.2, 0.05)
    violet = make_material("spectral violet", (0.58, 0.22, 1.0, 1), 0.3, 0.22, 0.05)
    rose = make_material("warm rose", (1.0, 0.3, 0.55, 1), 0.25, 0.28, 0.05)
    gold = make_material("warm gold", (1.0, 0.64, 0.24, 1), 0.2, 0.32, 0.05)
    white_emission = make_material("white beam emission", (1.0, 1.0, 0.92, 1), 3.0, 0.12, 0.0)
    ring_material = make_material("soft refraction rings", (0.66, 0.92, 1.0, 0.44), 0.7, 0.12, 0.0, alpha=0.44)
    wordmark_material = make_material("soft wordmark glow", (0.95, 0.68, 0.93, 1), 0.55, 0.45, 0.0)

    if ASSET_PATH.exists():
        ref_material = make_image_material("final mark reference image", ASSET_PATH, 0.22)
        bpy.ops.mesh.primitive_plane_add(size=5.6, location=(0, 0, -0.18))
        ref_plane = bpy.context.object
        ref_plane.name = "reference_final_mark_image_locked"
        ref_plane.data.materials.append(ref_material)
        ref_plane.hide_select = True
        put_in_collection(ref_plane, reference)

    # Base dark silhouette so the final form has the same high-contrast center.
    rounded_box("portal dark core", (0, -0.06, -0.03), (0.86, 2.3, 0.09), dark_glass, geometry, 0.22, 16)

    # Main portal/M gesture.
    curve_path("portal left arch tube", [(-0.62, -1.06), (-0.58, 0.5), (-0.42, 1.15), (-0.02, 1.18)], teal, geometry, 0.09)
    curve_path("portal right arch tube", [(0.62, -1.06), (0.58, 0.5), (0.42, 1.15), (0.02, 1.18)], blue, geometry, 0.09)
    rounded_box("portal center spine", (-0.01, -0.03, 0.05), (0.17, 2.33, 0.14), rose, geometry, 0.08, 18)
    curve_path("lower left portal curve", [(-0.52, -1.05), (-0.48, -1.35), (-0.32, -1.52), (-0.07, -1.53)], violet, geometry, 0.08)
    curve_path("lower right portal curve", [(0.52, -1.05), (0.48, -1.35), (0.32, -1.52), (0.07, -1.53)], violet, geometry, 0.08)

    # Side forms: simple model-friendly proxies for the O and E.
    torus("left O loop", (-2.0, -0.08, 0.04), 0.54, 0.09, teal, geometry, scale=(1.33, 0.82, 0.28))
    rounded_box("right E top bar", (2.1, 0.52, 0.04), (1.42, 0.19, 0.13), blue, geometry, 0.1, 18)
    rounded_box("right E middle bar", (2.03, -0.1, 0.04), (1.22, 0.16, 0.13), violet, geometry, 0.09, 18)
    rounded_box("right E bottom bar", (2.1, -0.72, 0.04), (1.42, 0.19, 0.13), gold, geometry, 0.1, 18)

    # Portal/refraction elements for TouchDesigner and animation experiments.
    beam = cylinder_beam("horizontal beam animated", (0, -0.08, 0.16), 5.2, 0.028, white_emission, geometry)
    beam_glow = cylinder_beam("horizontal beam soft glow", (0, -0.08, 0.12), 5.35, 0.085, make_material("cyan beam glow", (0.22, 0.9, 1, 0.34), 1.3, 0.55, 0.0, alpha=0.34), geometry)
    rings = [
        torus("left inner refraction ring", (-0.56, -0.08, 0.08), 0.46, 0.018, ring_material, geometry, scale=(0.75, 1.0, 0.22)),
        torus("left outer refraction ring", (-0.56, -0.08, 0.06), 0.69, 0.012, ring_material, geometry, scale=(0.86, 1.0, 0.18)),
        torus("right inner refraction ring", (0.56, -0.08, 0.08), 0.46, 0.018, ring_material, geometry, scale=(0.75, 1.0, 0.22)),
        torus("right outer refraction ring", (0.56, -0.08, 0.06), 0.69, 0.012, ring_material, geometry, scale=(0.86, 1.0, 0.18)),
    ]

    add_text("OPEN MUSIC EVENT wordmark", "OPEN MUSIC EVENT", (0, -1.86, 0.08), wordmark_material, geometry)

    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0.55))
    control = bpy.context.object
    control.name = "ANIMATION_CONTROLS_touchdesigner_handoff"
    control["beam_intensity"] = 1.0
    control["ring_pulse"] = 0.0
    control["portal_aperture"] = 1.0
    control["gradient_phase"] = 0.0
    control["notes"] = "Use these names as a handoff map for TouchDesigner parameters."
    put_in_collection(control, controls)

    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 120
    animate_scale(beam, [(1, (0.05, 1, 1)), (42, (1, 1, 1)), (120, (1, 1, 1))])
    animate_scale(beam_glow, [(1, (0.05, 1, 1)), (50, (1, 1, 1)), (120, (1, 1, 1))])
    for ring in rings:
        animate_scale(ring, [(1, (0.75, 0.75, 0.2)), (48, (1.08, 1.08, 0.2)), (92, (1, 1, 0.2)), (120, (1, 1, 0.2))])

    bpy.ops.object.light_add(type="AREA", location=(0, -2.2, 4.2))
    key = bpy.context.object
    key.name = "large softbox reflection"
    key.data.energy = 450
    key.data.size = 5
    put_in_collection(key, lighting)

    bpy.ops.object.camera_add(location=(0, 0, 7.4))
    camera = bpy.context.object
    camera.name = "orthographic front camera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 4.45
    look_at(camera, (0, 0, 0))
    bpy.context.scene.camera = put_in_collection(camera, lighting)

    bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
    bpy.context.scene.render.resolution_x = 1600
    bpy.context.scene.render.resolution_y = 1200
    bpy.context.scene.render.film_transparent = False
    bpy.context.scene.world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world.color = (0, 0, 0)

    bpy.context.scene.frame_set(72)
    bpy.context.scene.render.filepath = str(PREVIEW_PATH)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.export_scene.gltf(filepath=str(GLB_PATH), export_format="GLB")
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    build_scene()
