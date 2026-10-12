#!/usr/bin/env python3
"""Retain heavy request counters and correctness under concurrent test jobs."""

import hashlib
import json
import re
import shutil
import subprocess
import sys
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PREPARED = ROOT / "build/final-five-prepared"
OUTPUT = ROOT / "build/diagnostics"


# ---- Frozen diagnostic preparation ----


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def instrument(case):
    directory = OUTPUT / case["benchmark"]
    path = directory / "manifest.json"
    if not path.exists():
        subprocess.run([sys.executable, str(ROOT / "build/instrument-wasm.py"),
                        str(Path(case["directory"]) / "program.wasm"), str(directory)], check=True)
    manifest = json.loads(path.read_text())
    if manifest["input_sha256"] != case["artifact_sha256"]["program.wasm"]:
        raise ValueError("instrumentation source differs")
    if digest(directory / "instrumented.wasm") != manifest["instrumented_sha256"]:
        raise ValueError("instrumented artifact differs")
    return manifest


def counting_host():
    directory = ROOT / "build/counting-host"
    shutil.copytree(PREPARED / "host", directory, dirs_exist_ok=True)
    path = directory / "scripts/run-counted.mjs"
    source = (directory / "scripts/run-wasi.mjs").read_text()
    source += '\nconsole.error("+!PROBES!+" + JSON.stringify({counters: Object.fromEntries('
    source += 'Object.entries(instance.exports).filter(([name]) => name.startsWith("__snail_probe_"))'
    source += '.map(([name, global]) => [name, String(global.value)]))}));\n'
    path.write_text(source)
    return path


# ---- Counts and checked output, excluding comparative timing claims ----


def check_result(case, completed, directory):
    rows = [line[len("+!CSVLINE!+"):].split(",") for line in completed.stdout.splitlines()
            if line.startswith("+!CSVLINE!+")]
    if completed.returncode or len(rows) != 1 or rows[0][2] == "INCORRECT":
        raise ValueError("instrumented benchmark failed")
    if rows[0][0] != "snail-scheme" or rows[0][1].split(":")[0] != case["benchmark"]:
        raise ValueError("unexpected benchmark record")
    result = {"upstream_predicate_passed": True, "diagnostic_workload_seconds": float(rows[0][2])}
    if case["benchmark"] == "cat":
        original, copied = Path(case["directory"]) / "inputs/bib", Path(case["directory"]) / "outputs/cat.output"
        result["cat_check"] = {"input_bytes": original.stat().st_size, "output_bytes": copied.stat().st_size,
                               "input_sha256": digest(original), "output_sha256": digest(copied)}
        if original.read_bytes() != copied.read_bytes():
            raise ValueError("cat bytes differ")
    return result


def count_rows(stderr, manifest):
    markers = [line[len("+!PROBES!+"):] for line in stderr.splitlines() if line.startswith("+!PROBES!+")]
    if len(markers) != 1:
        raise ValueError("expected one counter snapshot")
    values = json.loads(markers[0])["counters"]
    return [{**row, "value": int(values[row["export"]])} for row in manifest["counters"]]


def compact(rows):
    constructors, indirect, imports = Counter(), 0, Counter()
    for row in rows:
        key, count = row["key"], row["value"]
        if key[0] == "constructor": constructors[(key[2], key[3])] += count
        if key[0] == "indirect-call": indirect += count
        if key[0] == "host-import": imports[key[3]] += count
    return {"constructor_requests": [{"operation": key[0], "type": key[1], "value": count}
                                     for key, count in constructors.most_common()],
            "constructor_request_total": sum(constructors.values()), "indirect_request_total": indirect,
            "host_import_requests": dict(imports),
            "top_function_entries": sorted([row for row in rows if row["key"][0] == "function-entry"],
                                           key=lambda row: -row["value"])[:35]}


def invoke(case, host, manifest):
    directory = OUTPUT / case["benchmark"] / "counters-only"
    directory.mkdir()
    artifact = directory.parent / "instrumented.wasm"
    command = ["taskset", "-c", "5", case["command"][0], "--no-warnings", str(host), str(artifact)]
    started = time.monotonic()
    completed = subprocess.run(command, cwd=case["directory"], text=True, input=(Path(case["directory"]) / "input.txt").read_text(),
                               capture_output=True, timeout=1200)
    (directory / "stdout.txt").write_text(completed.stdout)
    (directory / "stderr.txt").write_text(completed.stderr)
    result = {"benchmark": case["benchmark"], "returncode": completed.returncode,
              "diagnostic_process_wall_seconds": time.monotonic() - started, "command": command,
              "recorded_at_utc": datetime.now(timezone.utc).isoformat(), "runner_sha256": digest(host),
              "artifact_sha256": digest(artifact), "status": "failed", "cpu_sampling": False, "gc_tracing": False,
              "coexistence": "Root full typing/integration tests and experiment-owned preparation may run concurrently.",
              "scope": "Counts include initialization/result checking/output; exclude constant global initializers.",
              "caveats": "Probes precede operation operands and count reached requests, not completed or materialized allocations. Timings are diagnostic overhead only; no comparative claim."}
    (directory / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    result.update(check_result(case, completed, directory))
    rows = count_rows(completed.stderr, manifest)
    (directory / "counts.json").write_text(json.dumps(rows, indent=2) + "\n")
    result.update(status="passed", **compact(rows))
    (directory / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(case["benchmark"], "counter-only", result["status"], result["constructor_request_total"], flush=True)


def main():
    report = json.loads((PREPARED / "results.json").read_text())
    host = counting_host()
    for case in report["cases"]:
        manifest = instrument(case)
        invoke(case, host, manifest)


if __name__ == "__main__":
    main()
