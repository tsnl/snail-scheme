#!/usr/bin/env python3
"""Execute independent semantic cases against saved baseline observations."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_one(candidate, fixtures, output, name, baseline, mode, expected_exit, diagnostic):
    source = fixtures / f"{name}.scm"
    prefix = output / f"{name}-{mode}"
    wasm = prefix.with_suffix(".wasm")
    command = ["chibi-scheme", "-I", str(candidate / "src"),
               str(candidate / "tests/build-typed-program.scm"),
               str(candidate), str(source), str(wasm), mode]
    started = time.monotonic()
    with Path(str(prefix) + ".build.stdout").open("wb") as stdout, Path(str(prefix) + ".build.stderr").open("wb") as stderr:
        compiled = subprocess.run(command, cwd=candidate, stdout=stdout, stderr=stderr, timeout=240)
    assert compiled.returncode == 0, (name, mode, compiled.returncode)
    compile_seconds = time.monotonic() - started
    command = ["node", "--no-warnings", str(candidate / "scripts/run-wasi.mjs"), str(wasm)]
    result = subprocess.run(command, cwd=candidate, capture_output=True, timeout=180)
    Path(str(prefix) + ".stdout").write_bytes(result.stdout)
    Path(str(prefix) + ".stderr").write_bytes(result.stderr)
    expected = (fixtures / f"{baseline}.stdout").read_bytes()
    assert result.returncode == expected_exit, (name, mode, result.returncode, result.stderr)
    assert result.stdout == expected, (name, mode, result.stdout, expected)
    assert diagnostic.encode() in result.stderr, (name, mode, result.stderr)
    return {"source": str(source), "source_sha256": digest(source), "mode": mode,
            "compile_wall_seconds_overlapped": compile_seconds, "wasm_sha256": digest(wasm),
            "baseline_wasm_sha256": digest(fixtures / f"{baseline}.wasm"),
            "baseline_stdout_sha256": hashlib.sha256(expected).hexdigest(),
            "stdout_identical": True, "exit": result.returncode, "diagnostic": diagnostic}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--fixtures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.candidate, args.fixtures, args.output = (path.resolve() for path in
                                                  (args.candidate, args.fixtures, args.output))
    args.output.mkdir(parents=True)
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=args.candidate, text=True).strip()
    report = {"compiler": revision, "harness_sha256": digest(Path(__file__)), "complete": False, "runs": []}
    cases = (("specialization-semantics", "baseline-semantics", 0, ""),
             ("specialization-boundaries", "baseline-boundaries", 0, ""),
             ("instance-error-order", "baseline-instance-order", 1, "incorrect value type"))
    for name, baseline, expected_exit, diagnostic in cases:
        for mode in ("optimized", "folded"):
            result = check_one(args.candidate, args.fixtures, args.output,
                               name, baseline, mode, expected_exit, diagnostic)
            report["runs"].append(result)
            (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
            print(name, mode, "passed", flush=True)
    report["complete"] = True
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
