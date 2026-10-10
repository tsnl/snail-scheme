# WasmGC numeric prototype

This experiment lowers closed numeric functions from the production frontend's
HIR into ordinary WebAssembly functions. It does not change the production
compiler. `compile.scm` selects the supported HIR subset; `emit.py` serializes
structured WAT using the representations in `numbers.wat`.

Arguments and results inside recursive functions are dynamic `eqref` values.
Signed31 fixnums use `ref.i31`; larger exact integers and inexact numbers use
GC structs containing `i64` and `f64`. Booleans are distinct singleton structs.
Arithmetic checks representations and overflow, and mixed comparisons preserve
large exact integers. Tail recursion emits `return_call`. There is no manual
operand stack, allocator, collector, or root publication in this module.

The proposed production boundary is Scheme → HIR → WASM, with WASM replacing
MIR. A native WASM → LLVM compiler would be independent of Scheme and HIR.
These experiments test that boundary; the landed compiler still uses MIR/LLVM.
The agreed next direction is HIR → WASM, with Wastrel providing native output.
Rename HIR to IR as part of retiring MIR; the production migration is separate
from these experiments.

## Build and check

The recorded tools are Chibi 0.12, Binaryen 132, Node 24.15.0, Wasmtime 48.0.0,
and Rust 1.95.0. With the tools on PATH:

```sh
python3 experiments/wasmgc/build.py
python3 experiments/wasm-llvm/build.py
python3 experiments/wasmgc/measure.py
experiments/wasmgc-interop/run
```

`CHIBI`, `NODE`, `WASM_AS`, and `WASM_OPT` override executable paths. For this
machine the scripts also retain the exact Nix store paths used in the experiment.
The optional Wasmtime C runner requires headers and libwasmtime; override
`WASMTIME_INCLUDE` and `WASMTIME_LIB` when these are installed elsewhere.
All build commands are saved to `build/wasmgc/build-commands.json`.

The builder emits raw and Binaryen `-O3` modules, then runs 43 assertions on raw
and optimized output under V8's optimizing tier and on optimized output under
Liftoff. Cases include signed31 boxing, signed64 overflow, floating arithmetic,
mixed exact/inexact comparisons around 2^53 and the signed64 limits, NaN,
infinities, boolean type errors, adapter range checks, and two million tail calls.
The separate [Rust interop proof](../wasmgc-interop/README.md) tests retained
GC objects and direct calls between Rust and WASM, including statically merged
modules.

The independent [WASM → LLVM experiment](../wasm-llvm/README.md) translates the
same raw binary modules and links BDWGC for native execution. Its build also
checks collection with native register, stack, caller-frame and global roots.

## Measurement contract

`benchmarks/cpu.scm` is unchanged. Its expanded recursive Fibonacci function is
selected by HIR structure, not by name or benchmark input. The outer JS and C
drivers run inputs 22, 23, 24, 25 in order, weight each answer by `n + 1`, and
repeat 64 times. Every run must produce checksum `269118144`.

Only the recursive function is compiled through this experimental path. Its
arguments remain dynamic GC references. There is no numeric type inference,
memoization, alternative Fibonacci algorithm, or omitted overflow fallback.
Binaryen and each engine may optimize the emitted code normally.

The outer WASM drivers make 256 host-to-WASM calls. The frozen native controls
retain their Scheme VM outer harness; this harness difference is included in
the reported times and must not be mistaken for a whole-compiler comparison.
V8 uses `--no-liftoff --no-wasm-lazy-compilation` for optimized runs and
`--liftoff-only --no-wasm-lazy-compilation` for baseline runs. Module compilation,
instantiation, initial checks and warmup finish before the internal timer.
The Wasmtime C runner uses Cranelift's speed setting and includes no compilation
inside the timer. The process wall time is recorded separately.

Measurements pin to CPU2, discard one full process run per variant, and rotate
eight rounds of all variants. Source, executable and WASM hashes, tool versions,
commands, checksums, raw samples and ratios are saved in `build/wasmgc/results.json`.
Do not compile concurrently with measurement.

The controls are the previously frozen main, native SSA, Chez and Chibi artifacts
under `/tmp/snail-mir-memory-20261010`, `/tmp/snail-native-ssa-20261010`, and
`/tmp/snail-mir-20261010`. The measurement script reads their exact commands from
the native SSA experiment report. Those artifacts must be rebuilt or supplied
when reproducing on another machine; their hashes distinguish them from current
working-tree source.
`NATIVE_CONTROLS` can point to another report containing rebuilt control commands.

The [2026-10-10 report](../../benchmarks/results/2026-10-10-wasmgc.json) records
these medians. Ratios above one mean more time than Chez:

| Implementation | Seconds | Time / Chez |
| --- | ---: | ---: |
| Native SSA experiment | 0.027019 | 0.90 |
| Chez | 0.030073 | 1.00 |
| WASM → LLVM + BDWGC | 0.046837 | 1.56 |
| Wasmtime, optimized WASM | 0.073326 | 2.44 |
| V8, optimized WASM | 0.082465 | 2.74 |
| V8, raw WASM | 0.095364 | 3.17 |
| Production backend | 0.317802 | 10.57 |
| V8 Liftoff, optimized WASM | 0.360915 | 12.00 |
| Chibi | 0.461000 | 15.33 |

The translator is 6.79 times faster than the production control on this
workload, and 1.73 times slower than the native SSA experiment. This does not
measure allocator throughput: these Fibonacci inputs stay in immediate values.
Collector correctness is tested separately with allocating object graphs.
The earlier V8 preliminary result (0.0666 seconds) preceded the final adapter
range checks and module rebuild; the final artifact consistently measured
0.0824–0.0826 seconds. No cause is assigned without a separate ablation.

The subsequent [Wastrel comparison](../../benchmarks/results/2026-10-10-wastrel.json)
measured Wastrel + BDWGC at 0.04801 seconds versus our translator's 0.04695 and
Chez's 0.03015. This used GCC `-O3` + LTO with Nix's implicit register clearing
disabled; default GCC `-O2` + LTO measured 0.05263 seconds. The wrapper's outer
loop is itself compiled through WASM/C and uses WASI clocks/output. Its source,
input hashes, compiler revision, commands, raw samples and configuration are
preserved in the report. Wastrel was fetched and built only as a throwaway test.

## Supported boundary

The selected subset consists of immediate integer literals, argument references,
sequences, conditionals, checked binary numeric operators and self recursion.
It excludes closures, arbitrary calls, mutation, rest arguments, multiple values,
and continuations. The rest of the Scheme input is expanded but not executed by
this experiment. Mutation of selected functions or their primitive operators
is rejected; repeated initialization is outside its input contract.

Export adapters take signed31 `i32` inputs, full signed64 `i64` inputs, or `f64`
inputs. Ordinary exports require their integer results to fit signed32; `_i64`
exports preserve wider exact results. Predicate results become 0 or 1 only at
these test adapters. JavaScript callers are trusted to supply correctly typed
arguments before the engine's own numeric coercion. Errors trap with an exported
error code; this is not an implementation of Scheme exceptions or diagnostics.
The one-page exported linear memory is ordinary wasm32 memory, separate from
the engine-managed GC objects; memory64 is not used.
