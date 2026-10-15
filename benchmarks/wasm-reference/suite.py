#!/usr/bin/env python3
"""Check Rust/WASI ports against pinned R7RS inputs and independent Chez runs."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from audit_alpha import alpha_equivalent
from audit_nucleic import same_solutions

# ---- Pinned sources and selected workloads ----

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = Path(__file__).resolve().parent
REVISION = "85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1"


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical_names(source):
    groups = re.findall(r'^\w+_BENCHMARKS="([^$"\n]+)"', (source / "bench").read_text(), re.MULTILINE)
    return list(dict.fromkeys(" ".join(groups).split()))


def tools():
    commands = {"rustc": ["rustc", "--version", "--verbose"], "cargo": ["cargo", "--version"],
                "node": ["node", "-p", "JSON.stringify(process.versions)"], "chez": ["scheme", "--version"]}
    return {name: {"path": shutil.which(command[0]), "sha256": digest(shutil.which(command[0])),
                   "version": subprocess.check_output(command, text=True, stderr=subprocess.STDOUT).strip()}
            for name, command in commands.items()}


def pinned_sources(source):
    revision = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    changes = subprocess.check_output(["git", "-C", str(source), "status", "--porcelain", "--untracked-files=no"])
    if revision != REVISION or changes:
        raise ValueError("upstream must be clean and pinned to " + REVISION)
    paths = subprocess.check_output(["git", "-C", str(source), "ls-files"], text=True).splitlines()
    return {path: (source / path).read_bytes() for path in paths}


def freeze_sources(source, output, files):
    shutil.copytree(source / "inputs", output / "inputs", dirs_exist_ok=True)
    shutil.copytree(REFERENCE / "src", output / "reference-source/src", dirs_exist_ok=True)
    if (REFERENCE / "tests").is_dir():
        shutil.copytree(REFERENCE / "tests", output / "reference-source/tests", dirs_exist_ok=True)
    for name in ("Cargo.toml", "Cargo.lock", "run-wasi.mjs", "suite.py", "audit_alpha.py", "audit_nucleic.py", "small-inputs.json"):
        shutil.copy2(REFERENCE / name, output / "reference-source" / name)
    return {"upstream": {name: hashlib.sha256(data).hexdigest() for name, data in files.items()
                         if name == "bench" or name.startswith(("src/", "inputs/"))},
            "rust": {str(path.relative_to(output / "reference-source")): digest(path)
                     for path in sorted((output / "reference-source").rglob("*")) if path.is_file()}}


# ---- Linked execution and rejection checks ----

def execute(command, directory, source):
    try:
        completed = subprocess.run(command, cwd=directory, input=source, text=True,
                                   capture_output=True, timeout=900)
    except subprocess.TimeoutExpired as error:
        return {"command": command, "returncode": None, "stdout": str(error.stdout),
                "stderr": str(error.stderr), "timeout_seconds": 900, "files": {}}
    return {"command": command, "returncode": completed.returncode,
            "stdout": completed.stdout, "stderr": completed.stderr,
            "files": generated_files(directory)}


def generated_files(directory):
    paths = [path for path in (directory / "outputs").rglob("*") if path.is_file()]
    paths.extend(path for path in (directory / "pltexchk.jnk", directory / "xZfilhid.tex") if path.is_file())
    return {str(path.relative_to(directory)): {"sha256": digest(path), "bytes": path.stat().st_size}
            for path in sorted(paths)}



def passed(run):
    return run["returncode"] == 0 and "+!CSVLINE!+" in run["stdout"] and "INCORRECT" not in run["stdout"]


def chez_source(name):
    path = ROOT / "benchmarks/sfir" / name
    provenance = json.loads((path / "migration.json").read_text())
    source = path / "chez-original.scm"
    if digest(source) != provenance["controls"]["chez-original.scm"]:
        raise ValueError("authored Chez control differs from its provenance: " + name)
    return source.read_text()


def compile_chez(name, directory):
    source = directory / "program.scm"
    source.write_text(chez_source(name))
    artifact = directory / "program.so"
    script = directory / "compile.scm"
    script.write_text('(import (chezscheme))\n(parameterize ((optimize-level 2)) '
                      f'(compile-program "{source}" "{artifact}"))\n')
    command = [shutil.which("scheme"), "--script", str(script)]
    subprocess.run(command, check=True, capture_output=True)
    return [shutil.which("scheme"), "--program", str(artifact)], command


def prepare_case(files, name, output):
    directory = output / "cases" / name
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "outputs").mkdir(exist_ok=True)
    if not (directory / "inputs").exists():
        (directory / "inputs").symlink_to(output / "inputs", target_is_directory=True)
    artifact = directory / "program.wasm"
    shutil.copy2(REFERENCE / "target/wasm32-wasip1/release" / f"{name}.wasm", artifact)
    (directory / "input.txt").write_bytes(files[f"inputs/{name}.input"])
    rust = [shutil.which("node"), "--no-warnings", str(output / "reference-source/run-wasi.mjs"), str(artifact)]
    chez, compilation = compile_chez(name, directory)
    return directory, rust, chez, compilation


def check_case(files, name, output, checks, fixtures):
    directory, rust, chez, compilation = prepare_case(files, name, output)
    record = {"benchmark": name, "input_sha256": digest(directory / "input.txt"),
              "wasm_sha256": digest(directory / "program.wasm"), "wasm_bytes": (directory / "program.wasm").stat().st_size,
              "chez_sha256": digest(directory / "program.so"), "chez_source_sha256": digest(directory / "program.scm"),
              "chez_compilation": compilation, "checks": []}
    for fixture in fixtures.get(name, []):
        if not fixture.get("canonical_audit"):
            record["checks"].append(check_fixture(fixture, directory, rust, chez))
    if checks != "small":
        source = (directory / "input.txt").read_text()
        if checks == "quick" and name != "equal":
            source = re.sub(r"\A((?:\s|;[^\n]*(?:\n|$))*)\d+", lambda m: m[1] + "1", source, count=1)
        fixture = {"name": checks + "-canonical", "input": source}
        if checks == "full":
            for audit in fixtures.get(name, []):
                if audit.get("canonical_audit"):
                    assert "input" not in audit, "canonical audit cannot replace upstream input"
                    fixture.update({key: value for key, value in audit.items()
                                    if key not in ("name", "canonical_audit")})
        if name == "slatex":
            fixture.update(isolate_systems=True, compare_output_sets=True)
        if name in ("cat", "tail", "ray"):
            fixture["compare_files"] = [f"outputs/{name}.output"]
        record["checks"].append(check_fixture(fixture, directory, rust, chez))
    record["complete"] = bool(record["checks"]) and all(check["complete"] for check in record["checks"])
    return record


def check_fixture(fixture, directory, rust, chez):
    for name, text in fixture.get("files", {}).items():
        (directory / name).write_text(text)
    commands = (("rust-wasm", [*rust, *fixture.get("rust_arguments", [])]), ("chez", chez))
    directories = {}
    for system, _ in commands:
        case_directory = directory
        if fixture.get("isolate_systems"):
            case_directory = directory / fixture["name"] / system
            case_directory.mkdir(parents=True, exist_ok=True)
            (case_directory / "outputs").mkdir(exist_ok=True)
            (case_directory / "inputs").symlink_to(directory / "inputs", target_is_directory=True)
            for name, text in fixture.get("files", {}).items():
                (case_directory / name).write_text(text)
        directories[system] = case_directory
    runs = {system: execute(command, directories[system], fixture["input"])
            for system, command in commands}
    errors = []
    for system, run in runs.items():
        if not passed(run):
            errors.append(system + " failed its original predicate or target execution")
    for text in fixture.get("rust_stdout_contains", []):
        if text not in runs["rust-wasm"]["stdout"]:
            errors.append("incorrect complete Rust audit output: " + text)
    if "rust_audit_alpha_equivalent" in fixture:
        audits = [line.removeprefix("Audit: ") for line in runs["rust-wasm"]["stdout"].splitlines()
                  if line.startswith("Audit: ")]
        if len(audits) != 1 or not alpha_equivalent(audits[0], fixture["rust_audit_alpha_equivalent"]):
            errors.append("complete residual programs differ beyond bound-variable alpha renaming")
    if "rust_nucleic_audit" in fixture:
        audits = [line.removeprefix("Audit: ") for line in runs["rust-wasm"]["stdout"].splitlines()
                  if line.startswith("Audit: ")]
        expected = (directory.parents[1] / "reference-source" / fixture["rust_nucleic_audit"]).read_text()
        if len(audits) != 1 or not same_solutions(audits[0], expected):
            errors.append("complete nucleic solution identities/transforms differ")
    if "rust_exact_audit" in fixture:
        audits = [line.removeprefix("Audit: ") for line in runs["rust-wasm"]["stdout"].splitlines()
                  if line.startswith("Audit: ")]
        expected = (directory.parents[1] / "reference-source" / fixture["rust_exact_audit"]).read_text().strip()
        if audits != [expected]:
            errors.append("complete untimed serialized result differs from original Chez oracle")
    if fixture.get("compare_output_sets") and runs["rust-wasm"]["files"] != runs["chez"]["files"]:
        errors.append("complete generated file set or file contents differ")
    for name in fixture.get("compare_files", []):
        if runs["rust-wasm"]["files"].get(name) != runs["chez"]["files"].get(name):
            errors.append("file output differs: " + name)
    for name, text in fixture.get("expected_files", {}).items():
        expected = hashlib.sha256(text.encode()).hexdigest()
        if any(run["files"].get(name, {}).get("sha256") != expected for run in runs.values()):
            errors.append("incorrect complete file contents: " + name)
    rejected = {}
    if "wrong" in fixture:
        rejected = {system: execute(command, directories[system], fixture["wrong"])
                    for system, command in commands}
        if any(passed(run) for run in rejected.values()):
            errors.append("wrong result accepted")
    return {"name": fixture["name"], "input_sha256": hashlib.sha256(fixture["input"].encode()).hexdigest(),
            "complete": not errors, "errors": errors, "passed": runs, "wrong_result_rejected": rejected,
            "wrong_result_meaning": fixture.get("wrong_meaning", "deliberately wrong expected answer" if rejected else None)}


# ---- Command line ----

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "benchmarks/r7rs-benchmarks")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--benchmarks", nargs="+", default=["all"])
    parser.add_argument("--checks", choices=("small", "quick", "full"), default="small")
    parser.add_argument("--build", action="store_true")
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    files = pinned_sources(source)
    available = canonical_names(source)
    implemented = [name for name in available if (REFERENCE / "src/bin" / f"{name}.rs").exists()]
    names = implemented if args.benchmarks == ["all"] else args.benchmarks
    if any(name not in implemented for name in names) or len(names) != len(set(names)):
        raise ValueError("choose distinct implemented workloads: " + " ".join(implemented))
    if args.build:
        subprocess.run(["cargo", "build", "--offline", "--release", "--target", "wasm32-wasip1",
                        "--manifest-path", str(REFERENCE / "Cargo.toml")], check=True)
    output.mkdir(parents=True, exist_ok=True)
    report = {"kind": "functional-validation", "performance_samples": False, "checks": args.checks,
              "upstream_revision": REVISION, "revision": subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip(),
              "inventory": {"canonical": available, "implemented": implemented, "remaining": [n for n in available if n not in implemented]},
              "tools": tools(), "sources": freeze_sources(source, output, files), "cases": []}
    fixtures = json.loads((REFERENCE / "small-inputs.json").read_text())
    filename = output / "validation.json"
    for name in names:
        report["cases"].append(check_case(files, name, output, args.checks, fixtures))
        filename.write_text(json.dumps(report, indent=2) + "\n")
        print(f"checked {name} ({args.checks}): " + ("passed" if report["cases"][-1]["complete"] else "FAILED; retained diagnostics"), flush=True)
    report["complete"] = all(case["complete"] for case in report["cases"])
    filename.write_text(json.dumps(report, indent=2) + "\n")
    if not report["complete"]:
        raise SystemExit(1)


# ---- Tests ----

import tempfile
import unittest


class GeneratedFileTests(unittest.TestCase):
    def test_complete_snapshot_detects_corrupted_missing_and_extra_outputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            outputs = directory / "outputs"
            outputs.mkdir()
            first = outputs / "z0.tex"
            first.write_text("complete first fragment\n")
            second = outputs / "z1.tex"
            second.write_text("complete second fragment\n")
            original = generated_files(directory)
            self.assertEqual(set(original), {"outputs/z0.tex", "outputs/z1.tex"})
            self.assertEqual(generated_files(directory), original)
            second.write_text("complete second fragmenX\n")
            self.assertNotEqual(generated_files(directory), original)
            second.write_text("complete second fragment\n")
            second.unlink()
            self.assertNotEqual(generated_files(directory), original)
            second.write_text("complete second fragment\n")
            (outputs / "z2.tex").write_text("unexpected third fragment\n")
            self.assertNotEqual(generated_files(directory), original)

    def test_plain_tex_marker_is_observed_with_its_complete_contents(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "outputs").mkdir()
            (directory / "pltexchk.jnk").write_text("junk\n")
            snapshot = generated_files(directory)
            self.assertEqual(snapshot["pltexchk.jnk"], {"sha256": hashlib.sha256(b"junk\n").hexdigest(), "bytes": 5})


if __name__ == "__main__":
    main()

