#!/usr/bin/env python3
"""Freeze and check four String diagnostics; these are not canonical57 ports."""

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import tarfile

# ---- Fixed control and predicate contracts ----

ROOT = Path(__file__).resolve().parents[3]
CONTROL = ROOT / "benchmarks/string-reference-controls"
REFERENCE = ROOT / "benchmarks/wasm-reference"
MODES = {"byte": "string-byte-four-buffer", "u32": "string-u32-four-buffer",
         "byte-zeroed": "string-byte-zeroed", "u32-zeroed": "string-u32-zeroed"}
EDGES = [(0, 6), (5, 6), (6, 22), (21, 22), (22, 54), (30, 54)]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def blob(archive, manifest, original):
    expected = manifest["mapped_files"][original]
    data = archive.extractfile("blobs/" + expected).read()
    assert hashlib.sha256(data).hexdigest() == expected
    return data


def restore_chez(output):
    evidence = ROOT / "benchmarks/results/2026-10-13-rust-full-suite"
    manifest = json.loads((evidence / "manifest.json").read_text())
    case = next(case for case in manifest["cases"] if case["name"] == "string")
    with tarfile.open(evidence / "artifacts.tar.xz", "r:xz") as archive:
        report = json.loads(blob(archive, manifest, case["report"]))
        record = next(case for case in report["cases"] if case["benchmark"] == "string")
        run = next(check for check in record["checks"] if check["name"] == "full-canonical")
        source = run["passed"]["chez"]["command"][2]
        (output / "program.so").write_bytes(blob(archive, manifest, source))
        (output / "program.scm").write_bytes(blob(archive, manifest, str(Path(source).with_name("program.scm"))))
        (output / "input.txt").write_bytes(blob(archive, manifest, str(Path(source).with_name("input.txt"))))
    return report["tools"]


def execute(command, directory, source):
    result = subprocess.run(command, cwd=directory, input=source, text=True,
                            capture_output=True, timeout=60)
    return {"command": command, "input_sha256": hashlib.sha256(source.encode()).hexdigest(),
            "returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr}


def predicate_passed(run, case):
    lines = re.findall(r"^\+!CSVLINE!\+([^\n]+)$", run["stdout"], re.MULTILINE)
    if run["returncode"] or len(lines) != 1 or "INCORRECT" in run["stdout"] + run["stderr"]:
        return False
    system, name, elapsed = lines[0].split(",")
    seconds = float(elapsed)
    return system in ("rust-wasm", "chez") and name == case and math.isfinite(seconds) and seconds >= 0


# ---- Independent complete-payload oracle ----

# The final formula is independently derived from the original overlapping
# slices. It is used only in untimed verification, never in a Rust workload.
def payload_oracle(threshold):
    current = "abcdef"
    while len(current) <= threshold:
        current = "56" + current + "789123" + current + "45"
    return {"first": list(b"123abcdef456abcdef789"), "back": list(b"56abcdef789"),
            "front": list(b"123abcdef45"), "final": list(b"56abcdef789123abcdef45"),
            "trial": list(current.encode("ascii"))}


def complete_audit(run, threshold):
    audits = [line.removeprefix("Audit: ") for line in run["stdout"].splitlines()
              if line.startswith("Audit: ")]
    return len(audits) == 1 and json.loads(audits[0]) == payload_oracle(threshold)


def check_small(command, directory, case, threshold, expected):
    source = f"2\n{threshold}\n{expected}\n"
    run = execute([*command, "--audit"], directory, source)
    assert predicate_passed(run, case + ":2") and complete_audit(run, threshold), run
    return {"threshold": threshold, "expected_length": expected, "complete": True, "run": run}


def check_wrong(command, directory, case):
    run = execute(command, directory, "2\n30\n999\n")
    assert not predicate_passed(run, case + ":2"), run
    return run


def check_control(mode, case, output, node):
    command = [node, "--no-warnings", str(output / "run-wasi.mjs"), str(output / "program.wasm"), mode]
    full = execute([*command, "--audit"], output, (output / "input.txt").read_text())
    assert predicate_passed(full, case + ":100") and complete_audit(full, 500000), full
    small = [check_small(command, output, case, threshold, length) for threshold, length in EDGES]
    return {"name": case, "mode": mode, "complete": True, "full_original_count": full,
            "full_payload_audit": "One additional trial after the timer; not the last timed output",
            "small_complete_payloads": small, "wrong_result_rejected": check_wrong(command, output, case)}


def check_chez(output, scheme):
    command = [scheme, "--program", str(output / "program.so")]
    full = execute(command, output, (output / "input.txt").read_text())
    assert predicate_passed(full, "string:500000:100"), full
    small = []
    for threshold, length in EDGES:
        run = execute(command, output, f"2\n{threshold}\n{length}\n")
        assert predicate_passed(run, f"string:{threshold}:2"), run
        small.append(run)
    return {"full_original_count": full, "small": small,
            "wrong_result_rejected": check_wrong(command, output, "string:30")}


def complete_chez_oracle(output, scheme):
    original = (output / "program.scm").read_text()
    final_call = original.rfind("(run-benchmark)")
    assert final_call >= 0 and not original[final_call + len("(run-benchmark)"):].strip()
    tail = '(set! s "abcdef")\n(grow)\n(write s)\n(newline)\n'
    tail += '(for-each (lambda (n) (set! s "abcdef") (trial n) (write s) (newline)) \'(0 5 6 21 22 30 500000))\n'
    source, artifact = output / "complete-oracle.scm", output / "complete-oracle.so"
    source.write_text(original[:final_call] + tail)
    compile_source = output / "compile-oracle.scm"
    compile_source.write_text(f'(import (chezscheme))\n(parameterize ((optimize-level 2)) (compile-program "{source}" "{artifact}"))\n')
    subprocess.run([scheme, "--script", str(compile_source)], check=True, capture_output=True)
    run = execute([scheme, "--program", str(artifact)], output, "")
    values = [json.loads(line) for line in run["stdout"].splitlines()]
    expected = [payload_oracle(0)["final"]] + [payload_oracle(n)["trial"] for n in [0, 5, 6, 21, 22, 30, 500000]]
    assert run["returncode"] == 0 and [list(value.encode("ascii")) for value in values] == expected, run
    return {"run": run, "source_sha256": digest(source), "artifact_sha256": digest(artifact),
            "scope": "Untouched original grow/trial bodies; only final run-benchmark call removed and complete untimed calls appended"}


# ---- Frozen actual linked execution ----

def freeze_control(output, artifact):
    output.mkdir(parents=True)
    for source, destination in [(artifact, "program.wasm"), (REFERENCE / "run-wasi.mjs", "run-wasi.mjs")]:
        shutil.copy2(source, output / destination)
    for name in ("Cargo.toml", "Cargo.lock", "src/main.rs", "tests/check_controls.py"):
        target = output / "control-source" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(CONTROL / name, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    freeze_control(output, args.artifact.resolve())
    tools = restore_chez(output)
    node, scheme = shutil.which("node"), shutil.which("scheme")
    assert digest(node) == tools["node"]["sha256"] and digest(scheme) == tools["chez"]["sha256"]
    check_oracle_rejection()
    report = {"kind": "String control correctness; no performance samples", "performance_samples": False,
              "canonical57_modified": False, "tools": tools, "wasm_sha256": digest(output / "program.wasm"),
              "input_sha256": digest(output / "input.txt"), "host_sha256": digest(output / "run-wasi.mjs"),
              "chez_sha256": digest(output / "program.so"),
              "controls": [check_control(mode, case, output, node) for mode, case in MODES.items()],
              "original_chez": check_chez(output, scheme),
              "original_complete_payload_oracle": complete_chez_oracle(output, scheme), "complete": True}
    (output / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"All {len(MODES)} controls pass full100x10 and complete small/wrong-result checks")


# ---- Tests ----

def check_oracle_rejection():
    good = payload_oracle(30)
    for field in good:
        corrupted = copy.deepcopy(good)
        corrupted[field][len(corrupted[field]) // 2] ^= 1
        assert len(corrupted[field]) == len(good[field])
        assert not complete_audit({"stdout": "Audit: " + json.dumps(corrupted)}, 30)
    for field in ("back", "front", "trial"):
        truncated = copy.deepcopy(good)
        truncated[field].pop()
        assert not complete_audit({"stdout": "Audit: " + json.dumps(truncated)}, 30)


if __name__ == "__main__":
    main()
