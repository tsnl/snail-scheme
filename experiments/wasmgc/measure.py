#!/usr/bin/env python3
"""Rotate fixed, prebuilt artifacts; keep compilation outside reported timers."""

import hashlib
import json
import os
import platform
import re
import statistics
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/wasmgc"
NATIVE = Path(
    os.environ.get(
        "NATIVE_CONTROLS",
        "/tmp/snail-native-ssa-20261010/experiments/native-ssa/results.json",
    )
)
NODE = os.environ.get(
    "NODE", "/nix/store/q1r7qkrnbhakljr4j228v2yi2874jkl9-nodejs-slim-24.15.0/bin/node"
)
REPETITIONS, ROUNDS, CPU = 64, 8, 2


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def commands():
    controls = json.loads(NATIVE.read_text())["artifacts"]
    result = {
        name: controls[name]["command"]
        for name in ("vm", "ssa-fastcc", "chez", "chibi")
    }
    for name, flags, module in [
        ("v8-raw", ["--no-liftoff"], "cpu"),
        ("v8-opt", ["--no-liftoff"], "cpu-opt"),
        ("v8-liftoff", ["--liftoff-only"], "cpu-opt"),
    ]:
        result[name] = [
            NODE,
            *flags,
            "--no-wasm-lazy-compilation",
            str(ROOT / "experiments/wasmgc/run.mjs"),
            str(OUT / f"{module}.wasm"),
        ]
    if (OUT / "wasmtime-run").exists():
        result["wasmtime-opt"] = [str(OUT / "wasmtime-run"), str(OUT / "cpu-opt.wasm")]
    translated = ROOT / "build/wasm-llvm/cpu"
    if translated.exists():
        result["wasm-llvm-bdwgc"] = [str(translated)]
    return result


def sample(name, command):
    start = time.monotonic()
    text = subprocess.check_output([*command, str(REPETITIONS)], cwd=ROOT, text=True)
    checksum = int(re.search(r"checksum: (\d+)", text)[1])
    assert checksum == 269118144, text
    return {
        "variant": name,
        "elapsed_seconds": float(re.search(r"elapsed: ([\d.]+) s", text)[1]),
        "wall_seconds": time.monotonic() - start,
        "checksum": checksum,
    }


def collect(variants):
    for name, command in variants.items():
        sample(name, command)
    samples, items = [], list(variants.items())
    for round_index in range(ROUNDS):
        offset = round_index % len(items)
        for name, command in items[offset:] + items[:offset]:
            samples.append({**sample(name, command), "round": round_index + 1})
    return samples


def artifacts(variants):
    return {
        name: {
            "command": command,
            "file_sha256": {
                path: digest(path) for path in command if Path(path).is_file()
            },
        }
        for name, command in variants.items()
    }


def provenance(variants):
    sources = sorted((ROOT / "experiments/wasmgc").glob("*"))
    sources += sorted((ROOT / "experiments/wasm-llvm").glob("*"))
    native_build = ROOT / "build/wasm-llvm/build-commands.json"
    return {
        "base_revision": "3891fc8e173b1e5622a0105f84fc2587f4363fa2",
        "native_prototype_revision": "362b524",
        "host": platform.platform(),
        "node": subprocess.check_output([NODE, "--version"], text=True).strip(),
        "toolchains": {
            "binaryen": "132",
            "wasmtime": "48.0.0",
            "chez": "10.4.1",
            "chibi": "0.12",
            "llvm": "22.1.8",
            "bdwgc": "8.2.12",
        },
        "source_sha256": {
            str(path.relative_to(ROOT)): digest(path)
            for path in sources
            if path.is_file()
        },
        "artifacts": artifacts(variants),
        "build_commands": json.loads((OUT / "build-commands.json").read_text()),
        "native_build_commands": json.loads(native_build.read_text())
        if native_build.exists()
        else [],
        "target_architectures": {
            "vm": "i686",
            "ssa-fastcc": "i686",
            "wasm-llvm-bdwgc": "x86_64",
            "wasm_engines": "x86_64",
        },
        "scope": "HIR-selected numeric function uses dynamic WasmGC refs and i31 fast paths. "
        "Same recursion, inputs, repetitions and weighted checksum. Wasm outer loops "
        "are JS/C with 256 host calls; native controls retain the Scheme VM harness.",
    }


def measure():
    os.sched_setaffinity(0, {CPU})
    variants = commands()
    samples = collect(variants)
    medians = {
        name: statistics.median(
            s["elapsed_seconds"] for s in samples if s["variant"] == name
        )
        for name in variants
    }
    report = {
        **provenance(variants),
        "repetitions": REPETITIONS,
        "rounds": ROUNDS,
        "affinity": [CPU],
        "warmups": 1,
        "workload_sha256": digest(ROOT / "benchmarks/cpu.scm"),
        "clock": "Internal execution seconds; compilation and startup excluded",
        "commands": variants,
        "samples": samples,
        "median_seconds": medians,
        "ratios_to_native_ssa": {
            name: value / medians["ssa-fastcc"] for name, value in medians.items()
        },
        "ratios_to_chez": {
            name: value / medians["chez"] for name, value in medians.items()
        },
        "ratios_to_chibi": {
            name: value / medians["chibi"] for name, value in medians.items()
        },
    }
    (OUT / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(
        json.dumps(
            {key: report[key] for key in ("median_seconds", "ratios_to_native_ssa")},
            indent=2,
        )
    )


if __name__ == "__main__":
    measure()
