#!/usr/bin/env python3
"""Retain exact native LLVM and Wasm merger inputs before build cleanup."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


# ---- Immutable captured inputs ----


def capture_file(source, directory):
    data = source.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    shared = directory.parents[2] / "captured-inputs"
    shared.mkdir(exist_ok=True)
    stored = shared / (digest + source.suffix)
    if not stored.exists():
        stored.write_bytes(data)
    destination = directory / ("capture-" + source.name)
    destination.unlink(missing_ok=True)
    destination.hardlink_to(stored)
    return {"source": str(source), "file": destination.name, "sha256": digest}


def capture_inputs(arguments, directory):
    inputs = [Path(arg) for arg in arguments if Path(arg).is_file() and
              Path(arg).suffix in (".ll", ".wasm", ".wat", ".a", ".c")]
    staging = [path.parent for path in inputs if path.suffix == ".ll" or
               path.name == "scheme.optimized.wasm"]
    for parent in staging:
        inputs.extend(path for path in parent.iterdir() if path.is_file() and
                      path.suffix in (".ll", ".wasm", ".wat", ".scm"))
    return [capture_file(path, directory) for path in dict.fromkeys(inputs)]


# ---- Transparent tool invocation ----


def main():
    name = Path(sys.argv[0]).name
    real = os.environ["SNAIL_REAL_CLANG" if name.endswith("clang") else "SNAIL_REAL_WASM_MERGE"]
    directory = os.environ.get("SNAIL_CAPTURE_DIRECTORY")
    if directory and "--version" not in sys.argv:
        record = {"tool": real, "arguments": sys.argv[1:],
                  "inputs": capture_inputs(sys.argv[1:], Path(directory))}
        with (Path(directory) / "capture-commands.jsonl").open("a") as output:
            output.write(json.dumps(record) + "\n")
    raise SystemExit(subprocess.call([real, *sys.argv[1:]]))


if __name__ == "__main__":
    main()
