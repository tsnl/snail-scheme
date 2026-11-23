"""Pack a released degree-three RadFoam model.pt for the Snail WebGPU renderer."""

import argparse
import math
from pathlib import Path
from tempfile import TemporaryDirectory

import numpy as np
import torch


def array(scene, key, shape, dtype):
    tensor = scene[key]
    if tuple(tensor.shape) != shape or tensor.dtype != dtype:
        raise ValueError(f"{key} must be {dtype} with shape {shape}")
    data = tensor.numpy()
    if dtype == torch.float32 and not np.isfinite(data).all():
        raise ValueError(f"{key} contains non-finite values")
    return data


def pack(checkpoint, directory, scale):
    scene = torch.load(checkpoint, map_location="cpu", weights_only=True)
    n = len(scene["xyz"])
    edges = len(scene["adjacency"])
    if not (0 < 192 * n <= 2**30 and 8 * edges <= 2**30):
        raise ValueError("scene exceeds the renderer's storage buffer limits")
    xyz = array(scene, "xyz", (n, 3), torch.float32)
    raw = array(scene, "density", (n, 1), torch.float32)
    dc = array(scene, "color_dc", (n, 3), torch.float32)
    sh = array(scene, "color_sh", (n, 45), torch.float32)
    offsets = array(scene, "adjacency_offsets", (n + 1,), torch.int64)
    neighbors = array(scene, "adjacency", (edges,), torch.int64)
    if offsets[0] != 0 or offsets[-1] != edges or np.any(offsets[1:] < offsets[:-1]):
        raise ValueError("adjacency_offsets must partition the neighbor array")
    if edges and (neighbors.min() < 0 or neighbors.max() >= n):
        raise ValueError("adjacency contains a site outside the checkpoint")

    # World coordinates and extinction per world unit. The optimizer stores
    # raw density; the renderer sees the reference's beta=10 softplus.
    density = scale * torch.nn.functional.softplus(torch.from_numpy(raw), beta=10).numpy()
    if not np.isfinite(density).all():
        raise ValueError("activated density must be finite")
    with TemporaryDirectory(dir=directory.parent) as staging:
        dest = Path(staging) / "scene"
        dest.mkdir()
        np.concatenate((xyz, density), axis=1).astype("<f4", copy=False).tofile(dest / "sites.f32")
        np.concatenate((dc, sh), axis=1).astype("<f4", copy=False).tofile(dest / "sh.f32")
        offsets.astype("<u4").tofile(dest / "offsets.u32")
        neighbors.astype("<u4").tofile(dest / "neighbors.u32")
        dest.rename(directory)
    print(f"{n:,} sites, {edges:,} directed neighbor entries")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("directory", type=Path, help="new output directory")
    parser.add_argument("--activation-scale", type=float, default=1.0,
                        help="activation_scale from the checkpoint's config.yaml (default 1)")
    args = parser.parse_args()
    if args.directory.exists():
        parser.error("output directory already exists")
    if not math.isfinite(args.activation_scale) or args.activation_scale <= 0:
        parser.error("activation scale must be finite and positive")
    args.directory.parent.mkdir(parents=True, exist_ok=True)
    pack(args.checkpoint, args.directory, args.activation_scale)
