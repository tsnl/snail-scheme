#!/usr/bin/env python3
"""Restore verified cat ABI evidence; optionally repeat its clean timing batch."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile

HERE = Path(__file__).resolve().parent
LABELS = ("frozen-b218", "roundtrip-b218", "eof-carrier-elided", "chez")


# ---- Frozen evidence ----


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def restore(destination):
    manifest = json.loads((HERE / "manifest.json").read_text())
    archive = HERE / "artifacts.tar.gz"
    if digest(archive) != manifest["archive_sha256"]:
        raise ValueError("archive checksum differs")
    destination.mkdir(parents=True, exist_ok=False)
    with tarfile.open(archive) as stream:
        stream.extractall(destination, filter="data")
    for relative, expected in manifest["files"].items():
        if digest(destination / relative) != expected:
            raise ValueError(f"restored checksum differs: {relative}")
    print(f"Verified {len(manifest['files'])} archived files", flush=True)


def relocate(destination):
    experiment = destination / "build/cat-experiment"
    for label in LABELS:
        directory = experiment / label
        path = directory / "prepared.json"
        case = json.loads(path.read_text())
        tool = Path(case["tool"]["path"])
        if not tool.is_file() or digest(tool) != case["tool"]["sha256"]:
            raise ValueError(f"original executable missing or changed: {tool}")
        artifact = directory / ("program.so" if label == "chez" else "program.wasm")
        case["directory"] = str(directory)
        case["command"] = ([str(tool), "--program", str(artifact)] if label == "chez" else
                           [str(tool), "--no-warnings", str(experiment / "host/scripts/run-wasi.mjs"),
                            str(artifact)])
        path.write_text(json.dumps(case, indent=2) + "\n")
        (directory / "outputs").mkdir(exist_ok=True)
    return experiment


# ---- Optional clean execution ----


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--measure", action="store_true")
    parser.add_argument("--cpu", type=int, default=5)
    options = parser.parse_args()
    destination = options.output.resolve()
    restore(destination)
    experiment = relocate(destination)
    node = json.loads((experiment / "frozen-b218/prepared.json").read_text())["tool"]["path"]
    code = ("const fs = require('node:fs'); for (const path of process.argv.slice(1)) "
            "new WebAssembly.Module(fs.readFileSync(path));")
    subprocess.run([node, "-e", code, *[str(experiment / label / "program.wasm")
                                      for label in LABELS if label != "chez"]], check=True)
    print("Frozen Wasm modules validate; no workload executed", flush=True)
    if options.measure:
        subprocess.run([sys.executable, destination / "build/cat-experiment.py", "measure",
                        *LABELS, "--output", "replayed-clean", "--rounds", "3", "--cpu",
                        str(options.cpu)], check=True)


if __name__ == "__main__":
    main()
