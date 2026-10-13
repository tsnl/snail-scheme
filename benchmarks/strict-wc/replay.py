#!/usr/bin/env python3
"""Verify the wc archive, optionally rerun linked checks or its clean batch."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE.parent / "results/2026-10-13-strict-source-wc"


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
    tools = identity["actual_link_tools"]
    for name in ("NODE", "CHEZ"):
        if digest(Path(tools[name]["path"])) != tools[name]["sha256"]:
            raise ValueError(f"original {name} binary is missing or changed")
    artifacts = []
    for label in ("control", "strict-source", "chez"):
        directory = experiment / label
        path = directory / "prepared.json"
        case = json.loads(path.read_text())
        case["directory"] = str(directory)
        case["command"] = [tools["CHEZ"]["path"], "--program", str(directory / "program.so")] if label == "chez" else [
            tools["NODE"]["path"], "--no-warnings", str(experiment / "host/scripts/run-wasi.mjs"), str(directory / "program.wasm")]
        path.write_text(json.dumps(case, indent=2) + "\n")
        if label != "chez":
            artifacts.append(str(directory / "program.wasm"))
    code = "const fs=require('node:fs'); for(const p of process.argv.slice(1)) new WebAssembly.Module(fs.readFileSync(p));"
    subprocess.run([tools["NODE"]["path"], "-e", code, *artifacts], check=True)


# ---- Optional linked execution and clean timing ----


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--measure", action="store_true")
    parser.add_argument("--cpu", type=int, default=5)
    options = parser.parse_args()
    destination = options.output.resolve()
    restore(destination)
    experiment = destination / "experiment"
    relocate(experiment)
    print("Compiled Wasm artifacts validate; no workload executed", flush=True)
    if options.validate:
        (experiment / "validation").rename(experiment / "original-validation")
        subprocess.run([sys.executable, str(HERE / "measure.py"), "validate", "--output", str(experiment)], check=True)
    if options.measure:
        (experiment / "clean").rename(experiment / "original-clean")
        subprocess.run([sys.executable, str(HERE / "measure.py"), "measure", "--output", str(experiment),
                        "--cpu", str(options.cpu), "--rounds", "3"], check=True)


if __name__ == "__main__":
    main()
