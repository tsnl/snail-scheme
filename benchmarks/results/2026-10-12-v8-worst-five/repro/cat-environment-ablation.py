#!/usr/bin/env python3
"""Remove one invariant loop environment allocation in the frozen cat program.

This is a program-specific diagnostic, not a compiler optimization. Both ports
are constant throughout catport; the two environment operands retain all their
checks and side effects. No argument arrays or character/port code is changed.
"""

import argparse
import copy
import hashlib
import importlib.util
import json
import subprocess
from pathlib import Path

FEATURES = ["--mvp-features", "--enable-gc", "--enable-reference-types", "--enable-tail-call",
            "--enable-mutable-globals", "--enable-sign-ext", "--enable-bulk-memory",
            "--enable-nontrapping-float-to-int"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ablate(function):
    replacements = []

    def visit(node):
        if not isinstance(node, list):
            return
        if node[:2] == ["return_call", "$function132"]:
            environment = node[2]
            assert environment[:3] == ["array.new_fixed", "$vector", "2"]
            assert len(environment) == 5
            replacements.append(copy.deepcopy(environment))
            node[2] = ["block", ["result", ["ref", "$vector"]],
                       ["drop", environment[3]], ["drop", environment[4]], ["local.get", "$0"]]
        for child in node:
            visit(child)

    visit(function)
    assert len(replacements) == 1, len(replacements)
    return replacements[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--reader", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location("wat", args.reader)
    wat = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(wat)
    original = args.output / "original.wat"
    subprocess.run(["wasm-dis", str(args.input), "-o", str(original)], check=True)
    module = wat.read_wat(original.read_text())
    control = args.output / "roundtrip.wat"
    control.write_text(wat.write_wat(module) + "\n")
    function = next(n for n in module if isinstance(n, list) and n[:2] == ["func", "$function132"])
    removed = ablate(function)
    changed = args.output / "reuse-environment.wat"
    changed.write_text(wat.write_wat(module) + "\n")
    commands = []
    for source in (control, changed):
        command = ["wasm-as", str(source), "-o", str(source.with_suffix(".wasm")), *FEATURES, "-g"]
        subprocess.run(command, check=True)
        commands.append(command)
    record = {"input": str(args.input), "input_sha256": digest(args.input), "commands": commands,
              "reader_sha256": digest(args.reader), "script_sha256": digest(Path(__file__)),
              "removed_environment": wat.write_wat(removed),
              "scope": __doc__, "artifacts": {p.name: digest(p) for p in args.output.glob("*.wasm")}}
    (args.output / "manifest.json").write_text(json.dumps(record, indent=2) + "\n")


if __name__ == "__main__":
    main()
