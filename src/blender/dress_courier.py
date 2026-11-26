"""Redress Roadster.blend. Pass the extracted CC0 Blender Studio Human Base
Meshes .blend after --. The finished Roadster packs all its meshes and images.
Blender coordinates are metres, +Y is the bicycle's forward direction.
"""

import sys
from math import atan2, cos, pi, sin
from pathlib import Path
from random import Random

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

TAU = 2 * pi
NECK = Vector((0, 0.084, 1.493))
HEAD_SCALE = 0.76
RIG = bpy.data.objects["Rider rig"]
PARTS = []


def material(name, color, roughness, metal=0, sss=0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    for key, value in {
        "Base Color": (*color, 1),
        "Roughness": roughness,
        "Metallic": metal,
        "Subsurface Weight": sss,
        "Subsurface Radius": (0.009, 0.004, 0.002),
    }.items():
        bsdf.inputs[key].default_value = value
    m.diffuse_color = (*color, 1)
    return m


def paint(m, rgb):
    height, width = rgb.shape[:2]
    image = bpy.data.images.new(m.name, width, height, alpha=False)
    rgba = np.ones((height, width, 4), dtype=np.float32)
    rgba[:, :, :3] = np.clip(rgb, 0, 1)
    image.pixels.foreach_set(rgba.ravel())
    image.pack()
    tex = m.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])


def fabric(name, rgb, rough, seed):
    m = material(name, (1, 1, 1), rough)
    y, x = np.mgrid[:256, :256]
    grain = np.random.default_rng(seed).normal(0, 0.025, x.shape)
    weave = 0.028 * np.cos(TAU * (x - y) / 5) + 0.033 * np.cos(TAU * y / 4)
    dye = 0.033 * np.sin(TAU * (x + 2 * y) / 256)
    paint(m, np.array(rgb) * (1 + weave + dye + grain)[:, :, None])
    return m


def mesh(name, verts, faces, mat, weights, coords=None):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.materials.append(mat)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    PARTS.append(obj)
    if isinstance(weights, str):
        obj.vertex_groups.new(name=weights).add(list(range(len(verts))), 1, "REPLACE")
    else:
        for i, influences in enumerate(weights):
            for bone, strength in influences.items():
                if strength:
                    group = obj.vertex_groups.get(bone) or obj.vertex_groups.new(
                        name=bone
                    )
                    group.add([i], strength, "REPLACE")
    uv = data.uv_layers.new(name="Surface UV")
    for poly in data.polygons:
        poly.use_smooth = True
        for j, vi in zip(poly.loop_indices, poly.vertices):
            v = verts[vi]
            uv.data[j].uv = (
                coords[vi] if coords is not None else (v[0] * 7, (v[1] + v[2]) * 7)
            )
    return obj


def rings(name, rows, mat, bone):
    """Closed cross-sections in matching winding order, with optional skin weights per row."""
    n = len(rows[0])
    verts = [v for row in rows for v in row]
    faces = [tuple(reversed(range(n)))]
    faces.extend(
        (i * n + j, i * n + (j + 1) % n, (i + 1) * n + (j + 1) % n, (i + 1) * n + j)
        for i in range(len(rows) - 1)
        for j in range(n)
    )
    faces.append(tuple(range(len(verts) - n, len(verts))))
    weights = bone if isinstance(bone, str) else [w for w in bone for _ in range(n)]
    return mesh(name, verts, faces, mat, weights)


def horizontal(center, rx, ry, n=32, folds=0):
    x, y, z = center
    return [
        (
            x + rx * cos(a) * (1 + folds * sin(7 * a)),
            y + ry * sin(a) * (1 + folds * cos(5 * a)),
            z,
        )
        for a in (TAU * i / n for i in range(n))
    ]


def jacket(name, profile, mat, bone="Body"):
    return rings(
        name,
        [
            horizontal((0, y, z), x, depth, folds=fold)
            for z, y, x, depth, fold in profile
        ],
        mat,
        bone,
    )


def tube(name, points, radius, mat, bone, sides=8):
    pts = [Vector(p) for p in points]
    radii = [radius] * len(pts) if isinstance(radius, (float, int)) else radius
    rows = []
    for i, (p, r) in enumerate(zip(pts, radii)):
        axis = (pts[min(i + 1, len(pts) - 1)] - pts[max(0, i - 1)]).normalized()
        reference = Vector((1, 0, 0)) if abs(axis.x) < 0.85 else Vector((0, 1, 0))
        u = (reference - axis * reference.dot(axis)).normalized()
        v = axis.cross(u)
        rows.append(
            [
                p + r * (u * cos(a) + v * sin(a))
                for a in (TAU * k / sides for k in range(sides))
            ]
        )
    return rings(name, rows, mat, bone)


def patch(name, points, mat, bone):
    # Small turned-over hems, labels and pocket flaps have two visible sides.
    obj = mesh(name, points, [tuple(range(len(points)))], mat, bone)
    return obj


def ellipsoid(name, center, radii, mat, bone, count=18, levels=9):
    rows = []
    for i in range(levels + 1):
        a = pi * (i / levels - 0.5)
        p = (center[0], center[1], center[2] + radii[2] * sin(a))
        rows.append(
            horizontal(
                p, radii[0] * max(0.014, cos(a)), radii[1] * max(0.014, cos(a)), count
            )
        )
    return rings(name, rows, mat, bone)


def retain_bicycle():
    obj = next(o for o in RIG.children if o.type == "MESH")
    allowed = {"Root", "Fork", "WheelBack", "WheelFront", "Crank", "LPedal", "RPedal"}
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    drop = [
        bm.verts[v.index]
        for v in obj.data.vertices
        if not any(obj.vertex_groups[g.group].name in allowed for g in v.groups)
    ]
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    if obj.data.uv_layers.active:
        obj.data.uv_layers.active.name = "Surface UV"
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.material_slot_remove_unused()
    bpy.data.orphans_purge(do_recursive=True)
    return obj


def head_bone():
    bpy.context.view_layer.objects.active = RIG
    RIG.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    head = RIG.data.edit_bones.get("Head") or RIG.data.edit_bones.new("Head")
    head.head, head.tail = NECK, NECK + Vector((0, 0.10, 0))
    head.parent = RIG.data.edit_bones["Body"]
    bpy.ops.object.mode_set(mode="OBJECT")


def skull(x, front, z):
    return NECK + HEAD_SCALE * Vector((x, front, z))


def skin_paint():
    m = material("Courier | sun and freckles", (0.52, 0.27, 0.17), 0.47, sss=0.18)
    v, u = np.mgrid[:512, :1024]
    z = -0.045 + 0.38 * (v + 0.5) / 512
    a = TAU * ((u + 0.5) / 1024 - 0.5)
    rgb = np.zeros((*u.shape, 3)) + np.array([0.817, 0.599, 0.464])

    def tint(angle, height, w, h, amount, color):
        mask = np.exp(-(((a - angle) / w) ** 2) - ((z - height) / h) ** 2) * amount
        rgb[:] += mask[:, :, None] * (np.array(color) - rgb)

    for side in (-1, 1):
        tint(side * 0.60, 0.134, 0.34, 0.045, 0.46, (0.85, 0.46, 0.37))
        tint(side * 1.72, 0.158, 0.26, 0.045, 0.60, (0.77, 0.41, 0.35))
        tint(side * 0.38, 0.164, 0.25, 0.013, 0.25, (0.62, 0.37, 0.32))
    tint(0, 0.126, 0.16, 0.020, 0.50, (0.85, 0.49, 0.40))
    tint(0, 0.078, 0.155, 0.013, 0.70, (0.66, 0.34, 0.29))
    tint(0, 0.068, 0.16, 0.006, 0.55, (0.82, 0.48, 0.42))
    rng = Random(42)
    for _ in range(135):
        angle = rng.choice((-1, 1)) * rng.uniform(0.02, 0.93)
        tint(
            angle,
            rng.gauss(0.140, 0.009),
            rng.uniform(0.003, 0.011),
            rng.uniform(0.0004, 0.0011),
            rng.uniform(0.13, 0.43),
            (0.43, 0.26, 0.19),
        )
    rgb += np.random.default_rng(9).normal(0, 0.005, (*u.shape, 1))
    paint(m, rgb)
    return m


def paint_eye():
    m = material("Courier | hazel iris", (0.65, 0.55, 0.43), 0.25)
    y, x = np.mgrid[:256, :256]
    x, y = (x + 0.5 - 128) / 128, (y + 0.5 - 128) / 128
    r, a = np.hypot(x, y + 0.040), np.arctan2(y + 0.040, x)
    fiber = 0.055 * np.sin(53 * a + 8 * r) + 0.045 * np.sin(77 * a - 13 * r)
    rgb = np.broadcast_to(np.array([0.87, 0.84, 0.77]), (*r.shape, 3)).copy()
    iris = r < 0.49
    rgb[iris] = np.stack((0.46 + fiber, 0.33 + fiber, 0.17 + fiber), axis=2)[iris]
    rgb[(r < 0.52) & ~iris] = [0.21, 0.17, 0.13]
    rgb[r < 0.23] = [0.085, 0.062, 0.048]
    paint(m, rgb)
    return m


def face(source, skin, eye, brow):
    head, left, right, hand = source
    data = head.data
    shape = []
    for vertex in data.vertices:
        x, back, z = vertex.co
        # The asset's lower border flares out to join a bare chest. Taper it
        # inside the shirt collar and retain the original jaw and cheek width.
        neck = 0.64 + 0.36 * max(0, min(1, (z + 0.018) / 0.049))
        shape.append((-x * neck, -back * neck, z))
    uv = [(0.5 + atan2(x, front) / TAU, (z + 0.045) / 0.38) for x, front, z in shape]
    mesh(
        "Sculpted face and ears",
        [skull(*p) for p in shape],
        [tuple(f.vertices) for f in data.polygons],
        skin,
        "Head",
        coords=uv,
    )
    for globe in (left, right):
        delta = globe.location - head.location
        points = [v.co + delta for v in globe.data.vertices]
        eye_uv = [
            (0.5 - v.co.x / 0.078, 0.5 + v.co.z / 0.078) for v in globe.data.vertices
        ]
        mesh(
            "Eyeball",
            [skull(-p.x, -p.y, p.z) for p in points],
            [tuple(f.vertices) for f in globe.data.polygons],
            eye,
            "Head",
            coords=eye_uv,
        )
    surface = BVHTree.FromPolygons(
        [Vector(p) for p in shape], [f.vertices[:] for f in data.polygons]
    )
    for side in (-1, 1):
        # Place the brow on the sculpt itself, following the brow ridge past the temple.
        points = []
        for i in range(10):
            t = i / 9
            x, z = side * (0.018 + 0.066 * t), 0.19 + 0.009 * sin(pi * t) - 0.008 * t
            hit = surface.ray_cast(Vector((x, 0.25, z)), Vector((0, -1, 0)))[0]
            points.append(skull(x, hit.y + 0.001 if hit else 0.14, z))
        tube(
            "Arched brow",
            points,
            [0.0013 + 0.0027 * sin(pi * (i + 1) / 11) for i in range(10)],
            brow,
            "Head",
            7,
        )
    return hand, surface


def hair_and_cap(surface, hair, gleam, cap, seam):
    rng = Random(17)

    # Sections of the cropped hair hug the skull; the visible tips separate at the nape.
    def hairpoint(a, z, depth):
        radial = Vector((sin(a), cos(a), 0))
        origin = Vector((0, 0.012, z))
        hit = surface.ray_cast(origin + 0.32 * radial, -radial)[0]
        radius = (hit - origin).dot(radial) if hit is not None else 0.04
        if abs(sin(a)) > 0.83 and z < 0.189:
            radius = min(radius, 0.115)
        q = origin + radial * (radius + depth)
        return skull(q.x, q.y, q.z)

    def hairline(a):
        return 0.168 + 0.048 * cos(a) + 0.008 * cos(2 * a) + 0.010 * sin(3 * a + 0.2)

    rows = []
    for i in range(11):
        row = []
        for k in range(68):
            a = TAU * k / 68
            z = hairline(a) + (0.314 - hairline(a)) * i / 10
            row.append(hairpoint(a, z, 0.003))
        rows.append(list(reversed(row)))
    # The underside stays open against the scalp. A single concave cap here
    # would cross the eyes at the temples when the fringe follows the forehead.
    faces = [
        (
            i * 68 + j,
            i * 68 + (j + 1) % 68,
            (i + 1) * 68 + (j + 1) % 68,
            (i + 1) * 68 + j,
        )
        for i in range(10)
        for j in range(68)
    ]
    mesh("Chestnut hairline", [p for row in rows for p in row], faces, hair, "Head")
    for k in range(96):
        a = TAU * (k + rng.uniform(-0.24, 0.24)) / 96
        curve = 0.32 + 0.23 * cos(a) + rng.uniform(-0.10, 0.11)
        end = hairline(a + curve) - rng.uniform(0.002, 0.022)
        rows = []
        ridge = []
        for t, width in (
            (0, 0.013),
            (0.18, 0.057),
            (0.40, 0.060),
            (0.66, 0.053),
            (0.84, 0.032),
            (1, 0.002),
        ):
            z = 0.266 + (end - 0.266) * t
            angle = a + curve * (t * t * (3 - 2 * t))
            rows.append(
                [
                    hairpoint(angle + width * cos(b), z, 0.006 + 0.0035 * sin(b))
                    for b in (TAU * j / 8 for j in range(8))
                ]
            )
            ridge.append(hairpoint(angle - 0.012, z + 0.0002, 0.010))
        rings("Combed locks", rows, gleam if k % 5 == 1 else hair, "Head")
        if k % 3 == 0:
            tube(
                "Fine hair strand",
                ridge,
                [0.0002, 0.00045, 0.00045, 0.0004, 0.0003, 0.00012],
                gleam,
                "Head",
                5,
            )

    # Six stitched crown panels over a curved, bound bill. The crown slouches to one side.
    def crown(a, t):
        r = (0.98 + 0.15 * sin(pi * t)) * cos(0.5 * pi * t)
        return skull(
            0.146 * r * sin(a) - 0.016 * t,
            0.010 + 0.166 * r * cos(a) - 0.020 * t,
            0.237 + 0.117 * sin(t * pi / 2) + 0.018 * cos(a) * (1 - t),
        )

    rings(
        "Denim cap band",
        [
            list(
                reversed(
                    [
                        skull(
                            0.141 * sin(a),
                            0.015 + 0.164 * cos(a),
                            0.228 + 0.020 * cos(a) + z,
                        )
                        for a in (TAU * k / 48 for k in range(48))
                    ]
                )
            )
            for z in (-0.002, 0.002, 0.014, 0.020)
        ],
        cap,
        "Head",
    )
    rings(
        "Indigo cycling cap",
        [
            list(reversed([crown(TAU * k / 48, t) for k in range(48)]))
            for t in (0, 0.08, 0.20, 0.34, 0.5, 0.68, 0.84, 0.995)
        ],
        cap,
        "Head",
    )
    for i in range(6):
        a = TAU * i / 6
        tube(
            "Felled cap seam",
            [crown(a, t) for t in (0.01, 0.17, 0.34, 0.50, 0.68, 0.84, 0.98)],
            0.0008,
            seam,
            "Head",
            5,
        )
    bill = []
    for i in range(25):
        a = (i / 24 - 0.5) * 2.85
        p = crown(a, 0)
        edge = p + HEAD_SCALE * Vector(
            (0.012 * sin(a), 0.061 * cos(a) ** 2, -0.014 + 0.008 * sin(a) ** 2)
        )
        bill.append(
            [p, edge, edge - Vector((0, 0, 0.0035)), p - Vector((0, 0, 0.0035))]
        )
    rings("Bound peak", bill, cap, "Head")
    tube("Peak binding", [r[1] for r in bill], 0.0017, seam, "Head", 6)
    ellipsoid("Crown button", crown(0, 1), (0.007, 0.007, 0.004), cap, "Head")


def neckerchief(linen):
    # A narrow folded neckerchief ties to one side under the jacket collar.
    collar = [
        (1.451, 0.048, 0.064, 0.054, 0.012),
        (1.465, 0.052, 0.066, 0.058, 0.026),
        (1.487, 0.064, 0.055, 0.053, 0.025),
        (1.497, 0.067, 0.051, 0.048, 0.016),
    ]
    jacket("Folded neckerchief", collar, linen)
    ellipsoid(
        "Neckerchief knot",
        (-0.039, 0.096, 1.469),
        (0.014, 0.012, 0.014),
        linen,
        "Body",
        14,
        7,
    )
    rings(
        "Short scarf tail",
        [
            [
                (-0.042, 0.098, 1.476),
                (-0.031, 0.106, 1.469),
                (-0.042, 0.109, 1.46),
                (-0.049, 0.101, 1.465),
            ],
            [
                (-0.052, 0.118, 1.449),
                (-0.039, 0.127, 1.450),
                (-0.044, 0.128, 1.445),
                (-0.055, 0.121, 1.445),
            ],
            [
                (-0.067, 0.127, 1.431),
                (-0.055, 0.133, 1.432),
                (-0.059, 0.132, 1.427),
                (-0.065, 0.131, 1.426),
            ],
        ],
        linen,
        "Body",
    )


def wardrobe(coat, hem, shirt, brass, strap, bag, thread):
    jacket(
        "Linen neckband",
        [
            (1.40, 0.025, 0.052, 0.042, 0),
            (1.462, 0.055, 0.053, 0.046, 0),
            (1.480, 0.064, 0.046, 0.044, 0),
        ],
        shirt,
    )
    canvas = jacket(
        "Waxed field jacket",
        [
            (1.018, -0.176, 0.151, 0.126, 0.016),
            (1.045, -0.169, 0.153, 0.126, 0.024),
            (1.095, -0.157, 0.149, 0.124, 0.028),
            (1.14, -0.136, 0.141, 0.111, 0.055),
            (1.24, -0.093, 0.142, 0.117, 0.02),
            (1.34, -0.041, 0.156, 0.121, 0.01),
            (1.415, 0.002, 0.175, 0.115, 0.01),
            (1.451, 0.029, 0.180, 0.096, 0.01),
            (1.473, 0.046, 0.073, 0.065, 0),
        ],
        coat,
    )
    jacket(
        "Turned jacket hem",
        [
            (1.018, -0.176, 0.152, 0.127, 0.02),
            (1.025, -0.174, 0.154, 0.128, 0.021),
            (1.038, -0.171, 0.154, 0.128, 0.022),
        ],
        hem,
    )
    surface = BVHTree.FromPolygons(
        [v.co for v in canvas.data.vertices],
        [f.vertices[:] for f in canvas.data.polygons],
    )

    def shell(x, z, front=1, lift=0.004):
        hit = surface.ray_cast(Vector((x, front * 0.60, z)), Vector((0, -front, 0)))[0]
        if hit is None:
            raise ValueError(f"Coat pattern fell outside its panels at {x} {z}")
        return hit + Vector((0, front * lift, 0))

    for sign in (-1, 1):
        collar = [
            shell(sign * x, z, lift=0.009)
            for x, z in [
                (0.001, 1.46),
                (0.049, 1.469),
                (0.089, 1.446),
                (0.063, 1.399),
                (0.026, 1.421),
            ]
        ]
        patch("Point collar", collar, hem, "Body")
        tube("Collar stitch", collar[2:5], 0.0014, thread, "Body", 5)
        # Each pocket follows the jacket instead of being a flat card.
        for x, z, wide in [(0.088, 1.335, 0.036), (0.088, 1.137, 0.040)]:
            outline = [
                (-wide, 0.025),
                (0, 0.026),
                (wide, 0.024),
                (wide, -0.031),
                (0, -0.048),
                (-wide, -0.032),
            ]
            pouch = [shell(sign * (x + dx), z + dz, lift=0.006) for dx, dz in outline]
            patch("Patch pocket", pouch, coat, "Body")
            tube("Pocket piping", pouch[2:] + pouch[:1], 0.0018, hem, "Body", 6)
            flap = [
                shell(sign * (x + dx), z + dz, lift=0.011)
                for dx, dz in [
                    (-wide, 0.025),
                    (0, 0.027),
                    (wide, 0.024),
                    (wide, -0.002),
                    (0, -0.017),
                    (-wide, -0.002),
                ]
            ]
            patch("Mitred pocket flap", flap, hem, "Body")
            stud = shell(sign * x, z - 0.004, lift=0.013)
            ellipsoid(
                "Pocket snap", stud, (0.0036, 0.0025, 0.0036), brass, "Body", 10, 5
            )
        # Back storm yoke, drawn along the shoulder blades above the bag.
        yoke = [
            shell(sign * x, z, -1, 0.005)
            for x, z in [(0, 1.371), (0.064, 1.382), (0.109, 1.397), (0.14, 1.419)]
        ]
        tube("Back yoke seam", yoke, 0.0033, hem, "Body")
    placket = [
        shell(0, z, lift=0.008)
        for z in (1.055, 1.107, 1.163, 1.221, 1.281, 1.344, 1.407, 1.449)
    ]
    tube("Centre facing", placket, 0.006, hem, "Body")
    for v in placket[::2]:
        ellipsoid(
            "Horn button",
            v + Vector((0, 0.005, 0)),
            (0.0052, 0.003, 0.0052),
            brass,
            "Body",
            10,
            5,
        )
    # Follow the front and back shell around the shoulder, including the centre
    # of the belt where chordal interpolation could otherwise bury its stitching.
    front = [
        shell(x, z, 1, 0.016)
        for x, z in [
            (-0.119, 1.119),
            (-0.098, 1.155),
            (-0.066, 1.202),
            (-0.028, 1.250),
            (0.010, 1.300),
            (0.050, 1.349),
            (0.086, 1.397),
            (0.119, 1.441),
        ]
    ]
    rear = [
        shell(x, z, -1, 0.016)
        for x, z in [
            (0.118, 1.443),
            (0.086, 1.394),
            (0.050, 1.349),
            (0.008, 1.296),
            (-0.033, 1.245),
            (-0.075, 1.199),
            (-0.117, 1.147),
        ]
    ]
    gusset = [
        (-0.153, -0.288, 1.147),
        (-0.16, -0.225, 1.118),
        (-0.161, -0.166, 1.106),
        (-0.151, -0.124, 1.106),
        (-0.137, -0.092, 1.111),
    ]
    path = (
        gusset
        + front
        + [Vector((0.118, 0.021, 1.463))]
        + rear
        + [(-0.146, -0.281, 1.134)]
    )
    rings(
        "Crossbody bridle leather",
        [
            [
                (x - 0.015, y - 0.003, z + 0.008),
                (x + 0.015, y - 0.003, z - 0.008),
                (x + 0.015, y + 0.003, z - 0.008),
                (x - 0.015, y + 0.003, z + 0.008),
            ]
            for x, y, z in path
        ],
        strap,
        "Body",
    )
    for edge in (-1, 1):
        tube(
            "Saddle stitch",
            [(x + edge * 0.009, y + 0.0038, z - edge * 0.005) for x, y, z in front],
            0.0008,
            thread,
            "Body",
            5,
        )

    def back(x, z, depth=0):
        return (x - 0.044, -0.298 + 0.43 * (z - 1.10) + 0.10 * x - depth, z + 0.11 * x)

    outline = [
        (-0.142, 1.101),
        (-0.146, 1.252),
        (-0.132, 1.275),
        (0.123, 1.275),
        (0.142, 1.251),
        (0.137, 1.104),
        (0.118, 1.082),
        (-0.122, 1.082),
    ]
    rings(
        "Post bag gusset",
        [[back(x, z, d) for x, z in outline] for d in (-0.020, 0, 0.018, 0.050)],
        bag,
        "Body",
    )
    outline = [
        (-0.145, 1.274),
        (0.141, 1.274),
        (0.142, 1.184),
        (0.114, 1.159),
        (-0.119, 1.159),
        (-0.146, 1.185),
    ]
    points = [back(x, z, 0.057) for x, z in outline]
    patch("Rain flap", points, bag, "Body")
    tube("Leather piping", points + [points[0]], 0.0045, strap, "Body")
    for x in (-0.093, 0.094):
        p = [
            back(x + u, z, 0.063)
            for u, z in [
                (-0.009, 1.199),
                (0.009, 1.199),
                (0.009, 1.117),
                (-0.009, 1.117),
            ]
        ]
        patch("Leather keeper", p, strap, "Body")
        p = [
            back(x + u, 1.151 + v, 0.068)
            for u, v in [
                (-0.012, -0.007),
                (0.012, -0.007),
                (0.012, 0.007),
                (-0.012, 0.007),
                (-0.012, -0.007),
            ]
        ]
        tube("Rectangular brass buckle", p, 0.0022, brass, "Body", 6)
    points = [
        back(x, z, 0.062)
        for x, z in [(-0.031, 1.209), (0.031, 1.209), (0.031, 1.246), (-0.031, 1.246)]
    ]
    patch("Envelope patch", points, shirt, "Body")
    tube(
        "Post insignia",
        [points[3], back(0, 1.224, 0.065), points[2]],
        0.002,
        hem,
        "Body",
        6,
    )


def sleeve_or_trouser(name, landmarks, groups, sections, mat):
    a, b, c = landmarks
    path = []
    weights = []
    for along, width, depth, crease in sections:
        center = a.lerp(b, along) if along <= 1 else b.lerp(c, along - 1)
        axis = (
            (b - a)
            .normalized()
            .lerp((c - b).normalized(), max(0, min(1, (along - 0.76) / 0.48)))
            .normalized()
        )
        u = (Vector((1, 0, 0)) - axis * axis.x).normalized()
        v = axis.cross(u)
        row = []
        for i in range(20):
            angle = TAU * i / 20
            radial = 1 + crease * (
                0.59 * cos(3 * angle + along * 7) + 0.41 * sin(5 * angle - along * 4)
            )
            row.append(
                center + radial * (u * (width * cos(angle)) + v * (depth * sin(angle)))
            )
        path.append(row)
        w = min(1, max(0, (along - 0.76) / 0.48))
        weights.append({groups[0]: 1 - w, groups[1]: w})
    if name in ("Raglan sleeve", "Tapered work trousers"):
        # The cloth continues into the torso at each socket. The uppermost
        # ring tucks inside the yoke or waistband as the limb rotates.
        seam = 0.045 if name == "Raglan sleeve" else 0.061
        for i, (along, *_) in enumerate(sections):
            blend = max(0, min(1, (0.19 - along) / 0.35))
            path[i] = [
                v + Vector(((-1 if a.x > 0 else 1) * seam * blend, 0, -0.010 * blend))
                for v in path[i]
            ]
            weights[i] = {
                key: strength * (1 - blend) for key, strength in weights[i].items()
            }
            weights[i]["Body"] = blend
    if name == "Forearm":
        # Match the sculpt's 34 × 29 mm wrist opening. The last skin rings
        # rotate with the palm, leaving one continuous contour on a bent wrist.
        palm = groups[0][0] + "Hand"
        for i, (along, width, depth, _) in enumerate(sections):
            bend = min(1, max(0, (along - 1.82) / 0.18))
            if bend:
                height = (2 - along) * (c - b).length
                rim = [
                    c
                    + Vector(
                        (width * cos(TAU * j / 20), -depth * sin(TAU * j / 20), height)
                    )
                    for j in range(20)
                ]
                path[i] = [v.lerp(q, bend) for v, q in zip(path[i], rim)]
                weights[i] = {groups[1]: 1 - bend, palm: bend}
    return rings(name, path, mat, weights)


def limbs(hand, coat, hem, pants, leather, sole, thread, skin):
    coordinates = [(v.co.x, v.co.y, v.co.z) for v in hand.data.vertices]
    faces = [tuple(f.vertices) for f in hand.data.polygons]
    jacket(
        "Trouser seat",
        [
            (0.975, -0.17, 0.126, 0.098, 0.01),
            (1.015, -0.177, 0.143, 0.116, 0.02),
            (1.061, -0.163, 0.136, 0.103, 0.01),
            (1.11, -0.145, 0.130, 0.104, 0.01),
        ],
        pants,
    )
    for s, sign in (("R", 1), ("L", -1)):
        shoulder, elbow, wrist = [
            RIG.data.bones[s + b].head_local.copy()
            for b in ("UpperArm", "Forearm", "Hand")
        ]
        names = [s + "UpperArm", s + "Forearm"]
        sleeve_or_trouser(
            "Raglan sleeve",
            [shoulder, elbow, wrist],
            names,
            [
                (-0.12, 0.039, 0.045, 0),
                (0, 0.056, 0.057, 0.02),
                (0.19, 0.064, 0.062, 0.05),
                (0.50, 0.061, 0.060, 0.04),
                (0.77, 0.062, 0.06, 0.07),
                (0.88, 0.067, 0.064, 0.08),
                (0.96, 0.061, 0.055, 0.1),
                (1.04, 0.062, 0.056, 0.07),
                (1.16, 0.068, 0.061, 0.09),
                (1.31, 0.055, 0.052, 0.05),
                (1.48, 0.050, 0.048, 0.06),
                (1.52, 0.052, 0.049, 0.07),
            ],
            coat,
        )
        sleeve_or_trouser(
            "Rolled cuff",
            [shoulder, elbow, wrist],
            names,
            [
                (1.43, 0.052, 0.05, 0.05),
                (1.47, 0.056, 0.053, 0.05),
                (1.54, 0.055, 0.051, 0.05),
                (1.57, 0.047, 0.045, 0.03),
            ],
            hem,
        )
        sleeve_or_trouser(
            "Forearm",
            [shoulder, elbow, wrist],
            names,
            [
                (1.48, 0.045, 0.042, 0),
                (1.65, 0.043, 0.040, 0),
                (1.83, 0.030, 0.028, 0),
                (1.94, 0.022, 0.018, 0),
                (2.015, 0.0164, 0.0142, 0),
            ],
            skin,
        )
        # A relaxed half curl. The back of the hand follows the grip when steering.
        verts = []
        for x, y, z in coordinates:
            down = -z * 0.65
            curl = max(0, down - 0.068)
            verts.append(
                wrist
                + Vector(
                    (
                        sign * (-x * 0.62 - 0.32 * curl),
                        -y * 0.65 + 0.22 * down + 0.5 * curl,
                        -down + 0.50 * curl,
                    )
                )
            )
        mesh(
            "Hands and fingers",
            verts,
            [tuple(reversed(f)) for f in faces] if sign < 0 else faces,
            skin,
            s + "Hand",
        )
        hip, knee, ankle = [
            RIG.data.bones[s + b].head_local.copy() for b in ("Thigh", "Shin", "Foot")
        ]
        names = [s + "Thigh", s + "Shin"]
        sleeve_or_trouser(
            "Tapered work trousers",
            [hip, knee, ankle],
            names,
            [
                (-0.12, 0.083, 0.078, 0.015),
                (0.02, 0.09, 0.087, 0.03),
                (0.22, 0.093, 0.092, 0.025),
                (0.48, 0.082, 0.083, 0.02),
                (0.75, 0.071, 0.073, 0.04),
                (0.90, 0.067, 0.070, 0.06),
                (1.0, 0.069, 0.072, 0.05),
                (1.10, 0.065, 0.063, 0.11),
                (1.28, 0.063, 0.068, 0.04),
                (1.57, 0.056, 0.053, 0.03),
                (1.75, 0.046, 0.045, 0.07),
                (1.83, 0.049, 0.046, 0.06),
            ],
            pants,
        )
        sleeve_or_trouser(
            "Turned ankle cuff",
            [hip, knee, ankle],
            names,
            [
                (1.78, 0.049, 0.048, 0.05),
                (1.8, 0.051, 0.05, 0.05),
                (1.86, 0.048, 0.047, 0.05),
            ],
            hem,
        )
        # A boot last is narrower at the heel and curves up at the toe.
        bone = s + "Foot"

        def shoe(z, length, width, forward=0.047, origin=ankle):
            row = []
            for i in range(28):
                a = TAU * i / 28
                row.append(
                    origin
                    + Vector(
                        (
                            width * cos(a) * (1 + 0.18 * sin(a)),
                            forward + length * sin(a),
                            z + 0.013 * max(0, sin(a)) ** 3,
                        )
                    )
                )
            return row

        rings(
            "Rubber walking sole",
            [
                shoe(-0.080, 0.126, 0.046),
                shoe(-0.074, 0.131, 0.050),
                shoe(-0.056, 0.132, 0.050),
            ],
            sole,
            bone,
        )
        rings(
            "Welted boot upper",
            [
                shoe(-0.056, 0.132, 0.050),
                shoe(-0.051, 0.131, 0.051),
                shoe(-0.032, 0.127, 0.05),
                shoe(-0.006, 0.107, 0.047, 0.037),
                shoe(0.014, 0.066, 0.041, 0.008),
                shoe(0.051, 0.04, 0.038, -0.002),
                shoe(0.074, 0.040, 0.038, -0.008),
            ],
            leather,
            bone,
        )
        for j in range(4):
            y = 0.021 + 0.017 * j
            z = 0.032 - 0.008 * j
            tube(
                "Crossed boot lace",
                [
                    ankle + Vector((-0.028, y, z)),
                    ankle + Vector((0, y + 0.009, z + 0.004)),
                    ankle + Vector((0.028, y + 0.014, z - 0.003)),
                ],
                0.0016,
                thread,
                bone,
                5,
            )


def main():
    path = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
    bicycle = retain_bicycle()
    head_bone()
    with bpy.data.libraries.load(str(path)) as (_, loaded):
        loaded.objects = [
            "GEO-head_stylized",
            "GEO-head_stylized.eye.L",
            "GEO-head_stylized.eye.R",
            "Hand - Stylized ",
        ]
    skin = skin_paint()
    eye = paint_eye()
    plain_skin = material("Courier | hands", (0.59, 0.315, 0.195), 0.49, sss=0.15)
    coat = fabric("Courier | persimmon waxed cotton", (0.70, 0.385, 0.195), 0.64, 3)
    hem = fabric("Courier | ochre facing", (0.52, 0.285, 0.138), 0.70, 7)
    cap = fabric("Courier | indigo twill", (0.205, 0.287, 0.304), 0.79, 11)
    bag = fabric("Courier | willow canvas", (0.365, 0.435, 0.307), 0.75, 13)
    pants = fabric("Courier | ink denim", (0.218, 0.272, 0.286), 0.78, 16)
    shirt = fabric("Courier | linen", (0.78, 0.73, 0.58), 0.82, 4)
    strap = material("Courier | oiled leather", (0.112, 0.051, 0.024), 0.42)
    thread = material("Courier | waxed thread", (0.47, 0.33, 0.16), 0.67)
    brass = material("Courier | aged brass", (0.53, 0.31, 0.095), 0.32, 0.69)
    hair = material("Courier | chestnut", (0.058, 0.022, 0.013), 0.44)
    gleam = material("Courier | auburn locks", (0.097, 0.040, 0.019), 0.48)
    sole = material("Courier | boot soles", (0.037, 0.031, 0.025), 0.77)
    hand, scalp = face(loaded.objects, skin, eye, hair)
    hair_and_cap(scalp, hair, gleam, cap, pants)
    wardrobe(coat, hem, shirt, brass, strap, bag, thread)
    neckerchief(fabric("Courier | madder kerchief", (0.58, 0.212, 0.152), 0.74, 8))
    limbs(hand, coat, hem, pants, strap, sole, thread, plain_skin)
    bpy.ops.object.select_all(action="DESELECT")
    for part in PARTS + [bicycle]:
        part.select_set(True)
    bpy.context.view_layer.objects.active = bicycle
    bpy.ops.object.join()
    bicycle.name = "Willowbank courier and roadster"
    bicycle.data.name = "Courier, post bag and roadster"
    bpy.ops.object.material_slot_remove_unused()
    bpy.data.orphans_purge(do_recursive=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath, compress=True)


if __name__ == "__main__":
    main()
