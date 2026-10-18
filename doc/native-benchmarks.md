# Historical runtime benchmarks

> Historical investigation: the LLVM backend and custom native runtime have been
> removed. Commands and native-bootstrap plans below describe earlier revisions.
> The current self-hosting target is WasmGC on an engine such as V8; that milestone
> remains unimplemented. See [the current build contract](backend.md).


This page archives the October 10 Scheme experiments, including their language
scope, collector and build commands. It does not describe current Lofi behavior.
See [BENCHMARKS.md](../BENCHMARKS.md) for the active Lofi, Chez and Rust corpus.
The commands and fixtures below require their historical source checkout:

```sh
git worktree add --detach /tmp/snail-historical-cpu 9129147
cd /tmp/snail-historical-cpu
```

**Runtime comparisons exclude compilation and process startup.** Timers surround
the workload, with correctness checks before it and output afterward. Each sample starts a
fresh process; runtime tiering in V8 or Guile remains included.

## Complete linked Fibonacci programs

Measured October 10, 2026, in eight rotating rounds pinned to CPU 2, after one
discarded run per implementation. Every sample performs 64 repetitions of
Fibonacci inputs 22–25 and checks checksum `269118144`.

| Implementation | Median seconds | Time / Chez |
| --- | ---: | ---: |
| Snail Wasm→LLVM, x86-64, BDWGC | **0.02690** | **0.90×** |
| Chez Scheme 10.4.1, safe optimization level 2 | 0.02978 | 1.00× |
| Snail WasmGC, Node/V8 24.19.0 | 0.08347 | 2.80× |
| Guile 3.0.11, compiled `--r7rs -O2` | 0.09566 | 3.21× |
| Chibi Scheme 0.12 | 0.45900 | 15.41× |

Native Snail takes **9.7% less time than Chez** here, and runs about 3.10× faster
than V8, 3.56× faster than Guile, and 17.06× faster than Chibi. These are
observations for this CPU/call workload, not claims about allocation, floating-point
workloads, or other programs.

Every implementation ran the complete canonical
[Scheme program](https://github.com/tsnl/snail-scheme/blob/9129147/benchmarks/cpu.scm).
Native and V8 consume the **same final Rust-linked Wasm module**. The native
converter is implemented in Scheme and translates both the Scheme and Rust
portions; the outer workload, checks, clock calls, and output remain Scheme.
Clang `-O3` with LTO links the result to the C Wasm/WASI/BDWGC host. No extracted
Fibonacci function, replacement C workload, native Rust rebuild, type inference,
or fixture-specific LLVM patch is involved. Guile compilation precedes timing;
auto-compilation is disabled. Chibi runs the canonical source directly.

The [raw report](../benchmarks/results/2026-10-10-native-fibonacci.json) retains
samples, commands, tool versions, source/artifact hashes, and environment settings.
The [previous production report](../benchmarks/results/2026-10-10-binary-runtime.json)
measured native 0.03850s and Chez 0.03039s. The changes below close that gap while
preserving the `tailcc` calling convention, numeric checks, GC, and Rust callbacks.

## Code-generation ablation

A separate eight-round comparison translates the **same final linked Wasm binary**
four ways. Only immediate-integer lowering and the authored `cold` attributes
change; the complete Scheme workload and host remain identical:

| Native lowering | Median seconds | Time / Chez |
| --- | ---: | ---: |
| Previous lowering, no cold hints | 0.038198 | 1.27× |
| Cold numeric fallbacks only | 0.032532 | 1.09× |
| Simpler i31 packing/extraction only | 0.031989 | 1.07× |
| Both, as shipped | **0.026885** | **0.90×** |
| Chez in this run | 0.029969 | 1.00× |

Together these changes reduce runtime by **29.6%** versus the controlled baseline.
The old lowering widened and narrowed integers through i64 and i31 intermediates.
The new lowering packs with a wrapping i32 shift and zero extension, and extracts
with an i32 signed or unsigned shift. Heap references remain full-width pointers.

Explicit `cold.` names on the runtime's comparison, addition, and subtraction
fallbacks survive Binaryen through the standard Wasm name section. The native
converter maps that prefix to LLVM's `cold` attribute, which guides optimization
and code layout. It adds no type assumptions or special Fibonacci handling.
An earlier diagnostic found no improvement from `noinline` alone, so production
leaves inlining decisions to LLVM. These hints favor immediate integers; wide and
inexact arithmetic still takes the fully checked fallback.

The [ablation report](../benchmarks/results/2026-10-10-native-fibonacci-ablation.json)
contains all samples, source and artifact hashes, commands, and its executable
Python reproduction recipe. The baseline emitter comes from revision `23a7b20`;
the cold-only arm copies attributes from the current emitter by matching function
headers, without hardcoded benchmark function indices. No experimental calling
convention is used.

## Reproduce the historical comparison

Use an otherwise idle x86-64 Linux machine. Enter `nix-shell` for the repository
build tools, and add Guile (`guile` and `guild`) to `PATH`. Then run:

```sh
benchmarks/native
```

The runner builds all implementations before timing, rotates eight rounds,
checks every answer, and saves `build/native-benchmark/results.json`. `BENCH_CPU`
selects another allowed core; it defaults to 2. `CHIBI`, `CHEZ`, `GUILE`, `GUILD`,
`NODE`, `CLANG`, and Binaryen tool variables accept executable paths. Separate
BDWGC installations can set `BDWGC_INCLUDE` and `BDWGC_LIB` as described in
the native execution guide in that historical checkout. Record changed tools when comparing results;
the Nix shell and Rust stable channel are not a frozen benchmark toolchain.

Build scripts can also produce just the two Snail artifacts:

```sh
chibi-scheme -I bootstrap benchmarks/native-build.scm
build/native-benchmark/cpu 64
node --no-warnings scripts/run-wasi.mjs build/native-benchmark/cpu.wasm 64
```

To repeat the four-way ablation after running `benchmarks/native`:

```sh
python3 - <<'PY'
import json, pathlib, subprocess
report = json.loads(pathlib.Path(
    "benchmarks/results/2026-10-10-native-fibonacci-ablation.json").read_text())
script = pathlib.Path("build/reproduce-native-ablation.py")
script.write_text(report["recipe_python"])
subprocess.run(["python3", str(script)], check=True)
PY
```

## Translation time

Binary Wasm now goes directly through the bounded reader and immutable LLVM
operands. The folded-WAT reader, expression tree, repeated name formatting,
and operand-list reconstruction are gone. The compiler still runs in Chibi.

At revision `23a7b20`, on the same 253,481-byte linked resource module, three alternating rounds pinned
to CPU 2 measured **69.31 seconds → 2.06 seconds** median
wall time (**33.6× faster**). This measurement **includes Chibi
startup, module loading, reading, lowering, and writing LLVM**. It excludes the
prior Wasm build/disassembly, Clang optimization/linking, and program execution.
It measures translation latency, not the runtime workload in the table above.
The [raw report](../benchmarks/results/2026-10-10-binary-translation.json) records
commands, versions, hashes, and each sample.

The first binary implementation took about 3.6 seconds inside the process.
Writing integers directly and putting common operations first in Chibi's linear
`case` dispatch brought that to about 1.4 seconds. That last improvement is
roughly 2.6×, not another 10×. These development timings excluded startup and
were not the controlled process comparison above.

To repeat this translation experiment in the historical checkout, generate its
resource fixture with `scripts/test-native`, then time just the translator:

```sh
python3 - <<'PY'
import os, statistics, subprocess, time
os.sched_setaffinity(0, {2})
command = ["chibi-scheme", "-I", "src", "tests/translate-native.scm",
           "build/native-tests/resources.wasm", "build/native-tests/resources.ll"]
samples = []
for _ in range(3):
    start = time.perf_counter()
    subprocess.run(command, check=True)
    samples.append(time.perf_counter() - start)
print("seconds:", samples, "median:", statistics.median(samples))
PY
```

For the old route, use revision `d0e7940` in a separate worktree, disassemble the
same input once with `wasm-dis`, and time its
`(wat-file->llvm-file "resources.wat" "resources.ll")` procedure under Chibi.
Do not count disassembly in this comparison. Program paths embedded by Rust and
installed tool versions can change the fixture's exact bytes; record their
hashes when comparing across checkouts or machines.

## Historical language scope

The measured Scheme implementation was not fully R7RS compliant. Its design left reusable,
re-entrant (multi-shot) continuations out of the intended language. Calling
these a “1% feature” expressed a design priority, not a measured percentage
of Scheme programs. `call/cc` was unsupported; single-shot delimited
continuations and coroutines were planned. Other conformance gaps remained.
The benchmark does not isolate the cost of continuations. The current
[roadmap](roadmap.md) defers Scheme support entirely.

## Historical bounded experiment

The earlier [Guile comparison](../benchmarks/results/2026-10-10-guile.json) measured
a bounded translator with an extracted Fibonacci function and a C outer harness:

| Implementation | Median seconds | Time / Chez |
| --- | ---: | ---: |
| Tuned native prototype | 0.02676 | 0.89× |
| Chez | 0.02994 | 1.00× |
| Baseline native prototype | 0.04659 | 1.56× |
| Guile | 0.09490 | 3.17× |
| Chibi | 0.46000 | 15.37× |

Its [LLVM ablation](../benchmarks/results/2026-10-10-llvm-codegen.json) used static
boolean objects and `cold noinline` numeric fallbacks. Those fixture-specific
results do not describe the complete linked compiler route above. The historical
sources, build/check scripts, and detailed reproduction recipe remain available
at their recorded revision:

```sh
git worktree add --detach /tmp/snail-benchmark-repro feb1503a72f8c430227cbb3d959ca7bf48873ea4
cd /tmp/snail-benchmark-repro
# Follow BENCHMARKS.md in that checkout.
```

The [benchmark guide](../benchmarks/README.md) also retains the production Wasm
optimizer comparison and describes the allocation workload.
