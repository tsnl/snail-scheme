"""Export the editable Willowbank level and its two animated actors in Blender.

Run make iygtw-art. The runtime reads metres with north at -Z. Blender's
glTF exporter makes the same Y-up conversion for the visible geometry.
Objects tagged iy_surface supply wheel contact. Meshes tagged iy_solid or
iy_fence block travel, as does open water outside a bridge deck.
"""

import math
import struct
import sys
import tempfile
from array import array
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

APP = Path(__file__).resolve().parents[1] / "apps" / "iygtw"
SURFACES = {"meadow": 0, "lane": 1, "trail": 2, "bridge": 3}


def triangles(obj, depsgraph):
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    try:
        vertices = [evaluated.matrix_world @ v.co for v in mesh.vertices]
        mesh.calc_loop_triangles()
        return vertices, [tuple(t.vertices) for t in mesh.loop_triangles]
    finally:
        evaluated.to_mesh_clear()


def projected_rows(vertices, faces, rows, west, north):
    """Rasterize solid silhouettes into one-metre scanlines, including thin rails."""
    for face in faces:
        pts = [(vertices[i].x - west, -vertices[i].y - north) for i in face]
        for j in range(
            max(0, math.floor(min(p[1] for p in pts))),
            min(len(rows), math.ceil(max(p[1] for p in pts))),
        ):
            # Clip to the whole metre strip so a narrow diagonal cannot vanish.
            polygon = pts
            for edge, sign in ((j, 1), (j + 1, -1)):
                clipped = []
                for a, b in zip(polygon, polygon[1:] + polygon[:1]):
                    if sign * (a[1] - edge) >= 0:
                        clipped.append(a)
                    if (a[1] < edge < b[1]) or (b[1] < edge < a[1]):
                        t = (edge - a[1]) / (b[1] - a[1])
                        clipped.append((a[0] + t * (b[0] - a[0]), edge))
                polygon = clipped
            if polygon:
                lo = max(0, math.floor(min(p[0] for p in polygon)))
                hi = min(len(rows[j]), math.ceil(max(p[0] for p in polygon)))
                if hi > lo:
                    rows[j][lo:hi] = b"\1" * (hi - lo)


def triangle_tree(objects, depsgraph, label):
    vertices, faces, labels = [], [], []
    for obj in objects:
        points, triangles_ = triangles(obj, depsgraph)
        start = len(vertices)
        vertices.extend(points)
        faces.extend(tuple(start + i for i in face) for face in triangles_)
        labels.extend([label(obj)] * len(triangles_))
    return BVHTree.FromPolygons(vertices, faces, all_triangles=True), labels


def offsets(numbers):
    values = array("I", numbers)
    if sys.byteorder != "little":
        values.byteswap()
    return values.tobytes()


def contacts(directory):
    ground = next(o for o in bpy.context.scene.objects if "iy_cell" in o)
    corners = [ground.matrix_world @ Vector(b) for b in ground.bound_box]
    west = round(min(v.x for v in corners))
    north = round(-max(v.y for v in corners))
    width = round(max(v.x for v in corners)) - west
    depth = round(-min(v.y for v in corners)) - north
    if min(width, depth) <= 0 or width > 65535:
        raise ValueError("GRD1 scanline spans use unsigned 16-bit metre offsets")
    occupied = [bytearray(width) for _ in range(depth)]
    depsgraph = bpy.context.evaluated_depsgraph_get()
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    for obj in meshes:
        if obj.get("iy_solid") or obj.get("iy_fence"):
            projected_rows(*triangles(obj, depsgraph), occupied, west, north)
    ground_objects = [obj for obj in meshes if "iy_surface" in obj]
    tree, tags = triangle_tree(
        ground_objects, depsgraph, lambda o: SURFACES[o["iy_surface"]]
    )
    water_objects = [obj for obj in meshes if obj.get("iy_water")]
    water = (
        triangle_tree(water_objects, depsgraph, lambda o: 0)[0]
        if water_objects
        else None
    )

    def sample(x, z):
        # Pull boundary samples just inside the closed survey mesh.
        x = min(width - 0.0001, max(0.0001, x))
        z = min(depth - 0.0001, max(0.0001, z))
        point, _, index, _ = tree.ray_cast((west + x, -north - z, 400), (0, 0, -1))
        if point is None:
            raise ValueError(f"Missing ground at {west + x}, {north + z}")
        return round(point.z * 100), tags[index]

    heights = [[sample(x, z)[0] for x in range(width + 1)] for z in range(depth + 1)]
    packed, surfaces = bytearray(), bytearray()
    for z in range(depth):
        for x in range(width):
            h, surface = sample(x + 0.5, z + 0.5)
            surfaces.append(surface)
            point = (
                water.ray_cast((west + x + 0.5, -north - z - 0.5, 400), (0, 0, -1))[0]
                if water
                else None
            )
            underwater = point is not None and h < round(point.z * 100) + 5
            if underwater or x in (0, width - 1) or z in (0, depth - 1):
                occupied[z][x] = 1
            a, b = heights[z][x : x + 2]
            d, c = heights[z + 1][x : x + 2]
            packed.extend(struct.pack("<HHhHHhHHh", 0, 0, a, 100, 0, b, 0, 100, d))
            packed.extend(struct.pack("<HHhHHhHHh", 100, 0, b, 100, 100, c, 0, 100, d))
    spans, lines = bytearray(), [0]
    for row in occupied:
        lo = None
        for x, hit in enumerate(row + b"\0"):
            if hit and lo is None:
                lo = x
            if not hit and lo is not None:
                spans.extend(struct.pack("<HH", lo, x))
                lo = None
        lines.append(len(spans) // 4)
    count = width * depth * 2
    (directory / "ground.bin").write_bytes(
        struct.pack("<4siiIIII", b"GRD1", west, north, width, depth, 1, count)
        + offsets(range(0, count + 1, 2))
        + packed
        + offsets(lines)
        + spans
    )
    (directory / "surfaces.bin").write_bytes(surfaces)


def export(source, output, scenery):
    bpy.ops.wm.open_mainfile(filepath=str(APP / "art" / source))
    if scenery:
        contacts(output)
        marks = sorted(
            (o for o in bpy.context.scene.objects if "iy_waymark" in o),
            key=lambda o: o["iy_waymark"],
        )
        if not marks or marks[0]["iy_waymark"] != 0:
            raise ValueError("The village needs a start marker")
        data = bytearray()
        for obj in marks:
            name = obj.name.encode("utf-8")
            data.extend(
                struct.pack(
                    "<hhHH",
                    round(obj.matrix_world.translation.x),
                    round(-obj.matrix_world.translation.y),
                    round(obj["radius"]),
                    len(name),
                )
            )
            data.extend(name)
        (output / "waymarks.bin").write_bytes(data)
        # The source keeps its buildings and trees editable. One export mesh
        # lets the renderer upload one primitive per material.
        bpy.ops.object.select_all(action="DESELECT")
        meshes = [
            o
            for o in bpy.context.scene.objects
            if o.type == "MESH" and not o.hide_render
        ]
        for obj in meshes:
            # Blender joins UV layers by name. The runtime samples TEXCOORD_0,
            # so preserve each artist's active coordinates in that same layer.
            if obj.data.uv_layers.active:
                obj.data.uv_layers.active.name = "Surface UV"
            obj.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.join()
    for material in bpy.data.materials:
        if material.node_tree and (
            p := material.node_tree.nodes.get("Principled BSDF")
        ):
            weight = p.inputs["Subsurface Weight"].default_value
            if weight > 0:
                material["snailSubsurface"] = weight
            elif "snailSubsurface" in material:
                del material["snailSubsurface"]
    result = bpy.ops.export_scene.gltf(
        filepath=str(output / (Path(source).stem.lower() + ".glb")),
        export_format="GLB",
        use_selection=scenery,
        export_yup=True,
        export_extras=True,
        export_cameras=False,
        export_lights=False,
        export_texcoords=True,
        export_animations=not scenery,
        export_animation_mode="NLA_TRACKS",
        export_frame_range=False,
        export_skins=True,
        export_def_bones=False,
    )
    if "FINISHED" not in result:
        raise RuntimeError(f"Blender could not export {source}")


def main():
    dest = APP / "main.resources"
    dest.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=dest) as temp:
        out = Path(temp)
        for source in ["Willowbank.blend", "Roadster.blend", "Moss.blend"]:
            export(source, out, source == "Willowbank.blend")
        for path in out.iterdir():
            path.replace(dest / path.name)


if __name__ == "__main__":
    main()
