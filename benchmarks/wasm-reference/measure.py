#!/usr/bin/env python3
"""Freeze and measure only the five explicitly selected Rust/WASI references."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = Path(__file__).resolve().parent
FIVE = ("cat", "lattice", "wc", "graphs", "deriv")
CSV = re.compile(r"\+!CSVLINE!\+([^,]+),([^,]+),([0-9.eE+-]+)")

# ---- Frozen artifacts ----

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def command_output(command):
    result = subprocess.run(command, text=True, capture_output=True, check=True)
    return result.stdout.strip()


def tools():
    return {
        "rustc": command_output(["rustc", "--version", "--verbose"]),
        "cargo": command_output(["cargo", "--version"]),
        "node": command_output(["node", "--version"]),
        "node_versions": json.loads(command_output(["node", "-p", "JSON.stringify(process.versions)"])),
        "paths": {name: shutil.which(name) for name in ("rustc", "cargo", "node", "taskset")},
        "sha256": {name: digest(shutil.which(name)) for name in ("rustc", "cargo", "node")},
    }


def freeze_inputs(source, output):
    (output / "inputs").mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / "inputs/bib", output / "inputs/bib")
    shutil.copytree(REFERENCE / "src", output / "reference-source/src", dirs_exist_ok=True)
    for name in ("Cargo.toml", "Cargo.lock", "run-wasi.mjs", "measure.py", "validate.py"):
        shutil.copy2(REFERENCE / name, output / "reference-source" / name)
    upstream = output / "upstream"
    (upstream / "inputs").mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / "inputs/bib", upstream / "inputs/bib")
    shutil.copy2(source / "results.json", upstream / "results.json")
    for name in FIVE:
        target = upstream / "cases" / name / "snail-wasm"
        target.mkdir(parents=True, exist_ok=True)
        for filename in ("input.txt", "program.scm"):
            shutil.copy2(source / "cases" / name / "snail-wasm" / filename, target / filename)


def prepare_case(name, system, source, chez_report, chez_source, output):
    case = output / "cases" / name / system
    case.mkdir(parents=True, exist_ok=True)
    (case / "outputs").mkdir(exist_ok=True)
    shutil.copy2(source / "cases" / name / "snail-wasm/input.txt", case / "input.txt")
    shutil.copy2(source / "cases" / name / "snail-wasm/program.scm", case / "upstream.scm")
    if not (case / "inputs").exists():
        (case / "inputs").symlink_to(output / "inputs", target_is_directory=True)
    return prepare_command(name, system, case, chez_report, chez_source)


def prepare_command(name, system, case, chez_report, chez_source):
    if system == "rust-wasm":
        shutil.copy2(REFERENCE / "target/wasm32-wasip1/release" / f"{name}.wasm", case / "program.wasm")
        return [shutil.which("node"), "--no-warnings", str(case.parents[2] / "reference-source/run-wasi.mjs"), str(case / "program.wasm")]
    original = next(item for item in chez_report["cases"] if item["benchmark"] == name and item["system"] == "chez")
    original_path = chez_source / "cases" / name / "chez"
    for filename in ("program.so", "program.scm", "compile.scm"):
        shutil.copy2(original_path / filename, case / filename)
    return [original["command"][0], "--program", str(case / "program.so")]


def case_metadata(name, system, case, command):
    artifact = case / ("program.wasm" if system == "rust-wasm" else "program.so")
    return {
        "benchmark": name, "system": system, "directory": str(case), "command": command,
        "input_sha256": digest(case / "input.txt"), "source_sha256": digest(case / "upstream.scm"),
        "artifact_sha256": digest(artifact), "artifact_bytes": artifact.stat().st_size,
        "preliminary": None, "samples": [],
    }

# ---- Workload checks and timing ----

def validate(case, completed):
    match = CSV.search(completed.stdout)
    if completed.returncode or not match or "INCORRECT" in completed.stdout:
        raise RuntimeError(f"failed {case['benchmark']}/{case['system']}: {completed.stdout}\n{completed.stderr}")
    checks = {"original_predicate": True}
    if case["benchmark"] == "cat":
        filename = Path(case["directory"]) / "outputs/cat.output"
        checks.update(output_sha256=digest(filename), output_bytes=filename.stat().st_size)
        if checks["output_sha256"] != digest(Path(case["directory"]) / "inputs/bib"):
            raise RuntimeError("cat output differs from the complete input")
    result = re.search(r"^Result: (.+)$", completed.stdout, re.MULTILINE)
    if result:
        checks.update(result=result[1], result_sha256=hashlib.sha256(result[1].encode()).hexdigest())
    return float(match[3]), checks


def run_case(case, cpu, retained, round_number):
    command = ["taskset", "-c", str(cpu), *case["command"]]
    with (Path(case["directory"]) / "input.txt").open() as source:
        start = time.perf_counter()
        completed = subprocess.run(command, stdin=source, cwd=case["directory"], text=True, capture_output=True, timeout=300)
        process_seconds = time.perf_counter() - start
    workload_seconds, checks = validate(case, completed)
    return {"retained": retained, "round": round_number, "command": command,
            "workload_seconds": workload_seconds, "process_seconds": process_seconds,
            "returncode": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr, "checks": checks}


def write_report(filename, report):
    filename.write_text(json.dumps(report, indent=2) + "\n")


def measurement_order(cases, number):
    benchmarks = list(dict.fromkeys(case["benchmark"] for case in cases))
    rotated = benchmarks[number % len(benchmarks):] + benchmarks[:number % len(benchmarks)]
    order = []
    for name in rotated:
        group = [case for case in cases if case["benchmark"] == name]
        if (number + benchmarks.index(name)) % 2:
            group.reverse()
        order.extend(group)
    return order


def measure(report, filename, rounds, cpu):
    cases = report["cases"]
    for case in cases:
        case["preliminary"] = run_case(case, cpu, False, -1)
        write_report(filename, report)
    for number in range(rounds):
        order = measurement_order(cases, number)
        report["order"].append([f"{case['benchmark']}/{case['system']}" for case in order])
        for case in order:
            sample = run_case(case, cpu, True, number)
            case["samples"].append(sample)
            print(f"round {number + 1}: {case['benchmark']}/{case['system']} {sample['workload_seconds']:.6f}s", flush=True)
            write_report(filename, report)


def summarize(report):
    for case in report["cases"]:
        case["median_workload_seconds"] = statistics.median(sample["workload_seconds"] for sample in case["samples"])
        case["median_process_seconds"] = statistics.median(sample["process_seconds"] for sample in case["samples"])
    report["complete"] = True

# ---- Command line ----

def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("/tmp/snail-api-five-b218ce2-20261012/build/ordinary-five-prepared"))
    parser.add_argument("--chez-source", type=Path, default=Path("/tmp/snail-container-final-measurement-20261012/build/pre-storage-five"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--benchmarks", choices=FIVE, nargs="+", default=list(FIVE))
    parser.add_argument("--systems", choices=("rust-wasm", "chez"), nargs="+", default=["rust-wasm", "chez"])
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--cpu", type=int, default=5)
    parser.add_argument("--prepare-only", action="store_true")
    return parser.parse_args()


def prepare(args):
    output = args.output.resolve().parent
    output.mkdir(parents=True, exist_ok=True)
    source_report = json.loads((args.source / "results.json").read_text())
    chez_report = json.loads((args.chez_source / "results.json").read_text())
    freeze_inputs(args.source, output)
    cases = []
    for name in args.benchmarks:
        for system in args.systems:
            command = prepare_case(name, system, args.source, chez_report, args.chez_source, output)
            cases.append(case_metadata(name, system, output / "cases" / name / system, command))
    return {"schema": 1, "complete": False, "kind": "rust-wasm-five-reference", "scope": args.benchmarks,
            "date": datetime.datetime.now(datetime.timezone.utc).isoformat(), "revision": command_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"]),
            "upstream_revision": source_report["upstream_revision"], "cpu": args.cpu, "allowed_cpus": sorted(os.sched_getaffinity(0)),
            "rounds": args.rounds, "tools": tools(), "platform": platform.platform(), "cpu_info": Path("/proc/cpuinfo").read_text().split("\n\n")[0],
            "build": {"command": ["cargo", "build", "--offline", "--release", "--target", "wasm32-wasip1"], "profile": {"opt-level": 3, "lto": True, "codegen-units": 1, "panic": "abort"}},
            "input_sha256": digest(output / "inputs/bib"), "reference_source_sha256": {str(path.relative_to(output / "reference-source")): digest(path) for path in sorted((output / "reference-source").rglob("*")) if path.is_file()},
            "timing": {"process_startup": "excluded from workload timer; separately measured", "compilation": "excluded", "preliminary": "one discarded full run per case", "ordering": "rotate benchmark order and alternate system order for every benchmark in successive rounds", "tiering": "Node default", "concurrency": "coordinate quiet window before invoking measurement"},
            "cases": cases, "order": []}


def main():
    args = arguments()
    report = prepare(args)
    write_report(args.output, report)
    if not args.prepare_only:
        measure(report, args.output, args.rounds, args.cpu)
        summarize(report)
        write_report(args.output, report)


if __name__ == "__main__":
    main()
