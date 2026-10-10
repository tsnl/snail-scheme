#!/usr/bin/env python3
"""Run the pinned R7RS suite through Snail native, Chez, Guile, and Chibi."""

import argparse
import csv
import hashlib
import json
import math
import os
import platform
import re
import shutil
import signal
import statistics
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
REVISION = "85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1"
ARCHIVE_SHA256 = "651166b66af80410fdf28bfe018d25f5233e542040e9066f12813669e6819edb"
UPSTREAM = "https://github.com/ecraven/r7rs-benchmarks"
SYSTEMS = ("snail-native", "chez", "guile", "chibi")


# ---- Pinned sources and benchmark selection ----


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fetch_suite():
    archive = ROOT / "build/r7rs-upstream.tar.gz"
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        url = f"https://api.github.com/repos/ecraven/r7rs-benchmarks/tarball/{REVISION}"
        with urlopen(url, timeout=60) as response:
            archive.write_bytes(response.read())
    if digest(archive.read_bytes()) != ARCHIVE_SHA256:
        raise ValueError(f"upstream archive checksum mismatch: {archive}")
    return archive


def suite_sources():
    # Read directly from the verified archive: no mutable checkout or code vendoring.
    with tarfile.open(fetch_suite()) as archive:
        return {
            member.name.split("/", 1)[1]: archive.extractfile(member).read()
            for member in archive.getmembers()
            if member.isfile()
        }


def benchmark_names(files):
    groups = re.findall(r'^\w+_BENCHMARKS="([^$"\n]+)"', files["bench"].decode(), re.MULTILINE)
    return list(dict.fromkeys(" ".join(groups).split()))


def select_benchmarks(selection, files):
    available = benchmark_names(files)
    names = available if selection == ["all"] else selection
    if len(names) != len(set(names)) or any(name not in available for name in names):
        raise ValueError("choose unique upstream benchmarks from: " + " ".join(available))
    return names


def input_data(data, count):
    if count is None:
        return data
    # Only the first integer (iteration count) changes; algorithm inputs stay fixed.
    result, changes = re.subn(
        rb"\A((?:\s|;[^\n]*(?:\n|$))*)\d+", lambda m: m[1] + str(count).encode(), data, count=1
    )
    if changes != 1:
        raise ValueError("input does not start with an iteration count")
    return result


# ---- Build complete programs before measuring ----


def source_text(files, name, system):
    body = files[f"src/{name}.scm"].decode()
    if system == "chez":
        body, count = re.subn(r"^\(import [^\n]*\)\s*$", "", body, flags=re.MULTILINE)
        if count != 1:
            raise ValueError("expected one top-level R7RS import form")
        prelude = files["src/Petite-Chez-prelude.scm"].decode()
        prelude += (ROOT / "benchmarks/r7rs-chez.scm").read_text()
    else:
        prelude = ""
    identification = f'(define (this-scheme-implementation-name) "{system}")\n'
    return (
        prelude
        + "\n"
        + body
        + "\n"
        + identification
        + files["src/common.scm"].decode()
        + "\n(run-benchmark)\n"
    )


def prepare_case(files, name, system, args):
    directory = args.output / "cases" / name / system
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "outputs").mkdir(exist_ok=True)
    inputs = directory / "inputs"
    if not inputs.exists():
        inputs.symlink_to(args.output / "inputs", target_is_directory=True)
    source = directory / "program.scm"
    source.write_text(source_text(files, name, system))
    data = input_data(files[f"inputs/{name}.input"], args.count)
    (directory / "input.txt").write_bytes(data)
    return {
        "benchmark": name,
        "system": system,
        "directory": str(directory),
        "source_sha256": digest(source.read_bytes()),
        "input_sha256": digest(data),
        "samples": [],
        "status": "pending",
    }


def tool(name, default):
    value = shutil.which(os.environ.get(name, default))
    if value is None:
        raise FileNotFoundError(f"missing {name}: {os.environ.get(name, default)}")
    return value


def build_commands(case):
    directory, system = Path(case["directory"]), case["system"]
    source = str(directory / "program.scm")
    if system == "snail-native":
        if not os.environ.get("SNAIL_WASM_NATIVE"):
            raise FileNotFoundError(
                "set SNAIL_WASM_NATIVE to a compiler accepting INPUT.wasm -o OUTPUT"
            )
        return native_commands(directory, source)
    if system == "chez":
        return chez_commands(directory, source)
    if system == "guile":
        artifact = str(directory / "program.go")
        return [tool("GUILD", "guild"), "compile", "--r7rs", "-O2", "-o", artifact, source], [
            tool("GUILE", "guile"),
            "--no-auto-compile",
            "--r7rs",
            "-c",
            f"(load-compiled {json.dumps(artifact)})",
        ]
    return [], [tool("CHIBI", "chibi-scheme"), source]


def native_commands(directory, source):
    artifact, wasm = str(directory / "program"), str(directory / "program.wasm")
    quote = lambda value: json.dumps(str(value), ensure_ascii=False)
    native = tool("SNAIL_WASM_NATIVE", "")
    script = directory / "build.scm"
    script.write_text(
        "(import (scheme base) (snail-scheme build))\n"
        f"(build-wasm {quote(ROOT)} {quote(source)} {quote(wasm)})\n"
        f'(run-command "benchmark.native" (list {quote(native)} {quote(wasm)} "-o" {quote(artifact)}))\n'
    )
    return [tool("CHIBI", "chibi-scheme"), "-I", str(ROOT / "src"), str(script)], [artifact]


def chez_commands(directory, source):
    artifact = str(directory / "program.so")
    script = directory / "compile.scm"
    script.write_text(
        "(import (chezscheme))\n(parameterize ((optimize-level 2))\n"
        f"  (compile-program {json.dumps(source)} {json.dumps(artifact)}))\n"
    )
    chez = tool("CHEZ", "scheme")
    return [chez, "--script", str(script)], [chez, "--program", artifact]


def execute(command, directory, timeout, stdin=None):
    started = time.monotonic()
    with subprocess.Popen(
        command,
        cwd=directory,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    ) as process:
        try:
            stdout, stderr = process.communicate(stdin, timeout=timeout)
            status = "ok" if process.returncode == 0 else "error"
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
            status = "timeout"
        except BaseException:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            raise
    return {
        "status": status,
        "returncode": process.returncode,
        "wall_seconds": time.monotonic() - started,
        "stdout": stdout.decode(errors="replace"),
        "stderr": stderr.decode(errors="replace"),
    }


def build_case(case, timeout):
    try:
        build, command = build_commands(case)
    except FileNotFoundError as error:
        case.update(status="unavailable", diagnostic=str(error))
        return
    case.update(build_command=build, command=command)
    result = execute(build, case["directory"], timeout) if build else {"status": "ok"}
    case["build"] = result
    case["status"] = "ready" if result["status"] == "ok" else "build-" + result["status"]
    case["artifact_sha256"] = {
        p.name: digest(p.read_bytes())
        for p in Path(case["directory"]).iterdir()
        if p.is_file() and p.name in ["program", "program.so", "program.go", "program.scm"]
    }


# ---- Result validation and rotating rounds ----


def parse_result(output, system, benchmark):
    rows = [
        line.removeprefix("+!CSVLINE!+").split(",")
        for line in output.splitlines()
        if line.startswith("+!CSVLINE!+")
    ]
    if len(rows) != 1 or len(rows[0]) != 3:
        raise ValueError("expected one checked upstream timing record")
    implementation, name, duration = rows[0]
    if implementation != system or name.split(":", 1)[0] != benchmark:
        raise ValueError("timing record identifies a different implementation or benchmark")
    if duration == "INCORRECT":
        return {"status": "incorrect", "name": name}
    seconds = float(duration)
    if not math.isfinite(seconds) or seconds <= 0:
        raise ValueError(
            "timer must be finite and positive; use the full workload if below resolution"
        )
    return {"status": "ok", "seconds": seconds, "name": name}


def sample_case(case, timeout):
    data = (Path(case["directory"]) / "input.txt").read_bytes()
    result = execute(case["command"], case["directory"], timeout, data)
    if result["status"] == "ok":
        try:
            result.update(parse_result(result["stdout"], case["system"], case["benchmark"]))
        except ValueError as error:
            result.update(status="invalid-output", diagnostic=str(error))
    return result


def measure_case(case, round_number, timeout):
    sample = sample_case(case, timeout)
    if round_number == 0:
        case["preliminary"] = sample
    else:
        case["samples"].append({**sample, "round": round_number})
    if sample["status"] != "ok":
        case["status"] = "runtime-" + sample["status"]


def measure(report, args):
    allowed = os.sched_getaffinity(0)
    os.sched_setaffinity(0, {report["cpu"]})
    try:
        for index in range(args.rounds + 1):
            for name in report["benchmarks"]:
                cases = [case for case in report["cases"] if case["benchmark"] == name]
                offset = index % len(cases)
                for case in cases[offset:] + cases[:offset]:
                    if case["status"] == "ready":
                        measure_case(case, index, args.timeout)
                        report["order"].append([index, name, case["system"]])
            save_report(report, args.output)
            print(f"{'Preliminary' if index == 0 else 'Round ' + str(index)} complete", flush=True)
    finally:
        os.sched_setaffinity(0, allowed)


def save_report(report, output):
    temporary = output / "results.json.tmp"
    temporary.write_text(json.dumps(report, indent=2) + "\n")
    temporary.replace(output / "results.json")


# ---- Tables and plots from JSON ----


def results(report):
    if report.get("schema") != 1 or report.get("kind") != "r7rs" or not report.get("complete"):
        raise ValueError("expected a complete R7RS suite report")
    expected = {(name, system) for name in report["benchmarks"] for system in report["systems"]}
    actual = [(case["benchmark"], case["system"]) for case in report["cases"]]
    if set(actual) != expected or len(actual) != len(expected):
        raise ValueError("report does not contain the complete requested matrix")
    rows = []
    for case in report["cases"]:
        samples = case["samples"] if case["status"] == "passed" else []
        if case["status"] == "passed":
            validate_samples(case, report["rounds"])
        rows.append(
            {
                "benchmark": case["benchmark"],
                "system": case["system"],
                "status": case["status"],
                "median_seconds": statistics.median(s["seconds"] for s in samples)
                if samples
                else None,
            }
        )
    return rows


def validate_samples(case, rounds):
    if sorted(s["round"] for s in case["samples"]) != list(range(1, rounds + 1)):
        raise ValueError("missing or duplicate measured round")
    preliminary = case["preliminary"]
    for sample in [preliminary, *case["samples"]]:
        checked = parse_result(sample["stdout"], case["system"], case["benchmark"])
        if (
            sample["returncode"] != 0
            or sample["status"] != "ok"
            or checked.get("seconds") != sample["seconds"]
            or checked["name"] != preliminary["name"]
        ):
            raise ValueError("saved timing differs from checked output or workload identity")


def table(report, rows, output):
    with (output / "summary.csv").open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    lines = [
        "# R7RS suite",
        "",
        (
            f"Upstream `{report['upstream_revision']}` · {report['rounds']} rounds · "
            f"{'original inputs' if report['count'] is None else 'SMOKE RUN: iteration count ' + str(report['count'])}"
        ),
        "",
        "Build/startup excluded. Each successful result passed the upstream result predicate.",
        "",
        "| Benchmark | " + " | ".join(report["systems"]) + " |",
        "| --- | " + " | ".join("---:" for _ in report["systems"]) + " |",
    ]
    cells = {
        (r["benchmark"], r["system"]): f"{r['median_seconds']:.6g}s"
        if r["median_seconds"] is not None
        else r["status"]
        for r in rows
    }
    lines += [
        "| " + name + " | " + " | ".join(cells[name, s] for s in report["systems"]) + " |"
        for name in report["benchmarks"]
    ]
    (output / "summary.md").write_text("\n".join(lines) + "\n")


def plot(report, rows, output):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    plt.rcParams.update({"svg.fonttype": "none", "svg.hashsalt": "snail-r7rs"})
    names, systems = report["benchmarks"], report["systems"]
    lookup = {(r["benchmark"], r["system"]): r for r in rows}
    data = np.full((len(names), len(systems)), np.nan)
    for y, name in enumerate(names):
        for x, system in enumerate(systems):
            seconds = lookup[name, system]["median_seconds"]
            if seconds is not None:
                data[y, x] = math.log10(seconds)
    fig, axis = plt.subplots(
        figsize=(max(7, 2.3 * len(systems)), max(3, 0.34 * len(names) + 1.8)), layout="constrained"
    )
    colors = plt.get_cmap("YlGnBu").copy()
    colors.set_bad("#eeeeee")
    image = axis.imshow(np.ma.masked_invalid(data), cmap=colors, aspect="auto", vmin=-4, vmax=2)
    annotate_plot(axis, names, systems, lookup)
    axis.set(
        xticks=range(len(systems)), xticklabels=systems, yticks=range(len(names)), yticklabels=names
    )
    axis.set_title(
        "R7RS suite · "
        + ("original inputs" if report["count"] is None else "SMOKE RUN · reduced iterations")
    )
    fig.colorbar(image, ax=axis, label="log₁₀(seconds) · lower is faster")
    fig.supxlabel(
        "Median checked workload time · build/startup excluded · gray cells are failures, not timings",
        fontsize=9,
    )
    for extension in ["svg", "png"]:
        fig.savefig(
            output / f"suite.{extension}",
            dpi=160,
            metadata={"Date": None} if extension == "svg" else {},
        )
    plt.close(fig)


def annotate_plot(axis, names, systems, lookup):
    for y, name in enumerate(names):
        for x, system in enumerate(systems):
            row = lookup[name, system]
            value = row["median_seconds"]
            text = f"{value:.3g}s" if value is not None else row["status"]
            axis.text(
                x,
                y,
                text,
                ha="center",
                va="center",
                fontsize=8,
                color="white" if value is not None and value > 1 else "black",
            )


def render(report, output):
    rows = results(report)
    table(report, rows, output)
    plot(report, rows, output)
    print(
        f"{sum(r['status'] == 'passed' for r in rows)}/{len(rows)} cases passed; {output / 'summary.md'}"
    )


# ---- Command line and execution ----


def positive(text):
    value = int(text)
    if value <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return value


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/r7rs-report")
    parser.add_argument("--systems", nargs="+", choices=SYSTEMS, default=list(SYSTEMS))
    parser.add_argument("--benchmarks", nargs="+", default=["all"])
    parser.add_argument("--rounds", type=positive, default=3)
    parser.add_argument(
        "--count", type=positive, help="SMOKE ONLY: replace upstream iteration count"
    )
    parser.add_argument(
        "--timeout", type=positive, default=300, help="seconds per runtime invocation"
    )
    parser.add_argument("--build-timeout", type=positive, default=300)
    parser.add_argument("--cpu", type=int)
    parser.add_argument(
        "--allow-failures", action="store_true", help="exit zero after recording suite failures"
    )
    parser.add_argument(
        "--plot", type=Path, help="render saved JSON without downloading or executing"
    )
    return parser.parse_args()


def metadata(args, files, names):
    return {
        "schema": 1,
        "kind": "r7rs",
        "complete": False,
        "upstream": UPSTREAM,
        "upstream_revision": REVISION,
        "archive_sha256": ARCHIVE_SHA256,
        "date": datetime.now(timezone.utc).isoformat(),
        "revision": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip(),
        "platform": platform.platform(),
        "cpu": args.cpu,
        "allowed_cpus": sorted(os.sched_getaffinity(0)),
        "rounds": args.rounds,
        "count": args.count,
        "timeout": args.timeout,
        "build_timeout": args.build_timeout,
        "tools": tool_versions(),
        "cpu_info": Path("/proc/cpuinfo").read_text().split("\n\n")[0],
        "environment": {k: v for k, v in os.environ.items() if k.startswith("GUILE_")},
        "benchmarks": names,
        "systems": args.systems,
        "cases": [],
        "order": [],
        "native_translator": os.environ.get("SNAIL_WASM_NATIVE"),
        "input_sha256": {
            n: digest(data) for n, data in files.items() if n.startswith(("src/", "inputs/"))
        },
        "harness_sha256": {
            p.name: digest(p.read_bytes())
            for p in [Path(__file__), ROOT / "benchmarks/r7rs-chez.scm"]
        },
    }


def tool_versions():
    result = {}
    for key, default in [
        ("CHEZ", "scheme"),
        ("GUILE", "guile"),
        ("GUILD", "guild"),
        ("CHIBI", "chibi-scheme"),
        ("CARGO", "cargo"),
        ("NODE", "node"),
        ("WASM_OPT", "wasm-opt"),
    ]:
        path = shutil.which(os.environ.get(key, default))
        result[key] = {"path": path}
        if path:
            result[key]["version"] = execute(
                [path, "-V" if key == "CHIBI" else "--version"], ROOT, 10
            )
    return result


def materialize_inputs(files, output):
    for path, data in files.items():
        if path.startswith("inputs/"):
            destination = output / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)


def run_suite(args, files):
    names = select_benchmarks(args.benchmarks, files)
    report = metadata(args, files, names)
    materialize_inputs(files, args.output)
    report["cases"] = [
        {"benchmark": name, "system": system, "status": "pending", "samples": []}
        for name in names
        for system in args.systems
    ]
    try:
        for case in report["cases"]:
            case.update(prepare_case(files, case["benchmark"], case["system"], args))
            build_case(case, args.build_timeout)
            print(f"Build {case['benchmark']}/{case['system']}: {case['status']}", flush=True)
            save_report(report, args.output)
        measure(report, args)
        for case in report["cases"]:
            if case["status"] == "ready":
                case["status"] = "passed"
        report["complete"] = True
    finally:
        save_report(report, args.output)
    return report


def main():
    args = arguments()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("MPLCONFIGDIR", str(args.output / "matplotlib-cache"))
    import matplotlib  # Check plotting dependencies before any benchmark runs.

    matplotlib.use("Agg")

    if args.plot:
        return render(json.loads(args.plot.read_text()), args.output)
    allowed = sorted(os.sched_getaffinity(0))
    args.cpu = allowed[0] if args.cpu is None else args.cpu
    if args.cpu not in allowed or len(args.systems) != len(set(args.systems)):
        raise ValueError("choose an available CPU and unique systems")
    report = run_suite(args, suite_sources())
    render(report, args.output)
    if not args.allow_failures and any(c["status"] != "passed" for c in report["cases"]):
        raise SystemExit(1)


# ---- Tests ----


class ResultsTests(unittest.TestCase):
    def test_checked_records(self):
        self.assertEqual(
            parse_result("+!CSVLINE!+chez,fib:40:5,0.1\n", "chez", "fib")["seconds"], 0.1
        )
        for output in [
            "",
            "+!CSVLINE!+guile,fib:40:5,0.1",
            "+!CSVLINE!+chez,tak,0.1",
            "+!CSVLINE!+chez,fib,nan",
            "+!CSVLINE!+chez,fib,0",
            "+!CSVLINE!+chez,fib,0.1\n+!CSVLINE!+chez,fib,0.2",
        ]:
            with self.subTest(output=output), self.assertRaises(ValueError):
                parse_result(output, "chez", "fib")
        self.assertEqual(
            parse_result("+!CSVLINE!+chez,fib,INCORRECT", "chez", "fib")["status"], "incorrect"
        )

    def test_smoke_input_preserves_problem(self):
        source = b"500\n1000000\n; expected answer\n1000000\n"
        self.assertEqual(input_data(source, 1), b"1\n1000000\n; expected answer\n1000000\n")
        self.assertEqual(input_data(source, None), source)
        self.assertEqual(
            input_data(b"; upstream comment\n  5\n40\n", 1), b"; upstream comment\n  1\n40\n"
        )

    def test_incomplete_report_rejected(self):
        with self.assertRaises(ValueError):
            results({"schema": 1, "complete": False})

    def test_matrix_preserves_failures(self):
        report = {
            "schema": 1,
            "kind": "r7rs",
            "complete": True,
            "rounds": 1,
            "systems": ["chez"],
            "benchmarks": ["fib"],
            "cases": [],
        }
        with self.assertRaises(ValueError):
            results(report)
        report["cases"] = [
            {"benchmark": "fib", "system": "chez", "status": "build-error", "samples": []}
        ]
        self.assertIsNone(results(report)[0]["median_seconds"])
        report["cases"] *= 2
        with self.assertRaises(ValueError):
            results(report)

    def test_timeout_kills_descendants(self):
        with tempfile.TemporaryDirectory() as directory:
            child = "import time; time.sleep(30)"
            parent = (
                "import subprocess,sys,time; from pathlib import Path; "
                f"p=subprocess.Popen([sys.executable,'-c',{child!r}]); "
                "Path('pid').write_text(str(p.pid)); time.sleep(30)"
            )
            result = execute([sys.executable, "-c", parent], directory, 0.5)
            self.assertEqual(result["status"], "timeout")
            pid = (Path(directory) / "pid").read_text()
            status = Path(f"/proc/{pid}/stat")
            for _ in range(100):
                try:
                    if status.read_text().split()[2] in {"Z", "X"}:
                        return
                except FileNotFoundError:
                    return
                time.sleep(0.01)
            self.fail("benchmark descendant survived process-group timeout")


if __name__ == "__main__":
    main()
