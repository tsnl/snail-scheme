"""Comb Moss's layered coat in the open Moss.blend. Keep the existing skinned undercoat."""

import sys
from math import pi, sin, sqrt
from pathlib import Path
from random import Random

import bmesh
import bpy
from mathutils import Vector

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from groom import Ribbons, tuft_material


def remove_old_tufts(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    old = [
        v
        for v in bm.verts
        if all(
            obj.material_slots[f.material_index].name.startswith(("Fur •", "Moss |"))
            for f in v.link_faces
        )
    ]
    bmesh.ops.delete(bm, geom=old, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    if obj.data.uv_layers.active:
        obj.data.uv_layers.active.name = "Surface UV"


def coat_direction(p, normal, tail):
    if tail:
        comb = Vector((0, -1, 0.8 if p.z < 0.43 else -0.3))
        length = 0.073
    elif p.y > 0.16 and p.z > 0.38:
        # Expose the eyes and nose. The fringe falls down the cheeks and the beard.
        comb = Vector((0.38 if p.x > 0 else -0.38, -0.19, -1))
        length = 0.055 if abs(p.x) > 0.06 else 0.035
        if p.y > 0.29 and p.z > 0.45:
            length = 0.021
    elif p.z < 0.23:
        comb, length = Vector((0, -0.24, -1)), 0.028
    else:
        comb, length = Vector((0, -0.96, -0.76)), 0.068
    return (comb - normal * comb.dot(normal) + 0.14 * normal).normalized(), length


def coat(obj, material_name, number, seed):
    rng = Random(seed)
    mesh = obj.data
    mesh.calc_loop_triangles()
    triangles = [
        t
        for t in mesh.loop_triangles
        if obj.material_slots[t.material_index].name == material_name
    ]
    ribbons = Ribbons()
    for i, tri in enumerate(
        rng.choices(triangles, weights=[t.area for t in triangles], k=number)
    ):
        a, b, c = [mesh.vertices[k] for k in tri.vertices]
        r, s = sqrt(rng.random()), rng.random()
        bary = (1 - r, r * (1 - s), r * s)
        p = sum((v.co * w for v, w in zip((a, b, c), bary)), Vector())
        n = sum((v.normal * w for v, w in zip((a, b, c), bary)), Vector()).normalized()
        if (Vector((abs(p.x), p.y, p.z)) - Vector((0.089, 0.277, 0.51))).length < 0.025:
            continue
        if (p - Vector((0, 0.373, 0.461))).length < 0.026:
            continue
        weights = {}
        for v, w in zip((a, b, c), bary):
            for group in v.groups:
                name = obj.vertex_groups[group.group].name
                weights[name] = weights.get(name, 0) + group.weight * w
        flow, length = coat_direction(p, n, weights.get("Tail", 0) > 0.5)
        width = rng.uniform(0.006, 0.012)
        length *= rng.uniform(0.68, 1.26)
        twist = flow.cross(n) * rng.uniform(-0.009, 0.009)
        points = [
            p
            + n * (-0.006 * (1 - t) + 0.004 * sin(pi * t))
            + length * t * flow
            + t * t * twist
            for t in (0, 0.32, 0.67, 1)
        ]
        ribbons.comb(points, n, width, i % 4, weights, 0.14)
    data = bpy.data.meshes.new(material_name + " guides")
    data.from_pydata(ribbons.vertices, [], ribbons.faces)
    # The solid undercoat stores linear reflectance. Packed PNG strand
    # textures store sRGB, like the game's other glTF base-color maps.
    base = bpy.data.materials[material_name].node_tree.nodes.get("Principled BSDF")
    color = tuple(
        1.055 * c ** (1 / 2.4) - 0.055
        for c in base.inputs["Base Color"].default_value[:3]
    )
    data.materials.append(
        tuft_material("Moss | " + material_name, color, 0.56, 0.25, 0.70, seed)
    )
    layer = data.uv_layers.new(name="Surface UV")
    for poly in data.polygons:
        poly.use_smooth = True
        for loop, vertex in zip(poly.loop_indices, poly.vertices):
            layer.data[loop].uv = ribbons.uv[vertex]
    strands = bpy.data.objects.new(data.name, data)
    bpy.context.collection.objects.link(strands)
    for i, weights in enumerate(ribbons.weights):
        for name, weight in weights.items():
            group = strands.vertex_groups.get(name) or strands.vertex_groups.new(
                name=name
            )
            group.add([i], weight, "REPLACE")
    return strands


def main():
    obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    remove_old_tufts(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.material_slot_remove_unused()
    bpy.data.orphans_purge(do_recursive=True)
    bpy.ops.object.select_all(action="DESELECT")
    for source, count, seed in [
        ("Copper coat", 1350, 31),
        ("Cream ruff", 800, 33),
        ("Sable tips", 270, 35),
    ]:
        coat(obj, source, count, seed).select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()
    obj.data.uv_layers.active_index = obj.data.uv_layers.find("Surface UV")
    obj.data.uv_layers["Surface UV"].active_render = True
    bpy.ops.object.material_slot_remove_unused()
    bpy.data.orphans_purge(do_recursive=True)
    # Masked layers in the dense ruff should also pass light in Cycles previews.
    bpy.context.scene.cycles.transparent_max_bounces = 64
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath, compress=True)


if __name__ == "__main__":
    main()
