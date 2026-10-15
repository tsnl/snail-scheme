#!/usr/bin/env python3
"""Count selected trial allocation/zero-fill calls in a separate Wasm diagnostic."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

# ---- Explicit diagnostic state and wrappers ----

GLOBAL_BLOCK = """
 ;; Separate counters: selected trial allocations include seeds, not startup.
 (global $in_control_allocation (mut i32) (i32.const 0))
 (global $control_allocation_calls (export "control_allocation_calls") (mut i64) (i64.const 0))
 (global $control_requested_bytes (export "control_requested_bytes") (mut i64) (i64.const 0))
 (global $control_zero_fill_calls (export "control_zero_fill_calls") (mut i64) (i64.const 0))
 (global $control_zero_fill_bytes (export "control_zero_fill_bytes") (mut i64) (i64.const 0))
"""

WRAPPERS = """
 (func $control_malloc (param $size i32) (result i32)
  (global.set $control_allocation_calls
   (i64.add (global.get $control_allocation_calls) (i64.const 1)))
  (global.set $control_requested_bytes
   (i64.add (global.get $control_requested_bytes) (i64.extend_i32_u (local.get $size))))
  (call $malloc (local.get $size)))
 (func $control_calloc (param $size i32) (param $count i32) (result i32)
  (local $pointer i32)
  (global.set $control_allocation_calls
   (i64.add (global.get $control_allocation_calls) (i64.const 1)))
  (global.set $control_requested_bytes
   (i64.add (global.get $control_requested_bytes)
    (i64.mul (i64.extend_i32_u (local.get $size)) (i64.extend_i32_u (local.get $count)))))
  (global.set $in_control_allocation (i32.const 1))
  (local.set $pointer (call $calloc (local.get $size) (local.get $count)))
  (global.set $in_control_allocation (i32.const 0))
  (local.get $pointer))
"""

FILL_COUNTER = """   (if (global.get $in_control_allocation)
    (then
     (global.set $control_zero_fill_calls
      (i64.add (global.get $control_zero_fill_calls) (i64.const 1)))
     (global.set $control_zero_fill_bytes
      (i64.add (global.get $control_zero_fill_bytes) (i64.extend_i32_u (local.get $2))))))
"""


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def function_spans(text):
    lines = text.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.startswith(" (func ")]
    return lines, list(zip(starts, starts[1:] + [len(lines) - 1]))


def instrument_trials(text):
    lines, spans = function_spans(text)
    selected = []
    for start, end in spans:
        if "string_reference_controls11trial_" in lines[start]:
            body = "".join(lines[start:end])
            assert body.count("(call $malloc") + body.count("(call $calloc") == 5
            selected.append(lines[start].strip())
            for i in range(start, end):
                lines[i] = lines[i].replace("(call $malloc", "(call $control_malloc").replace("(call $calloc", "(call $control_calloc")
    assert len(selected) == 4
    return "".join(lines), selected


def instrument_calloc(text):
    lines, spans = function_spans(text)
    start, end = next((a, b) for a, b in spans if lines[a].startswith(" (func $calloc "))
    body = "".join(lines[start:end])
    assert body.count("   (memory.fill\n") == 1 and "(local.get $2)" in body
    changed = body.replace("   (memory.fill\n", FILL_COUNTER + "   (memory.fill\n")
    return "".join(lines[:start]) + changed + "".join(lines[end:])


def instrument(text):
    changed, selected = instrument_trials(text)
    changed = instrument_calloc(changed)
    assert changed.startswith("(module ") and changed.rstrip().endswith(")")
    first_function = changed.index("\n (func ") + 1
    changed = changed[:first_function] + GLOBAL_BLOCK + changed[first_function:]
    closing = changed.rfind("\n)")
    changed = changed[:closing] + WRAPPERS + changed[closing:]
    restored = changed.replace(GLOBAL_BLOCK, "", 1).replace(WRAPPERS, "", 1).replace(FILL_COUNTER, "", 1)
    restored = restored.replace("(call $control_malloc", "(call $malloc").replace("(call $control_calloc", "(call $calloc")
    assert restored == text, "counter removal must recover the exact original optimized WAT"
    return changed, selected


# ---- Actual reassembly and separate resource execution ----

def assemble(command, source, artifact):
    flags = ["--enable-mutable-globals", "--enable-sign-ext", "--enable-bulk-memory",
             "--enable-nontrapping-float-to-int", "--enable-reference-types",
             "--enable-multivalue", "--enable-extended-const"]
    subprocess.run([command, str(source), *flags, "-o", str(artifact)], check=True)


def run_probe(node, host, artifact, mode, directory, source):
    command = [node, "--no-warnings", str(host), str(artifact), mode]
    run = subprocess.run(command, cwd=directory, input=source, text=True,
                         capture_output=True, timeout=60)
    assert run.returncode == 0 and "Result: 524278\n" in run.stdout and "INCORRECT" not in run.stdout + run.stderr
    resources = [json.loads(line.removeprefix("Resource: ")) for line in run.stderr.splitlines()
                 if line.startswith("Resource: ")]
    assert len(resources) == 1
    return {"command": command, "returncode": run.returncode, "stdout": run.stdout,
            "stderr": run.stderr, "resource": resources[0]}


def check_counters(run, width, zeroed):
    counters = {name: int(value) for name, value in run["resource"]["counterValues"].items()}
    expected = {"control_allocation_calls": 61000, "control_requested_bytes": 3145173000 * width,
                "control_zero_fill_calls": 61000 if zeroed else 0,
                "control_zero_fill_bytes": 3145173000 * width if zeroed else 0}
    assert counters == expected, (counters, expected)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wat", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True)
    original = args.wat.read_text()
    (output / "original.wat").write_text(original)
    changed, selected = instrument(original)
    (output / "instrumented.wat").write_text(changed)
    wasm_as = "/nix/store/nd1279k2zlbp23gfqcl0qp5xk40xlxr8-binaryen-132/bin/wasm-as"
    assemble(wasm_as, output / "original.wat", output / "reassembled.wasm")
    assemble(wasm_as, output / "instrumented.wat", output / "instrumented.wasm")
    host = Path(__file__).with_name("resource-wasi.mjs").resolve()
    source = args.input.read_text()
    assert source == "100\n500000\n524278\n"
    modes = [("byte", 1, False), ("u32", 4, False), ("byte-zeroed", 1, True), ("u32-zeroed", 4, True)]
    reassembled = [run_probe(shutil.which("node"), host, output / "reassembled.wasm", mode, output, source)
                   for mode, _, _ in modes]
    instrumented = []
    for mode, width, zeroed in modes:
        run = run_probe(shutil.which("node"), host, output / "instrumented.wasm", mode, output, source)
        check_counters(run, width, zeroed)
        instrumented.append(run)
    report = {"kind": "Separate selected-allocation and logical zero-fill diagnostic", "performance_samples": False,
              "input_sha256": digest(args.input), "original_wat_sha256": digest(output / "original.wat"),
              "host_sha256": digest(host), "wasm_as_sha256": digest(wasm_as),
              "reassembled_wasm_sha256": digest(output / "reassembled.wasm"),
              "instrumented_wasm_sha256": digest(output / "instrumented.wasm"),
              "exact_wat_restored_after_removing_instrumentation": True, "selected_functions": selected,
              "reassembled_gate": reassembled, "instrumented": instrumented,
              "counter_scope": "Selected trial allocator calls, including seed allocations; startup excluded. Zero counters run only on reached calloc memory.fill under a selected allocation.",
              "limits": "Logical requested bytes and Wasm memory.fill executions/lengths, not physical stores, traffic, residency, peak RSS or uninstrumented elapsed performance. WASI.start resources include startup and reporting; maxRSS is process high-water.",
              "complete": True, "fresh_informed_probe_review": "pending after parent slot interruption"}
    (output / "probe.json").write_text(json.dumps(report, indent=2) + "\n")
    print("Four reassemblies and four instrumented full-count controls pass exact allocator/zero-fill counters")


if __name__ == "__main__":
    main()
