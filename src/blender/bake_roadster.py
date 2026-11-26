"""Bake the Roadster's seated, standing and steering actions in its open .blend.

The feet and level pedal platforms share a crank circle. Elbows and knees are
two rigid links. Arm actions use steering angle as their clock, independently
of the pedal stroke, so the hands stay on the grips while coasting.
"""

from math import cos, pi, sin, sqrt

import bpy
from mathutils import Matrix, Quaternion, Vector

SIDES = (("R", 1), ("L", -1))
CYCLING = ("Pedal", "Climb")
STEERING = ("Reach", "Standing reach")
ON_FOOT = ("Idle", "Walk", "Run", "Step left", "Step right")


def bone_head(rig, name):
    return rig.data.bones[name].head_local.copy()


def middle_joint(start, end, pole, upper_length, lower_length):
    span = end - start
    distance = span.length
    axis = span / distance
    projected = (distance**2 + upper_length**2 - lower_length**2) / (2 * distance)
    along = min(upper_length, max(0, projected))
    side = (pole - axis * pole.dot(axis)).normalized()
    return start + along * axis + side * sqrt(max(0, upper_length**2 - along**2))


def link_pose(start, end, posed_start, posed_end):
    rest, posed = end - start, posed_end - posed_start
    return (
        posed_start - start,
        rest.rotation_difference(posed),
        posed.length / rest.length,
    )


def torso(phase, standing):
    rock = sin(phase) * standing
    shift = Vector((0.017 * rock, 0.135 * standing, 0.080 * standing + 0.012 * rock**2))
    return shift, Quaternion((1, 0, 0), -0.095 - 0.105 * standing)


def arm_pose(rig, standing, steering, brace=0):
    shift, tilt = torso(0, standing)
    shift += Vector((0, 0.12 * brace, -0.025 * brace))
    tilt = Quaternion((1, 0, 0), -0.48 * brace) @ tilt
    pelvis, pivot = bone_head(rig, "Body"), bone_head(rig, "Fork")
    lock = Quaternion((0, 0, 1), steering)
    pose = {}
    for side, sign in SIDES:
        shoulder, elbow, wrist = [
            bone_head(rig, side + n) for n in ("UpperArm", "Forearm", "Hand")
        ]
        raised = pelvis + shift + tilt @ (shoulder - pelvis)
        grip = pivot + lock @ (wrist - pivot)
        bent = middle_joint(
            raised,
            grip,
            Vector((sign * 0.32, -0.77, -0.40)),
            (elbow - shoulder).length,
            (wrist - elbow).length,
        )
        pose[side + "UpperArm"] = link_pose(shoulder, elbow, raised, bent)
        pose[side + "Forearm"] = link_pose(elbow, wrist, bent, grip)
        pose[side + "Hand"] = grip - wrist, lock, 1
    return pose


def pedal_pose(rig, phase, standing):
    shift, tilt = torso(phase, standing)
    rotation = Quaternion((1, 0, 0), -phase)
    pose = {"Body": (shift, tilt, 1), "Crank": (Vector((0, 0, 0)), rotation, 1)}
    axle = bone_head(rig, "Crank")
    for side, sign in SIDES:
        hip, knee, ankle = [bone_head(rig, side + n) for n in ("Thigh", "Shin", "Foot")]
        platform = bone_head(rig, side + "Pedal") - axle
        travel = rotation @ platform - platform
        raised, shoe = hip + shift, ankle + travel
        bent = middle_joint(
            raised,
            shoe,
            Vector((0.055 * sign, 1, 0.15)),
            (knee - hip).length,
            (ankle - knee).length,
        )
        pose[side + "Thigh"] = link_pose(hip, knee, raised, bent)
        pose[side + "Shin"] = link_pose(knee, ankle, bent, shoe)
        pose[side + "Foot"] = pose[side + "Pedal"] = travel, Quaternion(), 1
    return pose


def walking_back(rig, phase):
    pose = {}
    shift = Vector((0.012 * sin(phase), 0, -0.13))
    pose["Body"] = shift, Quaternion((1, 0, 0), -0.065), 1
    for side, sign in SIDES:
        hip, knee, ankle = [bone_head(rig, side + n) for n in ("Thigh", "Shin", "Foot")]
        planted = sign * sin(phase)
        toe = Vector(
            (
                0.17 * sign,
                hip.y + 0.12 + 0.20 * planted,
                0.13 + 0.10 * max(0, sign * sin(phase - pi / 2)),
            )
        )
        start = hip + shift
        middle = middle_joint(
            start,
            toe,
            Vector((0.15 * sign, 1, 0.2)),
            (knee - hip).length,
            (ankle - knee).length,
        )
        pose[side + "Thigh"] = link_pose(hip, knee, start, middle)
        pose[side + "Shin"] = link_pose(knee, ankle, middle, toe)
        pose[side + "Foot"] = toe - ankle, Quaternion(), 1
    return pose


def reach_limb(rig, pose, side, names, start, end, pole, tip_rotation):
    a, b, c = [bone_head(rig, side + n) for n in names]
    mid = middle_joint(start, end, Vector(pole), (b - a).length, (c - b).length)
    pose[side + names[0]] = link_pose(a, b, start, mid)
    pose[side + names[1]] = link_pose(b, c, mid, end)
    pose[side + names[2]] = end - c, tip_rotation, 1


def shoe_contact(t, running):
    # While one sole bears weight it travels backward by exactly the ground
    # covered by the root. During swing the toe lifts and overtakes the hip.
    stance, stride = (0.38, 2.24) if running else (0.59, 1.32)
    span = stride * stance
    if t < stance:
        p = t / stance
        return span * (0.5 - p), 0.081, 0.11 * (1 - p) ** 4 - 0.21 * p**6
    p = (t - stance) / (1 - stance)
    eased = p * p * (3 - 2 * p)
    return (
        span * (eased - 0.5),
        0.081 + (0.29 if running else 0.13) * sin(pi * p),
        -0.33 * sin(2 * pi * p),
    )


def on_foot(rig, cycle, gait):
    phase = 2 * pi * cycle
    moving, running = gait != "Idle", gait == "Run"
    pelvis = bone_head(rig, "Body")
    sway = (0.016 if moving else 0.003) * cos(phase)
    height = (0.816 if running else 0.844) + (
        0.035 if running else 0.013 if moving else 0.003
    ) * cos(2 * phase)
    base = Vector((sway, 0, height))
    tilt = Quaternion((1, 0, 0), 0.25 if running else 0.435)
    turn = Quaternion(
        (0, 0, 1), (0.095 if running else 0.055 if moving else 0.005) * sin(phase)
    )
    gaze = Quaternion((1, 0, 0), -0.025)
    if not moving:
        base.x -= 0.024
        gaze = (
            Quaternion((0, 0, 1), -0.09 + 0.07 * sin(phase))
            @ Quaternion((0, 1, 0), 0.035)
            @ gaze
        )
    pose = {
        "Body": (base - pelvis, turn @ tilt, 1),
        "Head": (Vector(), tilt.inverted() @ gaze, 1),
    }
    for side, sign in SIDES:
        t = (cycle + (0.5 if sign < 0 else 0)) % 1
        hip = base + Vector((sign * 0.10, 0, 0))
        y, z, roll = shoe_contact(t, running) if moving else (0.031 * sign, 0.081, 0)
        foot = Vector((sign * (0.106 if moving else 0.133), y, z))
        reach_limb(
            rig,
            pose,
            side,
            ("Thigh", "Shin", "Foot"),
            hip,
            foot,
            (0.06 * sign, 1, 0.08),
            Quaternion((1, 0, 0), roll),
        )
        shoulder = base + turn @ tilt @ (bone_head(rig, side + "UpperArm") - pelvis)
        swing = (
            -cos(2 * pi * t) * (0.205 if running else 0.148) if moving else 0.008 * sign
        )
        hand = shoulder + Vector(
            (
                sign * (0.062 if running else 0.046),
                (0.11 if running else 0.025) + swing,
                (-0.298 if running else -0.421) + 0.16 * abs(swing),
            )
        )
        pole = (sign * 0.20, -1, -0.45)
        wrist = Quaternion((1, 0, 0), 0.14 + swing)
        if not moving and sign > 0:
            # He hooks a hand over the strap while waiting for Moss. Anchor
            # the wrist to the jacket so breathing carries the hand with it.
            hand = base + turn @ tilt @ Vector((0.064, 0.313, 0.260))
            pole = (0.35, -0.45, -1)
            wrist = Quaternion((1, 0, 0), 2.94) @ Quaternion((0, 1, 0), -0.20)
        reach_limb(
            rig,
            pose,
            side,
            ("UpperArm", "Forearm", "Hand"),
            shoulder,
            hand,
            pole,
            wrist,
        )
    return pose


def cross_saddle(rig, side):
    # The destination foot takes the load, the other clears the back of the
    # saddle. During this pose the world root is halfway to its landing spot.
    pelvis = bone_head(rig, "Body")
    base = Vector((-side * 0.11, -0.13, 1.066))
    tilt = Quaternion((0, 1, 0), -side * 0.12) @ Quaternion((1, 0, 0), -0.12)
    pose = {
        "Body": (base - pelvis, tilt, 1),
        "Head": (Vector(), Quaternion((1, 0, 0), 0.08), 1),
    }
    for limb, sign in SIDES:
        hip = base + Vector((sign * 0.114, 0, 0))
        shoe = (
            Vector((side * 0.235, -0.04, 0.32))
            if sign == side
            else Vector((-side * 0.215, -0.56, 0.93))
        )
        reach_limb(
            rig,
            pose,
            limb,
            ("Thigh", "Shin", "Foot"),
            hip,
            shoe,
            (sign * 0.40, 1, 0.35),
            Quaternion((1, 0, 0), -0.23),
        )
        shoulder = base + tilt @ (bone_head(rig, limb + "UpperArm") - pelvis)
        hand = bone_head(rig, limb + "Hand") + Vector((-side * 0.22, 0, 0.055))
        if sign != side:
            hand = shoulder + Vector((sign * 0.26, -0.04, -0.22))
        reach_limb(
            rig,
            pose,
            limb,
            ("UpperArm", "Forearm", "Hand"),
            shoulder,
            hand,
            (sign * 0.28, -1, -0.5),
            Quaternion(),
        )
    return pose


def impact_pose(rig, tuck):
    # Detached limb targets are relative to the pelvis. Each pair of rigid
    # links keeps its measured length as the hands guard and the knees tuck.
    pose = {"Body": (Vector(), Quaternion(), 1)}
    for side, sign in SIDES:
        for names, delta, pole in [
            (
                ("UpperArm", "Forearm", "Hand"),
                (0.12 * sign, -0.18 + 0.26 * tuck, 0.03 + 0.42 * tuck),
                (0.65 * sign, -0.6, -0.4),
            ),
            (
                ("Thigh", "Shin", "Foot"),
                (0.09 * sign, -0.19 + 0.11 * sign + 0.25 * tuck, 0.08 + 0.30 * tuck),
                (0.16 * sign, 1, 0.2),
            ),
        ]:
            a, b, c = [bone_head(rig, side + n) for n in names]
            end = c + Vector(delta)
            mid = middle_joint(a, end, Vector(pole), (b - a).length, (c - b).length)
            pose[side + names[0]] = link_pose(a, b, a, mid)
            pose[side + names[1]] = link_pose(b, c, mid, end)
            pose[side + names[2]] = end - c, Quaternion(), 1
    return pose


def bake(rig, name, frames):
    animation = rig.animation_data
    action = bpy.data.actions.new(name)
    animation.action = action
    previous = {}
    for frame, pose in frames:
        for name_, (position, rotation, stretch) in pose.items():
            bone = rig.pose.bones[name_]
            bone.rotation_mode = "QUATERNION"
            rotation = rotation.copy()
            if name_ in previous:
                rotation.make_compatible(previous[name_])
            previous[name_] = rotation
            bone.location, bone.rotation_quaternion, bone.scale = (
                position,
                rotation,
                (stretch,) * 3,
            )
            for channel in ("location", "rotation_quaternion", "scale"):
                bone.keyframe_insert(data_path=channel, frame=frame, group=name_)
    slot = animation.action_slot
    track = animation.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, int(action.frame_range[0]), action)
    strip.action_slot = slot
    track.mute = True
    animation.action = None
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)


def main():
    rig = next(
        o
        for o in bpy.context.scene.objects
        if o.type == "ARMATURE" and "Crank" in o.data.bones
    )
    tracks = rig.animation_data.nla_tracks
    rig.animation_data.action = None
    for track in list(tracks):
        track.mute = True
        if track.name in CYCLING + STEERING + ON_FOOT + (
            "Brace",
            "Tumble",
            "Walk back",
        ):
            action = track.strips[0].action
            tracks.remove(track)
            bpy.data.actions.remove(action)
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    for standing, name in enumerate(CYCLING):
        bake(
            rig,
            name,
            ((i + 1, pedal_pose(rig, 2 * pi * i / 32, standing)) for i in range(33)),
        )
    for standing, name in enumerate(STEERING):
        bake(
            rig,
            name,
            ((i + 1, arm_pose(rig, standing, (i / 8 - 0.5) * 1.20)) for i in range(9)),
        )

    def brace(steer):
        arms = arm_pose(rig, 0, steer, 1)
        arms["Body"] = Vector((0, 0.12, -0.025)), Quaternion((1, 0, 0), -0.575), 1
        return arms

    bake(
        rig,
        "Walk back",
        ((i + 1, walking_back(rig, 2 * pi * i / 24)) for i in range(25)),
    )
    bake(rig, "Brace", ((i + 1, brace((i / 8 - 0.5) * 1.20)) for i in range(9)))
    bake(rig, "Tumble", ((i + 1, impact_pose(rig, i / 8)) for i in range(9)))
    for name in ("Idle", "Walk", "Run"):
        bake(rig, name, ((i, on_foot(rig, i / 32, name)) for i in range(33)))
    for side, name in ((-1, "Step left"), (1, "Step right")):
        bake(rig, name, [(0, cross_saddle(rig, side)), (1, cross_saddle(rig, side))])
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath, compress=True)


if __name__ == "__main__":
    main()
