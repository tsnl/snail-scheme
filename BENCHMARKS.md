# Runtime benchmarks

**Compilation and process startup are excluded.** Timers surround the workload,
with correctness checks before it and output afterward. Each sample starts a
fresh process; runtime tiering in V8 or Guile remains included.

## Complete linked Fibonacci programs

Measured October 10, 2026, in eight rotating rounds pinned to CPU 2, after one
discarded run per implementation. Every sample performs 64 repetitions of
Fibonacci inputs 22–25 and checks checksum `269118144`.

| Implementation | Median seconds | Time / Chez |
| --- | ---: | ---: |
| Chez Scheme 10.4.1, safe optimization level 2 | 0.02996 | 1.00× |
| Snail Wasm→LLVM, x86-64, BDWGC | **0.03821** | **1.28×** |
| Snail WasmGC, Node/V8 24.19.0 | 0.08358 | 2.79× |
| Guile 3.0.11, compiled `--r7rs -O2` | 0.09426 | 3.15× |
| Chibi Scheme 0.12 | 0.46050 | 15.37× |

Native Snail takes 28% longer than Chez here, and runs about 2.19× faster than
V8, 2.47× faster than Guile, and 12.05× faster than Chibi. These are observations
for this CPU/call workload, not claims about allocation or other programs.

Every implementation runs the complete canonical [Scheme program](benchmarks/cpu.scm).
Native and V8 consume the **same final Rust-linked Wasm module**. The native
converter is implemented in Scheme and translates both the Scheme and Rust
portions; the outer workload, checks, clock calls, and output remain Scheme.
Clang `-O3` with LTO links the result to the C Wasm/WASI/BDWGC host. No extracted
Fibonacci function, replacement C workload, native Rust rebuild, type inference,
or fixture-specific LLVM patch is involved. Guile compilation precedes timing;
auto-compilation is disabled. Chibi runs the canonical source directly.

The [raw report](benchmarks/results/2026-10-10-native-production.json) retains
samples, commands, tool versions, source/artifact hashes, and environment settings.
The remaining gap to Chez has not been causally apportioned. Assembly inspection
shows initialization checks and the guaranteed-tail calling convention, but this
comparison does not isolate their individual cost. The converter preserves
Wasm's i31 width explicitly and keeps immutable numeric global objects distinct.

## Reproduce the current comparison

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
[native execution](doc/native.md). Record changed tools when comparing results;
the Nix shell and Rust stable channel are not a frozen benchmark toolchain.

Build scripts can also produce just the two Snail artifacts:

```sh
chibi-scheme -I src benchmarks/native-build.scm
build/native-benchmark/cpu 64
node --no-warnings scripts/run-wasi.mjs build/native-benchmark/cpu.wasm 64
```

Native **compilation remains slow**. A full resource fixture, 3.70 MB folded WAT
to 5.81 MB LLVM, took 68.8 seconds in Chibi after removing redundant intermediate
string construction. The resulting LLVM matched the tested artifact byte for
byte. Earlier concurrent builds spent 127–221 seconds in translation and about
3 seconds in Clang; these are observations, not a controlled compile-time
ablation. None of that time enters the runtime table.

## Language scope

Snail Scheme is not fully R7RS compliant. We deliberately leave reusable,
re-entrant (multi-shot) continuations out of the intended language. Calling
these a “1% feature” expresses a design priority, not a measured percentage
of Scheme programs. `call/cc` is currently unsupported; single-shot delimited
continuations and coroutines are planned. Other conformance gaps remain.
The benchmark does not isolate the cost of continuations. See [TODO.md](TODO.md).

## Historical bounded experiment

The earlier [Guile comparison](benchmarks/results/2026-10-10-guile.json) measured
a bounded translator with an extracted Fibonacci function and a C outer harness:

| Implementation | Median seconds | Time / Chez |
| --- | ---: | ---: |
| Tuned native prototype | 0.02676 | 0.89× |
| Chez | 0.02994 | 1.00× |
| Baseline native prototype | 0.04659 | 1.56× |
| Guile | 0.09490 | 3.17× |
| Chibi | 0.46000 | 15.37× |

Its [LLVM ablation](benchmarks/results/2026-10-10-llvm-codegen.json) used static
boolean objects and `cold noinline` numeric fallbacks. Those fixture-specific
results do not describe the complete linked compiler route above. The historical
sources, build/check scripts, and detailed reproduction recipe remain available
at their recorded revision:

```sh
git worktree add --detach /tmp/snail-benchmark-repro feb1503a72f8c430227cbb3d959ca7bf48873ea4
cd /tmp/snail-benchmark-repro
# Follow BENCHMARKS.md in that checkout.
```

The [benchmark guide](benchmarks/README.md) also retains the production Wasm
optimizer comparison and describes the allocation workload.
