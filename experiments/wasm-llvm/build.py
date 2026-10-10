#!/usr/bin/env python3
"""Translate actual Wasm binaries, link BDWGC, and check optimized native code."""

import hashlib
import json
import os
import resource
import shutil
import signal
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "experiments/wasm-llvm"
OUT = ROOT / "build/wasm-llvm"
CLANG = os.environ.get("CLANG", "clang")
OPT = os.environ.get("OPT", "opt")
WASM_AS = os.environ.get(
    "WASM_AS",
    shutil.which("wasm-as")
    or "/nix/store/nd1279k2zlbp23gfqcl0qp5xk40xlxr8-binaryen-132/bin/wasm-as",
)
INCLUDE = os.environ.get(
    "BDWGC_INCLUDE",
    "/nix/store/nw0fc624zk4fjqwaws8kyv23d7q5dr2i-boehm-gc-8.2.12-dev/include",
)
LIBRARY = os.environ.get(
    "BDWGC_LIB", "/nix/store/fhmdw5g0b3d1ahcdi0vl5wxcf5f6ylf8-boehm-gc-8.2.12/lib"
)
GC_LINK = ["-L" + LIBRARY, "-Wl,-rpath," + LIBRARY, "-lgc"]
COMMANDS = []


def run(command):
    COMMANDS.append([str(value) for value in command])
    subprocess.run(COMMANDS[-1], cwd=ROOT, check=True)


def translate(name, source):
    output = OUT / f"{name}.ll"
    run(["python3", SOURCE / "translate.py", source, output])
    run([OPT, "-passes=verify", "-disable-output", output])
    return output


def assemble(name):
    output = OUT / f"{name}.wasm"
    run(
        [
            WASM_AS,
            SOURCE / f"{name}.wat",
            "--mvp-features",
            "--enable-gc",
            "--enable-reference-types",
            "--enable-tail-call",
            "--enable-mutable-globals",
            "-g",
            "-o",
            output,
        ]
    )
    return output


def executable(name, llvm, runner):
    object_file = OUT / f"{name}.o"
    run(
        [
            CLANG,
            "-Wno-unused-command-line-argument",
            "-O3",
            "-c",
            llvm,
            "-o",
            object_file,
        ]
    )
    run([CLANG, object_file, runner, *GC_LINK, "-o", OUT / name])


def compile_runner(name):
    output = OUT / f"{name}-c.o"
    run(
        [
            CLANG,
            "-O3",
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-I" + INCLUDE,
            "-c",
            SOURCE / f"{name}.c",
            "-o",
            output,
        ]
    )
    return output


def check_store_order():
    command = [str(OUT / "semantics"), "--trap"]
    COMMANDS.append(command)
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode == -signal.SIGILL, result
    assert result.stdout == "RHS evaluated\n", result
    print("Native Wasm semantics: equivalent types, i31 bounds, store order passed")


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    runner = compile_runner("runner")
    executable("cpu", translate("cpu", ROOT / "build/wasmgc/cpu.wasm"), runner)
    check = translate("check", ROOT / "build/wasmgc/check.wasm")
    run(
        [
            CLANG,
            "-Wno-unused-command-line-argument",
            "-O3",
            "-shared",
            "-fPIC",
            check,
            *GC_LINK,
            "-o",
            OUT / "check.so",
        ]
    )
    executable("gc-test", translate("gc-test", assemble("gc-test")), runner)
    executable(
        "semantics",
        translate("semantics", assemble("semantics")),
        compile_runner("semantics"),
    )


def checks():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    run(["python3", SOURCE / "check.py", OUT / "check.so"])
    run([OUT / "gc-test", "--gc-test"])
    run([OUT / "semantics"])
    check_store_order()


def record():
    inputs = [ROOT / "build/wasmgc" / f"{name}.wasm" for name in ("cpu", "check")]
    inputs += [OUT / f"{name}.wasm" for name in ("gc-test", "semantics")]
    report = {
        "commands": COMMANDS,
        "input_sha256": {
            str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in inputs
        },
        "target": "x86_64-unknown-linux-gnu",
    }
    (OUT / "build-commands.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    build()
    checks()
    record()
