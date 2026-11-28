"""Project one 30 Hz Kimodo SOMA walking cycle onto the game humanoid."""
import math

import numpy as np


# SOMA bone order (nv-tlabs/kimodo, skeleton/definitions.py). The demo ships
# 30-joint samples. The current CLI expands the hands and toes to 77 joints.
# For each side the indices identify the hip, shoulder and toe-contact label.
SOMA = {30: ((26, 17, 3), (22, 11, 1)), 77: ((72, 40, 4), (67, 12, 1))}


def load_soma(source):
    with np.load(source, allow_pickle=False) as motion:
        p = motion["posed_joints"].astype(np.float64)
        rot = motion["global_rot_mats"]
        contacts = motion["foot_contacts"]
    if p.ndim != 3 or p.shape[1] not in SOMA or p.shape[2] != 3:
        raise ValueError("expected SOMA joint positions [frames, 30 or 77, 3]")
    sides = SOMA[p.shape[1]]
    contact_count = 4 if p.shape[1] == 30 else 6
    if rot.shape != (*p.shape, 3) or contacts.shape != (len(p), contact_count):
        raise ValueError("rotation or foot contact dimensions disagree with skeleton")
    if not (np.isfinite(p).all() and np.isfinite(rot).all() and np.isfinite(contacts).all()):
        raise ValueError("non-finite motion")

    return p, rot, contacts, sides


def walking_cycle(contacts, right_toe, cycle):
    # Successive right heel strikes enclose exactly one gait cycle. Keep its
    # second strike just long enough to measure displacement and the loop seam.
    right_heel = contacts[:, right_toe-1] > 0.5
    strikes = np.flatnonzero(right_heel[1:] & ~right_heel[:-1]) + 1
    if not 0 <= cycle < len(strikes)-1:
        raise ValueError(f"expected a cycle index between 0 and {len(strikes)-2}")
    return strikes[cycle:cycle+2]


def walking_direction(p, rot):
    delta = p[-1, 0] - p[0, 0]
    delta[1] = 0
    stride = np.linalg.norm(delta)
    if stride < 0.1:
        raise ValueError("cycle has too little forward travel")
    forward = delta/stride
    heading = rot[:, 0, :, 2].copy()  # The SOMA character faces +Z at rest.
    heading[:, 1] = 0
    if np.any(heading @ forward < math.cos(math.radians(35))*np.linalg.norm(heading, axis=1)):
        raise ValueError("cycle turns or moves sideways beyond the sagittal rig")

    return forward, stride


def project(source, cycle):
    p, rot, contacts, sides = load_soma(source)
    a, b = walking_cycle(contacts, sides[0][2], cycle)
    p, rot, contacts = p[a:b+1], rot[a:b+1], contacts[a:b+1]
    forward, stride = walking_direction(p, rot)

    def down(v):
        return np.arctan2(v @ forward, -v[:, 1])

    trunk = down(-rot[:, 0, :, 1])
    legs, arms, planted = [], [], []
    for hip, shoulder, toe in sides:
        thigh = down(p[:, hip+1] - p[:, hip])
        shin = down(p[:, hip+2] - p[:, hip+1])
        sole = rot[:, hip+2, :, 2]
        legs.extend((thigh-trunk, shin-thigh, np.arctan2(sole[:, 1], sole @ forward)-shin))
        upper = down(p[:, shoulder+1] - p[:, shoulder])
        lower = down(p[:, shoulder+2] - p[:, shoulder+1])
        arms.extend((upper-trunk, lower-upper))
        # Measure horizontal toe speed only across pairs of planted frames.
        stance = contacts[:, toe] > 0.5
        travel = np.diff(p[:, hip+3, :], axis=0)[stance[1:] & stance[:-1]]
        planted.extend(np.linalg.norm(travel[:, [0, 2]], axis=1)*30)
    if not planted:
        raise ValueError("cycle has no planted toe intervals")
    # Scale linear quantities to the game's thigh + shin length in metres.
    h = sides[0][0]
    length = sum(np.linalg.norm(p[:, i+1]-p[:, i], axis=1).mean() for i in (h, h+1))
    scale = (0.421546 + 0.409870)/length
    rows = np.stack([*legs, trunk, p[:, 0, 1]*scale, *arms], axis=1)
    seam = np.sqrt(np.mean((rows[-1, :6] - rows[0, :6])**2))
    if seam > 0.25:
        raise ValueError(f"leg poses do not form a continuous loop (seam RMS {seam:.3f} rad)")
    duration = (b-a)/30
    print(f"frames {a}:{b}, speed {stride*scale/duration:.3f} m/s, "
          f"leg seam RMS {seam:.3f} rad, planted toe speed {np.mean(planted)*scale:.3f} m/s")
    return rows[:-1], duration, stride*scale
