#!/usr/bin/env python3
"""Compare warm-cache linked builds without overwriting frozen run artifacts."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import time


# ---- Frozen build recipes ----


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare_case(report_path, benchmark):
    report = json.loads(report_path.read_text())
    case = next(case for case in report["cases"]
                if case["system"] == "snail-wasm" and case["benchmark"] == benchmark)
    directory = Path(case["directory"])
    for name in ("program.scm", "program.wasm", "build.scm"):
        assert sha256(directory / name) == case["artifact_sha256"][name], name
    return {"report": str(report_path), "report_sha256": sha256(report_path),
            "revision": report["revision"], "case": case}


def build_one(prepared, directory, cpu):
    directory.mkdir(parents=True)
    case = prepared["case"]
    frozen = Path(case["directory"])
    # Keep the compiler root and source path exactly as prepared. Only outputs
    # move; no measured executable, input, or preparation report is overwritten.
    script = (frozen / "build.scm").read_text()
    for name in ("program.wasm", "build.trace.json"):
        script = script.replace(str(frozen / name), str(directory / name))
    (directory / "build.scm").write_text(script)
    command = ["taskset", "-c", str(cpu), *case["build_command"][:-1], str(directory / "build.scm")]
    start = time.monotonic()
    with (directory / "stdout").open("wb") as stdout, (directory / "stderr").open("wb") as stderr:
        result = subprocess.run(command, stdout=stdout, stderr=stderr, timeout=900)
    elapsed = time.monotonic() - start
    assert result.returncode == 0, (directory, result.returncode)
    digest = sha256(directory / "program.wasm")
    assert digest == case["artifact_sha256"]["program.wasm"], (directory, digest)
    return {"command": command, "wall_seconds": elapsed, "exit": result.returncode,
            "wasm_sha256": digest, "frozen_wasm_identical": True}


# ---- Alternating fresh compiler processes ----


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--benchmark", default="graphs")
    parser.add_argument("--cpu", type=int, default=5)
    parser.add_argument("--rounds", type=int, default=3)
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True)
    sources = {name: prepare_case(path, args.benchmark)
               for name, path in (("baseline", args.baseline), ("candidate", args.candidate))}
    assert sources["baseline"]["case"]["source_sha256"] == sources["candidate"]["case"]["source_sha256"]
    report = {"benchmark": args.benchmark, "sources": sources, "cpu": args.cpu,
              "rounds": args.rounds, "samples": [], "complete": False,
              "scope": "Fresh Chibi process and complete linked Wasm build; existing local Rust caches and warm file cache; excludes prior compiler/runtime setup.",
              "environment": {key: os.environ.get(key) for key in
                              ("BINARYEN_CORES", "WASM_MERGE", "SNAIL_REAL_WASM_MERGE", "NODE_OPTIONS")},
              "harness_sha256": sha256(Path(__file__))}
    for number in range(args.rounds + 1):
        labels = ("baseline", "candidate") if number % 2 == 0 else ("candidate", "baseline")
        for label in labels:
            sample = build_one(sources[label], args.output / f"round-{number}" / label, args.cpu)
            sample.update(system=label, round=number, preliminary=(number == 0))
            report["samples"].append(sample)
            (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
            print(number, label, sample["wall_seconds"], flush=True)
    report["medians"] = {label: statistics.median(sample["wall_seconds"] for sample in report["samples"]
                                                 if sample["system"] == label and not sample["preliminary"])
                         for label in sources}
    report["complete"] = True
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
