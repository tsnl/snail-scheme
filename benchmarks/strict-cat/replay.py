#!/usr/bin/env python3
"""Verify the strict cat archive and optionally repeat its final clean batch."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE.parent / "results/2026-10-13-strict-source-cat"


# ---- Verified restoration ----


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def restore(destination):
    manifest = json.loads((EVIDENCE / "manifest.json").read_text())
    archive = EVIDENCE / manifest["archive"]
    if digest(archive) != manifest["archive_sha256"]:
        raise ValueError("archive checksum differs")
    destination.mkdir(parents=True, exist_ok=False)
    with tarfile.open(archive) as stream:
        stream.extractall(destination, filter="data")
    for relative, expected in manifest["files"].items():
        if digest(destination / relative) != expected:
            raise ValueError(f"restored checksum differs: {relative}")
    print(f"Verified {len(manifest['files'])} archived files", flush=True)


def relocate(experiment):
    identity = json.loads((experiment / "identity.json").read_text())
    node = identity["actual_link_tools"]["NODE"]
    if digest(Path(node["path"])) != node["sha256"]:
        raise ValueError("original Node binary is missing or changed")
    artifacts = []
    for label in ("control", "hand-loop", "strict-source"):
        directory = experiment / label
        path = directory / "prepared.json"
        case = json.loads(path.read_text())
        case["directory"] = str(directory)
        case["command"] = [node["path"], "--no-warnings", str(experiment / "host/scripts/run-wasi.mjs"),
                           str(directory / "program.wasm")]
        path.write_text(json.dumps(case, indent=2) + "\n")
        artifacts.append(str(directory / "program.wasm"))
    code = "const fs=require('node:fs'); for(const p of process.argv.slice(1)) new WebAssembly.Module(fs.readFileSync(p));"
    subprocess.run([node["path"], "-e", code, *artifacts], check=True)


# ---- Read-only validation or an explicit rerun ----


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--measure", action="store_true")
    parser.add_argument("--cpu", type=int, default=5)
    options = parser.parse_args()
    destination = options.output.resolve()
    restore(destination)
    experiment = destination / "final-candidate"
    relocate(experiment)
    print("Final Wasm artifacts validate; no workload executed", flush=True)
    if options.measure:
        (experiment / "clean").rename(experiment / "original-clean")
        subprocess.run([sys.executable, str(HERE / "measure.py"), "measure", "--output", str(experiment),
                        "--cpu", str(options.cpu), "--rounds", "3"], check=True)


if __name__ == "__main__":
    main()
