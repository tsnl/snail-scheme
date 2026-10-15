#!/usr/bin/env python3
"""Compile a strict Scheme cat loop and compare it with frozen scalar controls."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LABELS = ("control", "hand-loop", "strict-source")
OUTPUT_HASH = "2994b446dfb07d7cf324fb6aa32d519b3f0bd53a582268714adf08df5f45b8d3"
FROZEN_MANIFEST = ROOT / "benchmarks/results/2026-10-13-cat-scalar-extern/manifest.json"


# ---- Frozen identities and recorded build commands ----


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


def run_build(command, directory, environment, records):
    run = subprocess.run(list(map(str, command)), cwd=ROOT, env=environment,
                         capture_output=True, text=True, timeout=900)
    records.append(dict(command=list(map(str, command)), returncode=run.returncode,
                        stdout=run.stdout, stderr=run.stderr))
    save(directory / "build.json", records)
    if run.returncode:
        raise RuntimeError(run.stderr)
    return run.stdout


def checked_tools(identity):
    tools = identity["actual_link_tools"]
    for name, record in tools.items():
        if digest(record["path"]) != record["sha256"]:
            raise ValueError(f"recorded tool changed: {name}")
    return {name: record["path"] for name, record in tools.items()}


def removed_exports(frozen, tools, output, environment, records):
    code = ("const fs=require('node:fs');const names=p=>WebAssembly.Module.exports("
            "new WebAssembly.Module(fs.readFileSync(p))).map(x=>x.name);"
            "const [a,b]=process.argv.slice(1).map(names);"
            "console.log(JSON.stringify(a.filter(x=>!b.includes(x))));")
    text = run_build([tools["NODE"], "-e", code, frozen / "control/linked.wasm",
                      frozen / "control/program.wasm"], output, environment, records)
    return json.loads(text)


def compiler_files(compiler):
    return [*sorted(compiler.glob("src/**/*.sld")), compiler / "scripts/build-strict",
            compiler / "tests/build-strict-program.scm"]


def compiler_snapshot(compiler, output):
    files = compiler_files(compiler)
    for source in files:
        copied(source, output / "compiler-source" / source.relative_to(compiler))
    return {str(path.relative_to(compiler)): digest(output / "compiler-source" / path.relative_to(compiler))
            for path in files}


def verify_control(frozen):
    manifest = load(FROZEN_MANIFEST)["files"]
    consumed = ("control/program.wat", "control/program.wasm", "control/linked.wasm",
                "control/program.scm", "control/input.txt", "control/inputs/bib",
                "control/platform.wasm", "runtime.wasm", "identity.json", "sources/tests/typed-extern/cat-loop.wat",
                "validation/check-scalar-io.mjs", "sources/tests/typed-extern/wrong-signature.wat")
    for relative in consumed:
        if digest(frozen / relative) != manifest["typed-extern-cat/" + relative]:
            raise ValueError(f"frozen artifact changed: {relative}")
    prefix = "typed-extern-cat/host/"
    host_hashes = {name[len(prefix):]: sha for name, sha in manifest.items() if name.startswith(prefix)}
    for relative, expected in host_hashes.items():
        if digest(frozen / "host" / relative) != expected:
            raise ValueError(f"frozen host changed: {relative}")
    return host_hashes


# ---- Matching legacy adapters and native Scheme worker ----


def replace_function(module, replacement):
    pattern = re.compile(r"^\(func \$function171 .*\)$", re.M)
    result, count = pattern.subn(lambda unused: replacement.rstrip(), module)
    if count != 1:
        raise ValueError(f"expected one frozen catport function, found {count}")
    return result


def hand_adapter(frozen):
    source = (frozen / "sources/tests/typed-extern/cat-loop.wat").read_text()
    source = source.replace("(call $prototype_port_id (local.get $a1))", "(call $probe:output-id)")
    source = source.replace("  (local.set $input-id", "  (global.set $probe:output (local.get $a1))\n  (local.set $input-id")
    return source.replace("  (call $abi_release (local.get $output-root))",
                          "  (global.set $probe:output (ref.null eq))\n  (call $abi_release (local.get $output-root))")


def variant_wat(frozen, label):
    module = (frozen / "control/program.wat").read_text()
    declaration = '(import "snail.strict-cat" "copy-code" (func $strict:copy-code (param i32)))'
    module = module.replace("(module\n", "(module\n" + declaration + "\n", 1)
    module = module.rstrip()[:-1] + (HERE / "bridge.wat").read_text() + "\n)\n"
    if label == "hand-loop":
        return replace_function(module, hand_adapter(frozen))
    if label == "strict-source":
        return replace_function(module, (HERE / "adapter.wat").read_text())
    return module


def link_variant(directory, output, tools, flags, removed, environment, records):
    feature_flags = flags[:flags.index("-O3")]
    optimize_flags = flags[flags.index("-O3"):]
    run_build([tools["WASM_AS"], *feature_flags, directory / "program.wat", "-o",
               directory / "scheme.wasm"], output, environment, records)
    run_build([tools["WASM_OPT"], *flags, directory / "scheme.wasm", "-o",
               directory / "scheme.optimized.wasm"], output, environment, records)
    run_build([tools["WASM_MERGE"], *feature_flags,
               directory / "scheme.optimized.wasm", "snail.abi",
               output / "runtime.wasm", "snail.library", output / "platform.wasm", "snail.platform",
               output / "entry.wasm", "snail.entry", output / "strict.wasm", "snail.strict-cat",
               "-o", directory / "linked.wasm"], output, environment, records)
    run_build([tools["WASM_OPT"], *feature_flags, "--remove-exports",
               "--pass-arg=remove-exports@" + ",".join(removed), *optimize_flags,
               directory / "linked.wasm", "-o", directory / "program.wasm"], output, environment, records)


def prepare_variant(label, options, identity, tools, environment, removed, records):
    directory = options.output / label
    directory.mkdir()
    (directory / "program.wat").write_text(variant_wat(options.frozen, label))
    for relative in ("program.scm", "input.txt", "inputs/bib"):
        copied(options.frozen / "control" / relative, directory / relative)
    (directory / "outputs").mkdir()
    if digest(directory / "inputs/bib") != OUTPUT_HASH:
        raise ValueError("benchmark input changed")
    link_variant(directory, options.output, tools, identity["link_flags"]["scheme"],
                 removed, environment, records)
    case = dict(label=label, directory=str(directory),
                artifact_sha256=digest(directory / "program.wasm"),
                input_sha256=digest(directory / "input.txt"),
                source_sha256=digest(directory / "program.scm"),
                command=[tools["NODE"], "--no-warnings", str(options.output / "host/scripts/run-wasi.mjs"),
                         str(directory / "program.wasm")])
    save(directory / "prepared.json", case)
    print("Prepared", label, case["artifact_sha256"], flush=True)


def prepare(options):
    identity = load(options.frozen / "identity.json")
    host_hashes = verify_control(options.frozen)
    tools = checked_tools(identity)
    environment = {**os.environ, **tools, "BINARYEN_CORES": "1"}
    options.output.mkdir(parents=True, exist_ok=False)
    records = []
    if digest(options.frozen / "runtime.wasm") != identity["runtime_sha256"]:
        raise ValueError("frozen provider changed")
    copied(options.frozen / "runtime.wasm", options.output / "runtime.wasm")
    copied(options.frozen / "control/platform.wasm", options.output / "platform.wasm")
    shutil.copytree(options.frozen / "host", options.output / "host")
    for source in HERE.iterdir():
        if source.is_file():
            copied(source, options.output / "experiment-source" / source.name)
    copied(options.frozen / "validation/check-scalar-io.mjs", options.output / "original-check.mjs")
    copied(options.frozen / "sources/tests/typed-extern/wrong-signature.wat", options.output / "wrong-signature.wat")
    copied(HERE / "entry.wat", options.output / "entry.wat")
    flags = identity["link_flags"]["scheme"]
    run_build([tools["WASM_AS"], *flags[:flags.index("-O3")], options.output / "entry.wat",
               "-o", options.output / "entry.wasm"], options.output, environment, records)
    sources = compiler_snapshot(options.compiler, options.output)
    run_build([options.compiler / "scripts/build-strict", "--export", "copy-code", HERE / "copy.scm",
               options.output / "strict.wasm"], options.output, environment, records)
    after = {str(path.relative_to(options.compiler)): digest(path) for path in compiler_files(options.compiler)}
    if after != sources:
        raise ValueError("compiler changed during preparation")
    removed = removed_exports(options.frozen, tools, options.output, environment, records)
    save(options.output / "identity.json", dict(date=datetime.now(timezone.utc).isoformat(),
         actual_link_tools=identity["actual_link_tools"], compiler_sources=sources, removed_exports=removed,
         frozen_manifest_sha256=digest(FROZEN_MANIFEST), frozen_identity=identity,
         runtime_sha256=identity["runtime_sha256"], source_sha256=digest(HERE / "copy.scm"),
         driver_sha256=digest(__file__), scheme_flags=flags,
         host_sha256=host_hashes, build_environment={**tools, "BINARYEN_CORES": "1"},
         strict_sha256=digest(options.output / "strict.wasm")))
    for label in LABELS:
        prepare_variant(label, options, identity, tools, environment, removed, records)


# ---- Linked behavior outside the timing batch ----


def validation_script(output):
    script = (output / "original-check.mjs").read_text()
    # Use the frozen host's port cleanup contract, matching its timing loader.
    script = script.replace("createIdentityHasher, dropResource", "createIdentityHasher")
    script = script.replace("dropResource(instance.exports, kind, id)", "instance.exports['ports/drop-resource'](kind, id)")
    script = script.replace("abi['test/initialize']();", "abi['test/initialize']();\nabi.main();")
    # Both errors terminate this process. They never resume with borrowed IDs.
    extra = """
if (mode === 'cat-closed-input' || mode === 'cat-closed-output') {
  const input = openInput('A'), output = portCall('ports/open-output-string', []);
  scalar('close', mode === 'cat-closed-input' ? input : output);
  try { abi['test/catport'](input, output); }
  catch (error) {
    if (error instanceof Error) throw error;
    process.exit(1);
  }
  throw new Error('fatal cat error returned');
}
"""
    return script + extra


def validate(options):
    identity = load(options.output / "identity.json")
    tools = checked_tools(identity)
    directory = options.output / "validation"
    directory.mkdir(exist_ok=False)
    copied(__file__, directory / "measure.py")
    script = options.output / "host/tests/typed-extern/check.mjs"
    script.parent.mkdir(parents=True, exist_ok=True)
    script.write_text(validation_script(options.output))
    records = []
    flags = identity["scheme_flags"]
    feature_flags = flags[:flags.index("-O3")]
    wrong = directory / "wrong-signature.wasm"
    run_build([tools["WASM_AS"], options.output / "wrong-signature.wat", "-o", wrong],
              directory, os.environ, records)
    report = dict(complete=False, artifacts={}, checks=[], script_sha256=digest(script),
                  driver_sha256=digest(__file__))
    try:
        for label in ("hand-loop", "strict-source"):
            source = options.output / label / "program.wasm"
            report["artifacts"][label] = digest(source)
            probe = directory / (label + ".wasm")
            run_build([tools["WASM_OPT"], *feature_flags, "--remove-exports",
                       "--pass-arg=remove-exports@_start", source, "-o", probe],
                      directory, os.environ, records)
            for mode in ("success", "closed", "cat-closed-input", "cat-closed-output"):
                command = [tools["NODE"], "--no-warnings", "--expose-gc", str(script), str(probe), mode, str(wrong)]
                run = subprocess.run(command, cwd=directory, capture_output=True, text=True, timeout=120)
                row = dict(label=label, mode=mode, command=command, returncode=run.returncode,
                           stdout=run.stdout, stderr=run.stderr)
                report["checks"].append(row)
                expected = (0, "Native scalar I/O checks passed\n", "") if mode == "success" else (1, "", "snail-scheme: port is closed\n")
                if (run.returncode, run.stdout, run.stderr) != expected:
                    raise RuntimeError(f"linked functional check failed: {row}")
        report["complete"] = True
    finally:
        save(directory / "results.json", report)
    print("Linked scalar loops passed Unicode, EOF, fatal errors, and owner checks", flush=True)


# ---- Clean timing and complete output validation ----


def sample(case, round_number):
    directory = Path(case["directory"])
    for filename, key in (("program.wasm", "artifact_sha256"), ("input.txt", "input_sha256"),
                          ("program.scm", "source_sha256")):
        if digest(directory / filename) != case[key]:
            raise ValueError(f"prepared artifact changed: {filename}")
    if digest(directory / "inputs/bib") != OUTPUT_HASH:
        raise ValueError("benchmark input changed")
    output = directory / "outputs/cat.output"
    output.unlink(missing_ok=True)
    start = time.monotonic()
    result = dict(label=case["label"], round=round_number, returncode=None, status="invalid")
    try:
        run = subprocess.run(case["command"], cwd=directory, input=(directory / "input.txt").read_bytes(),
                             capture_output=True, timeout=180)
        result.update(returncode=run.returncode, stdout=run.stdout.decode(errors="replace"),
                      stderr=run.stderr.decode(errors="replace"))
    except subprocess.TimeoutExpired as failure:
        result.update(stdout=(failure.stdout or b"").decode(errors="replace"),
                      stderr=(failure.stderr or b"").decode(errors="replace"), error="timeout")
    except OSError as failure:
        result.update(stdout="", stderr=str(failure), error="process launch failed")
    result["process_seconds"] = time.monotonic() - start
    if output.is_file():
        result.update(output_bytes=output.stat().st_size, output_sha256=digest(output))
    times = re.findall(r"^\+!CSVLINE!\+[^,]+,cat:50,([0-9.eE+-]+)$", result["stdout"], re.M)
    if (result["returncode"] == 0 and not result["stderr"] and len(times) == 1
            and math.isfinite(float(times[0])) and float(times[0]) > 0
            and result.get("output_bytes") == 4460056 and result.get("output_sha256") == OUTPUT_HASH):
        result.update(status="ok", seconds=float(times[0]))
    return result


def measure(options):
    if os.environ.get("NODE_OPTIONS"):
        raise ValueError("NODE_OPTIONS must be unset for clean timings")
    identity = load(options.output / "identity.json")
    checked_tools(identity)
    validation = load(options.output / "validation/results.json")
    if not validation["complete"]:
        raise ValueError("linked functional validation has not passed")
    for label, expected in validation["artifacts"].items():
        if digest(options.output / label / "program.wasm") != expected:
            raise ValueError(f"validated artifact changed: {label}")
    for relative, expected in identity["host_sha256"].items():
        if digest(options.output / "host" / relative) != expected:
            raise ValueError(f"prepared host changed: {relative}")
    destination = options.output / "clean"
    destination.mkdir(exist_ok=False)
    copied(__file__, destination / "measure.py")
    cases = [load(options.output / label / "prepared.json") for label in LABELS]
    report = dict(date=datetime.now(timezone.utc).isoformat(), cpu=options.cpu,
                  rounds=options.rounds, cases=cases, identity=identity, observations=[], complete=False,
                  driver_sha256=digest(__file__))
    affinity = os.sched_getaffinity(0)
    os.sched_setaffinity(0, {options.cpu})
    try:
        for index in range(options.rounds + 1):
            offset = index % len(cases)
            for case in cases[offset:] + cases[:offset]:
                result = sample(case, index)
                report["observations"].append(result)
                save(destination / "results.json", report)
                print(case["label"], index, result.get("seconds", result["status"]), flush=True)
                if result["status"] != "ok":
                    raise RuntimeError("invalid cat run; observation preserved")
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
    parser.add_argument("--output", type=Path, default=ROOT / "build/strict-cat")
    parser.add_argument("--frozen", type=Path)
    parser.add_argument("--compiler", type=Path)
    parser.add_argument("--cpu", type=int, default=5)
    parser.add_argument("--rounds", type=int, default=3)
    options = parser.parse_args()
    if options.command == "prepare" and (not options.frozen or not options.compiler):
        parser.error("prepare requires --frozen and --compiler")
    for field in ("output", "frozen", "compiler"):
        if value := getattr(options, field):
            setattr(options, field, value.resolve())
    {"prepare": prepare, "validate": validate, "measure": measure}[options.command](options)


if __name__ == "__main__":
    main()
