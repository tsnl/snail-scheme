"""Crown the Willowbank road meshes and place editable puddle basins on them.
Run once on the original survey in Blender. Each ribbon has five vertices per
cross-section, from verge to verge. Subdivide its broad interior strips for ruts.
"""

from math import exp, sin

import bmesh
import bpy

# Positions along each road in cross-sections, offset sideways in metres.
HOLLOWS = {
    "Lantern Row to Foxglove Farm": [(25, -0.32), (31, 0.62), (98, -0.67), (188, 0.51)],
    "Old orchard loop": [(7, 0.25), (39, -0.40), (88, 0.34), (177, 0.32)],
    "Millpond lane": [(14, -0.2), (63, 0.3), (157, -0.35), (260, 0.25)],
    "Lookout path": [(31, 0.20), (150, -0.24)],
    "Mill path": [(8, -0.12), (42, 0.20)],
}


def shape_road(road, markers):
    mesh = road.data
    sections = [mesh.vertices[i].co.copy() for i in range(2, len(mesh.vertices), 5)]
    for slot in road.material_slots:
        name = slot.material.name + " • roadbed"
        mat = bpy.data.materials.get(name) or slot.material.copy()
        mat.name = name
        mat["snailGroundLayer"] = True
        slot.material = mat
    pools = []
    for j, (i, lateral) in enumerate(HOLLOWS[road.name]):
        right = mesh.vertices[5 * i + 4].co - mesh.vertices[5 * i].co
        right.z = 0
        center = sections[i] + right.normalized() * lateral
        rx, ry = (0.66 + 0.14 * (j % 3), 1.08 + 0.23 * (j % 2))
        obj = bpy.data.objects.new(f"{road.name} • hollow {j + 1}", None)
        markers.objects.link(obj)
        obj.empty_display_type = "SPHERE"
        obj.empty_display_size = 1
        obj.location = road.matrix_world @ center
        obj.scale = (rx, ry, 0.042)
        obj["iy_basin"] = True
        scale = road.matrix_world.to_scale()
        pools.append((center, rx / scale.x, ry / scale.y))
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    inner = [
        bm.edges.get((bm.verts[i + side], bm.verts[i + side + 1]))
        for i in range(0, len(mesh.vertices), 5)
        for side in (1, 2)
    ]
    bmesh.ops.subdivide_edges(bm, edges=inner, cuts=1, use_grid_fill=True)
    # Use the nearest station in XY. These small crowns share their silhouette
    # and collision survey, and the verge edges stay sewn into the landscape.
    for v in bm.verts:
        x, y, _ = v.co
        i = min(
            range(len(sections)),
            key=lambda i: (sections[i].x - x) ** 2 + (sections[i].y - y) ** 2,
        )
        width = (mesh.vertices[5 * i].co - sections[i]).length
        across = min(
            1, ((x - sections[i].x) ** 2 + (y - sections[i].y) ** 2) ** 0.5 / width
        )
        crown = (1 - across**2) * (0.066 + 0.017 * sin(i * 0.29))
        rut = 0.043 * exp(-(((across - 0.5) / 0.17) ** 2))
        hollow = max(
            (
                0.060 * exp(-2 * (((x - p.x) / rx) ** 2 + ((y - p.y) / ry) ** 2))
                for p, rx, ry in pools
            ),
            default=0,
        )
        v.co.z += max(0.002, crown - rut - hollow) * (1 - across)
    bm.to_mesh(mesh)
    bm.free()


def main():
    if bpy.data.collections.get("Road drainage"):
        raise ValueError("The roadbeds have already been shaped")
    markers = bpy.data.collections.new("Road drainage")
    bpy.context.scene.collection.children.link(markers)
    for name in HOLLOWS:
        shape_road(bpy.data.objects[name], markers)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath, compress=True)


if __name__ == "__main__":
    main()
