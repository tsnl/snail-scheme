#!/usr/bin/env python3
"""Measure Snail compiling its own source; verify WAT against the Chibi host."""

import argparse
import json
import os
import platform
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from plots import GRAY, ORANGE, duration_chart
from r7rs import (
    check_hashes,
    digest,
    execute,
    experiment_environment,
    parse_result,
    positive,
    save_report,
    tool,
    tool_versions,
    validate_samples,
)

ROOT = Path(__file__).resolve().parents[1]
ENTRY = "benchmarks/compile-self.scm"
LABELS = {
    "chibi": "Chibi host",
    "snail-wasm": "Snail Wasm / V8",
}


# ---- Frozen input and compiler preparation ----


def snapshot(output):
    frozen = output / "source"
    frozen.mkdir()  # A fresh directory keeps previous measurements and sources intact.
    paths = [ROOT / name for name in [ENTRY, "Cargo.toml", "Cargo.lock", "rust-toolchain.toml",
                                     "src/runtime/host.mjs", "src/runtime/build.mjs", "scripts/run-wasi.mjs"]]
    for pattern in ["src/**/*.sld", "bootstrap/**/*.sld", "src/**/*.rs"]:
        paths.extend(sorted(ROOT.glob(pattern)))
    for path in paths:
        destination = frozen / path.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(path.read_bytes())
    return manifest(frozen, exclude_build=True)


def manifest(directory, *, exclude_build=False):
    return {
        str(p.relative_to(directory)): digest(p.read_bytes())
        for p in sorted(directory.rglob("*"))
        if p.is_file() and not (exclude_build and p.relative_to(directory).parts[0] == "build")
    }


def checked_build(report, command, args, *, capture=None):
    environment = {"SNAIL_CAPTURE_DIRECTORY": str(capture)} if capture else {}
    result = execute(list(map(str, command)), args.output, args.build_timeout, environment=environment)
    report["builds"].append({"command": list(map(str, command)), **result})
    save_report(report, args.output)
    if result["status"] != "ok":
        raise RuntimeError(f"compiler preparation {result['status']}: {result['stderr']}")


def prepare(report, args):
    frozen, reference = args.output / "source", args.output / "reference.wat"
    chibi = [tool("CHIBI", "chibi-scheme"), "-h512M", "-I", str(frozen / "src"), str(frozen / ENTRY)]
    checked_build(report, [*chibi, frozen, frozen / ENTRY, reference, "chibi"], args)
    report["reference_sha256"] = digest(reference.read_bytes())
    checked_build(
        report,
        [
            tool("WASM_AS", "wasm-as"),
            reference,
            "--all-features",
            "-o",
            args.output / "reference.wasm",
        ],
        args,
    )
    for case in report["cases"]:
        directory = args.output / "cases/compiler-self" / case["system"]
        directory.mkdir(parents=True, exist_ok=True)
        case["directory"] = str(directory)
        try:
            case["command"] = compiler_command(case, chibi, report, args)
            case["artifact_sha256"] = manifest(directory)
            case["status"] = "ready"
        except (OSError, RuntimeError) as error:
            case.update(
                status="unavailable" if isinstance(error, OSError) else "build-error",
                diagnostic=str(error),
            )
        save_report(report, args.output)


def compiler_command(case, chibi, report, args):
    system, directory = case["system"], Path(case["directory"])
    if system == "chibi":
        return chibi
    frozen = args.output / "source"
    wasm = args.output / "compiler.wasm"
    if not wasm.exists():
        link = args.output / "link.scm"
        link.write_text(
            "(import (scheme base) (snail-scheme build) (snail-scheme chromium-trace))\n"
            '(with-chromium-trace-to "link.trace.json" (lambda ()\n'
            f'(link-wasm "reference.wat" (build-runtime {json.dumps(str(frozen))}) "compiler.wasm")))\n'
        )
        checked_build(report, [chibi[0], "-h512M", "-I", frozen / "src", link], args, capture=directory)
        report["compiler_wasm_sha256"] = digest(wasm.read_bytes())
    return [tool("NODE", "node"), "--no-warnings", str(frozen / "scripts/run-wasi.mjs"), str(wasm)]


def sample(case, report, args, index):
    output = Path(case["directory"]) / f"attempt-{index}.wat"
    frozen = args.output / "source"
    output.unlink(missing_ok=True)
    command = [
        *case["command"],
        str(frozen),
        str(frozen / ENTRY),
        str(output),
        case["system"],
    ]
    result = execute(command, args.output, args.timeout)
    result["command"] = command
    if result["status"] == "ok":
        try:
            result.update(parse_result(result["stdout"], case["system"], "compiler-self"))
            contents = output.read_bytes()
            result["wat_sha256"] = digest(contents)
            trace = Path(str(output) + ".trace.json")
            events = json.loads(trace.read_text())
            result["stages_seconds"] = {
                name: sum(event["dur"] for event in events
                          if event.get("ph") == "X" and event["name"] == name) / 1_000_000
                for name in ("syntax-list->ir-library", "analyze-types", "partial-evaluate",
                             "ir-library->wasm", "write-wasm")
            }
            if contents != (args.output / "reference.wat").read_bytes():
                raise ValueError("compiler output differs from the Chibi reference")
        except (ValueError, OSError) as error:
            result.update(status="invalid-output", diagnostic=str(error))
    return result


def measure(report, args):
    allowed = os.sched_getaffinity(0)
    os.sched_setaffinity(0, {report["cpu"]})
    try:
        for index in range(args.rounds + 1):
            cases = report["cases"]
            offset = index % len(cases)
            for case in cases[offset:] + cases[:offset]:
                if case["status"] == "ready":
                    record_sample(case, index, report, args)
                else:
                    case.setdefault("blocked_attempts", []).append(
                        {"round": index, "reason": case["status"]})
            save_report(report, args.output)
    finally:
        os.sched_setaffinity(0, allowed)


def record_sample(case, index, report, args):
    report["active_attempt"] = [index, case["system"]]
    save_report(report, args.output)
    result = sample(case, report, args, index)
    if index == 0:
        case["preliminary"] = result
    else:
        case["samples"].append({"round": index, **result})
    if result["status"] != "ok":
        case["status"] = "runtime-" + result["status"]
    report["order"].append([index, case["system"]])
    report["active_attempt"] = None
    save_report(report, args.output)
    print(
        f"{case['system']} {'preliminary' if index == 0 else index}: "
        f"{result.get('seconds', result['status'])}",
        flush=True,
    )


# ---- Reports and command line ----


def render(report, output):
    if report.get("kind") != "compiler-self" or not report.get("complete"):
        raise ValueError("expected a complete compiler benchmark report")
    series, missing = [], []
    for case in report["cases"]:
        if case["status"] != "passed":
            missing.append(f"{LABELS[case['system']]}: {case['status']}")
            continue
        validate_samples(case, report["rounds"])
        if any(
            s["wat_sha256"] != report["reference_sha256"]
            for s in [case["preliminary"], *case["samples"]]
        ):
            raise ValueError("saved output differs from the reference")
        series.append(
            {
                "label": LABELS[case["system"]],
                "seconds": [s["seconds"] for s in case["samples"]],
                "color": GRAY if case["system"] == "chibi" else ORANGE,
            }
        )
    duration_chart(
        series,
        output / "compiler-self",
        title="Compiling the compiler",
        subtitle="Full Scheme source → WAT · slowest to fastest",
        missing=missing,
        notes=[
            f"{report['rounds']} measured runs · byte-identical to the Chibi reference",
            "Includes parsing, library loading, emission, and file output; excludes startup and linking.",
        ],
    )


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--systems", nargs="+", choices=LABELS, default=["chibi", "snail-wasm"])
    parser.add_argument("--rounds", type=positive, default=3)
    parser.add_argument("--cpu", type=int)
    parser.add_argument("--timeout", type=positive, default=300)
    parser.add_argument("--build-timeout", type=positive, default=600)
    parser.add_argument("--output", type=Path, default=ROOT / "build/compiler-report")
    parser.add_argument("--plot", type=Path, help="plot saved JSON without running the compiler")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--measure", type=Path, help="measure a prepared compiler without rebuilding")
    args = parser.parse_args()
    if len(set(args.systems)) != len(args.systems):
        parser.error("choose each system only once")
    return args


def metadata(args):
    return {
        "schema": 1,
        "kind": "compiler-self",
        "date": datetime.now(timezone.utc).isoformat(),
        "complete": False,
        "revision": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip(),
        "working_tree": subprocess.check_output(["git", "status", "--short"], cwd=ROOT, text=True),
        "platform": platform.platform(),
        "cpu_info": Path("/proc/cpuinfo").read_text().split("\n\n")[0],
        "cpu": args.cpu,
        "rounds": args.rounds,
        "tools": tool_versions(),
        "experiment_environment": experiment_environment(),
        "runtime": "Binaryen-optimized WasmGC on V8",
        "timeout": args.timeout,
        "build_timeout": args.build_timeout,
        "build_environment": {name: os.environ.get(name) for name in
                              ("RUSTFLAGS", "BINARYEN_CORES")},
        "source_sha256": snapshot(args.output),
        "harness_sha256": {
            name: digest((ROOT / "benchmarks" / name).read_bytes())
            for name in ["compile-self.py", "r7rs.py", "plots.py", "shell.nix"]
        },
        "builds": [],
        "order": [],
        "active_attempt": None,
        "cases": [
            {
                "system": system,
                "benchmark": "compiler-self",
                "status": "pending",
                "samples": [],
            }
            for system in args.systems
        ],
    }


def run(args):
    report = metadata(args)
    save_report(report, args.output)
    try:
        prepare(report, args)
        if args.prepare_only:
            return 0
        measure(report, args)
        if manifest(args.output / "source", exclude_build=True) != report["source_sha256"]:
            raise ValueError("frozen compiler sources changed during measurement")
        for case in report["cases"]:
            if case["status"] == "ready":
                case["status"] = "passed"
        report["complete"] = True
    finally:
        save_report(report, args.output)
    render(report, args.output)
    return int(any(case["status"] != "passed" for case in report["cases"]))


def measure_prepared(report, args):
    if report["complete"] or any(case["samples"] or case.get("preliminary") for case in report["cases"]):
        raise ValueError("compiler report already contains timing attempts")
    if report["experiment_environment"] != experiment_environment():
        raise ValueError("prepared compiler environment changed")
    check_hashes(args.output / "source", report["source_sha256"])
    check_hashes(ROOT / "benchmarks", report["harness_sha256"])
    check_hashes(args.output, {"reference.wat": report["reference_sha256"]})
    for case in report["cases"]:
        check_hashes(Path(case["directory"]), case.get("artifact_sha256", {}))
    if report.get("compiler_wasm_sha256"):
        check_hashes(args.output, {"compiler.wasm": report["compiler_wasm_sha256"]})
    for key in ("cpu", "rounds", "timeout"):
        setattr(args, key, report[key])
    measure(report, args)
    check_hashes(args.output / "source", report["source_sha256"])
    for case in report["cases"]:
        if case["status"] == "ready":
            case["status"] = "passed"
    report["complete"] = True
    save_report(report, args.output)
    render(report, args.output)
    return int(any(case["status"] != "passed" for case in report["cases"]))


def main():
    args = arguments()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("MPLCONFIGDIR", str(args.output / "matplotlib-cache"))
    if args.plot:
        render(json.loads(args.plot.read_text()), args.output)
        return 0
    if args.measure:
        args.output = args.measure.resolve().parent
        return measure_prepared(json.loads(args.measure.read_text()), args)
    allowed = sorted(os.sched_getaffinity(0))
    args.cpu = allowed[0] if args.cpu is None else args.cpu
    if args.cpu not in allowed:
        raise ValueError("requested CPU is outside the allowed affinity set")
    return run(args)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print(f"compiler benchmark: {error}", file=sys.stderr)
        sys.exit(1)
