"""Pack a captured DeepMimic stride or a generated SOMA walking cycle."""
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


def encode(frames, duration, stride):
    header = struct.pack("<4sHIH", b"WLK1", len(frames), round(duration*1e6), round(stride*1000))
    return header + b"".join(struct.pack("<12h", *(round(v*1000) for v in row)) for row in frames)


def deepmimic(source):
    if hashlib.sha256(source).hexdigest() != DIGEST:
        raise ValueError("expected DeepMimic humanoid3d_walk.txt at the documented revision")
    frames = json.loads(source)["Frames"]
    # The last frame repeats the first pose one stride forward, with zero duration.
    duration = sum(f[0] for f in frames)
    stride = frames[-1][1] - frames[0][1]
    return encode([frame(f) for f in frames[:-1]], duration, stride)


if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] == "kimodo":
        from soma_stride import project
        Path(sys.argv[4]).write_bytes(encode(*project(sys.argv[2], int(sys.argv[3]))))
    elif len(sys.argv) == 3:
        Path(sys.argv[2]).write_bytes(deepmimic(Path(sys.argv[1]).read_bytes()))
    else:
        sys.exit("usage: pack-walk.py CLIP.txt OUT.bin | kimodo SOMA.npz CYCLE OUT.bin")
