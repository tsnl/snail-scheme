#!/usr/bin/env python3
"""Compile one unchanged optimized Wasm artifact with the recovered Immix path."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = Path(__file__).resolve().parent
CLANG = os.environ.get("CLANG", "/nix/store/mw4gasdvwgscgpxpzihjgchfhs3hhqhn-clang-wrapper-21.1.8/bin/clang")
LLD = os.environ.get("LLD", "/nix/store/5rhnyy8qnwnasmadd83bbrp1agylvwjs-lld-21.1.8/bin/ld.lld")
DIS = os.environ.get("WASM_DIS", "/nix/store/nd1279k2zlbp23gfqcl0qp5xk40xlxr8-binaryen-132/bin/wasm-dis")
CHIBI = os.environ.get("CHIBI", "chibi-scheme")


# ---- Runtime specification ----

def values_text(values):
    return str(len(values)) + "\n" + "".join(f"{int(value)} {float(value)!r}\n" for value in values)


def write_inputs(specification, output):
    spec = json.loads(Path(specification).read_text())
    arrays = [value if isinstance(value, list) else [value] for value in spec["inputs"]]
    expected = spec["expected"]
    checked = spec.get("result_kind") in ["i64-list-values", "f64-vector-values", "i64-vector-values"]
    text = (f'{spec["count"]} {1 if checked else expected} {spec["barriers_per_iteration"]} '
            f'{spec.get("setup_barriers", -1)} {len(arrays)} {spec.get("tolerance", 0)}\n')
    text += "".join(values_text(value) for value in arrays)
    text += values_text(expected if isinstance(expected, list) else [])
    Path(output).write_text(text)


# ---- Reproducible build commands and source identity ----

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def invoke(command, directory, records):
    result = subprocess.run([str(arg) for arg in command], cwd=ROOT, text=True, capture_output=True)
    records.append({"command": [str(arg) for arg in command], "exit": result.returncode,
                    "stdout": result.stdout, "stderr": result.stderr})
    (directory / "build.json").write_text(json.dumps(records, indent=2) + "\n")
    if result.returncode:
        raise RuntimeError(result.stderr)


def compile_native(directory, records):
    defines = ["-DSNAIL_NATIVE_LIBRARY", "-DSNAIL_PRECISE_GC", "-I", ROOT / "src"]
    # Separate native object preserves host opacity across guest/runtime LTO.
    invoke([CLANG, "-O3", "-fno-lto", *defines, "-c", SCRIPTS / "host.c", "-o", directory / "host.o"], directory, records)
    invoke([CLANG, "-O3", "-flto", f"-fuse-ld={LLD}", *defines,
            directory / "module.ll", ROOT / "src/native.c", ROOT / "src/precise-gc.c",
            directory / "host.o", "-lm", "-o", directory / "native"], directory, records)


def lower_wasm(wasm, specification, directory, records):
    shutil.copyfile(wasm, directory / "input.wasm")
    shutil.copyfile(specification, directory / "spec.json")
    write_inputs(specification, directory / "inputs.txt")
    invoke([DIS, directory / "input.wasm", "-o", directory / "input.wat"], directory, records)
    invoke([CHIBI, "-h512M", "-I", ROOT / "src", SCRIPTS / "translate.scm",
            directory / "input.wat", directory / "module.ll"], directory, records)


def tool_identity(executable, option):
    path = Path(shutil.which(executable)).resolve()
    version = subprocess.run([path, option], text=True, capture_output=True, check=True)
    return {"path": str(path), "sha256": digest(path), "version": version.stdout + version.stderr}


def record_manifest(wasm, specification, directory):
    files = [directory / name for name in ["input.wasm", "input.wat", "inputs.txt", "spec.json", "module.ll", "native", "host.o"]]
    files += [ROOT / name for name in ["src/native.c", "src/precise-gc.c", "src/precise-gc.h",
        "src/snail-scheme/llvm.sld", "src/snail-scheme/wasm-read.sld", "src/snail-scheme/wasm-resolve.sld", "src/snail-scheme/llvmlite.sld"]]
    files += [SCRIPTS / name for name in ["prepare.py", "host.c", "translate.scm", "node-host.mjs"]]
    manifest = {"source_wasm": str(Path(wasm).resolve()), "source_specification": str(Path(specification).resolve()),
        "sha256": {str(path): digest(path) for path in files},
        "collector": "nonmoving Immix with exact explicit roots, tuned allocation search, no evacuation",
        "archive_revision": "5c277ab", "collector_revision": "7f698687b9e7c6af4272a6a19c35ca9e1a9f9d11",
        "host_opacity": "host.c compiled separately with -fno-lto; inputs read at runtime",
        "tools": {"clang": tool_identity(CLANG, "--version"), "lld": tool_identity(LLD, "--version"),
                  "wasm_dis": tool_identity(DIS, "--version"), "chibi": tool_identity(CHIBI, "-V")},
        "build_environment": {name: os.environ.get(name) for name in ["PATH", "CPATH", "C_INCLUDE_PATH", "LIBRARY_PATH",
            "LD_LIBRARY_PATH", "NIX_CFLAGS_COMPILE", "NIX_LDFLAGS", "BINARYEN_CORES", "CHIBI", "CLANG", "LLD", "WASM_DIS"]}}
    assert digest(wasm) == digest(directory / "input.wasm")
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def prepare(wasm, specification, destination):
    directory = Path(destination).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    records = []
    lower_wasm(wasm, specification, directory, records)
    compile_native(directory, records)
    record_manifest(wasm, specification, directory)
    print(directory / "native")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--inputs":
        write_inputs(sys.argv[2], sys.argv[3])
    else:
        prepare(*sys.argv[1:])
