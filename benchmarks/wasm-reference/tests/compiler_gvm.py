#!/usr/bin/env python3
"""Compare complete Compiler GVM graphs; full assembly validation is separate."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import unittest

REFERENCE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REFERENCE))
from audit_alpha import read_program
from suite import pinned_sources, tools

# ---- Complete instruction-graph equality ----

def same_graph(first, second):
    try:
        return read_program(first) == read_program(second)
    except (ValueError, StopIteration):
        return False


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare_oracle(output):
    module, files = pinned_sources(REFERENCE.parent / "r7rs-benchmarks")
    source = module.source_text(files, "compiler", "chez").rstrip()
    assert source.endswith("(run-benchmark)")
    source = source[:-len("(run-benchmark)")]
    source = source.replace("    current-time\n", "    current-time\n    parameterize\n    print-extended-identifiers\n", 1)
    tail = (REFERENCE / "tests/compiler-gvm-oracle-tail.scm").read_text()
    for stage in ("raw", "purified"):
        stop = "(set! bbs-purify! (lambda (bbs) #f))" if stage == "raw" else ""
        slots = "" if stage == "raw" else "(map code-slots-needed (bbs->code-list (proc-obj-code proc)))"
        program, artifact = output / f"{stage}-gvm.scm", output / f"{stage}-gvm.so"
        program.write_text(source + tail.replace("@PHASE_STOP@", stop).replace("@SLOT_AUDIT@", slots))
        script = output / f"{stage}-gvm-compile.scm"
        script.write_text(f'(import (chezscheme))\n(parameterize ((optimize-level 2)) (compile-program "{program}" "{artifact}"))\n')
        subprocess.run(["scheme", "--script", str(script)], check=True, capture_output=True)
    return files["inputs/compiler.input"]


def check_program(name, supplied, output, wasm, stage):
    (output / f"{name}.input").write_bytes(supplied)
    flag = "--gvm-raw" if stage == "raw" else "--gvm"
    commands = {"rust-wasm": ["node", "--no-warnings", str(REFERENCE / "run-wasi.mjs"), str(wasm), flag],
                "chez": ["scheme", "--program", str(output / f"{stage}-gvm.so")]}
    runs = {}
    for system, command in commands.items():
        result = subprocess.run(command, input=supplied, capture_output=True, timeout=60)
        (output / f"{name}-{stage}-{system}.txt").write_bytes(result.stdout)
        runs[system] = {"command": command, "returncode": result.returncode,
                        "stdout": result.stdout.decode(), "stderr": result.stderr.decode()}
    complete = all(run["returncode"] == 0 for run in runs.values()) and same_graph(runs["rust-wasm"]["stdout"], runs["chez"]["stdout"])
    print(f"{name} / {stage} GVM: {complete}", flush=True)
    return {"name": name, "stage": stage, "complete": complete, "input_sha256": hashlib.sha256(supplied).hexdigest(), "runs": runs}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    canonical = prepare_oracle(output)
    wasm = REFERENCE / "target/wasm32-wasip1/release/examples/compiler_frontend.wasm"
    shutil.copy2(wasm, output / "compiler_frontend.wasm")
    for source in [*REFERENCE.glob("src/compiler*.rs"), *REFERENCE.glob("src/compiler*.scm")]:
        shutil.copy2(source, output / source.name)
    records = [check_program("canonical-program", canonical, output, output / "compiler_frontend.wasm", stage) for stage in ("raw", "purified")]
    fixtures = json.loads((REFERENCE / "tests/compiler-front-fixtures.json").read_text())
    fixtures.update(json.loads((REFERENCE / "tests/compiler-gvm-fixtures.json").read_text()))
    fixtures.update(json.loads((REFERENCE / "tests/compiler-blocks-fixtures.json").read_text()))
    for name, expression in fixtures.items():
        supplied = f"1\n(begin (declare (standard-bindings) (fixnum) (not safe) (block)) {expression})\nm68000\nasm\nignored\n".encode()
        records.extend(check_program(name, supplied, output, output / "compiler_frontend.wasm", stage) for stage in ("raw", "purified"))
    report = {"kind": "complete GVM correctness", "canonical_full_compiler_pending": True,
              "performance_samples": False, "source_sha256": {path.name: digest(path) for path in output.glob("compiler*")},
              "oracle_source_sha256": {stage: digest(output / f"{stage}-gvm.scm") for stage in ("raw", "purified")}, "oracle_binary_sha256": {stage: digest(output / f"{stage}-gvm.so") for stage in ("raw", "purified")},
              "records": records, "tools": tools(), "complete": all(record["complete"] for record in records)}
    (output / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    if not report["complete"]:
        raise SystemExit(1)


# ---- Tests ----

class GraphOracleTests(unittest.TestCase):
    def test_changed_instruction_frame_and_alias_are_rejected(self):
        original = "((copy (register 1) (stack 2) (2 (0 1) (2) () (0 1))))"
        self.assertTrue(same_graph(original, original + "\n"))
        for changed in [original.replace("register 1", "register 2"),
                        original.replace("stack 2", "stack 1"),
                        original.replace("(0 1)", "(0 0)"),
                        original.replace("(2 (", "(3 ("),
                        original[:-1] + " (jump (label 1) #f #t))"]:
            self.assertFalse(same_graph(original, changed))


if __name__ == "__main__":
    main()
