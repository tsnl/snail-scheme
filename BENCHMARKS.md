# Runtime benchmarks

**Runtime comparisons exclude compilation and process startup.** Timers surround
the workload, with correctness checks before it and output afterward. Each sample starts a
fresh process; runtime tiering in V8 or Guile remains included.

## Complete linked Fibonacci programs

Measured October 10, 2026, in eight rotating rounds pinned to CPU 2, after one
discarded run per implementation. Every sample performs 64 repetitions of
Fibonacci inputs 22–25 and checks checksum `269118144`.

| Implementation | Median seconds | Time / Chez |
| --- | ---: | ---: |
| Chez Scheme 10.4.1, safe optimization level 2 | 0.03039 | 1.00× |
| Snail Wasm→LLVM, x86-64, BDWGC | **0.03850** | **1.27×** |
| Snail WasmGC, Node/V8 24.19.0 | 0.08477 | 2.79× |
| Guile 3.0.11, compiled `--r7rs -O2` | 0.09555 | 3.14× |
| Chibi Scheme 0.12 | 0.46300 | 15.23× |

Native Snail takes 27% longer than Chez here, and runs about 2.20× faster than
V8, 2.48× faster than Guile, and 12.03× faster than Chibi. These are observations
for this CPU/call workload, not claims about allocation or other programs.

Every implementation runs the complete canonical [Scheme program](benchmarks/cpu.scm).
Native and V8 consume the **same final Rust-linked Wasm module**. The native
converter is implemented in Scheme and translates both the Scheme and Rust
portions; the outer workload, checks, clock calls, and output remain Scheme.
Clang `-O3` with LTO links the result to the C Wasm/WASI/BDWGC host. No extracted
Fibonacci function, replacement C workload, native Rust rebuild, type inference,
or fixture-specific LLVM patch is involved. Guile compilation precedes timing;
auto-compilation is disabled. Chibi runs the canonical source directly.

The [raw report](benchmarks/results/2026-10-10-binary-runtime.json) retains
samples, commands, tool versions, source/artifact hashes, and environment settings.
The earlier [text-translator baseline](benchmarks/results/2026-10-10-native-production.json)
measured native 0.03821s and Chez 0.02996s; the faster compiler preserves runtime
performance within the variation between these runs. The remaining gap to Chez
has not been causally apportioned. Earlier assembly inspection showed
initialization checks and the guaranteed-tail calling convention, but this
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

## Translation time

Binary Wasm now goes directly through the bounded reader and immutable LLVM
operands. The folded-WAT reader, expression tree, repeated name formatting,
and operand-list reconstruction are gone. The compiler still runs in Chibi.

On the same 253,481-byte linked resource module, three alternating rounds pinned
to CPU 2 measured **69.31 seconds → 2.06 seconds** median
wall time (**33.6× faster**). This measurement **includes Chibi
startup, module loading, reading, lowering, and writing LLVM**. It excludes the
prior Wasm build/disassembly, Clang optimization/linking, and program execution.
It measures translation latency, not the runtime workload in the table above.
The [raw report](benchmarks/results/2026-10-10-binary-translation.json) records
commands, versions, hashes, and each sample.

The first binary implementation took about 3.6 seconds inside the process.
Writing integers directly and putting common operations first in Chibi's linear
`case` dispatch brought that to about 1.4 seconds. That last improvement is
roughly 2.6×, not another 10×. These development timings excluded startup and
were not the controlled process comparison above.

To reproduce the current translation measurement, first generate the resource
fixture with `scripts/test-native`, then time just the translator:

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
