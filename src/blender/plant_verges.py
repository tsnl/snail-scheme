"""Replant the editable Willowbank verge collection in the open level.

blender src/apps/iygtw/art/Willowbank.blend -b --python src/blender/plant_verges.py
Grass, dock leaves and foxgloves occupy moist banks and the first few metres
beside a lane. Overlapping ash crowns shelter the mill and the orchard approach.
The road and water meshes decide where a plant may take root.
"""

from math import cos, pi, sin
from random import Random

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def survey(objects):
    points, faces = [], []
    for obj in objects:
        mesh = obj.data
        mesh.calc_loop_triangles()
        start = len(points)
        points.extend(obj.matrix_world @ v.co for v in mesh.vertices)
        faces.extend(tuple(start + i for i in f.vertices) for f in mesh.loop_triangles)
    return BVHTree.FromPolygons(points, faces, all_triangles=True)


def material(name, color):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    surface = mat.node_tree.nodes.get("Principled BSDF")
    surface.inputs["Base Color"].default_value = (*color, 1)
    surface.inputs["Roughness"].default_value = 0.77
    mat.diffuse_color = (*color, 1)
    return mat


class Bed:
    def __init__(self):
        self.points, self.faces, self.colors = [], [], []

    def polygon(self, vertices, faces, color):
        base = len(self.points)
        self.points.extend(vertices)
        self.faces.extend(tuple(base + i for i in face) for face in faces)
        self.colors.extend([color] * len(faces))

    def leaf(self, root, angle, height, reach, width, color):
        along = Vector((cos(angle), sin(angle), 0))
        across = Vector((-along.y, along.x, 0)) * width
        shoulder = root + along * (0.46 * reach) + Vector((0, 0, height * 0.83))
        tip = root + along * reach + Vector((0, 0, height))
        self.polygon(
            [
                root,
                shoulder - across,
                shoulder + Vector((0, 0, width * 0.49)),
                shoulder + across,
                tip,
            ],
            [(0, 1, 2), (0, 2, 3), (1, 4, 2), (2, 4, 3)],
            color,
        )

    def coppice(self, root, radius, height, rng):
        # Hazel sends several shoots up from a common stool. Paired leaves
        # step down each twig, making a solid, irregular silhouette from below.
        for j in range(22):
            az = j * 2.4 + rng.uniform(-0.5, 0.5)
            run = radius * rng.uniform(0.32, 1.0)
            rise = height * (1.15 - 0.56 * (run / radius) ** 2) * rng.uniform(0.72, 1.0)
            direction = Vector((cos(az), sin(az), 0))
            offset = root + direction * rng.uniform(0.02, 0.14) * radius
            self.leaf(offset, az, rise * 0.91, run, 0.022 * height, 7)
            for pair in range(4):
                t = 0.32 + 0.19 * pair
                node = offset + direction * run * t + Vector((0, 0, rise * t))
                long = radius * rng.uniform(0.18, 0.31)
                for sign in (-1, 1):
                    self.leaf(
                        node,
                        az + sign * rng.uniform(0.42, 1.12),
                        long * rng.uniform(0.27, 0.70),
                        long,
                        long * 0.32,
                        8 + (j + pair) % 3,
                    )

    def spike(self, p, height, angle, color):
        # Six hanging bells on alternating sides of the stem.
        self.leaf(p, angle, height, 0.065, 0.008, 1)
        for i in range(6):
            a = angle + 2.4 * i
            side = Vector((cos(a), sin(a), 0))
            cross = Vector((-side.y, side.x, 0))
            root = p + Vector(
                (0.04 * cos(angle), 0.04 * sin(angle), height * (0.48 + 0.084 * i))
            )
            head = root + side * (0.041 - 0.003 * i)
            rim = [
                head
                + side * (0.019 * cos(k * pi / 2))
                + cross * (0.019 * sin(k * pi / 2))
                + Vector((0, 0, -0.046 + 0.003 * i))
                for k in range(4)
            ]
            self.polygon(
                [root, *rim], [(0, 1, 2), (0, 2, 3), (0, 3, 4), (0, 4, 1)], color
            )

    def mesh(self, collection, name, materials):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.points, [], self.faces)
        mesh.update()
        for m in materials:
            mesh.materials.append(m)
        mesh.polygons.foreach_set("material_index", self.colors)
        mesh.polygons.foreach_set("use_smooth", [True] * len(self.faces))
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        return obj


class Canopy:
    """Bent, textured leaf sprays grow out of real branches in five tiers."""

    def __init__(self):
        self.bed = Bed()
        self.uv = []

    def branch(self, a, b, radius, tip):
        axis = (b - a).normalized()
        u = axis.cross(Vector((1, 0, 0))).normalized()
        v = axis.cross(u)
        ring = [u * cos(i * 2 * pi / 5) + v * sin(i * 2 * pi / 5) for i in range(5)]
        faces = [(i, (i + 1) % 5, (i + 1) % 5 + 5, i + 5) for i in range(5)]
        self.bed.polygon(
            [a + radius * d for d in ring] + [b + tip * d for d in ring], faces, 0
        )
        for i in range(5):
            self.uv.extend(
                [
                    (i / 5, 0),
                    ((i + 1) / 5, 0),
                    ((i + 1) / 5, (b - a).length),
                    (i / 5, (b - a).length),
                ]
            )

    def spray(self, start, az, length, width, lift):
        direction = Vector((cos(az), sin(az), 0))
        side = Vector((-direction.y, direction.x, 0)) * width
        mid = (
            start
            + direction * length * 0.54
            + Vector((0, 0, lift * 0.65 + width * 0.36))
        )
        tip = start + direction * length + Vector((0, 0, lift))
        self.bed.polygon(
            [
                start - side * 0.25,
                start + side * 0.25,
                mid - side,
                mid + side,
                tip - side * 0.52,
                tip + side * 0.52,
            ],
            [(0, 2, 3, 1), (2, 4, 5, 3)],
            1,
        )
        self.uv.extend(
            [(0, 0), (0, 0.52), (1, 0.52), (1, 0), (0, 0.52), (0, 1), (1, 1), (1, 0.52)]
        )

    def tree(self, root, height, rng):
        up = Vector((0, 0, height))
        lean = Vector((rng.uniform(-0.06, 0.06), rng.uniform(-0.06, 0.06), 0)) * height
        axis = up + lean
        self.branch(root, root + axis * 0.92, height * 0.026, height * 0.008)
        twist = rng.uniform(0, 2 * pi)
        spread = rng.uniform(0.43, 0.57) * height
        for i in range(15):
            t = i / 14
            az = twist + i * 2.40 + rng.uniform(-0.28, 0.28)
            side = Vector((cos(az), sin(az), 0))
            r = (
                spread
                * (0.43 + 0.57 * sin((0.24 + 0.73 * t) * pi))
                * rng.uniform(0.87, 1.13)
            )
            fork = root + axis * (0.33 + 0.52 * t)
            elbow = fork + side * r * 0.58 + up * (0.15 + t * 0.02)
            self.branch(fork, elbow, height * 0.013 * (1 - 0.50 * t), height * 0.003)
            for j in range(5):
                angle = az + (j - 2) * 0.52 + rng.uniform(-0.20, 0.20)
                self.spray(
                    elbow - side * r * 0.24,
                    angle,
                    r * rng.uniform(0.67, 1.04),
                    r * rng.uniform(0.27, 0.41),
                    height * rng.uniform(-0.07, 0.13),
                )

    def mesh(self, collection):
        mesh = self.bed.mesh(
            collection,
            "Broadleaf canopy above the mill road",
            [
                bpy.data.materials["Ash • fissured bark"],
                bpy.data.materials["Leaflets • spring ash"],
            ],
        )
        layer = mesh.data.uv_layers.new(name="Surface UV")
        layer.data.foreach_set("uv", [n for uv in self.uv for n in uv])


def groves(collection, lanes, grounds, excluded):
    canopy, trunks = Canopy(), Bed()
    rng = Random(1723)
    # Each section follows a surveyed piece of road. Paired banks enclose the
    # uphill climb; gaps at the bridge and the top leave a view over the valley.
    sections = [
        [(-5, -14), (0, 0), (8, 11), (14, 22)],
        [(15, 42), (12, 51), (6, 61), (2, 69), (-3, 76), (-5, 83)],
        [(-48, 41), (-41, 51), (-32, 61), (-18, 71)],
        [(-69, 53), (-60, 64), (-50, 73), (-39, 82)],
    ]
    survivors = []
    for section in sections:
        for start, end in zip(section, section[1:]):
            a, b = Vector(start), Vector(end)
            d = (b - a).normalized()
            n = Vector((-d.y, d.x))
            for side in (-1, 1):
                t = rng.uniform(0.5, 3.2)
                while t < (b - a).length:
                    xy = a + d * t + n * side * rng.uniform(3.4, 7.1)
                    t += rng.uniform(3.8, 6.4)
                    origin = (*xy, 150)
                    p = grounds.ray_cast(origin, (0, 0, -1))[0]
                    if p is None or lanes.find_nearest(p, 1.45)[0] is not None:
                        continue
                    roof = excluded.ray_cast(origin, (0, 0, -1))[0]
                    if roof is not None and roof.z >= p.z - 0.05:
                        continue
                    if any((p - other).length < 2.7 for other in survivors):
                        continue
                    height = rng.uniform(4.4, 7.6)
                    canopy.tree(p, height, rng)
                    survivors.append(p)
                    radius = height * 0.026
                    trunks.polygon(
                        [
                            p + Vector((radius * x, radius * y, 0))
                            for x, y in ((1, 0), (0, 1), (-1, 0), (0, -1))
                        ],
                        [(0, 1, 2), (0, 2, 3)],
                        0,
                    )
    canopy.mesh(collection)
    contact = trunks.mesh(collection, "Wheel contact • new ash trunks", [])
    contact["iy_solid"] = True
    contact.hide_render = True
    contact.display_type = "WIRE"
    print("Sheltering ash trees:", len(survivors))


def main():
    scene = bpy.context.scene
    name = "10 • Banks and living verges"
    old = bpy.data.collections.get(name)
    if old:
        for o in list(old.objects):
            mesh = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            if not mesh.users:
                bpy.data.meshes.remove(mesh)
        bpy.data.collections.remove(old)
    collection = bpy.data.collections.new(name)
    scene.collection.children.link(collection)
    land = next(o for o in scene.objects if "iy_cell" in o)
    roads = [
        o for o in scene.objects if o.get("iy_surface") in {"lane", "trail", "bridge"}
    ]
    grounds, lanes = survey([land]), survey(roads)
    excluded = survey(
        [
            o
            for o in scene.objects
            if o.type == "MESH" and (o.get("iy_solid") or o.get("iy_water"))
        ]
    )
    materials = [
        material(n, c)
        for n, c in [
            ("Sedge • shaded blades", (0.051, 0.105, 0.037)),
            ("Sedge • fresh blades", (0.115, 0.194, 0.048)),
            ("Hay • sunlit tips", (0.255, 0.268, 0.093)),
            ("Dock • glossy leaf", (0.061, 0.151, 0.052)),
            ("Dock • young leaf", (0.151, 0.232, 0.063)),
            ("Foxglove • rose", (0.51, 0.17, 0.30)),
            ("Foxglove • pale throat", (0.71, 0.57, 0.52)),
            ("Hazel • shoots", (0.16, 0.11, 0.047)),
            ("Hazel • lower leaves", (0.034, 0.091, 0.028)),
            ("Hazel • middle leaves", (0.070, 0.152, 0.039)),
            ("Hazel • spring tips", (0.149, 0.232, 0.064)),
        ]
    ]
    rng = Random(43177)
    # A one-metre mask bins the road edge. The exact vertical ray below keeps
    # roots outside the wheel surface even on diagonals and the bridge decks.
    bounds = [land.matrix_world @ Vector(b) for b in land.bound_box]
    xs = range(round(min(v.x for v in bounds)), round(max(v.x for v in bounds)))
    ys = range(round(min(v.y for v in bounds)), round(max(v.y for v in bounds)))
    down = (0, 0, -1)
    lane = {
        (x, y)
        for x in xs
        for y in ys
        if lanes.ray_cast((x + 0.5, y + 0.5, 150), down)[0] is not None
    }
    shoulder = {
        (x + i, y + j)
        for x, y in lane
        for i in range(-4, 5)
        for j in range(-4, 5)
        if i * i + j * j <= 18
    }
    beds = [Bed() for _ in range(3)]
    for x in xs:
        for y in ys:
            close = (x, y) in shoulder
            moisture = 0.5 + 0.5 * sin(x * 0.18 + 1.6 * sin(0.13 * y)) * cos(
                y * 0.24 - 0.08 * x
            )
            for _ in range(5 if close else 1):
                if rng.random() > (
                    0.49 + 0.51 * moisture if close else 0.045 + 0.10 * moisture
                ):
                    continue
                xx, yy = x + rng.random(), y + rng.random()
                origin = (xx, yy, 150)
                ground = grounds.ray_cast(origin, down)[0]
                if ground is None or lanes.ray_cast(origin, down)[0] is not None:
                    continue
                roof = excluded.ray_cast(origin, down)[0]
                if roof is not None and roof.z >= ground.z - 0.02:
                    continue
                ground.z -= 0.022
                angle = rng.uniform(0, 2 * pi)
                h = rng.uniform(0.14, 0.37) * (0.80 + 0.48 * moisture)
                bed = beds[0]
                for j in range(rng.randrange(4, 8)):
                    a = angle + j * 2.40 + rng.uniform(-0.25, 0.25)
                    bed.leaf(
                        ground,
                        a,
                        h * rng.uniform(0.65, 1.2),
                        h * rng.uniform(0.42, 1.15),
                        rng.uniform(0.014, 0.031),
                        rng.choices((0, 1, 2), (4, 5, 1))[0],
                    )
                if close and moisture > 0.53 and rng.random() < 0.19:
                    for j in range(7):
                        beds[1].leaf(
                            ground,
                            angle + j * 2.4,
                            rng.uniform(0.14, 0.39),
                            rng.uniform(0.14, 0.38),
                            rng.uniform(0.039, 0.083),
                            3 + j % 2,
                        )
                    if moisture > 0.66 and rng.random() < 0.29:
                        beds[2].spike(
                            ground,
                            rng.uniform(0.47, 0.89),
                            angle,
                            5 if rng.random() < 0.8 else 6,
                        )
    shrubs = Bed()
    # Connect the larger trees into hedgerows while leaving shop entrances,
    # grazed clearings and bridge approaches open.
    trees = [o for o in scene.objects if o.type == "MESH" and " crown " in o.data.name]
    for tree in trees:
        for j in range(3):
            az = rng.uniform(0, 2 * pi)
            distance = rng.uniform(0.9, 3.8)
            x, y = (
                tree.location.x + cos(az) * distance,
                tree.location.y + sin(az) * distance,
            )
            origin = (x, y, 150)
            p = grounds.ray_cast(origin, down)[0]
            if p is None or lanes.find_nearest(p, 1.15)[0] is not None:
                continue
            roof = excluded.ray_cast(origin, down)[0]
            if roof is None or roof.z < p.z - 0.05:
                shrubs.coppice(p, rng.uniform(0.68, 1.30), rng.uniform(0.65, 1.48), rng)
    shrubs.mesh(
        collection, "Hazel coppices under the orchard and beside the mill", materials
    )
    for bed, label in zip(
        beds, ("Bent sedges and meadow grass", "Dock rosettes", "Foxglove spires")
    ):
        bed.mesh(collection, label, materials)
    groves(collection, lanes, grounds, excluded)
    print("Planted verge triangles:", sum(len(b.faces) for b in [*beds, shrubs]))
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath, compress=True)


if __name__ == "__main__":
    main()
