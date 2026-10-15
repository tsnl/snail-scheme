#!/usr/bin/env python3
"""Untimed character and complete graph equivalence checks for the references."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

# ---- Character semantics ----

def run_rust(prepared, benchmark, case, source, arguments=(), output=None):
    command = ["node", "--no-warnings", str(prepared / "reference-source/run-wasi.mjs"),
               str(prepared / "cases" / benchmark / "rust-wasm/program.wasm"), *arguments]
    completed = subprocess.run(command, cwd=case, input=source, stdout=output or subprocess.PIPE,
                               stderr=subprocess.PIPE, check=True)
    return {"command": command, "stdout": completed.stdout.decode() if completed.stdout else None,
            "stderr": completed.stderr.decode()}


def characters(prepared):
    case = prepared / "character-audit"
    (case / "inputs").mkdir(parents=True, exist_ok=True)
    (case / "outputs").mkdir(exist_ok=True)
    text = "é🐌\t a\r\nβ x\n".encode()
    (case / "inputs/unicode").write_bytes(text)
    cat = run_rust(prepared, "cat", case, b'2\n"inputs/unicode"\n"outputs/cat.output"\nignored\n')
    assert (case / "outputs/cat.output").read_bytes() == text
    wc = run_rust(prepared, "wc", case, b'2\n"inputs/unicode"\n(2 4 11)\n')
    assert "Result: (2 4 11)" in wc["stdout"]
    return {"cat": cat, "wc": wc, "output_sha256": hashlib.sha256(text).hexdigest(),
            "meaning": "UTF-8 character copying; tab and carriage return remain word characters"}

# ---- Entire graph materialization ----

def prepare_chez_graph(prepared, audit):
    source = (prepared / "cases/graphs/chez/program.scm").read_text()
    source = source.rsplit("(run-benchmark)", 1)[0] + "(write (run 7))\n(newline)\n"
    (audit / "program.scm").write_text(source)
    script = f'(import (chezscheme))\n(parameterize ((optimize-level 2)) (compile-program "{audit}/program.scm" "{audit}/program.so"))\n'
    (audit / "compile.scm").write_text(script)
    report = json.loads((prepared / "results.json").read_text())
    chez = next(case["command"][0] for case in report["cases"] if case["system"] == "chez")
    command = [chez, "--script", str(audit / "compile.scm")]
    subprocess.run(command, check=True, capture_output=True)
    return chez, command


def output_digest(filename):
    data = filename.read_bytes()
    canonical = b"".join(data.split())
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "canonical_bytes": len(canonical), "canonical_sha256": hashlib.sha256(canonical).hexdigest()}


def graphs(prepared):
    audit = prepared / "graph-audit"
    audit.mkdir(exist_ok=True)
    chez, compilation = prepare_chez_graph(prepared, audit)
    with (audit / "chez.output").open("wb") as output:
        subprocess.run([chez, "--program", str(audit / "program.so")], stdout=output, check=True)
    with (audit / "rust.output").open("wb") as output:
        rust = run_rust(prepared, "graphs", audit, b"1\n7\n213829\n", ["--dump"], output)
    original, reference = output_digest(audit / "chez.output"), output_digest(audit / "rust.output")
    assert original["canonical_sha256"] == reference["canonical_sha256"]
    return {"equal": True, "chez": original, "rust": reference, "rust_command": rust["command"],
            "chez_compilation": compilation, "canonicalization": "remove ASCII whitespace; atoms are single-digit vertices 0..6",
            "meaning": "all 213829 graphs in original traversal order, including every ordered outgoing-edge list"}

# ---- Command line ----

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepared", type=Path, required=True)
    args = parser.parse_args()
    prepared = args.prepared.resolve()
    validation = {"kind": "untimed functional checks", "characters": characters(prepared), "graphs": graphs(prepared)}
    (prepared / "validation.json").write_text(json.dumps(validation, indent=2) + "\n")
    print(json.dumps(validation, indent=2))


if __name__ == "__main__":
    main()
