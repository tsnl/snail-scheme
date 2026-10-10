#!/usr/bin/env python3
"""Build the isolated HIR-to-WasmGC experiment before any timing runs."""

import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/wasmgc"
BINARYEN = "/nix/store/nd1279k2zlbp23gfqcl0qp5xk40xlxr8-binaryen-132/bin"
CHIBI = os.environ.get(
    "CHIBI",
    shutil.which("chibi-scheme")
    or "/nix/store/rymbc3gyix886hxf3ns6cr7smmc9swy2-chibi-scheme-0.12/bin/chibi-scheme",
)
NODE = os.environ.get(
    "NODE",
    shutil.which("node")
    or "/nix/store/q1r7qkrnbhakljr4j228v2yi2874jkl9-nodejs-slim-24.15.0/bin/node",
)
COMMANDS = []
FEATURES = [
    "--mvp-features",
    "--enable-gc",
    "--enable-reference-types",
    "--enable-tail-call",
    "--enable-mutable-globals",
]


def run(command):
    COMMANDS.append([str(value) for value in command])
    subprocess.run(COMMANDS[-1], cwd=ROOT, check=True)


def tool(name):
    return os.environ.get(
        name.upper().replace("-", "_"), shutil.which(name) or f"{BINARYEN}/{name}"
    )


def build(source, name):
    descriptor, wat = OUT / f"{name}.sexp", OUT / f"{name}.wat"
    run(
        [CHIBI, "-I", "src", "experiments/wasmgc/compile.scm", ROOT, source, descriptor]
    )
    run(["python3", "experiments/wasmgc/emit.py", descriptor, wat])
    run([tool("wasm-as"), wat, *FEATURES, "-g", "-o", OUT / f"{name}.wasm"])
    run(
        [
            tool("wasm-opt"),
            OUT / f"{name}.wasm",
            *FEATURES,
            "-O3",
            "-g",
            "-o",
            OUT / f"{name}-opt.wasm",
        ]
    )


def build_wasmtime():
    include = os.environ.get(
        "WASMTIME_INCLUDE",
        "/nix/store/zk67k91by6w8h0al8dd764qhl3rgq2g6-wasmtime-48.0.0-dev/include",
    )
    library = os.environ.get(
        "WASMTIME_LIB",
        "/nix/store/jrqxad974ahz55ka8dq2xr618mx51x4a-wasmtime-48.0.0-lib/lib",
    )
    if not Path(include).is_dir():
        print("Wasmtime C API not found; skipping that optional runner")
        return
    run(
        [
            os.environ.get("CC", "cc"),
            "-O3",
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "experiments/wasmgc/wasmtime-run.c",
            "-I" + include,
            "-L" + library,
            "-Wl,-rpath," + library,
            "-lwasmtime",
            "-o",
            OUT / "wasmtime-run",
        ]
    )


def check_modules():
    for module in ["check.wasm", "check-opt.wasm"]:
        run([NODE, "--no-liftoff", "experiments/wasmgc/check.mjs", OUT / module])
    run(
        [NODE, "--liftoff-only", "experiments/wasmgc/check.mjs", OUT / "check-opt.wasm"]
    )


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    build("benchmarks/cpu.scm", "cpu")
    build("experiments/wasmgc/check.scm", "check")
    check_modules()
    build_wasmtime()
    (OUT / "build-commands.json").write_text(json.dumps(COMMANDS, indent=2) + "\n")
