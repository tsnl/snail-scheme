#!/usr/bin/env python3
"""Restore scalar-extern evidence; optionally repeat the frozen clean batch."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

HERE = Path(__file__).resolve().parent
LABELS = ("control", "scalar-wrappers", "scalar-loop")


# ---- Frozen artifacts and relocated process commands ----


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def restore(destination):
    manifest = json.loads((HERE / "manifest.json").read_text())
    archive = HERE / manifest["archive"]
    if digest(archive) != manifest["archive_sha256"]:
        raise ValueError("archive checksum differs")
    destination.mkdir(parents=True, exist_ok=False)
    with tarfile.open(archive) as stream:
        stream.extractall(destination / "build", filter="data")
    for relative, expected in manifest["files"].items():
        if digest(destination / "build" / relative) != expected:
            raise ValueError(f"restored checksum differs: {relative}")
    print(f"Verified {len(manifest['files'])} archived files", flush=True)
    return destination / "build/typed-extern-cat"


def relocate(experiment):
    for label in LABELS:
        directory = experiment / label
        path = directory / "prepared.json"
        case = json.loads(path.read_text())
        node = Path(case["tool"]["path"])
        if not node.is_file() or digest(node) != case["tool"]["sha256"]:
            raise ValueError(f"original Node missing or changed: {node}")
        case["directory"] = str(directory)
        case["runtime_source"] = str(experiment / "runtime.wasm")
        case["command"] = [str(node), "--no-warnings",
                           str(experiment / "host/scripts/run-wasi.mjs"),
                           str(directory / "program.wasm")]
        path.write_text(json.dumps(case, indent=2) + "\n")
    return node


# ---- Validation without a workload, or an explicit clean rerun ----


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--measure", action="store_true")
    parser.add_argument("--cpu", type=int, default=5)
    options = parser.parse_args()
    destination = options.output.resolve()
    experiment = restore(destination)
    node = relocate(experiment)
    code = ("const fs = require('node:fs'); for (const path of process.argv.slice(1)) "
            "new WebAssembly.Module(fs.readFileSync(path));")
    subprocess.run([node, "-e", code, *[str(experiment / label / "program.wasm")
                                      for label in LABELS]], check=True)
    print("Frozen Wasm modules validate; no workload executed", flush=True)
    if options.measure:
        scripts = destination / "scripts"
        scripts.mkdir()
        driver = scripts / "prototype-typed-extern-cat"
        shutil.copy2(experiment / "sources/scripts" / driver.name, driver)
        subprocess.run([sys.executable, driver, "measure", *LABELS, "--output",
                        "replayed-clean", "--rounds", "3", "--cpu", str(options.cpu)], check=True)


if __name__ == "__main__":
    main()
