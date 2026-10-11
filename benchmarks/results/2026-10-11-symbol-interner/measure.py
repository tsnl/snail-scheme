#!/usr/bin/env python3
"""Compare compiler hosts and isolate the native initial-heap change."""

import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HARNESS = ROOT / "benchmarks/results/2026-10-10-visitor-typing/measure.py"
spec = importlib.util.spec_from_file_location("compiler_comparison", HARNESS)
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)


# ---- One additional control, with the same frozen input and output checks ----


def main():
    args = comparison.arguments()
    before, after = args.before.resolve(), args.after.resolve()
    reports = [json.loads((path / "results.json").read_text()) for path in (before, after)]
    report = comparison.comparison_report(before, after, args, reports)
    native = next(case for case in report["cases"] if case["system"] == "snail-native-before")
    report["cases"].append({**native, "system": "snail-native-before-4gib", "samples": [],
                            "command": ["env", "GC_INITIAL_HEAP_SIZE=4294967296", *native["command"]]})
    report["control"] = "The before native executable also runs with a 4 GiB initial BDWGC heap."
    report["wrapper_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    try:
        comparison.prepare_references(report, before, args)
        comparison.measure(report, args)
        comparison.verify_sources(before, after, reports)
        comparison.finish_report(report)
    finally:
        comparison.benchmark.save_report(report, args.output)
    for case in report["cases"]:
        print(case["system"], case.get("median_seconds", case["status"]), flush=True)
    return int(any(case["status"] != "passed" for case in report["cases"]))


if __name__ == "__main__":
    raise SystemExit(main())
