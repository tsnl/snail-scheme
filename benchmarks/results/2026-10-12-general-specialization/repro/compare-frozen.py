#!/usr/bin/env python3
"""Compare frozen baseline/candidate Wasm artifacts in fresh rotating runs."""

import argparse
import copy
import json
import sys
from pathlib import Path

ROOT = Path.cwd()
sys.path.insert(0, str(ROOT / "benchmarks"))
import r7rs


# ---- Frozen inputs ----


def read_report(path):
    report = json.loads(path.read_text())
    if report["count"] is not None or report["upstream_revision"] != r7rs.REVISION:
        raise ValueError("comparison requires original inputs at the pinned corpus revision")
    return report


def validate_files(report):
    base = Path(report["output"])
    r7rs.check_hashes(base / "host", report["host_sha256"])
    r7rs.check_hashes(base, {k: v for k, v in report["input_sha256"].items() if k.startswith("inputs/")})
    for tool in ("NODE", "CHEZ"):
        entry = report["tools"][tool]
        r7rs.check_hashes(Path("/"), {entry["path"]: entry["sha256"]})
    for case in report["cases"]:
        if case["status"] not in ("passed", "ready"):
            raise ValueError(f"case unavailable: {case['benchmark']}/{case['system']}")
        r7rs.check_hashes(Path(case["directory"]), {
            **case["artifact_sha256"], "input.txt": case["input_sha256"]})


def selected_cases(report, system, label):
    selected = []
    for original in report["cases"]:
        if original["system"] == system:
            case = copy.deepcopy(original)
            for key in ("preliminary", "blocked_attempts"):
                case.pop(key, None)
            case.update(system=label, status="ready", samples=[])
            selected.append(case)
    return selected


def check_comparable(baseline, candidate):
    for field in ("benchmarks", "upstream_revision", "host_sha256"):
        if baseline[field] != candidate[field]:
            raise ValueError("comparison differs in " + field)
    if baseline["tools"]["NODE"]["sha256"] != candidate["tools"]["NODE"]["sha256"]:
        raise ValueError("Node engine differs")
    old = {c["benchmark"]: c for c in baseline["cases"] if c["system"] == "snail-wasm"}
    for case in candidate["cases"]:
        if case["system"] == "snail-wasm":
            for key in ("source_sha256", "input_sha256"):
                if old[case["benchmark"]][key] != case[key]:
                    raise ValueError(case["benchmark"] + " differs in " + key)


def prepare(args):
    baseline, candidate = read_report(args.baseline), read_report(args.candidate)
    check_comparable(baseline, candidate)
    if any(source["experiment_environment"].get("NODE_OPTIONS") != r7rs.experiment_environment()["NODE_OPTIONS"]
           for source in (baseline, candidate)):
        raise ValueError("NODE_OPTIONS differs from preparation")
    for source in (baseline, candidate):
        validate_files(source)
    report = copy.deepcopy(baseline)
    report.update(complete=False, output=str(args.output), cpu=args.cpu, rounds=args.rounds,
                  order=[], active_attempt=None, systems=["baseline", "candidate", "chez"])
    report["cases"] = (selected_cases(baseline, "snail-wasm", "baseline")
                       + selected_cases(candidate, "snail-wasm", "candidate")
                       + selected_cases(baseline, "chez", "chez"))
    report["comparison_sources"] = {
        name: {"path": str(path), "sha256": r7rs.digest(path.read_bytes()), "revision": source["revision"]}
        for name, path, source in [("baseline", args.baseline, baseline), ("candidate", args.candidate, candidate)]}
    report["comparison_harness_sha256"] = r7rs.digest(Path(__file__).read_bytes())
    report["comparison_environment"] = r7rs.experiment_environment()
    return report


# ---- Checked repetitions ----


def checked_sample(case, timeout):
    sample = SAMPLE_CASE(case, timeout)
    if sample["status"] == "ok" and case["benchmark"] == "cat":
        directory = Path(case["directory"])
        original = directory / "inputs/bib"
        output = directory / "outputs/cat.output"
        try:
            sample["cat_sha256"] = r7rs.digest(output.read_bytes())
            if sample["cat_sha256"] != r7rs.digest(original.read_bytes()):
                sample.update(status="incorrect", diagnostic="cat output differs from input bytes")
        except OSError as error:
            sample.update(status="invalid-output", diagnostic=str(error))
    return sample


SAMPLE_CASE = r7rs.sample_case


def compare(report):
    rows = r7rs.results(report)
    medians = {(row["benchmark"], row["system"]): row["median_seconds"] for row in rows}
    comparisons = []
    for name in report["benchmarks"]:
        old, new = medians[name, "baseline"], medians[name, "candidate"]
        comparisons.append({"benchmark": name, "baseline_seconds": old, "candidate_seconds": new,
                            "baseline_over_candidate": old / new if old and new else None,
                            "chez_seconds": medians[name, "chez"]})
    return comparisons


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", type=int, default=5)
    parser.add_argument("--rounds", type=r7rs.positive, default=3)
    parser.add_argument("--timeout", type=r7rs.positive, default=300)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if (args.output / "results.json").exists():
        raise ValueError("refusing to overwrite comparison results")
    report = prepare(args)
    r7rs.save_report(report, args.output)
    if args.prepare_only:
        return
    r7rs.sample_case = checked_sample
    r7rs.measure(report, args)
    for case in report["cases"]:
        if case["status"] == "ready":
            case["status"] = "passed"
    report["complete"] = True
    r7rs.save_report(report, args.output)
    (args.output / "comparison.json").write_text(json.dumps(compare(report), indent=2) + "\n")
    r7rs.table(report, r7rs.results(report), args.output)
    if any(case["status"] != "passed" for case in report["cases"]):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
