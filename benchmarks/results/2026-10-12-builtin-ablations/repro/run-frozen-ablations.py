#!/usr/bin/env python3
"""Restore checked frozen artifacts and rerun either independent ablation."""

import argparse
import copy
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

REPORT = Path(__file__).resolve().parent.parent


# ---- Checked archive reads ----


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_blob(archive, checksum):
    data = archive.extractfile("blobs/" + checksum).read()
    if digest(data) != checksum:
        raise ValueError("archive blob differs: " + checksum)
    return data


def write_blob(archive, checksum, output):
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(read_blob(archive, checksum))


def restore_case(archive, entry, directory, host):
    case = copy.deepcopy(entry["case"])
    for name, checksum in entry["files"].items():
        write_blob(archive, checksum, directory / name)
    (directory / "outputs").mkdir(exist_ok=True)
    case.update(directory=str(directory), samples=[], status="ready")
    case.pop("preliminary", None)
    case["command"] = [case["command"][0], "--no-warnings", str(host / "scripts/run-wasi.mjs"),
                       str(directory / "program.wasm")]
    return case


def restore_report(archive, manifest, side, directory):
    source = read_blob(archive, manifest["reports"][side["report"]]["sha256"])
    report = json.loads(source)
    cases = [manifest["cases"][name] for name in side["cases"]]
    for name, checksum in manifest["host"].items():
        write_blob(archive, checksum, directory / "host" / name)
    inputs = ["inputs/bib"] + ["inputs/" + row["case"]["benchmark"] + ".input" for row in cases]
    for name in inputs:
        write_blob(archive, report["input_sha256"][name], directory / name)
    report["cases"] = [restore_case(archive, entry, directory / "cases" / entry["case"]["benchmark"], directory / "host")
                       for entry in cases]
    report.update(output=str(directory), benchmarks=[entry["case"]["benchmark"] for entry in cases], systems=["snail-wasm"])
    report["input_sha256"] = {name: value for name, value in report["input_sha256"].items()
                              if not name.startswith("inputs/") or name in inputs}
    report["relocated_source"] = {"sha256": digest(source), "original_output": json.loads(source)["output"]}
    path = directory / "results.json"
    path.write_text(json.dumps(report, indent=2) + "\n")
    return path, report


# ---- Original measured helpers ----


def restore_runner(directory):
    benchmark = directory / "benchmarks"
    helper = benchmark / "results/2026-10-12-general-specialization/repro"
    helper.mkdir(parents=True)
    shutil.copyfile(REPORT / "repro/r7rs.py", benchmark / "r7rs.py")
    shutil.copyfile(REPORT / "repro/compare-frozen.py", helper / "compare-frozen.py")


def measured_environment(report):
    environment = dict(os.environ)
    for name, value in report["experiment_environment"].items():
        if value is None:
            environment.pop(name, None)
        else:
            environment[name] = value
    return environment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("experiment", choices=("write-char", "requested-kind", "typed-intrinsics"))
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--cpu", type=int, default=5)
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--restore-only", action="store_true")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir()
    manifest = json.loads((REPORT / "manifest.json").read_text())
    archive_path = REPORT / "artifacts.tar.xz"
    if digest(archive_path.read_bytes()) != manifest["archive_sha256"]:
        raise ValueError("archive hash differs")
    experiment = manifest["experiments"][args.experiment]
    with tarfile.open(archive_path) as archive:
        old_path, old = restore_report(archive, manifest, experiment["baseline"], args.output / "baseline")
        new_path, new = restore_report(archive, manifest, experiment["candidate"], args.output / "candidate")
    runner = args.output / "runner"
    restore_runner(runner)
    if args.restore_only:
        return
    command = [sys.executable, str(REPORT / "repro" / experiment["harness"]), str(old_path), str(new_path),
               "--output", str(args.output / "measurements"), "--cpu", str(args.cpu), "--rounds", str(args.rounds)]
    subprocess.run(command, cwd=runner, env=measured_environment(old), check=True)


if __name__ == "__main__":
    main()
