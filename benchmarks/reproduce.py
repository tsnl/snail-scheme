#!/usr/bin/env python3
"""Rebuild the bounded native Fibonacci comparison, measure it, and plot the data."""

import argparse
import hashlib
import json
import math
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LABELS = {
    "llvm-tuned": "Snail native translator · tuned",
    "chez": "Chez Scheme · safe O2",
    "llvm-baseline": "Snail native translator · baseline",
    "guile": "Guile · bytecode O2",
    "guile-warm": "Guile · after in-process warmup",
    "chibi": "Chibi Scheme",
}
SCOPE = "Recursive Fibonacci · extracted function with a C workload harness"
TOOLS = {
    "CHIBI": "chibi-scheme",
    "CHEZ": "scheme",
    "GUILE": "guile",
    "GUILD": "guild",
    "CLANG": "clang",
    "OPT": "opt",
    "WASM_AS": "wasm-as",
    "WASM_OPT": "wasm-opt",
    "NODE": "node",
}


# ---- Preparation and provenance ----


def run(command, log):
    command = [str(part) for part in command]
    log.append(command)
    subprocess.run(command, cwd=ROOT, check=True)


def resolve_tools():
    tools = {key: shutil.which(os.environ.get(key, name)) for key, name in TOOLS.items()}
    missing = [key for key, value in tools.items() if value is None]
    if missing:
        raise ValueError("missing tools: " + ", ".join(missing))
    os.environ.update(tools)
    return tools


def native_programs(log):
    for script in ["experiments/wasmgc/build.py", "experiments/wasm-llvm/build.py"]:
        run([sys.executable, ROOT / script], log)
    sys.path.insert(0, str(ROOT / "experiments/wasm-llvm"))
    import ablate

    ablate.OUT.mkdir(parents=True, exist_ok=True)
    programs = {
        "llvm-baseline": ablate.cpu_variant("baseline"),
        "llvm-tuned": ablate.cpu_variant("both"),
    }
    ablate.check_numeric_boundaries()
    log.extend(ablate.build.COMMANDS)
    return programs


def prepare(tools, out, log):
    programs = native_programs(log)
    source = ROOT / "benchmarks/cpu.scm"
    for name, extension in [("chez", "so"), ("chibi", "scm")]:
        programs[name] = out / f"cpu-{name}.{extension}"
        flags = ["--script"] if name == "chez" else []
        run(
            [tools[name.upper()], *flags, ROOT / f"benchmarks/{name}.scm", source, programs[name]],
            log,
        )
    programs["guile"] = out / "cpu.go"
    run([tools["GUILD"], "compile", "--r7rs", "-O2", "-o", programs["guile"], source], log)
    return programs


def commands(tools, programs, repetitions):
    guile = [tools["GUILE"], "--no-auto-compile", "--r7rs", "-c"]
    load = f"(load-compiled {json.dumps(str(programs['guile']))})"
    result = {name: [str(programs[name])] for name in ["llvm-baseline", "llvm-tuned"]}
    result["chez"] = [tools["CHEZ"], "--program", str(programs["chez"])]
    result["guile"] = [*guile, load]
    result["guile-warm"] = [*guile, load + " (main)"]
    result["chibi"] = [tools["CHIBI"], str(programs["chibi"])]
    return {name: [*command, str(repetitions)] for name, command in result.items()}


def hashes(paths):
    return {
        str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path): hashlib.sha256(
            path.read_bytes()
        ).hexdigest()
        for path in sorted(set(paths))
    }


def source_files():
    paths = [Path(__file__), ROOT / "benchmarks/shell.nix"]
    paths += [ROOT / f"benchmarks/{name}" for name in ["cpu.scm", "chez.scm", "chibi.scm"]]
    for directory in ["src", "bootstrap", "experiments/wasmgc", "experiments/wasm-llvm"]:
        paths += [
            p
            for p in (ROOT / directory).rglob("*")
            if p.is_file() and p.suffix in {".sld", ".scm", ".py", ".c", ".mjs", ".wat"}
        ]
    return paths


def provenance(tools, programs):
    versions = {
        key: subprocess.check_output(
            [path, "-V" if key == "CHIBI" else "--version"], text=True, stderr=subprocess.STDOUT
        ).strip()
        for key, path in tools.items()
    }
    git = lambda *args: subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()
    return {
        "revision": git("rev-parse", "HEAD"),
        "working_tree": git("status", "--short"),
        "source_sha256": hashes(source_files()),
        "artifact_sha256": hashes(programs.values()),
        "build_details": {
            name: json.loads((ROOT / "build" / name / "build-commands.json").read_text())
            for name in ["wasmgc", "wasm-llvm"]
        },
        "tools": tools,
        "versions": versions,
        "platform": platform.platform(),
        "cpu_info": Path("/proc/cpuinfo").read_text().split("\n\n")[0],
        "environment": {
            k: v
            for k, v in os.environ.items()
            if k.startswith("GUILE_") or k in ["BDWGC_INCLUDE", "BDWGC_LIB"]
        },
    }


# ---- Fixed work and verified timing ----


def expected_checksum(repetitions):
    a, b, total = 0, 1, 0
    for n in range(26):
        if n >= 22:
            total += (n + 1) * a
        a, b = b, a + b
    return total * repetitions


def parse_intervals(output, repetitions, expected_intervals):
    checksums = re.findall(r"^checksum: (\d+)$", output, re.MULTILINE)
    times = re.findall(r"^elapsed: (\S+) s; repetitions: (\d+)$", output, re.MULTILINE)
    if len(checksums) != expected_intervals or len(times) != expected_intervals:
        raise ValueError(f"expected {expected_intervals} complete timing intervals: {output!r}")
    result = []
    for checksum, (seconds, count) in zip(checksums, times):
        seconds = float(seconds)
        if int(checksum) != expected_checksum(repetitions) or int(count) != repetitions:
            raise ValueError(f"wrong checksum or repetition count: {output!r}")
        if not math.isfinite(seconds) or seconds <= 0:
            raise ValueError(
                f"invalid timer value {seconds}; increase repetitions if below resolution"
            )
        result.append({"seconds": seconds, "checksum": int(checksum), "repetitions": int(count)})
    return result


def sample(name, command, repetitions):
    result = subprocess.run(
        command, cwd=ROOT, capture_output=True, text=True, check=True, timeout=300
    )
    intervals = parse_intervals(result.stdout, repetitions, 2 if name == "guile-warm" else 1)
    return {
        "variant": name,
        "seconds": intervals[-1]["seconds"],
        "intervals": intervals,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }


def measure(report, cpu):
    allowed = os.sched_getaffinity(0)
    os.sched_setaffinity(0, {cpu})
    try:
        for name, command in report["commands"].items():
            report["preliminary"].append(sample(name, command, report["repetitions"]))
        items = list(report["commands"].items())
        for index in range(report["rounds"]):
            offset = index % len(items)
            for name, command in items[offset:] + items[:offset]:
                row = sample(name, command, report["repetitions"])
                report["samples"].append({**row, "round": index + 1})
            print(f"Round {index + 1}/{report['rounds']} complete", flush=True)
    finally:
        os.sched_setaffinity(0, allowed)


def collect(args, tools, programs, log):
    allowed = sorted(os.sched_getaffinity(0))
    cpu = args.cpu if args.cpu is not None else allowed[0]
    report = {
        "schema": 1,
        "kind": "native-fibonacci",
        "complete": False,
        "scope": SCOPE,
        "date": datetime.now(timezone.utc).isoformat(),
        "rounds": args.rounds,
        "repetitions": args.repetitions,
        "cpu": cpu,
        "allowed_cpus": allowed,
        "provenance": provenance(tools, programs),
        "build_commands": log,
        "commands": commands(tools, programs, args.repetitions),
        "preliminary": [],
        "samples": [],
    }
    try:
        measure(report, cpu)
        report["complete"] = True
    finally:
        name = "results.json" if report["complete"] else "partial.json"
        (args.output / name).write_text(json.dumps(report, indent=2) + "\n")
    return report


# ---- Reports from saved data ----


def distributions(report):
    if (
        report.get("schema") != 1
        or report.get("kind") != "native-fibonacci"
        or not report.get("complete")
    ):
        raise ValueError("expected a complete version-1 benchmark report")
    result = {name: [] for name in LABELS}
    seen = set()
    for row in report["samples"]:
        identity = (row["variant"], row["round"])
        if identity in seen or row["round"] not in range(1, report["rounds"] + 1):
            raise ValueError("duplicate or invalid measurement round")
        seen.add(identity)
        intervals = parse_intervals(
            row["stdout"], report["repetitions"], 2 if row["variant"] == "guile-warm" else 1
        )
        if intervals[-1]["seconds"] != row["seconds"]:
            raise ValueError("saved time does not match verified output")
        result[row["variant"]].append(row["seconds"])
    if any(len(values) != report["rounds"] for values in result.values()):
        raise ValueError("missing or duplicate samples")
    return result


def summary(report, values, out):
    chez = statistics.median(values["chez"])
    lines = [
        "# Recursive Fibonacci",
        "",
        report["scope"],
        "",
        (
            f"{report['date']}; CPU {report['cpu']}; {report['rounds']} rounds; "
            f"{report['repetitions']} repetitions. Build and startup excluded."
        ),
        "",
        "| Implementation | Median seconds | Min–max seconds | Time / Chez |",
        "| --- | ---: | ---: | ---: |",
    ]
    for name, samples in values.items():
        median = statistics.median(samples)
        lines.append(
            f"| {LABELS[name]} | {median:.5f} | {min(samples):.5f}–{max(samples):.5f} | "
            f"{median / chez:.2f}× |"
        )
    (out / "summary.md").write_text("\n".join(lines) + "\n")


def plot(report, values, out):
    if __package__:
        from .plots import GRAY, ORANGE, duration_chart
    else:
        from plots import GRAY, ORANGE, duration_chart

    labels = {
        "llvm-tuned": "Snail native\ntuned",
        "llvm-baseline": "Snail native\nbaseline",
        "chez": "Chez Scheme\nsafe O2",
        "guile": "Guile\nbytecode O2",
        "guile-warm": "Guile\nsecond interval",
        "chibi": "Chibi Scheme",
    }
    series = {
        name: {
            "label": labels[name],
            "seconds": samples,
            "color": ORANGE
            if name == "llvm-tuned"
            else "#f4b17d"
            if name == "llvm-baseline"
            else GRAY,
        }
        for name, samples in values.items()
    }
    notes = [
        f"Median of {report['rounds']} runs × {report['repetitions']} repetitions · whiskers: observed min–max · build/startup excluded",
        "Snail: extracted native function + C harness. Other systems: complete Scheme program.",
    ]
    duration_chart(
        list(series.values()),
        out / "comparison",
        title="Recursive Fibonacci",
        subtitle="All implementations and controls · slowest to fastest",
        notes=notes,
    )
    snail = statistics.median(values["llvm-tuned"])
    speedups = {name: statistics.median(values[name]) / snail for name in ["chez", "guile"]}
    series["llvm-tuned"]["label"] = "Snail Scheme\nnative · tuned"
    duration_chart(
        [series[name] for name in ["guile", "chez", "llvm-tuned"]],
        out / "readme",
        title="Recursive Fibonacci",
        subtitle=f"Snail: {speedups['chez']:.2f}× faster than Chez · {speedups['guile']:.2f}× faster than Guile",
        notes=notes,
    )


def render(report, out):
    values = distributions(report)
    summary(report, values, out)
    plot(report, values, out)
    print((out / "summary.md").read_text())


# ---- Command line ----


def positive(text):
    value = int(text)
    if value <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return value


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/benchmark-report")
    parser.add_argument("--rounds", type=positive, default=8)
    parser.add_argument("--repetitions", type=positive, default=64)
    parser.add_argument("--cpu", type=int, help="Linux CPU number; default: first allowed CPU")
    parser.add_argument(
        "--plot", type=Path, help="regenerate reports from JSON without running benchmarks"
    )
    return parser.parse_args()


def main():
    args = arguments()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("MPLCONFIGDIR", str(args.output / "matplotlib-cache"))
    import matplotlib  # Fail before builds if plotting dependencies are missing.

    matplotlib.use("Agg")

    if args.plot:
        return render(json.loads(args.plot.read_text()), args.output)
    if args.cpu is not None and args.cpu not in os.sched_getaffinity(0):
        raise ValueError("requested CPU is outside the allowed affinity set")
    tools, log = resolve_tools(), []
    programs = prepare(tools, args.output, log)
    render(collect(args, tools, programs, log), args.output)


# ---- Tests ----


class TimingTests(unittest.TestCase):
    def output(self, checksum=4204971, seconds="0.01", repetitions=1):
        return f"checksum: {checksum}\nelapsed: {seconds} s; repetitions: {repetitions}\n"

    def test_work_and_timer_validation(self):
        self.assertEqual(expected_checksum(64), 269118144)
        for text in [
            self.output(checksum=0),
            self.output(repetitions=2),
            self.output(seconds="nan"),
            self.output(seconds="0"),
            self.output(seconds="-1"),
            self.output() * 2,
        ]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_intervals(text, 1, 1)

    def test_both_guile_intervals_must_pass(self):
        intervals = parse_intervals(self.output() + self.output(seconds="0.02"), 1, 2)
        self.assertEqual([row["seconds"] for row in intervals], [0.01, 0.02])
        with self.assertRaises(ValueError):
            parse_intervals(self.output(checksum=0) + self.output(), 1, 2)

    def test_partial_reports_cannot_be_published(self):
        with self.assertRaises(ValueError):
            distributions({"schema": 1, "complete": False})


if __name__ == "__main__":
    main()
