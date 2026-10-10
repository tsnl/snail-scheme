#!/usr/bin/env python3
"""Build actual Wasm workers, lower to LLVM, and test native stack switching."""

import os
import subprocess
from pathlib import Path

# ---- Tools and outputs ----

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "experiments/wasm-stack-switching"
OUT = ROOT / "build/wasm-stack-switching"
BINARYEN = Path(
    os.environ.get(
        "BINARYEN", "/nix/store/nd1279k2zlbp23gfqcl0qp5xk40xlxr8-binaryen-132/bin"
    )
)
GC_INCLUDE = os.environ.get(
    "BDWGC_INCLUDE",
    "/nix/store/nw0fc624zk4fjqwaws8kyv23d7q5dr2i-boehm-gc-8.2.12-dev/include",
)
GC_LIB = os.environ.get(
    "BDWGC_LIB", "/nix/store/fhmdw5g0b3d1ahcdi0vl5wxcf5f6ylf8-boehm-gc-8.2.12/lib"
)


def run(command):
    subprocess.run([str(part) for part in command], check=True, cwd=ROOT)


# ---- Tests ----


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    run(
        [
            BINARYEN / "wasm-as",
            SOURCE / "workers.wat",
            "-g",
            "--enable-gc",
            "--enable-reference-types",
            "--enable-multivalue",
            "--enable-stack-switching",
            "--enable-exception-handling",
            "-o",
            OUT / "workers.wasm",
        ]
    )
    decoded = subprocess.check_output(
        [BINARYEN / "wasm-dis", OUT / "workers.wasm"], text=True
    )
    (OUT / "workers.decoded.wat").write_text(decoded)
    assert all(op in decoded for op in ("(cont.new ", "(resume ", "(suspend "))
    run(
        [
            "python3",
            ROOT / "experiments/wasm-llvm/translate.py",
            OUT / "workers.wasm",
            OUT / "workers.ll",
        ]
    )
    run(["opt", "-passes=verify", "-disable-output", OUT / "workers.ll"])
    run(
        [
            "clang",
            "-O3",
            "-g",
            "-Wno-unused-command-line-argument",
            "-c",
            OUT / "workers.ll",
            "-o",
            OUT / "workers.o",
        ]
    )
    run(
        [
            "clang",
            "-O3",
            "-g",
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-I" + GC_INCLUDE,
            SOURCE / "proof.c",
            OUT / "workers.o",
            "-L" + GC_LIB,
            "-Wl,-rpath," + GC_LIB,
            "-lgc",
            "-o",
            OUT / "proof",
        ]
    )
    run([OUT / "proof"])
    for flag, expected in [
        ("--double-resume", "already consumed"),
        ("--foreign-escape", "Rust boundary"),
        ("--null-new", "null function"),
        ("--null-resume", "null continuation"),
        ("--unhandled", "no matching"),
        ("--foreign-unmatched", "Rust boundary"),
    ]:
        result = subprocess.run(
            [OUT / "proof", flag], capture_output=True, text=True, check=False
        )
        assert result.returncode == 86 and expected in result.stderr, result
        print(f"ok: {flag} traps before transferring control")
    run(
        [
            BINARYEN / "wasm-as",
            SOURCE / "unsupported-cont-bind.wat",
            "--enable-stack-switching",
            "--enable-reference-types",
            "--enable-gc",
            "-o",
            OUT / "unsupported.wasm",
        ]
    )
    rejected = subprocess.run(
        [
            "python3",
            ROOT / "experiments/wasm-llvm/translate.py",
            OUT / "unsupported.wasm",
            OUT / "unsupported.ll",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert (
        rejected.returncode != 0
        and "unsupported instruction: cont.bind" in rejected.stderr
    ), rejected
    print("ok: unsupported standard cont.bind fails explicitly")


if __name__ == "__main__":
    main()
