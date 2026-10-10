# Baseline workloads

See [BENCHMARKS.md](../BENCHMARKS.md) for the native comparison, generated plots,
and the integrated R7RS suite. Run `python3 benchmarks/reproduce.py` to rebuild
and measure Fibonacci, or `python3 benchmarks/r7rs.py` for the pinned 57-workload
suite. Both accept `--plot` to regenerate reports from JSON;
[`shell.nix`](shell.nix) supplies the measurement and plotting dependencies.
Initialize the upstream suite with
`git submodule update --init benchmarks/r7rs-benchmarks` before running it.
**Workload times exclude compilation and process startup.**

## Native LLVM CPU experiment

The [LLVM code-generation ablation](results/2026-10-10-llvm-codegen.json)
measures the bounded Wasm-to-LLVM Fibonacci fixture with x86-64 and BDWGC:
unchanged output **0.046632s**, static boolean objects **0.035495s**, cold
out-of-line numeric fallbacks **0.029078s**, and both changes **0.026140s**.
Eight rotating CPU2 rounds check the same work and exclude compilation/startup.
All 43 numeric and tail-call checks pass with the combined changes.
See [BENCHMARKS.md](../BENCHMARKS.md) for reproduction at the recorded Git
revision. The transformations were LLVM-level prototypes; they are not
measurements of the current full production pipeline.

## Production WasmGC CPU baseline

The [October 10 production report](results/2026-10-10-wasmgc-production.json)
compiles the complete canonical `cpu.scm` through IR → WasmGC, merges the Rust
WASI runtime, and executes it in Node 24.15.0. This replaces the custom outer
JavaScript loop used by the earlier bounded experiment. Eight rotating rounds
on CPU 2 use 64 repetitions and check checksum `269118144` on every execution:

| Implementation / optimizer setting | Median seconds | Time / Chez |
| --- | ---: | ---: |
| WasmGC, Binaryen `-O3` | 0.338602 | 11.09× |
| WasmGC, inline threshold 40 | 0.127694 | 4.18× |
| WasmGC, second optimization pass with threshold 40 | 0.102202 | 3.35× |
| WasmGC, threshold 40 plus `--converge` | **0.086272** | **2.83×** |
| Chez 10.4.1, safe optimization level 2 | 0.030527 | 1.00× |
| Chibi 0.12 | 0.481500 | 15.77× |

The converged configuration takes **0.179× Chibi's time** (5.58× faster), and is
**3.92× faster** than the initial production WasmGC output. This is an optimizer
configuration change: `--always-inline-max-function-size=40 --converge` alongside
`-O3 --closed-world`. It preserves numeric representation checks and error paths.
The initial Fibonacci worker already used direct calls and avoided argument
vectors, but retained many tiny single-value and initialization helper calls.
Inlining exposes their surrounding operations to further optimization. This
ablation establishes the benefit of the configuration; it does not separately
attribute every part of the speedup to one helper.

For this module, one optimizer invocation took 0.265 seconds with threshold 40,
and 0.616 seconds with convergence. These are preliminary single compile-time
samples. The default module is 200,816 bytes with 543 defined functions; the
converged module is 222,711 bytes with 337. A preliminary threshold-80 experiment
regressed, so a larger inlining threshold is not assumed to be better.

Compilation and process startup are outside the program's timer. Each execution
starts a fresh Node process; its default V8 tiering remains enabled. The canonical
untimed checks exercise Fibonacci through input 12, but any subsequent tier-up
during the workload is included. One full fresh-process warmup per variant is
discarded before measurement. Chez and Chibi execute the same source through the
reference hosts, with unchanged timing boundaries; Chibi's clock has millisecond
resolution. The report retains raw samples, commands, tool versions, frozen
artifact hashes, the compiler/runtime source snapshot, and optimizer controls.
This measures CPU Fibonacci, not allocation-heavy workloads or native output
from the new backend.

With the tools described in [doc/backend.md](../doc/backend.md) available:

```sh
chibi-scheme -I src benchmarks/build.scm
scheme --script benchmarks/chez.scm benchmarks/cpu.scm build/cpu-chez.so
taskset -c 2 node scripts/run-wasi.mjs build/cpu.wasm 64
taskset -c 2 scheme --program build/cpu-chez.so 64
taskset -c 2 chibi-scheme benchmarks/cpu.scm 64
```

## Allocation workload

`memory.scm` builds a prime sieve and retains a list of its results. Its checks
validate the vector, list, and summary before reporting execution time. It runs
unchanged under Chibi; use the Chez adapter or `build-wasm` to compile it:

```scheme
(import (scheme base) (snail-scheme build))
(build-wasm "." "benchmarks/memory.scm" "build/memory.wasm")
(run-wasm "." "build/memory.wasm" '("1"))
```

There is no I/O benchmark or collector-counter benchmark. WasmGC does not expose
portable collection counters. Retired prototypes, tools, and results remain in
Git history. Compiler throughput can be inspected with the always-on
[Chromium traces](../doc/tracing.md).
