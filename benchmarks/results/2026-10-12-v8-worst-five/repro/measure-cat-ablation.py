#!/usr/bin/env python3
"""Measure the output-checked cat environment ablation against its WAT control."""

import argparse
import copy
import importlib.util
import json
import shutil
from pathlib import Path

spec = importlib.util.spec_from_file_location("comparison", Path(__file__).with_name("compare-frozen.py"))
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)
r7rs = comparison.r7rs


def prepare_case(original, mode, artifacts, output):
    case = copy.deepcopy(original)
    directory = output / mode
    directory.mkdir()
    (directory / "inputs").symlink_to(Path(original["directory"]) / "inputs", target_is_directory=True)
    (directory / "outputs").mkdir()
    for name in ("input.txt", "program.scm"):
        shutil.copy2(Path(original["directory"]) / name, directory / name)
    shutil.copy2(artifacts / (mode + ".wasm"), directory / "program.wasm")
    case.update(system=mode, status="ready", directory=str(directory), samples=[])
    for key in ("preliminary", "build", "build_command"):
        case.pop(key, None)
    case["command"][-1] = str(directory / "program.wasm")
    case["artifact_sha256"] = {p.name: r7rs.digest(p.read_bytes()) for p in directory.iterdir() if p.is_file()}
    return case


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("artifacts", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", type=int, default=5)
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir()
    baseline = comparison.read_report(args.baseline)
    comparison.validate_files(baseline)
    manifest = json.loads((args.artifacts / "manifest.json").read_text())
    r7rs.check_hashes(args.artifacts, manifest["artifacts"])
    original = next(c for c in baseline["cases"] if c["benchmark"] == "cat" and c["system"] == "snail-wasm")
    report = copy.deepcopy(baseline)
    report.update(complete=False, output=str(args.output), cpu=args.cpu, rounds=args.rounds,
                  order=[], active_attempt=None, benchmarks=["cat"], systems=["roundtrip", "reuse-environment"])
    report["cases"] = [prepare_case(original, mode, args.artifacts, args.output) for mode in report["systems"]]
    report["ablation"] = manifest
    report["baseline_report"] = {"path": str(args.baseline), "sha256": r7rs.digest(args.baseline.read_bytes())}
    report["measurement_script_sha256"] = r7rs.digest(Path(__file__).read_bytes())
    report["comparison_environment"] = r7rs.experiment_environment()
    r7rs.sample_case = comparison.checked_sample
    r7rs.save_report(report, args.output)
    r7rs.measure(report, args)
    for case in report["cases"]:
        if case["status"] == "ready":
            case["status"] = "passed"
    report["complete"] = True
    r7rs.save_report(report, args.output)
    r7rs.table(report, r7rs.results(report), args.output)
    if any(c["status"] != "passed" for c in report["cases"]):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
