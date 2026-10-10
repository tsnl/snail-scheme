# Runtime benchmarks

**EXCLUDES COMPILATION TIME AND PROCESS STARTUP.** These numbers measure
execution after ahead-of-time compilation has finished. They do not measure
the time taken by `snail-scheme` to build and launch a program.

## Recursive Fibonacci: native LLVM, Chez, Guile, and Chibi

Measured October 10, 2026, on the same machine in eight rotating rounds pinned
to CPU 2. Each sample performs 64 repetitions of Fibonacci inputs 22–25,
with checksum `269118144`. Lower times and ratios are better.

| Implementation | Median seconds | Time / Chez |
| --- | ---: | ---: |
| Snail Wasm→LLVM prototype, tuned, x86-64 | **0.02676** | **0.89×** |
| Chez Scheme 10.4.1 | 0.02994 | 1.00× |
| Snail Wasm→LLVM prototype, baseline, x86-64 | 0.04659 | 1.56× |
| Guile 3.0.11 | 0.09490 | 3.17× |
| Chibi Scheme 0.12 | 0.46000 | 15.37× |

The tuned LLVM prototype is **3.55× faster than Guile**, **1.12× faster than
Chez**, and **17.19× faster than Chibi** on this workload.

## Language-compliance trade-off

**Snail Scheme is not fully R7RS compliant.** We deliberately leave reusable,
re-entrant (multi-shot) continuations out of the intended language. We regard
these as a “1% feature”: a small part of the language that we are willing to
forgo to simplify execution and prioritize fast ordinary calls. That phrase
expresses our design priorities, not a measured percentage of Scheme programs.

The current production Wasm backend rejects `call/cc` and
`call-with-current-continuation` entirely. Single-shot delimited continuations
and coroutines are planned; an independent native stack-switching experiment
demonstrates a bounded subset. Other conformance gaps also remain, so this is
not a claim of “R7RS compliant except for re-entrant continuations.”

The simpler execution model supports our performance goals, but the benchmark
above does **not** isolate the cost of reusable continuations. Its latest
measured speedup comes from exposing boolean identities and keeping numeric
fallbacks out of line. See [future work](TODO.md) for the language scope.

## What these results measure

- The LLVM rows use the bounded experimental Wasm-to-LLVM translator, optimized
  with Clang `-O3` and linked with BDWGC. Its C harness runs the extracted
  recursive Fibonacci procedure. These are **not yet measurements of the full
  production compiler's linked Wasm output**.
- The tuned variant exposes distinct static boolean objects and marks numeric
  fallback functions `cold noinline`. Integer representation and checks remain
  intact. These changes are reproduced by an experimental LLVM patcher; the
  general translator does not yet implement them. The combined variant passed
  all 43 numeric and tail-call checks.
- Chez, Guile, and Chibi run the complete canonical
  [Scheme benchmark](benchmarks/cpu.scm). Chez uses safe optimization level 2.
  Guile compiles the unchanged source to bytecode with `guild compile --r7rs
  -O2`; auto-compilation is disabled during execution. Chibi uses the existing
  compatibility adapter without changing the benchmark algorithms.
- Each measured sample starts a fresh process. One preliminary sample per
  implementation is discarded. Guile uses its default runtime/JIT settings;
  any JIT activity during execution is included, not separately subtracted.
  An additional Guile control performs a full 64-repetition warmup inside each
  process before timing again: **0.09514s**, essentially unchanged.
- Timers surround the workload, excluding build time, process startup, initial
  correctness checks, and final output. This is a CPU/call benchmark, not a
  measure of allocation-heavy workloads, compilation speed, or browser speed.

## Reproduction and raw data

The [Guile comparison report](benchmarks/results/2026-10-10-guile.json) records
all samples, commands, versions, artifact hashes, relevant Guile environment
settings, and the measurement script. The
[LLVM ablation](benchmarks/results/2026-10-10-llvm-codegen.json) records how the
two native variants were built.

To prepare the native artifacts:

```sh
python3 experiments/wasmgc/build.py
python3 experiments/wasm-llvm/build.py
python3 experiments/wasm-llvm/ablate.py
```

To compile and run Guile separately from its timed workload:

```sh
mkdir -p build/guile
guild compile --r7rs -O2 -o build/guile/cpu.go benchmarks/cpu.scm
taskset -c 2 guile --no-auto-compile --r7rs \
  -c '(load-compiled "build/guile/cpu.go")' 64
```

Tool requirements, other workloads, production Wasm engine measurements, and
historical results are in the [benchmark guide](benchmarks/README.md).
