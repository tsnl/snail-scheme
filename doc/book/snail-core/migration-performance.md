# Migration measurements

The heap-object and ownership migration increases the cost of retained record
lists and incremental expansion. The measured arithmetic loop is faster;
nested record updates and arrays are near parity, and Siegework's simulation
is slightly faster. These are measurements of the combined migration,
including callable simplification, counted ownership, constant evaluation and
compiler optimizations. They do not isolate boxing alone.

The comparison is between baseline
[`a1790f347`](https://github.com/tsnl/snail-scheme/commit/a1790f3474a70b14c14196c2c46544265b99e3c8)
and migration
[`ea158b23d`](https://github.com/tsnl/snail-scheme/commit/ea158b23d6074ff9058975fe4a671afaf7664822),
measured on 2026-11-12 UTC, with Siegework repeated on 2026-11-13 UTC.
[Raw samples, compiler hashes and workload artifact hashes](measurements/java-style-20261112.json)
record every observation.

The orchestration script was first committed with this report in
[`b9c7ace25`](https://github.com/tsnl/snail-scheme/commit/b9c7ace250e779cf8742438e6ca4182d2125871c).
Its compiler and workload sources are those from the measured implementation
revision above. The final harness is
[`bb1568398`](https://github.com/tsnl/snail-scheme/commit/bb1568398d0057387cb8d419314b2d1591235cc3),
which balances the simulation warm-ups. Use those benchmark scripts when
reproducing the experiment, rather than looking for the driver at `ea158b23d`.

## Runtime

Linux x86-64, Intel Core Ultra 7 270K Plus, Node 26.8.1 and V8
14.6.202.34. Execution is pinned to CPU 2. Both compilers link the same Rust
scalar runtime. Each instance runs its entry before measurement, including the
baseline's global initialization. Compilation, initialization, three warm-ups
and forced GC before each sample are outside the timed region. The table gives
medians from 21 alternating baseline/current repetitions, or 11 for Siegework.

| Workload | Baseline | Migration | Time ratio |
| --- | ---: | ---: | ---: |
| Scalar arithmetic, 20 million iterations | 41.042 ms | 14.342 ms | 0.35× |
| Nested record updates, 5 million | 16.398 ms | 16.131 ms | 0.98× |
| Build and fold a retained list of 300,000 records | 1.673 ms | 2.412 ms | 1.44× |
| Allocate, fill and sum 2 million array elements | 2.409 ms | 2.065 ms | 0.86× |
| Siegework, 32 deterministic colonies | 491.016 ms | 476.997 ms | 0.97× |

The array samples overlap: baseline 1.919–2.519 ms and migration
1.982–2.646 ms. Treat that result as near parity rather than a reliable
14% improvement. Record updates also overlap. The record-list workload has
the largest measured regression among these value workloads.

Siegework uses the same compiled artifacts in its repeated measurement, with
checksum discovery included in the baseline's three warm-ups. The raw data
retains the superseded samples, which had one extra baseline warm-up, separately.

The microbenchmarks use identical source and verify checksums on every call.
Siegework runs the corresponding revision's simulation libraries with identical
seed/order logic, advances each colony until its outcome or 2,000 ticks, and
verifies the same checksum. It excludes rendering, browser events and startup;
it is not a frame-rate measurement. Wasmtime supplies independent correctness
checks, but these timing results describe V8 only.

The backend omits ownership operations on a closure only when its capture
layout proves that it owns nothing requiring cleanup. Exact aliases of that
closure preserve the proof. Counted closures, arguments and captures retain
their ordinary lifetime operations. This removes redundant self-retain,
self-release and dropper checks from ordinary recursive loops without changing
their tail-call behavior.

## Compilation and incremental builds

Compiling `tests/benchmarks/value-model.sld` to Wasm text takes a median
**170 ms on both revisions**, including a fresh Node process and compiler
instantiation. GNU time reports in 10 ms increments. The median peak process
RSS is 106,568 KiB before and 103,096 KiB after. These are five measured runs
after two discarded runs, alternating revisions; assembly and linking are
excluded.

`tests/benchmarks/session.sld` measures retained sessions separately. Its
fixture has three emitted modules, 30 small helper functions, an importer and
an entry. Each round builds cold, builds unchanged, then edits a helper body.
The provider variant also declares a class instance. Medians below use 40
rounds after ten warm-up rounds; file edits and printing are outside each
measurement.

Each variant runs its 50 rounds in one Node/Wasm process, creating a fresh
compiler session each round. All baseline rounds precede all migration rounds;
these measurements are not interleaved, so small differences may include drift.

| Session operation | Baseline | Migration |
| --- | ---: | ---: |
| Ordinary helper: cold | 3.933 ms | 4.132 ms |
| Ordinary helper: unchanged | 0.968 ms | 1.693 ms |
| Ordinary helper: body edited | 3.177 ms | 3.939 ms |
| Instance provider: cold | 4.282 ms | 3.806 ms |
| Instance provider: unchanged | 0.962 ms | 1.799 ms |
| Instance provider: body edited | 3.640 ms | 4.245 ms |

Unchanged builds still reuse every checked module and Wasm string, but now
expand current declarations. An ordinary body edit rebuilds all three modules
instead of one because importers can evaluate that function while forcing a
constant. Provider edits rebuild all three on both revisions in this fixture.
In larger projects the migration conservatively invalidates every checked
library when any instance provider changes, including siblings outside explicit
imports. This small fixture does not measure that worst case. The
[compiler chapter](compilers.md#separate-compilation) explains the cache keys.

## Memory and code size

Each memory observation uses a fresh Node process containing one module,
initialization, and four checksum-verified calls with GC before each call.
These are medians of five process high-water RSS observations, in KiB:

| Workload | Baseline | Migration |
| --- | ---: | ---: |
| Scalar loop | 67,284 | 67,356 |
| Record updates | 69,184 | 69,108 |
| Retained record list | 109,208 | 110,396 |
| Arrays | 83,644 | 83,620 |

RSS includes V8, JIT code and allocator capacity. It does not measure live
WasmGC heap size or total allocated bytes, so these close totals do not establish
that individual boxed records use the same memory as inline records.

| Linked Wasm artifact | Baseline bytes | Migration bytes |
| --- | ---: | ---: |
| Microbenchmark | 190,451 | 182,991 |
| Siegework simulation benchmark | 407,742 | 387,537 |
| Self-hosted compiler | 2,817,339 | 3,270,751 |

The compiler grows about 16%. The representation, field-access, borrow and
callable paths lose machinery, while compile-time evaluation and deterministic
shared ownership add machinery. The combined change does not make the whole
compiler smaller.

## Migration scope and reproduction

At the measured revision, the migration changes 952 tracked files, with
20,641 lines added and 18,531 removed. Twenty compiler modules change; the
remaining work spans core/shell libraries, both applications, hosts, bootstrap,
fixtures, tooling and the book. Most changed files are test migrations.
These counts precede this report and its raw-data artifact. README work and
effect-name capitalization remain separate roadmap items.

In the repository's `nix-shell`, prepare the current compiler, native linker
and scalar runtime by building the small benchmark once. Supply an existing
self-hosted baseline compiler built at the baseline revision, then run on a
quiet machine:

```sh
make fetch
./scripts/snail-tool compile -o build/benchmark-prerequisite.wasm \
  tests/benchmarks/value-model.sld
BENCH_CPU=2 node scripts/benchmark-migration.mjs \
  /path/to/baseline /path/to/baseline/compiler.wasm \
  build/compiler/snailc.wasm
```

The driver requires Linux `taskset` and GNU `time`, builds the workloads,
runs the measurements serially, and writes
`build/migration/benchmarks/final/results.json`. It never bootstraps either
checkout. The baseline session fixture uses its required `dyn` spelling and
explicit top-level entry call; the migration fixture uses `Fn` and the root
function entry. Their benchmark operations are otherwise the same. No Chibi
tests or bootstrap were used to obtain these results.
