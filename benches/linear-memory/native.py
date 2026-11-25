"""Time checked and unchecked native builds of the same C kernels on Linux."""

import ctypes as c
import json
import os
from pathlib import Path
from shutil import which
import statistics
import subprocess
import sys
from time import perf_counter_ns


def load(checked):
    name = "checked" if checked else "unchecked"
    library = out / f"native-{name}.so"
    obj = library.with_suffix(".o")
    driver = os.environ.get("NATIVE_CC", "clang")
    original = Path(which(driver)).resolve().parent.parent / "nix-support/orig-cc"
    # The Nix host wrapper removes -march=native. Use its Clang to generate
    # the object and the host wrapper to supply the platform's link paths.
    compiler = Path(original.read_text().strip()) / "bin/clang" if original.is_file() else driver
    flags = ["-DCHECK_BOUNDS"] if checked else []
    subprocess.run([compiler, "-O3", "-march=native", "-fPIC", *flags,
                    "-c", src / "managers.c", "-o", obj], check=True)
    subprocess.run([driver, "-shared", obj, "-o", library], check=True)
    api = c.CDLL(str(library))
    ptr, i64 = c.c_void_p, c.c_longlong
    for function, result, args in [
        ("prepare_walls", ptr, [i64, i64]), ("cast", c.c_double, [ptr, i64, c.c_double, c.c_int]),
        ("prepare_grid", ptr, []), ("set_open", None, [ptr, i64, c.c_int]),
        ("packed_field", None, [ptr, i64]), ("grid_distance", i64, [ptr, i64]),
    ]:
        fn = getattr(api, function)
        fn.argtypes, fn.restype = args, result
    return "Native C " + name, api


def measure(workload, cases, expected, repetitions=1):
    samples = {name: [] for name, _ in cases}
    for round_no in range(22):
        for offset in range(len(cases)):
            name, run = cases[(round_no + offset) % len(cases)]
            start = perf_counter_ns()
            for _ in range(repetitions):
                result = run()
            elapsed = (perf_counter_ns() - start) / repetitions / 1e6
            assert result == expected, (name, result, expected)
            if round_no >= 7:
                samples[name].append(elapsed)
    for name, ms in samples.items():
        print(json.dumps(dict(workload=workload, name=name, medianMs=statistics.median(ms),
                              minMs=min(ms), maxMs=max(ms))))


def rays(walls, phase, count, seed, checksum):
    cases = []
    for name, api in builds:
        scene = api.prepare_walls(walls, phase)
        for mode, label in enumerate(["dense", "WallId"]):
            def run(api=api, scene=scene, mode=mode):
                return api.cast(scene, count, seed, mode)
            cases.append((name + " " + label, run))
    measure(dict(rays=count, walls=walls, phase=phase, seed=seed, checksum=checksum), cases, checksum)


def fields(seed):
    data = json.loads((out / f"grid-{seed}.json").read_text())
    hub, far = data["goals"]
    cases = []
    for name, api in builds:
        grid = api.prepare_grid()
        for slot, walkable in enumerate(data["open"]):
            api.set_open(grid, slot, walkable)
        for goal, expected in zip(data["goals"], data["fields"], strict=True):
            api.packed_field(grid, goal)
            assert [api.grid_distance(grid, i) for i in range(len(expected))] == expected

        def run(api=api, grid=grid):
            api.packed_field(grid, hub)
            there = api.grid_distance(grid, far)
            api.packed_field(grid, far)
            return there + api.grid_distance(grid, hub)
        cases.append((name, run))
    measure(dict(game="Siegework distance field", seed=seed, fields=2), cases,
            data["fields"][0][far] + data["fields"][1][hub], 8)


if len(sys.argv) != 2:
    sys.exit("usage: python3 native.py OUTPUT_DIRECTORY")
out, src = Path(sys.argv[1]).resolve(), Path(__file__).resolve().parent
subprocess.run(["node", src / "managers.mjs", out, "--write-grids"], check=True)
builds = [load(True), load(False)]
rays(12, 0, 50_000, -2.375, 342894.0)
rays(96, 3, 12_500, 1.125, 33763.25)
fields(1)
fields(4)
