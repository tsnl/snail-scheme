"""Export the isolated, unit-radius material probe used by the furnace app."""

from pathlib import Path

import bmesh
import bpy


def export_probe():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=64, radius=1)
    sphere = bpy.context.object
    sphere.name = "Furnace probe"
    # Blender can visit these faces in a different order between runs.
    # Keep triangle IDs and the content-addressed resource stable.
    mesh = bmesh.new()
    mesh.from_mesh(sphere.data)
    ordered = sorted(mesh.faces, key=lambda face: tuple(sorted(tuple(v.co) for v in face.verts)))
    for index, face in enumerate(ordered):
        face.index = index
    mesh.faces.sort()
    mesh.faces.index_update()
    mesh.to_mesh(sphere.data)
    mesh.free()
    for polygon in sphere.data.polygons:
        polygon.use_smooth = True
    material = bpy.data.materials.new("White metal")
    material.use_nodes = True
    surface = material.node_tree.nodes.get("Principled BSDF")
    surface.inputs["Base Color"].default_value = (1, 1, 1, 1)
    surface.inputs["Metallic"].default_value = 1
    surface.inputs["Roughness"].default_value = 1
    sphere.data.materials.append(material)
    path = Path(__file__).resolve().parents[1] / "apps/furnace/sphere.glb"
    bpy.ops.export_scene.gltf(filepath=str(path), export_texcoords=False, export_format="GLB")


if __name__ == "__main__":
    export_probe()
