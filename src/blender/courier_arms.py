"""Fit the open CC0 forearm and hand sculpt to the Roadster and rig its digits."""

from collections import Counter, defaultdict

import bpy
from mathutils import Vector

# Blender Studio sculpt face sets follow the actual joints. Adjacent regions
# share their ring of vertices, including the wrist and the thumb saddle.
FOREARM, PALM = 262, 273
DIGITS = {
    "Index": (278, 283, 282),
    "Middle": (277, 279, 272),
    "Ring": (280, 274, 275),
    "Little": (281, 286, 276),
    "Thumb": (359, 285, 284),
}


def dress_arm(rig, source, side, sign, skin, mesh, middle_joint):
    data = source.data
    sets = data.attributes[".sculpt_face_set"].data
    names = {FOREARM: "Forearm", PALM: "Hand", 263: "UpperArm"}
    for digit, regions in DIGITS.items():
        names.update((region, digit + str(i)) for i, region in enumerate(regions, 1))
    members = defaultdict(set)
    weights = defaultdict(Counter)
    faces = []
    for face in data.polygons:
        region = sets[face.index].value
        if region not in names or face.center.x <= 0:
            continue
        members[region].update(face.vertices)
        if region != 263:
            faces.append(list(face.vertices))
            for i in face.vertices:
                weights[i][side + names[region]] += 1

    def joint(a, b):
        ring = members[a] & members[b]
        return sum((data.vertices[i].co for i in ring), Vector()) / len(ring)

    native_wrist, native_elbow = joint(PALM, FOREARM), joint(FOREARM, 263)
    shoulder = rig.data.bones[side + "UpperArm"].head_local.copy()
    wrist = Vector((0.217 * sign, 0.305, 1.062))
    elbow = middle_joint(
        shoulder, wrist, Vector((0.32 * sign, -0.77, -0.40)), 0.267, 0.228
    )

    def mirror(v):
        return Vector((sign * v.x, -v.y, v.z))

    def hand(p):
        return wrist + 0.75 * mirror(p - native_wrist)

    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    edit = rig.data.edit_bones
    for name, p in (("Forearm", elbow), ("Hand", wrist)):
        bone = edit[side + name]
        bone.head, bone.tail = p, p + Vector((0, 0.10, 0))
    for digit, regions in DIGITS.items():
        parent, before = edit[side + "Hand"], PALM
        for i, region in enumerate(regions, 1):
            name = side + digit + str(i)
            bone = edit.get(name) or edit.new(name)
            bone.head = hand(joint(before, region))
            bone.tail = bone.head + Vector((0, 0.015, 0))
            bone.parent = parent
            parent, before = bone, region
    bpy.ops.object.mode_set(mode="OBJECT")

    axis = native_wrist - native_elbow
    towards = mirror(axis).rotation_difference(wrist - elbow)
    vertices, influences, indices = [], [], {}
    for i, counts in weights.items():
        p = data.vertices[i].co
        t = (p - native_elbow).dot(axis) / axis.length_squared
        # Blend both the shape and its weights over the wrist crease. The
        # forearm and hand use the same vertex there, whichever way it bends.
        blend = max(0, min(1, (t - 0.88) / 0.20))
        along = elbow.lerp(wrist, t)
        across = mirror(p - native_elbow - axis * t)
        position = (along + 0.81 * (towards @ across)).lerp(hand(p), blend)
        if side + "Forearm" in counts:
            influence = {side + "Forearm": 1 - blend, side + "Hand": blend}
        else:
            influence = {name: n / counts.total() for name, n in counts.items()}
        indices[i] = len(vertices)
        vertices.append(position)
        influences.append(influence)
    polygons = [
        [indices[i] for i in (reversed(face) if sign > 0 else face)] for face in faces
    ]
    mesh("Forearm, wrist and fingers", vertices, polygons, skin, influences)
