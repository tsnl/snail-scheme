#!/usr/bin/env python3
"""Compare genuine full Compiler assembly in actual Node/Wasm and original Chez."""

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
from suite import pinned_sources, tools, chez_source

# ---- Original one-pass complete assembly oracle ----

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare_oracle(output):
    files = pinned_sources(REFERENCE.parent / "r7rs-benchmarks")
    source = chez_source("compiler").rstrip()
    assert source.endswith("(run-benchmark)")
    source = source[:-len("(run-benchmark)")]
    source = source.replace("    current-time\n", "    current-time\n    parameterize\n", 1)
    program, artifact = output / "assembly.scm", output / "assembly.so"
    program.write_text(source + (REFERENCE / "tests/compiler-assembly-oracle-tail.scm").read_text())
    script = output / "assembly-compile.scm"
    script.write_text(f'(import (chezscheme))\n(parameterize ((optimize-level 2)) (compile-program "{program}" "{artifact}"))\n')
    subprocess.run(["scheme", "--script", str(script)], check=True, capture_output=True)
    return files["inputs/compiler.input"]


def same_assembly(first, second):
    try:
        return read_program(first) == read_program(second)
    except (ValueError, StopIteration):
        return False


def check_program(name, supplied, output):
    (output / f"{name}.input").write_bytes(supplied)
    commands = {"rust-wasm": ["node", "--no-warnings", str(REFERENCE / "run-wasi.mjs"), str(output / "compiler_frontend.wasm"), "--assembly-audit"],
                "chez": ["scheme", "--program", str(output / "assembly.so")]}
    runs = {}
    for system, command in commands.items():
        run = subprocess.run(command, input=supplied, capture_output=True, timeout=60)
        (output / f"{name}-{system}.txt").write_bytes(run.stdout)
        runs[system] = {"command": command, "returncode": run.returncode,
                        "stdout": run.stdout.decode(), "stderr": run.stderr.decode()}
    complete = all(run["returncode"] == 0 for run in runs.values()) and same_assembly(runs["rust-wasm"]["stdout"], runs["chez"]["stdout"])
    print(f"{name} / complete assembly: {complete}", flush=True)
    return {"name": name, "complete": complete, "input_sha256": hashlib.sha256(supplied).hexdigest(), "runs": runs}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    output = parser.parse_args().output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    canonical = prepare_oracle(output)
    shutil.copy2(REFERENCE / "target/wasm32-wasip1/release/examples/compiler_frontend.wasm", output / "compiler_frontend.wasm")
    for source in [*REFERENCE.glob("src/compiler*.rs"), *REFERENCE.glob("src/compiler*.scm")]:
        shutil.copy2(source, output / source.name)
    records = [check_program("canonical-program-once", canonical, output)]
    fixtures = {}
    for group in ["front", "gvm", "blocks", "assembly"]:
        path = REFERENCE / f"tests/compiler-{group}-fixtures.json"
        if path.exists():
            fixtures.update(json.loads(path.read_text()))
    for name, expression in fixtures.items():
        supplied = f"1\n(begin (declare (standard-bindings) (fixnum) (not safe) (block)) {expression})\nm68000\nasm\nignored\n".encode()
        records.append(check_program(name, supplied, output))
    report = {"kind": "complete assembly and normalized object-word correctness", "canonical_full_count_pending": True,
              "performance_samples": False, "source_sha256": {path.name: digest(path) for path in output.glob("compiler*")},
              "oracle_source_sha256": digest(output / "assembly.scm"), "oracle_binary_sha256": digest(output / "assembly.so"),
              "records": records, "tools": tools(), "complete": all(record["complete"] for record in records)}
    (output / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    if not report["complete"]:
        raise SystemExit(1)


# ---- Tests ----

class AssemblyOracleTests(unittest.TestCase):
    def test_complete_lines_and_object_words_reject_changes_and_truncation(self):
        original = '(("L1:" " movl d1,d2" "L0:" "") (5 0 32768 8))'
        self.assertTrue(same_assembly(original, original + "\n"))
        for changed in [original.replace("d2", "d3"), original.replace("32768", "32769"),
                        original.replace(' "L0:"', ''), original.replace(" 8)", " 8 0)")]:
            self.assertFalse(same_assembly(original, changed))


if __name__ == "__main__":
    main()
