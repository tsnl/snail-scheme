"""Pack the pinned DeepMimic humanoid3d_walk clip into the game's sagittal rig."""
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

DIGEST = "32d082c3599bc40aac50b1afa196ff1e2cf3842bb40f0541ab088845f6328a41"


def compose(a, b):
    w, x, y, z = a
    v, i, j, k = b
    return (w*v-x*i-y*j-z*k, w*i+x*v+y*k-z*j,
            w*j-x*k+y*v+z*i, w*k+x*j-y*i+z*v)


def hinge(angle):
    return math.cos(angle/2), 0, 0, math.sin(angle/2)


def pitch(q):
    # Direction of the bone's downward local Y axis projected into world XY.
    w, x, y, z = q
    return math.atan2(2*(w*z-x*y), 1-2*(x*x+z*z))


def foot_pitch(q):
    w, x, y, z = q
    return math.atan2(2*(w*z+x*y), 1-2*(y*y+z*z))


def leg(root, f, i):
    thigh = compose(root, f[i:i+4])
    shin = compose(thigh, hinge(f[i+4]))
    foot = compose(shin, f[i+5:i+9])
    return pitch(thigh)-pitch(root), pitch(shin)-pitch(thigh), foot_pitch(foot)-pitch(shin)


def frame(f):
    root = f[4:8]
    chest = compose(root, f[8:12])
    def arm(i):
        shoulder = compose(chest, f[i:i+4])
        forearm = compose(shoulder, hinge(f[i+4]))
        return pitch(shoulder)-pitch(root), pitch(forearm)-pitch(shoulder)

    return (*leg(root, f, 16), *leg(root, f, 30), pitch(root), f[2],
            *arm(25), *arm(39))


def pack(source):
    if hashlib.sha256(source).hexdigest() != DIGEST:
        raise ValueError("expected DeepMimic humanoid3d_walk.txt at the documented revision")
    frames = json.loads(source)["Frames"]
    # The last frame repeats the first pose one stride forward, with zero duration.
    duration = sum(f[0] for f in frames)
    stride = frames[-1][1] - frames[0][1]
    header = struct.pack("<4sHIH", b"WLK1", len(frames)-1, round(duration*1e6), round(stride*1000))
    return header + b"".join(struct.pack("<12h", *(round(v*1000) for v in frame(f)))
                             for f in frames[:-1])


if __name__ == "__main__":
    Path(sys.argv[2]).write_bytes(pack(Path(sys.argv[1]).read_bytes()))
