#!/usr/bin/env python3
"""Compare complete Fibonacci programs on Snail, Chez, and Chibi."""

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
from pathlib import Path

import measure

ROOT = measure.ROOT
BUILD = ROOT / "build/scheme-comparison"


# ---- Identical workloads and native lowering ----


def build_native(wasm):
    output = wasm.with_suffix("")
    wat = wasm.with_suffix(".wasm.wat")
    script = output.with_suffix(".native.scm")
    quoted = [json.dumps(str(path)) for path in (output, ROOT, wat, BUILD)]
    program, root, source, directory = quoted
    script.write_text(
        "(import (scheme base) (scheme file) (scheme read) (snail-scheme native-link) "
        "(snail-scheme chromium-trace))\n"
        f"(with-chromium-trace-to {json.dumps(str(output) + '.native.trace.json')} "
        f"(lambda () (link-native {root} (call-with-input-file {source} read) "
        f"{directory} {program})))\n"
    )
    measure.run([os.environ.get("CHIBI", "chibi-scheme"), "-I", "src", script])
    return [output]


def build_variants(workload):
    source = measure.tail_source if workload == "tail-fibonacci" else measure.scheme_source
    arguments = "i32 i32 i32 i32" if workload == "tail-fibonacci" else "i32 i32 i32"
    plain = source("").replace(" (snail typing)", "")
    typed = source(f"(: fibonacci (-> {arguments}))")
    commands = {}
    for name, contents, mode, workers in (
        ("untyped", plain, "boxed", 0), ("i32", typed, "optimized", 1)
    ):
        command = measure.build_scheme(f"{workload}-{name}", "", mode, contents)
        wat = command[-1].with_suffix(".wasm.wat").read_text()
        assert measure.count_i32_workers(wat) == workers
        commands[f"snail-wasm-{name}"] = command
        commands[f"snail-native-{name}"] = build_native(command[-1])
    source_path = BUILD / f"{workload}-untyped.scm"
    chez = BUILD / f"{workload}-chez.so"
    measure.run([os.environ.get("CHEZ", "scheme"), "--script", "benchmarks/chez.scm", source_path, chez])
    commands["chez-safe-O2"] = [os.environ.get("CHEZ", "scheme"), "--program", chez]
    commands["chibi"] = [os.environ.get("CHIBI", "chibi-scheme"), source_path]
    return commands


# ---- Rotating measurements and provenance ----


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes():
    paths = measure.run(["git", "ls-files", "src", "bootstrap", "tests", "benchmarks/typing"])
    paths = [ROOT / name for name in paths.splitlines()]
    paths += [Path(__file__), ROOT / "benchmarks/cpu.scm", ROOT / "benchmarks/chez.scm",
              ROOT / "Cargo.toml", ROOT / "Cargo.lock", ROOT / "rust-toolchain.toml"]
    return {str(path.relative_to(ROOT)): digest(path) for path in sorted(set(paths)) if path.is_file()}


def provenance():
    versions = {name: {"path": shutil.which(command),
                       "version": subprocess.check_output([command, flag], text=True, stderr=subprocess.STDOUT).strip()}
                for name, command, flag in (
        ("chez", os.environ.get("CHEZ", "scheme"), "--version"),
        ("chibi", os.environ.get("CHIBI", "chibi-scheme"), "-V"),
        ("node", os.environ.get("NODE", "node"), "--version"),
        ("clang", os.environ.get("CLANG", "clang"), "--version"),
        ("binaryen", os.environ.get("WASM_OPT", "wasm-opt"), "--version"))}
    return {"base_revision": measure.run(["git", "rev-parse", "HEAD"]).strip(),
            "source_diff": measure.run(["git", "diff", "HEAD"]), "source_sha256": source_hashes(),
            "platform": platform.platform(), "versions": versions,
            "environment": {name: os.environ.get(name) for name in (
                "CHIBI", "CHEZ", "NODE", "CLANG", "WASM_OPT", "WASM_AS", "WASM_MERGE", "CARGO",
                "BDWGC_INCLUDE", "BDWGC_LIB", "BINARYEN_CORES", "RUSTFLAGS", "GC_INITIAL_HEAP_SIZE",
                "GC_FREE_SPACE_DIVISOR", "SNAIL_NATIVE_GC_INTERVAL")},
            "cpu_model": next(line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines()
                              if line.startswith("model name"))}


def measure_workload(workload, commands, args):
    repetitions = 1048576 if workload == "tail-fibonacci" else 256
    expected, results, order = 4204971 * repetitions, {name: [] for name in commands}, []
    names = list(commands)
    preliminary = {name: measure.sample(command, repetitions, args.cpu, expected)
                   for name, command in commands.items()}
    for index in range(args.rounds):
        for name in names[index % len(names):] + names[:index % len(names)]:
            results[name].append(measure.sample(commands[name], repetitions, args.cpu, expected))
            order.append([index + 1, name])
        print(f"{workload}: round {index + 1}/{args.rounds}", flush=True)
    return {"workload": workload, "repetitions": repetitions, "checksum": expected,
            "discarded_seconds": preliminary,
            "warmup_repetitions": repetitions if workload == "tail-fibonacci" else 0,
            "order": order, "variants": {name: measure.describe(command, results[name])
                                           for name, command in commands.items()}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rounds", type=int, default=8)
    parser.add_argument("--cpu", type=int, default=2)
    parser.add_argument("--output", type=Path, default=BUILD / "results.json")
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error("--rounds must be positive")
    BUILD.mkdir(parents=True, exist_ok=True)
    measure.BUILD = BUILD
    workloads = {}
    for name in ("fibonacci", "tail-fibonacci"):
        print(f"Building {name}", flush=True)
        workloads[name] = build_variants(name)
    report = {**provenance(), "complete": False, "cpu": args.cpu, "rounds": args.rounds, "discarded_runs": 1,
              "scope": "Complete Scheme programs; internal workload timers exclude compilation and startup. "
              "Tail workload has a full in-process warmup. Chez uses safe O2. "
              "Snail partial evaluation is disabled; i32 specialization is enabled only in the i32 variants. "
              "Native and Wasm lower the same emitted WAT. Chibi and Chez use the exact untyped Snail source, "
              "with only the Chez import/time/record adapter. Required checks remain enabled.",
              "generated_sources": {path.name: {"sha256": digest(path), "text": path.read_text()}
                                    for path in sorted(BUILD.iterdir()) if path.suffix in (".scm", ".sps")},
              "workloads": []}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    for name, commands in workloads.items():
        result = measure_workload(name, commands, args)
        report["workloads"].append(result)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
        for name, variant in result["variants"].items():
            print(f"{name}: {variant['median_seconds']:.6f} s", flush=True)
    report["complete"] = True
    args.output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
