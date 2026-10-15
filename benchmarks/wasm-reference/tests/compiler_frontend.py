#!/usr/bin/env python3
"""Check one-pass Compiler intermediate trees; full assembly validation is separate."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

REFERENCE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REFERENCE))
from audit_alpha import alpha_equivalent
from suite import pinned_sources, tools, chez_source

# ---- Original compiler diagnostics ----

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare_oracles(output):
    upstream = REFERENCE.parent / "r7rs-benchmarks"
    files = pinned_sources(upstream)
    source = chez_source("compiler").rstrip()
    assert source.endswith("(run-benchmark)")
    source = source[:-len("(run-benchmark)")]
    # Serialization controls are private oracle imports, not algorithm edits.
    source = source.replace("    current-time\n", "    current-time\n    parameterize\n    print-extended-identifiers\n", 1)
    tail = (REFERENCE / "tests/compiler-front-oracle-tail.scm").read_text()
    for stage in ("raw", "partial", "normalized"):
        program, artifact = output / f"{stage}.scm", output / f"{stage}.so"
        program.write_text(source + tail.replace("@STAGE@", stage))
        script = output / f"{stage}-compile.scm"
        script.write_text(f'(import (chezscheme))\n(parameterize ((optimize-level 2)) (compile-program "{program}" "{artifact}"))\n')
        subprocess.run(["scheme", "--script", str(script)], check=True, capture_output=True)
    return files["inputs/compiler.input"]


# ---- Complete linked intermediate comparisons ----

def check_program(name, supplied, output, wasm):
    (output / f"{name}.input").write_bytes(supplied)
    records = []
    for stage, extra in (("raw", []), ("partial", ["--partial"]), ("normalized", ["--normalize"])):
        commands = {"rust-wasm": ["node", "--no-warnings", str(REFERENCE / "run-wasi.mjs"), str(wasm), *extra],
                    "chez": ["scheme", "--program", str(output / f"{stage}.so")]}
        runs = {}
        for system, command in commands.items():
            result = subprocess.run(command, input=supplied, capture_output=True, timeout=60)
            (output / f"{name}-{stage}-{system}.txt").write_bytes(result.stdout)
            runs[system] = {"command": command, "returncode": result.returncode,
                            "stdout": result.stdout.decode(), "stderr": result.stderr.decode()}
        complete = all(run["returncode"] == 0 for run in runs.values()) and alpha_equivalent(runs["rust-wasm"]["stdout"], runs["chez"]["stdout"])
        records.append({"name": name, "stage": stage, "complete": complete,
                        "input_sha256": hashlib.sha256(supplied).hexdigest(), "runs": runs})
        print(f"{name} / {stage}: {complete}", flush=True)
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    canonical = prepare_oracles(output)
    wasm = REFERENCE / "target/wasm32-wasip1/release/examples/compiler_frontend.wasm"
    shutil.copy2(wasm, output / "compiler_frontend.wasm")
    shutil.copy2(REFERENCE / "src/compiler.rs", output / "compiler.rs")
    wasm = output / "compiler_frontend.wasm"
    records = check_program("canonical-program", canonical, output, wasm)
    fixtures = json.loads((REFERENCE / "tests/compiler-front-fixtures.json").read_text())
    for name, expression in fixtures.items():
        supplied = f"1\n(begin (declare (standard-bindings) (fixnum) (not safe) (block)) {expression})\nm68000\nasm\nignored\n".encode()
        records.extend(check_program(name, supplied, output, wasm))
    report = {"kind": "intermediate frontend correctness", "canonical_full_compiler_pending": True,
              "performance_samples": False, "source_sha256": digest(output / "compiler.rs"),
              "wasm_sha256": digest(output / "compiler_frontend.wasm"), "records": records, "tools": tools(),
              "original_stage_oracle_printing": "extended identifiers printed literally; compiler algorithms unchanged",
              "oracle_source_sha256": {stage: digest(output / f"{stage}.scm") for stage in ("raw", "partial", "normalized")},
              "oracle_binary_sha256": {stage: digest(output / f"{stage}.so") for stage in ("raw", "partial", "normalized")},
              "complete": all(record["complete"] for record in records)}
    (output / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    if not report["complete"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
