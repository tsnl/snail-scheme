#!/usr/bin/env python3
"""Ablate boolean identity and cold numeric fallbacks in the bounded fixture.

Run the existing WasmGC and Wasm-to-LLVM builders first. This deliberately
patches their numeric fixture's LLVM, not the general translator. Static atoms
assume one module instance, initialized once; no integer checks are removed.
"""

import hashlib
import json
import os
import re
import statistics
import subprocess
from pathlib import Path

import build

OUT = build.ROOT / "build/wasm-llvm-ablation"
VARIANTS = {
    "baseline": (False, False),
    "static-atoms": (True, False),
    "cold-fallbacks": (False, True),
    "both": (True, True),
}


# ---- Deliberately bounded LLVM transformations ----


def static_atoms(llvm):
    # Keep this entire fixture-specific replacement visible. Type IDs differ
    # between cpu.wasm and check.wasm; read them rather than assuming a tag.
    init = re.search(r"define void @wasm_init\(\) \{.*?\n\}", llvm, re.DOTALL)[0]
    assert set(re.findall(r"^@global_(\w+) =", llvm, re.MULTILINE)) == {
        "false",
        "true",
        "error_code",
    }
    kinds = re.findall(r"store i32 (\d+), ptr %v(?:1|7), align 8", init)
    assert len(kinds) == 2 and kinds[0] == kinds[1], "unexpected atom layout"
    assert init.count("call ptr @GC_malloc(i64 16)") == 2
    assert (
        "store i32 0, ptr %v5, align 8" in init
        and "store i32 1, ptr %v11, align 8" in init
    )
    for name, payload in [("false", 0), ("true", 1)]:
        old = f"@global_{name} = internal global i64 0, align 8"
        assert llvm.count(old) == 1, "unexpected numeric fixture globals"
        llvm = llvm.replace(
            old,
            f"@static_{name} = internal global {{ i64, i64 }} "
            f"{{ i64 {kinds[0]}, i64 {payload} }}, align 8\n"
            f"@global_{name} = internal constant i64 "
            f"ptrtoint (ptr @static_{name} to i64), align 8",
        )
    return llvm.replace(
        init,
        """define void @wasm_init() {
entry:
  call void @GC_set_all_interior_pointers(i32 1)
  call void @GC_init()
  store i32 0, ptr @global_error_code, align 8
  ret void
}""",
    )


def cold_fallbacks(llvm):
    pattern = r"^(define internal fastcc [^\n]*@fn_(?:compare|slow_[01])\([^\n]*\)) \{"
    result, count = re.subn(pattern, r"\1 cold noinline {", llvm, flags=re.MULTILINE)
    assert count == 3, "expected three numeric fallback functions"
    return result


def transform(source, name):
    llvm = source.read_text()
    static, cold = VARIANTS[name]
    if static:
        llvm = static_atoms(llvm)
    if cold:
        llvm = cold_fallbacks(llvm)
    output = OUT / f"{source.stem}-{name}.ll"
    output.write_text(llvm)
    return output


# ---- Optimized builds and correctness ----


def cpu_variant(name):
    llvm = transform(build.OUT / "cpu.ll", name)
    object_file, executable = llvm.with_suffix(".o"), llvm.with_suffix("")
    build.run([build.OPT, "-passes=verify", "-disable-output", llvm])
    build.run(
        [
            build.CLANG,
            "-Wno-unused-command-line-argument",
            "-O3",
            "-c",
            llvm,
            "-o",
            object_file,
        ]
    )
    build.run(
        [
            build.CLANG,
            object_file,
            build.OUT / "runner-c.o",
            *build.GC_LINK,
            "-o",
            executable,
        ]
    )
    return executable


def check_numeric_boundaries():
    llvm = transform(build.OUT / "check.ll", "both")
    library = llvm.with_suffix(".so")
    build.run(
        [
            build.CLANG,
            "-Wno-unused-command-line-argument",
            "-O3",
            "-shared",
            "-fPIC",
            llvm,
            *build.GC_LINK,
            "-o",
            library,
        ]
    )
    build.run(["python3", build.SOURCE / "check.py", library])


# ---- Fixed-work measurements ----


def sample(name, executable):
    output = subprocess.check_output([str(executable), "64"], text=True)
    assert "checksum: 269118144" in output, output
    seconds = float(re.search(r"elapsed: ([\d.]+) s", output)[1])
    return {"variant": name, "seconds": seconds, "checksum": 269118144}


def measure(executables):
    os.sched_setaffinity(0, {2})
    for name, path in executables.items():
        sample(name, path)
    rows, items = [], list(executables.items())
    for round in range(8):
        offset = round % len(items)
        for name, path in items[offset:] + items[:offset]:
            rows.append({**sample(name, path), "round": round + 1})
    return rows


def report(executables, rows):
    paths = [build.OUT / f"{name}.ll" for name in ("cpu", "check")]
    paths += [Path(__file__), *executables.values(), *OUT.glob("*.ll")]
    return {
        "scope": __doc__,
        "method": "8 rotating CPU2 rounds, 64 repetitions; "
        "compilation/startup excluded; one warmup per variant",
        "samples": rows,
        "median_seconds": {
            name: statistics.median(
                row["seconds"] for row in rows if row["variant"] == name
            )
            for name in executables
        },
        "commands": build.COMMANDS,
        "sha256": {
            str(p.relative_to(build.ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in paths
        },
        "clang": subprocess.check_output(
            [build.CLANG, "--version"], text=True
        ).splitlines()[0],
    }


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    executables = {name: cpu_variant(name) for name in VARIANTS}
    check_numeric_boundaries()
    result = report(executables, measure(executables))
    (OUT / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result["median_seconds"], indent=2))


if __name__ == "__main__":
    main()
