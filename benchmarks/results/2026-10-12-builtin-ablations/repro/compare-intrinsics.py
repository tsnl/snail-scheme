#!/usr/bin/env python3
"""Compare two frozen workload sets, preserving full cat checks per run."""

import argparse
import copy
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path.cwd()
sys.path.insert(0, str(ROOT / "benchmarks"))
import r7rs

HELPER = ROOT / "benchmarks/results/2026-10-12-general-specialization/repro/compare-frozen.py"
SPEC = importlib.util.spec_from_file_location("frozen_comparison", HELPER)
FROZEN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FROZEN)


# ---- Frozen inputs ----


def read_source(path):
    source = FROZEN.read_report(path)
    FROZEN.validate_files(source)
    report = copy.deepcopy(source)
    return source, report


def prepare(args):
    old, baseline = read_source(args.baseline)
    new, candidate = read_source(args.candidate)
    FROZEN.check_comparable(baseline, candidate)
    for field in ("harness_sha256", "experiment_environment", "build_environment", "input_sha256"):
        if old[field] != new[field]:
            raise ValueError("comparison differs in " + field)
    if old["experiment_environment"] != r7rs.experiment_environment():
        raise ValueError("current experiment environment differs from preparation")
    report = copy.deepcopy(baseline)
    report.update(complete=False, output=str(args.output), cpu=args.cpu, rounds=args.rounds,
                  order=[], active_attempt=None, systems=["baseline", "candidate"])
    report["cases"] = (FROZEN.selected_cases(baseline, "snail-wasm", "baseline")
                       + FROZEN.selected_cases(candidate, "snail-wasm", "candidate"))
    report["comparison_sources"] = {
        label: {"path": str(path), "sha256": r7rs.digest(path.read_bytes()), "revision": source["revision"]}
        for label, path, source in [("baseline", args.baseline, old), ("candidate", args.candidate, new)]}
    report["comparison_harness_sha256"] = r7rs.digest(Path(__file__).read_bytes())
    report["comparison_environment"] = r7rs.experiment_environment()
    report["scope"] = "Clean typed-intrinsic ablation; original inputs, fresh processes, upstream workload timers."
    return report


# ---- Checked rotating repetitions ----


def checked_sample(case, timeout):
    sample = FROZEN.checked_sample(case, timeout)
    if sample["status"] == "ok" and case["benchmark"] == "cat":
        directory = Path(case["directory"])
        sample["cat_input_bytes"] = (directory / "inputs/bib").stat().st_size
        sample["cat_output_bytes"] = (directory / "outputs/cat.output").stat().st_size
        if sample["cat_output_bytes"] != sample["cat_input_bytes"]:
            sample.update(status="incorrect", diagnostic="cat output byte length differs")
    return sample


def summary(report):
    rows = r7rs.results(report)
    medians = {(row["benchmark"], row["system"]): row["median_seconds"] for row in rows}
    return [{"benchmark": name, "baseline_seconds": medians[name, "baseline"],
             "candidate_seconds": medians[name, "candidate"],
             "baseline_over_candidate": medians[name, "baseline"] / medians[name, "candidate"],
             "elapsed_reduction_fraction": 1 - medians[name, "candidate"] / medians[name, "baseline"]}
            for name in report["benchmarks"]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", type=int, default=5)
    parser.add_argument("--rounds", type=r7rs.positive, default=3)
    parser.add_argument("--timeout", type=r7rs.positive, default=300)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if (args.output / "results.json").exists():
        raise ValueError("refusing to overwrite comparison results")
    report = prepare(args)
    r7rs.sample_case = checked_sample
    r7rs.measure(report, args)
    for case in report["cases"]:
        if case["status"] == "ready":
            case["status"] = "passed"
    report["complete"] = True
    r7rs.save_report(report, args.output)
    if any(case["status"] != "passed" for case in report["cases"]):
        raise SystemExit(1)
    (args.output / "comparison.json").write_text(json.dumps(summary(report), indent=2) + "\n")
    r7rs.table(report, r7rs.results(report), args.output)


if __name__ == "__main__":
    main()
