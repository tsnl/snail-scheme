#!/usr/bin/env python3
"""Compile and measure strict wc against matched legacy code and frozen Chez."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import statistics
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LABELS = ("control", "strict-source", "chez")
CORPUS_HASH = "2994b446dfb07d7cf324fb6aa32d519b3f0bd53a582268714adf08df5f45b8d3"
PROVIDER_MANIFEST = ROOT / "benchmarks/results/2026-10-13-cat-scalar-extern/manifest.json"
CHEZ_MANIFEST = ROOT / "benchmarks/results/2026-10-13-wasm-five-reference/manifest.json"
INITIALIZER_INPUT = b'0\n"unused"\n#f\n'


# ---- Frozen inputs and recorded commands ----


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + "\n")


def copied(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    if digest(source) != digest(destination):
        raise ValueError(f"copied artifact differs: {destination}")


def checked_tools(identity):
    records = identity["actual_link_tools"]
    for name, record in records.items():
        if digest(record["path"]) != record["sha256"]:
            raise ValueError(f"recorded tool changed: {name}")
    return {name: record["path"] for name, record in records.items()}


def run_build(command, output, environment, records):
    run = subprocess.run(list(map(str, command)), cwd=ROOT, env=environment,
                         capture_output=True, text=True, timeout=900)
    records.append(dict(command=list(map(str, command)), returncode=run.returncode,
                        stdout=run.stdout, stderr=run.stderr))
    save(output / "build.json", records)
    if run.returncode:
        raise RuntimeError(run.stderr)
    return run.stdout


def freeze_provider(options):
    manifest = load(PROVIDER_MANIFEST)["files"]
    prefix = "typed-extern-cat/"
    consumed = ("runtime.wasm", "identity.json", "imports.wat")
    for name, expected in manifest.items():
        relative = name.removeprefix(prefix)
        if relative in consumed or relative.startswith(("host/", "sources/")):
            source = options.frozen / relative
            if digest(source) != expected:
                raise ValueError(f"frozen provider changed: {relative}")
            copied(source, options.output / "provider" / relative)
            if relative.startswith("host/") or relative == "runtime.wasm":
                copied(source, options.output / relative)
    return load(options.output / "provider/identity.json")


def freeze_legacy(options):
    report = load(options.legacy / "results.json")
    case = next(row for row in report["cases"] if row["benchmark"] == "wc" and row["system"] == "snail-wasm")
    for relative, expected in case["artifact_sha256"].items():
        source = options.legacy / "cases/wc/snail-wasm" / relative
        if digest(source) != expected:
            raise ValueError(f"frozen legacy wc changed: {relative}")
        copied(source, options.output / "legacy/cases/wc/snail-wasm" / relative)
    source = options.legacy / "cases/wc/snail-wasm/input.txt"
    if digest(source) != case["input_sha256"]:
        raise ValueError("original wc parameters changed")
    copied(source, options.output / "legacy/cases/wc/snail-wasm/input.txt")
    copied(options.legacy / "results.json", options.output / "legacy/results.json")
    copied(options.legacy / "inputs/bib", options.output / "legacy/inputs/bib")
    copied(options.legacy / "inputs/bib", options.output / "inputs/bib")
    if digest(options.output / "inputs/bib") != CORPUS_HASH:
        raise ValueError("original corpus changed")
    return report["upstream_revision"]


def freeze_chez(options):
    directory = options.output / "chez"
    directory.mkdir()
    for entry in load(CHEZ_MANIFEST)["entries"]:
        if entry["path"].startswith("cases/wc/chez/") and entry["kind"] == "file":
            name = Path(entry["path"]).name
            if name == "upstream.scm":
                continue
            source = options.chez / name
            if digest(source) != entry["sha256"]:
                raise ValueError(f"frozen Chez wc changed: {name}")
            copied(source, directory / name)


def compiler_snapshot(compiler, output):
    files = [*sorted(compiler.glob("src/**/*.sld")), compiler / "scripts/build-strict",
             compiler / "tests/build-strict-program.scm"]
    for source in files:
        copied(source, output / "compiler-source" / source.relative_to(compiler))
    return {str(path.relative_to(compiler)): digest(path) for path in files}


# ---- Matched legacy scaffolding and native source ----


def variant_wat(output, label):
    module = (output / "legacy/cases/wc/snail-wasm/capture-program.wat").read_text()
    imports = (output / "provider/imports.wat").read_text().strip()[len("(module"): -1]
    imports += '\n(import "snail.strict-wc" "count-code" (func $strict:count-code (param i32)))\n'
    module = module.replace("(module\n", "(module\n" + imports, 1)
    module = module.rstrip()[:-1] + (HERE / "bridge.wat").read_text() + "\n)\n"
    if label == "strict-source":
        module, count = re.subn(r"^\(func \$function171 .*\)$", lambda unused: (HERE / "adapter.wat").read_text().rstrip(),
                               module, flags=re.M)
        if count != 1:
            raise ValueError(f"expected one frozen wcport function, found {count}")
    return module


def removed_exports(output, tools, environment, records):
    code = ("const fs=require('node:fs');const names=p=>WebAssembly.Module.exports("
            "new WebAssembly.Module(fs.readFileSync(p))).map(x=>x.name);"
            "const [a,b]=process.argv.slice(1).map(names);"
            "console.log(JSON.stringify(a.filter(x=>!b.includes(x))));")
    legacy = output / "legacy/cases/wc/snail-wasm"
    result = run_build([tools["NODE"], "-e", code, legacy / "capture-linked.wasm",
                        legacy / "program.wasm"], output, environment, records)
    return json.loads(result)


def link_variant(directory, output, tools, flags, removed, environment, records):
    feature = flags[:flags.index("-O3")]
    optimize = flags[flags.index("-O3"):]
    run_build([tools["WASM_AS"], *feature, directory / "program.wat", "-o", directory / "scheme.wasm"],
              output, environment, records)
    run_build([tools["WASM_OPT"], *flags, directory / "scheme.wasm", "-o", directory / "scheme.optimized.wasm"],
              output, environment, records)
    run_build([tools["WASM_MERGE"], *feature, directory / "scheme.optimized.wasm", "snail.abi",
               output / "runtime.wasm", "snail.library", output / "platform.wasm", "snail.platform",
               output / "entry.wasm", "snail.entry", output / "strict.wasm", "snail.strict-wc",
               "-o", directory / "linked.wasm"], output, environment, records)
    run_build([tools["WASM_OPT"], *feature, "--remove-exports", "--pass-arg=remove-exports@" + ",".join(removed),
               *optimize, directory / "linked.wasm", "-o", directory / "program.wasm"], output, environment, records)


def prepare_cases(options, identity, tools, environment, records):
    removed = removed_exports(options.output, tools, environment, records)
    for label in LABELS:
        directory = options.output / label
        directory.mkdir(exist_ok=True)
        copied(options.output / "inputs/bib", directory / "inputs/bib")
        if label != "chez":
            (directory / "program.wat").write_text(variant_wat(options.output, label))
            for name in ("program.scm", "input.txt"):
                copied(options.output / "legacy/cases/wc/snail-wasm" / name, directory / name)
            link_variant(directory, options.output, tools, identity["scheme_flags"], removed, environment, records)
        save(directory / "prepared.json", prepared_case(directory, label, tools, options.output))
        print("Prepared", label, flush=True)
    identity["removed_exports"] = removed


def prepared_case(directory, label, tools, output):
    artifact = "program.so" if label == "chez" else "program.wasm"
    command = [tools["CHEZ"], "--program", str(directory / artifact)] if label == "chez" else [
        tools["NODE"], "--no-warnings", str(output / "host/scripts/run-wasi.mjs"), str(directory / artifact)]
    files = (artifact, "program.scm", "input.txt", "inputs/bib")
    return dict(label=label, directory=str(directory), command=command,
                files={name: digest(directory / name) for name in files})


def compile_worker(options, identity, tools, environment, records):
    copied(HERE / "entry.wat", options.output / "entry.wat")
    feature = identity["scheme_flags"][:identity["scheme_flags"].index("-O3")]
    run_build([tools["WASM_AS"], *feature, options.output / "entry.wat", "-o", options.output / "entry.wasm"],
              options.output, environment, records)
    sources = compiler_snapshot(options.compiler, options.output)
    identity["compiler_revision"] = run_build(["git", "-C", options.compiler, "rev-parse", "HEAD"],
                                              options.output, environment, records).strip()
    run_build([options.compiler / "scripts/build-strict", "--export", "count-code", HERE / "count.scm",
               options.output / "strict.wasm"], options.output, environment, records)
    if any(digest(options.compiler / name) != expected for name, expected in sources.items()):
        raise ValueError("compiler changed during preparation")
    identity.update(compiler_sources=sources, strict_sha256=digest(options.output / "strict.wasm"))


def archive_execution_sources(output):
    copied(output / "legacy/cases/wc/snail-wasm/capture-platform.wasm", output / "platform.wasm")
    for source in HERE.iterdir():
        if source.is_file():
            copied(source, output / "experiment-source" / source.name)
    copied(HERE / "check.mjs", output / "host/tests/strict-wc/check.mjs")
    copied(output / "provider/sources/tests/typed-extern/wrong-signature.wat", output / "wrong-signature.wat")


def prepare(options):
    options.output.mkdir(parents=True, exist_ok=False)
    provider = freeze_provider(options)
    upstream = freeze_legacy(options)
    freeze_chez(options)
    identity = dict(date=datetime.now(timezone.utc).isoformat(), upstream_revision=upstream,
                    actual_link_tools={**provider["actual_link_tools"], "CHEZ": provider["tools"]["CHEZ"]},
                    frozen_provider_identity=provider, scheme_flags=provider["link_flags"]["scheme"],
                    driver_sha256=digest(__file__), source_sha256=digest(HERE / "count.scm"),
                    provider_manifest_sha256=digest(PROVIDER_MANIFEST), chez_manifest_sha256=digest(CHEZ_MANIFEST))
    tools = checked_tools(identity)
    environment = {**os.environ, **tools, "BINARYEN_CORES": "1"}
    identity["build_environment"] = {**tools, "BINARYEN_CORES": "1"}
    archive_execution_sources(options.output)
    records = []
    compile_worker(options, identity, tools, environment, records)
    prepare_cases(options, identity, tools, environment, records)
    identity["host_sha256"] = {str(path.relative_to(options.output / "host")): digest(path)
                               for path in sorted((options.output / "host").rglob("*")) if path.is_file()}
    save(options.output / "identity.json", identity)


# ---- Linked behavior outside clean timing ----


def check_case(case):
    for relative, expected in case["files"].items():
        if digest(Path(case["directory"]) / relative) != expected:
            raise ValueError(f"prepared artifact changed: {case['label']}/{relative}")


def functional_run(command, directory, input_bytes):
    run = subprocess.run(command, cwd=directory, input=input_bytes, capture_output=True, timeout=120)
    return dict(command=list(map(str, command)), directory=str(directory), returncode=run.returncode,
                stdout=run.stdout.decode(errors="replace"), stderr=run.stderr.decode(errors="replace"))


def successful_check(row, mode):
    if mode == "success":
        return row["returncode"] == 0 and not row["stderr"] and row["stdout"].endswith(
            "WC scalar checks passed: (31102 851820 4460056)\n")
    diagnostic = {"closed": "port is closed", "wrong-direction": "expected an input port",
                  "invalid": "invalid UTF-8", "truncated": "failed to fill whole buffer"}[mode]
    return row["returncode"] == 1 and row["stderr"] == "snail-scheme: " + diagnostic + "\n"


def validate_variant(output, label, tools, wrong, checks):
    case = load(output / label / "prepared.json")
    check_case(case)
    for mode in ("success", "closed", "wrong-direction", "invalid", "truncated"):
        working = output / "validation" / label / mode
        working.mkdir(parents=True)
        command = [tools["NODE"], "--no-warnings", "--expose-gc", str(output / "host/tests/strict-wc/check.mjs"),
                   str(output / label / "program.wasm"), mode, str(output / "inputs/bib"), str(wrong)]
        row = {**functional_run(command, working, INITIALIZER_INPUT), "label": label, "mode": mode}
        checks.append(row)
        if not successful_check(row, mode):
            raise RuntimeError(f"linked functional check failed: {row}")
    return case["files"]["program.wasm"]


def validate_chez(output, checks):
    case = load(output / "chez/prepared.json")
    check_case(case)
    row = {**functional_run(case["command"], Path(case["directory"]), b'1\n"inputs/bib"\n(31102 851820 4460056)\n'),
           "label": "chez", "mode": "original-predicate"}
    checks.append(row)
    if row["returncode"] or row["stderr"] or not re.search(r"^\+!CSVLINE!\+[^,]+,wc:inputs/bib:1,[0-9.eE+-]+$", row["stdout"], re.M):
        raise RuntimeError("Chez original predicate failed")
    return case["files"]["program.so"]


def validate(options):
    identity = load(options.output / "identity.json")
    tools = checked_tools(identity)
    directory = options.output / "validation"
    directory.mkdir(exist_ok=False)
    copied(__file__, directory / "measure.py")
    records, checks = [], []
    wrong = directory / "wrong-signature.wasm"
    run_build([tools["WASM_AS"], options.output / "wrong-signature.wat", "-o", wrong], directory, os.environ, records)
    report = dict(complete=False, checks=checks, artifacts={}, driver_sha256=digest(__file__))
    try:
        for label in ("control", "strict-source"):
            report["artifacts"][label] = validate_variant(options.output, label, tools, wrong, checks)
        report["artifacts"]["chez"] = validate_chez(options.output, checks)
        report["complete"] = True
    finally:
        save(directory / "results.json", report)
    print("Linked wc checks passed Unicode, delimiters, EOF, fatal errors, and roots", flush=True)


# ---- Fresh processes and original workload checks ----


def sample(case, round_number):
    check_case(case)
    directory = Path(case["directory"])
    start = time.monotonic()
    row = dict(label=case["label"], round=round_number, status="invalid")
    try:
        row.update(functional_run(case["command"], directory, (directory / "input.txt").read_bytes()))
    except subprocess.TimeoutExpired as failure:
        row.update(returncode=None, stdout=(failure.stdout or b"").decode(errors="replace"),
                   stderr=(failure.stderr or b"").decode(errors="replace"), error="timeout")
    except OSError as failure:
        row.update(returncode=None, stdout="", stderr=str(failure), error="process launch failed")
    row["process_seconds"] = time.monotonic() - start
    times = re.findall(r"^\+!CSVLINE!\+[^,]+,wc:inputs/bib:50,([0-9.eE+-]+)$", row["stdout"], re.M)
    if (row["returncode"] == 0 and not row["stderr"] and len(times) == 1
            and math.isfinite(float(times[0])) and float(times[0]) > 0):
        row.update(status="ok", seconds=float(times[0]), original_predicate=True, expected=[31102, 851820, 4460056])
    return row


def checked_preparation(output):
    identity = load(output / "identity.json")
    checked_tools(identity)
    if digest(__file__) != identity["driver_sha256"]:
        raise ValueError("driver changed since preparation")
    validation = load(output / "validation/results.json")
    if not validation["complete"]:
        raise ValueError("linked functional validation has not passed")
    for label, expected in validation["artifacts"].items():
        artifact = "program.so" if label == "chez" else "program.wasm"
        if digest(output / label / artifact) != expected:
            raise ValueError(f"validated artifact changed: {label}")
    for relative, expected in identity["host_sha256"].items():
        if digest(output / "host" / relative) != expected:
            raise ValueError(f"prepared host changed: {relative}")
    return identity


def measure(options):
    if os.environ.get("NODE_OPTIONS"):
        raise ValueError("NODE_OPTIONS must be unset for clean timings")
    identity = checked_preparation(options.output)
    destination = options.output / "clean"
    destination.mkdir(exist_ok=False)
    copied(__file__, destination / "measure.py")
    cases = [load(options.output / label / "prepared.json") for label in LABELS]
    report = dict(date=datetime.now(timezone.utc).isoformat(), cpu=options.cpu, rounds=options.rounds,
                  platform=platform.platform(), cpu_info=Path("/proc/cpuinfo").read_text().split("\n\n")[0],
                  cases=cases, identity=identity, observations=[], complete=False, driver_sha256=digest(__file__))
    affinity = os.sched_getaffinity(0)
    os.sched_setaffinity(0, {options.cpu})
    try:
        for number in range(options.rounds + 1):
            offset = number % len(cases)
            for case in cases[offset:] + cases[:offset]:
                row = sample(case, number)
                report["observations"].append(row)
                save(destination / "results.json", report)
                print(case["label"], number, row.get("seconds", row["status"]), flush=True)
                if row["status"] != "ok":
                    raise RuntimeError("invalid wc run; observation preserved")
    finally:
        os.sched_setaffinity(0, affinity)
    report["summary"] = {label: statistics.median(row["seconds"] for row in report["observations"]
                                                if row["label"] == label and row["round"])
                         for label in LABELS}
    report["complete"] = True
    save(destination / "results.json", report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "validate", "measure"))
    parser.add_argument("--output", type=Path, default=ROOT / "build/strict-wc")
    parser.add_argument("--compiler", type=Path, default=ROOT)
    parser.add_argument("--frozen", type=Path)
    parser.add_argument("--legacy", type=Path)
    parser.add_argument("--chez", type=Path)
    parser.add_argument("--cpu", type=int, default=5)
    parser.add_argument("--rounds", type=int, default=3)
    options = parser.parse_args()
    if options.command == "prepare" and not all((options.frozen, options.legacy, options.chez)):
        parser.error("prepare requires --frozen, --legacy, and --chez")
    if options.rounds < 1:
        parser.error("rounds must be positive")
    for field in ("output", "compiler", "frozen", "legacy", "chez"):
        if value := getattr(options, field):
            setattr(options, field, value.resolve())
    {"prepare": prepare, "validate": validate, "measure": measure}[options.command](options)


if __name__ == "__main__":
    main()
