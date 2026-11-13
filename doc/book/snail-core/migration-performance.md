# Migration measurements

The first comparison records the Java-style migration in #754. The
[lazy runtime follow-up](#lazy-runtime-follow-up) below measures the subsequent
replacement of compile-time evaluation with shared runtime caches.

The migration reduces measured arithmetic, vector-growth and Siegework simulation
time. Retained record lists, pre-sized vectors and incremental expansion cost
more. Nested record updates remain close. These measurements cover the combined
migration: heap objects, counted ownership, callable simplification, constant
evaluation, mutable vectors, compiler optimizations and application changes.
They do not isolate boxing alone.

The comparison is between baseline
[`a1790f347`](https://github.com/tsnl/snail-scheme/commit/a1790f3474a70b14c14196c2c46544265b99e3c8)
and migration
[`d1e321b0f`](https://github.com/tsnl/snail-scheme/commit/d1e321b0feec346aade403f582edf690ad9a8fa5),
measured on 2026-11-13 UTC, including a separate Siegework confirmation.
[Raw samples, compiler hashes and workload artifact hashes](measurements/java-style-20261112.json)
record every observation.

The driver, workload sources and migration compiler sources are all from the
measured migration revision. Its preceding implementation commit is
[`022e4350e`](https://github.com/tsnl/snail-scheme/commit/022e4350e1e3106cc2ff347dc831af9032648c00);
`d1e321b0f` adds artifact and workload provenance to the driver.

## Runtime

Linux x86-64, Intel Core Ultra 7 270K Plus, Node 26.8.1 and V8
14.6.202.34. Execution is pinned to CPU 2. Both compilers link the same Rust
scalar runtime. Each instance runs its entry before measurement, including the
baseline's global initialization. Compilation, initialization, three warm-ups
and forced GC before each sample are outside the timed region. The table gives
medians from 21 alternating baseline/current repetitions, or 11 for Siegework.

| Workload | Baseline | Migration | Time ratio |
| --- | ---: | ---: | ---: |
| Scalar arithmetic, 20 million iterations | 41.231 ms | 13.908 ms | 0.34× |
| Nested record updates, 5 million | 15.960 ms | 16.482 ms | 1.03× |
| Build and fold a retained list of 300,000 records | 1.673 ms | 2.423 ms | 1.45× |
| Allocate, fill and sum 2 million pre-sized elements | 1.981 ms | 2.965 ms | 1.50× |
| Append and read 1 million elements | 9.520 ms | 6.335 ms | 0.67× |
| Siegework, 32 deterministic colonies | 491.840 ms | 341.376 ms | 0.69× |

Pre-sized vectors have the largest measured value-workload regression: about
50% more time than the old array API. Those samples range from 1.913–2.510 ms
before and 2.494–3.088 ms after. Growing a vector takes about 33% less time than
the old mutable-vector API. Record updates cost about 3% more in this run;
retained record lists cost about 45% more.

Siegework's roughly 31% reduction was confirmed in a separate process using
the same linked artifacts and 11 alternating repetitions: 491.352 ms before,
340.884 ms after. The raw data keeps both runs. The simulation migration removes
three conversion copies of fresh local buffers in `distance-field`, `crowding`
and `lit-cells`. Some run repeatedly during simulation. That makes a gain
plausible, but these measurements cannot attribute it among those copy removals,
representation changes and compiler changes.

The microbenchmarks use equivalent logical workloads and verify checksums on
every call. The driver translates the pre-sized workload to baseline `Array`
operations and the growth workload to baseline `MutVector` operations; both
use the single mutable `Vector` in the migration. They are not identical source.
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
RSS is 106,772 KiB before and 104,176 KiB after. These are five measured runs
after two discarded runs, alternating revisions; assembly and linking are
excluded.

`tests/benchmarks/session.sld` measures retained sessions separately. Its
fixture has three emitted modules, 30 small helper functions, an importer and
an entry. Each round builds cold, builds unchanged, then edits a helper body.
The provider variant also declares a class instance. Medians below use 40
rounds after ten warm-up rounds; file edits and printing are outside each
measurement.

Each variant runs its 50 rounds in one Node/Wasm process, creating a fresh
compiler session each round. Within each fixture, all baseline rounds precede
all migration rounds; these measurements are not interleaved, so small
differences may include drift.

| Session operation | Baseline | Migration |
| --- | ---: | ---: |
| Ordinary helper: cold | 4.307 ms | 4.029 ms |
| Ordinary helper: unchanged | 0.951 ms | 1.712 ms |
| Ordinary helper: body edited | 3.101 ms | 3.995 ms |
| Instance provider: cold | 3.969 ms | 4.429 ms |
| Instance provider: unchanged | 0.968 ms | 1.819 ms |
| Instance provider: body edited | 3.694 ms | 4.452 ms |

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
| Scalar loop | 67,248 | 67,284 |
| Record updates | 69,256 | 69,164 |
| Retained record list | 109,292 | 110,412 |
| Pre-sized vector | 83,492 | 83,576 |
| Growing vector | 120,080 | 92,376 |

RSS includes V8, JIT code and allocator capacity. It does not measure live
WasmGC heap size or total allocated bytes. The growing-vector process uses about
23% less peak RSS; the other totals remain close. This does not establish that
individual boxed records use the same memory as inline records.

| Linked Wasm artifact | Baseline bytes | Migration bytes |
| --- | ---: | ---: |
| Microbenchmark | 192,543 | 184,415 |
| Siegework simulation benchmark | 407,742 | 389,031 |
| Self-hosted compiler | 2,817,339 | 3,297,329 |

The compiler grows about 17%. The representation, field-access, borrow and
callable paths lose machinery, while compile-time evaluation and deterministic
shared ownership add machinery. The combined change does not make the whole
compiler smaller.

## Migration scope and reproduction

At the measured revision, excluding this report and its raw-data artifact, the
migration changes 968 tracked files, with 21,376 lines added and 18,758 removed.
Twenty compiler modules change; the remaining work spans core/shell libraries,
both applications, hosts, bootstrap,
fixtures, tooling and the book. Most changed files are test migrations.
README work and effect-name capitalization remain separate roadmap items.

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

## Lazy runtime follow-up

The follow-up removes the compile-time interpreter and graph reconstruction.
Top-level values now initialize once on first read and share the result.
Initializers still require an empty effect row. Cyclic initialization panics;
ordinary recursive functions remain ordinary code. The change also replaces
an evaluator-only enum-case diagnostic with an explicit runtime tag check,
including cases with identical Wasm layouts.

This compares the landed #754 tree at
[`b3b591ae8`](https://github.com/tsnl/snail-scheme/commit/b3b591ae8704833fd2c268a45f2ab6434ace74f2)
with implementation and harness
[`7b77a209e`](https://github.com/tsnl/snail-scheme/commit/7b77a209ee8e8f88a8d03a46bb2159d39d54c037),
measured on 2026-11-13 UTC.
[Raw observations, confirmation runs and hashes](measurements/lazy-runtime-20261112.json)
retain the evidence. Both revisions use identical workload sources and the same
Rust scalar runtime; Siegework's application sources are unchanged.

| Footprint | #754 | Lazy runtime |
| --- | ---: | ---: |
| Linked compiler, including names | 3,297,329 bytes | 2,899,936 bytes |
| Compiler Wasm code-section payload | 1,054,871 bytes | 901,943 bytes |
| Ordinary value-workload module | 184,415 bytes | 184,415 bytes |
| Siegework workload module | 389,031 bytes | 394,611 bytes |
| Lazy-value workload module | 181,083 bytes | 185,949 bytes |

The compiler is **12.05% smaller**, with **14.50% less code-section payload**.
Runtime initializers and guards can enlarge an application's module: Siegework
adds 1.43% here. Across compiler and Chez sources the patch adds 200 lines and
removes 2,757, a net reduction of 2,557. Excluding this report and its raw data,
the change touches 88 files, adding 820 and removing 2,967 lines. The interpreter,
freezing/copying machinery, evaluation budgets and evaluator scalar bridge are
gone; ordinary lifetime/control lowering now handles initializer bodies.

The machine and V8 version match the earlier experiment. Execution is pinned
to CPU 2. Steady-state medians use 21 alternating pairs after three warm-ups;
Siegework uses 11 pairs. Compilation, instantiation, entry and forced GC are
outside runtime timing. Every call verifies its checksum.

| Workload | #754 | Lazy runtime |
| --- | ---: | ---: |
| 20 million scalar-global reads | 4.151 ms | 10.925 ms |
| 100,000 reads from a 64-element aggregate global | 2.360 ms | 0.134 ms |
| Siegework, 32 deterministic colonies | 341.388 ms | 351.025 ms |
| First force of a sum over 20,000 list elements | 0.883 µs | 68.548 µs |

The scalar loop exposes guard overhead, about **2.63×** in this tiny operation.
Aggregate access takes about **0.057×** the time because it reads shared storage
instead of rebuilding a graph. This is an intentional semantic change, not a
measurement of getter dispatch alone. First-force measurements use a fresh
instance for each sample but reuse a warmed compiled module. The old compiler
already computed the sum; its first read is near the timing floor. The new
initializer performs the actual computation. These are first-force costs,
not total startup costs.

Separate processes with reversed module instantiation order confirm the
changed workloads: scalar reads 4.150/11.427 ms, aggregate reads 2.370/0.133 ms,
first force 0.877/68.617 µs, and Siegework 340.901/350.547 ms (before/after).
Siegework is about **2.8% slower** in both runs; this does not isolate lazy
reads from the accompanying enum-case checks. The raw confirmation records
map the harness's positional labels back to the actual compiler variants.

The ordinary arithmetic/record/vector workload is a control: both compilers
emit **byte-identical Wasm**. Its timings still vary between instances. For
example, pre-sized-vector medians are 2.489/2.978 ms, with overlapping ranges
of 2.447–3.076/2.443–3.057 ms. Those differences cannot establish a compiler
regression; the raw samples are retained without attributing speed changes.

Nine alternating pairs of cold compilations per fixture include process startup and
compiler instantiation, but exclude linking. All nine observations contribute
to each median; GNU time resolves elapsed time in 10 ms increments.

| Compile to Wasm text | #754 time / peak RSS | Lazy runtime time / peak RSS |
| --- | ---: | ---: |
| Ordinary value workload | 170 ms / 103,940 KiB | 170 ms / 103,452 KiB |
| Lazy-value fixture, including the 20,000-element sum | 440 ms / 179,312 KiB | 170 ms / 103,280 KiB |

RSS is the compiler process's peak, not live managed heap. Runtime heap usage
and whole-program startup are unmeasured. Cached aggregates and counted owners
now live with their module instance; see [lazy runtime values](types.md#lazy-runtime-values)
for sharing, finalization and relink lifetime rules.

To reproduce, create checkouts at the two revisions named in this section:
`BASE_ROOT` is `b3b591ae8`, and the follow-up checkout is `7b77a209e`.
In each checkout's `nix-shell`, run `make fetch` and `make bootstrap` with Chez.
This prepares the compilers, native linker and scalar runtime. Then run from
the follow-up checkout on a quiet machine:

```sh
node --no-warnings scripts/benchmark-lazy-values.mjs \
  BASE_ROOT BASE_ROOT/build/compiler/snailc.wasm build/compiler/snailc.wasm
```

The default output is `build/migration/lazy-benchmark/results.json`. For the
independent confirmation, run `scripts/benchmark-siege.mjs` and the driver's
`--reads` mode under `taskset -c 2 node --no-warnings --expose-gc`, passing the
current artifact before the baseline artifact. The raw file retains that
argument order explicitly. No Chibi tests or bootstrap were used.
