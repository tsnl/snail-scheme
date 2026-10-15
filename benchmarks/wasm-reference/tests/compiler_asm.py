#!/usr/bin/env python3
"""Check the complete original assembler pipeline; full Compiler remains pending."""

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

# ---- Original assembler diagnostics ----

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def supplied_cases():
    return {
        "zero-distance-widening": "((branch 24576 1) (label 1 #t))",
        "empty-code": "()",
        "forward-backward-relocations": "((label 1 #t) (branch 26368 2) " + "(word 20081) " * 70 + "(label 2 #t) (branch 26112 1) (word-relative 1 -6) (long-relative 2 3 127) (align 8 4) (text \"relocated\"))",
        "symbol-and-procedure-records": "((label 1 #t) (word 8192) (global-reference \"alpha\") (text \"read\") (global-assignment \"alpha\") (word 3) (global-jump \"beta\") (procedure-reference 7 -2) (primitive-reference \"+\" 10) (global-reference \"beta\") (m68020) (m68881) (text \"records\"))",
        "signed-words-and-alignment": "((label 1 #t) (long -65537) (long -131072) (word -1) (word 65537) (align 8 4) (label 2 #t) (word-relative 1 32766) (text \"signed\"))",
    }


def prepare_oracle(output):
    files = pinned_sources(REFERENCE.parent / "r7rs-benchmarks")
    source = chez_source("compiler").rstrip()
    assert source.endswith("(run-benchmark)")
    source = source[:-len("(run-benchmark)")]
    source = source.replace("    current-time\n", "    current-time\n    parameterize\n    print-extended-identifiers\n", 1)
    program, artifact = output / "assembler.scm", output / "assembler.so"
    program.write_text(source + (REFERENCE / "tests/compiler-asm-oracle-tail.scm").read_text())
    script = output / "assembler-compile.scm"
    script.write_text(f'(import (chezscheme))\n(parameterize ((optimize-level 2)) (compile-program "{program}" "{artifact}"))\n')
    subprocess.run(["scheme", "--script", str(script)], check=True, capture_output=True)


# ---- Complete words, lines and descriptor positions ----

def same_assembly(first, second):
    try:
        return read_program(first) == read_program(second)
    except (ValueError, StopIteration):
        return False


def check_case(name, supplied, output):
    supplied = (supplied + "\n").encode()
    (output / f"{name}.input").write_bytes(supplied)
    commands = {"rust-wasm": ["node", "--no-warnings", str(REFERENCE / "run-wasi.mjs"), str(output / "compiler_frontend.wasm"), "--asm-probe"],
                "chez": ["scheme", "--program", str(output / "assembler.so")]}
    runs = {}
    for system, command in commands.items():
        result = subprocess.run(command, input=supplied, capture_output=True, timeout=60)
        (output / f"{name}-{system}.txt").write_bytes(result.stdout)
        runs[system] = {"command": command, "returncode": result.returncode,
                        "stdout": result.stdout.decode(), "stderr": result.stderr.decode()}
    complete = all(run["returncode"] == 0 for run in runs.values()) and same_assembly(runs["rust-wasm"]["stdout"], runs["chez"]["stdout"])
    print(f"{name}: {complete}", flush=True)
    return {"name": name, "input_sha256": hashlib.sha256(supplied).hexdigest(), "complete": complete, "runs": runs}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    output = parser.parse_args().output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    prepare_oracle(output)
    shutil.copy2(REFERENCE / "target/wasm32-wasip1/release/examples/compiler_frontend.wasm", output / "compiler_frontend.wasm")
    for source in [*REFERENCE.glob("src/compiler*.rs"), *REFERENCE.glob("src/compiler*.scm")]:
        shutil.copy2(source, output / source.name)
    records = [check_case(name, supplied, output) for name, supplied in supplied_cases().items()]
    report = {"kind": "complete assembler diagnostics", "canonical_full_compiler_pending": True,
              "performance_samples": False, "source_sha256": {path.name: digest(path) for path in output.glob("compiler*")},
              "oracle_source_sha256": digest(output / "assembler.scm"), "oracle_binary_sha256": digest(output / "assembler.so"),
              "records": records, "tools": tools(), "complete": all(record["complete"] for record in records)}
    (output / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    if not report["complete"]:
        raise SystemExit(1)


# ---- Tests ----

class AssemblyOracleTests(unittest.TestCase):
    def test_complete_lines_words_and_positions_remain_distinct(self):
        original = '(("L0:" "step") (32776 20081 65535) ((1 0)))'
        self.assertTrue(same_assembly(original, original))
        for changed in [original.replace("step", "other"), original.replace("20081", "20085"),
                        original.replace("(1 0)", "(1 1)"), original.replace("65535", "65535 0")]:
            self.assertFalse(same_assembly(original, changed))


if __name__ == "__main__":
    main()
