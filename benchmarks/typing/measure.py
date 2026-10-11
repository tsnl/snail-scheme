#!/usr/bin/env python3
"""Measure typing ablations for recursive/tail Fibonacci or union/record dispatch."""

import argparse
import hashlib
import json
import os
import platform
import re
import statistics
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build/typing-benchmark"
TAIL_FUNCTION = """(define (fibonacci n a b)
  (if (< n 2)
      (if (<= n 0) a b)
      (fibonacci (- n 1) b (+ a b))))
"""


# ---- Reproducible compilation ----


def run(arguments):
    result = subprocess.run([str(arg) for arg in arguments], cwd=ROOT, check=False,
                            text=True, capture_output=True, timeout=240)
    if result.returncode:
        raise RuntimeError(f"command failed: {arguments}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def scheme_source(annotation):
    source = (ROOT / "benchmarks/cpu.scm").read_text()
    source = source.replace("(scheme process-context))", "(scheme process-context) (snail typing))")
    source = source.replace("(define (fibonacci n)",
                            annotation + "\n(define (fibonacci n offset)")
    source = source.replace("      n\n", "      (+ n offset)\n")
    source = source.replace("(fibonacci (- n 1))", "(fibonacci (- n 1) offset)")
    source = source.replace("(fibonacci (- n 2))", "(fibonacci (- n 2) offset)")
    return source.replace("(fibonacci n)", "(fibonacci n 0)")


def tail_source(annotation):
    source = (ROOT / "benchmarks/cpu.scm").read_text()
    source = source.replace("(scheme process-context))", "(scheme process-context) (snail typing))")
    first, last = source.index("(define (fibonacci n)"), source.index("(define (fibonacci-linear n)")
    source = source[:first] + annotation + "\n" + TAIL_FUNCTION + "\n" + source[last:]
    return source.replace("(fibonacci n)", "(fibonacci n 0 1)").replace(
        '(display "CPU: recursive Fibonacci")', '(display "CPU: tail Fibonacci")').replace(
        '(start (current-jiffy))', '(warmup (repeat-work count expected))\n         (start (current-jiffy))').replace(
        "\n(main)\n", '\n(require-equal (fibonacci 10 2 3) 233 "Fibonacci seeds")\n'
        '(require-equal (fibonacci 46 0 1) 1836311903 "Fibonacci i32 boundary")\n(main)\n')


def build_scheme(name, annotation, mode, contents=None):
    source, output = BUILD / f"{name}.scm", BUILD / f"{name}.wasm"
    source.write_text(scheme_source(annotation) if contents is None else contents)
    run([os.environ.get("CHIBI", "chibi-scheme"), "-I", "src",
         "tests/build-typed-program.scm", ROOT, source, output, mode])
    return [os.environ.get("NODE", "node"), "--no-warnings", "scripts/run-wasi.mjs", output]


def check_specialization(commands):
    for name, command in commands.items():
        if name.startswith("c-"):
            continue
        wat = Path(command[-1]).with_suffix(".wasm.wat").read_text()
        expected = 1 if name.startswith("i32-specialized") else 0
        actual = wat.count("(func $i32_")
        if actual != expected:
            raise RuntimeError(f"{name}: expected {expected} i32 workers, emitted {actual}")


def wasm_compiler():
    compiler = Path(shutil.which(os.environ.get("TYPING_WASM_CC", "clang"))).resolve()
    original = compiler.parent.parent / "nix-support/orig-cc"
    return Path(original.read_text().strip()) / "bin/clang" if original.exists() else compiler


def build_c(name, kernel, wasm=False, extra=(), tail=False):
    output = BUILD / (name + (".wasm" if wasm else ""))
    flags = (["--target=wasm32", "-ffreestanding", "-nostdlib", "-Wl,--no-entry", "-Wl,--export=fibonacci"]
             if wasm else [f"benchmarks/typing/{'fibonacci-tail-driver' if tail else 'fibonacci'}.c"])
    run([wasm_compiler() if wasm else os.environ.get("TYPING_CC", "clang"), "-O3", *extra, *flags,
         f"benchmarks/typing/{kernel}.c", "-o", output])
    runner = "run-tail-kernel.mjs" if tail else "run-kernel.mjs"
    return ([os.environ.get("NODE", "node"), "--no-warnings", f"benchmarks/typing/{runner}", output]
            if wasm else [output])


def variants(workload):
    if workload == "occurrence":
        source = (ROOT / "benchmarks/typing/occurrence.scm").read_text()
        return {f"occurrence-{mode}": build_scheme(f"occurrence-{mode}", "", mode, source)
                for mode in ("guarded", "boxed")}
    if workload == "tail-fibonacci":
        return tail_variants()
    return {
        "untyped-guarded": build_scheme("untyped-guarded", "", "guarded"),
        "untyped-boxed": build_scheme("untyped", "", "boxed"),
        "integer-guarded": build_scheme("integer-guarded", "(: fibonacci (-> ExactInteger ExactInteger ExactInteger))", "guarded"),
        "integer-optimized": build_scheme("integer", "(: fibonacci (-> ExactInteger ExactInteger ExactInteger))", "boxed"),
        "i32-guarded": build_scheme("guarded", "(: fibonacci (-> i32 i32 i32))", "guarded"),
        "i32-boxed": build_scheme("boxed", "(: fibonacci (-> i32 i32 i32))", "boxed"),
        "i32-specialized": build_scheme("specialized", "(: fibonacci (-> i32 i32 i32))", "optimized"),
        "c-native-O3": build_c("c-native", "fibonacci-kernel"),
        "c-native-checked": build_c("c-checked", "fibonacci-checked"),
        "c-native-no-sibling-calls": build_c("c-recursive", "fibonacci-kernel", extra=["-fno-optimize-sibling-calls"]),
        "c-wasm-O3": build_c("c-wasm", "fibonacci-kernel", wasm=True),
        "c-wasm-checked": build_c("c-wasm-checked", "fibonacci-checked", wasm=True),
    }


def tail_variants():
    variants = {}
    for name, annotation, mode in (
        ("untyped-guarded", "", "guarded"), ("untyped-boxed", "", "boxed"),
        ("integer-guarded", "(: fibonacci (-> ExactInteger ExactInteger ExactInteger ExactInteger))", "guarded"),
        ("integer-optimized", "(: fibonacci (-> ExactInteger ExactInteger ExactInteger ExactInteger))", "boxed"),
        ("i32-guarded", "(: fibonacci (-> i32 i32 i32 i32))", "guarded"),
        ("i32-boxed", "(: fibonacci (-> i32 i32 i32 i32))", "boxed"),
        ("i32-specialized", "(: fibonacci (-> i32 i32 i32 i32))", "optimized"),
    ):
        variants[name] = build_scheme("tail-" + name, annotation, mode, tail_source(annotation))
    variants.update({
        "i32-specialized-kernel": build_tail_kernel(),
        "c-native-O3": build_c("tail-c-native", "fibonacci-tail", tail=True),
        "c-native-checked": build_c("tail-c-checked", "fibonacci-tail-checked", tail=True),
        "c-native-no-sibling-calls": build_c("tail-c-recursive", "fibonacci-tail", extra=["-fno-optimize-sibling-calls"], tail=True),
        "c-wasm-O3": build_c("tail-c-wasm", "fibonacci-tail", wasm=True, tail=True),
        "c-wasm-checked": build_c("tail-c-wasm-checked", "fibonacci-tail-checked", wasm=True, tail=True),
    })
    return variants


def build_tail_kernel():
    """Expose the existing pure worker for the same JS driver used by C-to-Wasm."""
    source = "(import (scheme base) (snail typing))\n(: fibonacci (-> i32 i32 i32 i32))\n" + TAIL_FUNCTION
    command = build_scheme("tail-i32-kernel", "", "optimized", source)
    output = command[-1]
    wat = output.with_suffix(".wasm.wat")
    export_i32_worker(wat)
    link = f"(link-wasm {json.dumps(str(wat))} (build-runtime {json.dumps(str(ROOT))}) {json.dumps(str(output))})"
    link = f"(with-chromium-trace-to {json.dumps(str(output) + '.link.trace.json')} (lambda () {link}))"
    run([os.environ.get("CHIBI", "chibi-scheme"), "-I", "src", "-m", "snail-scheme.build",
         "-m", "snail-scheme.chromium-trace", "-e", link])
    return [os.environ.get("NODE", "node"), "--no-warnings", "benchmarks/typing/run-tail-kernel.mjs", output]


def export_i32_worker(wat):
    contents = wat.read_text()
    workers = re.findall(r"^\(func (\$i32_\d+) ", contents, re.MULTILINE)
    if len(workers) != 1:
        raise RuntimeError(f"expected exactly one specialized tail kernel, got {workers}")
    contents = contents.rstrip().removesuffix(")") + f'(export "fibonacci" (func {workers[0]}))\n)\n'
    wat.write_text(contents)


# ---- Execution measurements ----


def sample(command, repetitions, cpu, expected):
    output = run(["taskset", "-c", str(cpu), *command, str(repetitions)])
    checksum = int(re.search(r"checksum: (\d+)", output)[1])
    if checksum != expected:
        raise RuntimeError(f"checksum mismatch: {output}")
    return float(re.search(r"elapsed: ([\d.]+) s", output)[1])


def describe(command, samples):
    artifact = Path(command[-1])
    result = {"command": list(map(str, command)), "seconds": samples,
              "median_seconds": statistics.median(samples), "bytes": artifact.stat().st_size,
              "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()}
    wat = artifact.with_suffix(artifact.suffix + ".wat")
    if wat.exists():
        emitted = "\n".join(line for line in wat.read_text().splitlines()
                            if line.startswith(("(func $function", "(func $library", "(func $i32_")))
        result["emitted_single_calls"] = emitted.count("(call $single ")
        result["integer_helper_calls"] = emitted.count("$integer_")
        result["string_helper_calls"] = emitted.count("$known_string_length")
        result["record_helper_calls"] = emitted.count("$known_record_ref")
        result["i32_workers"] = emitted.count("(func $i32_")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rounds", type=int, default=8)
    parser.add_argument("--repetitions", type=int)
    parser.add_argument("--cpu", type=int, default=2)
    parser.add_argument("--workload", choices=("fibonacci", "tail-fibonacci", "occurrence"), default="fibonacci")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.repetitions is None:
        args.repetitions = 1048576 if args.workload == "tail-fibonacci" else 256
    BUILD.mkdir(parents=True, exist_ok=True)
    commands = variants(args.workload)
    check_specialization(commands)
    expected = (210000 if args.workload == "occurrence" else 4204971) * args.repetitions
    results = {name: [] for name in commands}
    for command in commands.values():
        sample(command, args.repetitions, args.cpu, expected)
    names = list(commands)
    for index in range(args.rounds):
        order = names[index % len(names):] + names[:index % len(names)]
        for name in order:
            results[name].append(sample(commands[name], args.repetitions, args.cpu, expected))
        print(f"completed rotating round {index + 1}/{args.rounds}", flush=True)
    report = {"base_revision": run(["git", "rev-parse", "HEAD"]).strip(),
              "source_diff_sha256": hashlib.sha256(run(["git", "diff", "HEAD"]).encode()).hexdigest(),
              "source_hashes": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                for directory in ("src", "bootstrap", "benchmarks", "tests")
                                for path in sorted((ROOT / directory).rglob("*"))
                                if path.is_file() and path.suffix in (".sld", ".scm", ".wat", ".rs", ".c", ".py", ".mjs")},
              "platform": platform.platform(), "cpu": args.cpu, "rounds": args.rounds,
              "cpu_model": next(line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines()
                                if line.startswith("model name")),
              "compilers": {"native": shutil.which(os.environ.get("TYPING_CC", "clang")), "wasm": str(wasm_compiler())},
              "workload": args.workload, "repetitions": args.repetitions, "checksum": expected,
              "warmup_repetitions": args.repetitions if args.workload == "tail-fibonacci" else 0,
              "versions": {tool: run([tool, "--version"]).splitlines()[0] for tool in ("node", "clang", "wasm-opt")},
              "variants": {name: describe(commands[name], results[name]) for name in names}}
    output = args.output or ROOT / f"benchmarks/results/2026-10-10-typing-{args.workload}.json"
    output.write_text(json.dumps(report, indent=2) + "\n")
    for name, result in report["variants"].items():
        print(f"{name}: {result['median_seconds']:.6f}s")


if __name__ == "__main__":
    main()
