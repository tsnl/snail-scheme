# Baseline workloads

See [BENCHMARKS.md](../BENCHMARKS.md) for the current native LLVM comparison
against Chez, Guile, and Chibi. **Runtime comparisons exclude compilation time
and process startup**; the report explains Guile's runtime JIT timing separately.

For compiler latency, parser ablations, and the distinction between Chibi and
the generated compiler, see [compilation measurements](../doc/compilation-performance.md).

## Native LLVM CPU experiment

The [LLVM code-generation ablation](results/2026-10-10-llvm-codegen.json)
measures the bounded Wasm-to-LLVM Fibonacci fixture with x86-64 and BDWGC:
unchanged output **0.046632s**, static boolean objects **0.035495s**, cold
out-of-line numeric fallbacks **0.029078s**, and both changes **0.026140s**.
Eight rotating CPU2 rounds check the same work and exclude compilation/startup.
All 43 numeric and tail-call checks pass with the combined changes.
See the [experiment](../experiments/wasm-llvm/README.md#llvm-code-generation-ablation)
for reproduction and scope. The transformations are explicit LLVM-level
prototypes; the general translator and full production pipeline do not yet
implement them.

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
existing adapters, with unchanged timing boundaries; Chibi's clock has millisecond
resolution. The report retains raw samples, commands, tool versions, frozen
artifact hashes, the compiler/runtime source snapshot, and optimizer controls.
This measures CPU Fibonacci, not allocation-heavy workloads or native output
from the new backend.

With the tools described in `doc/backend.md` available:

```sh
./snail-scheme benchmarks/cpu.scm -o build/cpu.wasm
scheme --script benchmarks/chez.scm benchmarks/cpu.scm build/cpu-chez.so
chibi-scheme benchmarks/chibi.scm benchmarks/cpu.scm build/cpu-chibi.scm
taskset -c 2 node scripts/run-wasi.mjs build/cpu.wasm 64
taskset -c 2 scheme --program build/cpu-chez.so 64
taskset -c 2 chibi-scheme build/cpu-chibi.scm 64
```

The scripts and native-target instructions below describe historical LLVM/MIR
measurements; they are not the current WasmGC build interface.

The historical [MIR memory comparison](results/2026-10-10-mir-memory.json) records
eight rotating CPU2 rounds with compilation/startup excluded: immediate literals
and alias scopes reduce Fibonacci runtime from 0.336965 s to 0.318272 s (5.5%).
The final implementation takes 0.6874× Chibi's time and 10.58× Chez's time.
The report retains scratch ablations, artifact/source hashes, samples, and validation
scope; [MIR measurements](../doc/mir.md#acceptance) explain the remaining overhead.

The [WasmGC experiment](../experiments/wasmgc/README.md) compares a bounded
HIR-to-WASM numeric lowering against those native controls, native SSA, Chibi,
and Chez. Its JS/C outer harnesses and dynamic GC-reference representation are
documented separately from the production backend baseline.

These four standalone Scheme programs provide fixed work and checked answers
before type inference or other compiler optimizations are added. Each prints
exactly three lines: its title, a deterministic checksum, and elapsed seconds.
The GC program also reports collection count and cumulative pause time on its
third line. Timing uses the runtime's monotonic nanosecond clock and excludes
the compiler, process startup, initial checks, and final console output. The
timed loop includes repetition control and the fixed-size result comparisons.

From the repository root, with the usual compiler toolchain available:

```sh
nix-shell --run 'benchmarks/run --target native --samples 3 --json build/baseline-native.json'
nix-shell --run 'benchmarks/run --target wasm --json build/baseline-wasm.json'
nix-shell --run 'benchmarks/run cpu memory --repeat 2'
```

Native means `i686-unknown-linux-musl`: a static 32-bit Linux executable. Install
that Rust target and `wasm32-wasip1`; `rust-lld` links native output. The host must
permit executing i386 programs. Chez remains the host-native reference. Earlier
reports below used x86-64 native Snail, so compare matching targets when assessing
the representation change.

The runner compiles with Chibi, builds release executables through Cargo, verifies
the frozen corpus, and checks every program's output. It also compiles the same
benchmark with native Chez Scheme and reports the Snail/Chez elapsed-time ratio.
Release builds use shared Scheme/Rust LTO, matching the optimized CLI default.
Set `SNAIL_SHARED_LTO=0` for the ordinary-link control; custom Rust flags require
that opt-out so they cannot silently replace the shared-LTO settings.
Set `CHEZ` or `--chez PATH` if Chez's `scheme` executable is not on `PATH`, and
`NODE` for the WASI launcher if needed. Chez is required by default; use
`--snail-only` to deliberately omit the comparison. Snail executables are copied to
`build/benchmarks/native/` and `build/benchmarks/wasm/`, so later Cargo builds do
not overwrite an earlier benchmark. Chez objects go to `build/benchmarks/chez/`.
Input hashes are captured before compilation and checked again before recording
a successful build, catching ordinary source edits during a long build.
`--no-build` runs saved artifacts only when their sidecars match the canonical
source, executable bytes, and, for Chez, adapter and compiler version. Older
artifacts without sidecars need one normal rebuild.

Every program accepts one optional positive repetition count. Counts are fixed,
not automatically adjusted to a time budget: comparisons must perform identical
work. The defaults aim for tens to hundreds of milliseconds on a release native
build; different hardware, WASI hosts, GC stress mode, and later compilers will
change the durations. Increase repetitions for more stable samples. JSON reports
record executable hashes, target, count, checked answer, and separate timing
samples. Repository revision and dirty state describe the checkout at measurement
time; they do not claim that a `--no-build` artifact came from that checkout. Host
platform and the external Node version are recorded separately from the WASM hash.
Run on an otherwise idle machine and compare several samples; one timing is not
a performance claim. The runner checks and discards one warmup execution for each
program and target before recording samples. Three samples are recorded by default.
Each invocation is a fresh process: warmup affects host caches, not a retained
Scheme heap or a JIT compiler.

## Reproduce the MIR migration comparison

`benchmarks/mir` compares six frozen native CPU executables: the preceding
LLVM-handler backend with ordinary/shared linking, MIR with the same two link
pipelines, Chibi, and Chez. Its preparation mode verifies baseline source and
executable hashes and records the current reference runtimes. Use the same
Rust/LLVM tools for both source revisions, with `CHIBI` and `CHEZ` set as needed.
The old harness remains available in Git history:

```sh
git worktree add --detach /tmp/snail-mir-baseline f251627
(cd /tmp/snail-mir-baseline && taskset -c 3 benchmarks/rust-instructions --build-only)
benchmarks/mir --prepare-controls /tmp/snail-mir-baseline
taskset -c 3 benchmarks/mir --build-only
benchmarks/mir --measure-only --samples 8
```

Preparation copies the two old LLVM-handler executables from that clean
checkout, compiles the canonical workload with Chez at safe optimization level 2,
and copies the canonical source verbatim for Chibi. The old harness also builds
its historical Rust-handler variants; this comparison does not use those.
`--build-only` then freezes the two MIR executables and verifies that shared LTO
removed every tiny representation-helper call from the linked LLVM artifact.

Run the final command on an otherwise idle host. It pins execution to CPU 2,
warms every executable once, and rotates all six through eight rounds of the
same 64 repetitions. Every run must report checksum `269118144`. Program-internal
timing excludes compilation and process startup; emission and Cargo durations
are recorded separately. Chibi's clock has millisecond resolution here.

Artifacts, commands, tool versions, source/runtime hashes, raw samples, and the
report remain under `build/mir-benchmark/`; the report is `results.json`.
Measurement rejects changed sources, harnesses, executable bytes, or reference
runtimes. Rebuild after editing compiler/runtime sources. The preparatory old
checkout must remain clean at `f251627`; preparation never rewrites it.

The [October 10 final report](results/2026-10-10-mir.json) records eight rotating
rounds after the library-preserving HIR/MIR migration:

| Native implementation | Median seconds, 64 repetitions |
| --- | ---: |
| Previous backend, ordinary linking | 0.448189 |
| Previous backend, shared LTO | 0.392260 |
| MIR, ordinary linking | 5.503267 |
| MIR, shared LTO | 0.334274 |
| Chibi 0.12 | 0.461500 |
| Chez 10.4.1, safe level 2 | 0.029874 |

MIR with shared LTO takes 14.8% less time than the matched previous shared-LTO
backend. Snail/Chibi is **0.7243×** and Snail/Chez is **11.1896×**. The shared
artifact contains no calls to the tiny representation helpers. Ordinary MIR
retains those calls and is much slower; it remains a correctness/control build,
while optimized CLI and normal benchmark builds default to shared LTO. These
numbers describe this CPU workload, not allocation-heavy programs or WASI.
The later streaming-serialization change reproduced byte-identical CPU LLVM and
all six artifacts. The report retains those samples with explicit source-hash
and artifact-hash revalidation, rather than claiming another timing run.

## Chez comparisons

`chez.scm` reads each canonical benchmark with Chez's Scheme reader, validates
its imports, prepends a small compatibility layer, and uses `compile-program`
at safe optimization level 2. Benchmark definitions and their final `(main)`
call are copied as Scheme forms; there is no second implementation of the
workload. All compilation completes before execution and the existing clocks
retain exactly the same timing boundaries. Chez's native record definitions
implement the immutable R7RS records these programs use. See the official
[compilation controls](https://cisco.github.io/ChezScheme/csug/system.html)
for the distinction between safe levels and level 3's unchecked operations.

Each sample pair runs equal repetition counts in separate processes. Pair order
alternates between Chez-first and Snail-first. The reported ratio is
`median(Snail elapsed seconds) / median(Chez elapsed seconds)`;
values above one mean Snail took longer. Both Snail native and Snail WASI compare
against **native Chez on this host**. This is not a comparison of two WASM engines.
The runner writes ratio summaries to stderr while preserving each Snail program's
three-line stdout report. Chez output is checked with the same title/checksum/time
parser and its raw measurements are saved in JSON. Human-readable reports use
seconds with six decimal places. JSON retains its explicitly named `_ms` fields
for compatibility with saved reports; older executables reporting milliseconds
are also accepted.

Chez's CPU, memory, and GC loops may finish in less than a millisecond at the
defaults. The clock uses monotonic nanoseconds, but reports round down to
microseconds; short samples remain sensitive to scheduling and timer overhead.
Use more matched repetitions and several samples when judging an optimization:

```sh
nix-shell --run 'benchmarks/run cpu --repeat 32 --samples 5 --json build/cpu-ratios.json'
```

The runner never silently adjusts work independently for one implementation.
A Chez duration rounded to zero rejects the comparison and requests a larger
repetition count. No universal ratio or cross-workload average is reported.

These ratios compare complete implementations, including their runtime services:

- Chez uses `get-string-n` on buffered text ports. Snail currently loads and
  decodes an entire file when opening it.
- The tested Chez 10.4.1 has no built-in substring search. The adapter supplies
  a straightforward checked character loop, compiled to native code; Snail uses
  Rust's `str::find`.
  Search semantics and inputs match, but the host algorithms differ.
- Both receive the same explicit full-collection requests. Chez has a moving,
  generational collector, unlike Snail's precise nonmoving mark-and-sweep
  collector. The adapter uses actual Chez collection counts and wall-clock
  collection time. Its reclaimed counter measures bytes; Snail's counter measures
  objects. Unavailable adapter fields are `#f`. The canonical GC check requires
  positive reclamation, without assuming either unit. GC pause-time ratios and
  cross-runtime object-count comparisons are deliberately absent. Chez documents
  its [statistics](https://cisco.github.io/ChezScheme/csug/system.html)
  and [collection policy](https://cisco.github.io/ChezScheme/csug/smgmt.html).

JSON schema version 2 retains every checked sample in `measurements`, identified
by implementation, actual target, repetition count, source and executable hashes.
Compared samples also record pair number, execution position, and paired Snail
target. Chez samples include the adapter hash and compilation settings.
`comparisons` contains the two medians, their ratio, and each paired ratio. Host
metadata records Chez's executable, version, and safe optimization level,
alongside the Node version for WASI runs and whether Snail's GC stress mode is
enabled. The artifact sidecars establish source identity; checkout metadata still describes the
measurement context rather than claiming a saved binary's build revision.

## Recorded Chez baseline

The 2026-10-09 measurements used clean commit `f0c4e91`, LLVM O2, Cargo release,
and Chez 10.4.1 at safe optimization level 2. Compilation and process startup are
excluded. The [default report](results/2026-10-09-final-default.json) preserves
all four workloads; the [longer report](results/2026-10-09-final-repeated.json)
uses 16 matched repetitions for CPU, memory, and GC to lengthen Chez's samples.
Both contain three measured pairs per program and target.

Times below are median milliseconds **per repetition**. Each ratio uses the
native Chez samples paired with that Snail target, on this host.

| Program | Repetitions | Snail native ms | Snail WASI ms | Native / Chez | WASI / Chez |
| --- | ---: | ---: | ---: | ---: | ---: |
| CPU | 16 | 126.748 | 194.325 | 276.9 | 424.5 |
| Memory | 16 | 135.815 | 222.152 | 260.9 | 435.5 |
| I/O | 4 | 13.876 | 19.791 | 1.90 | 2.73 |
| GC | 16 | 18.560 | 29.868 | 125.8 | 201.7 |

The I/O comparison retains the documented difference between Rust substring
search and Chez's Scheme scan. CPU, memory, and GC still show large runtime
overheads; see the [profile analysis](../doc/performance-baseline.md).

## Runtime optimization ablations

`ablate` saves compiled runtime variants before measuring them. Build both
snapshots first, changing one runtime feature between them, then stop competing
builds and tests before comparing:

```sh
benchmarks/ablate snapshot before
# Apply one runtime change.
benchmarks/ablate snapshot after --reuse-ir before
benchmarks/ablate compare before after --json build/benchmarks/runtime-change.json
```

Snapshots live under `build/benchmarks/ablations/NAME/`. Existing names are
refused. Each successful snapshot contains native and WASI executables, source
and binary hash sidecars, reusable LLVM, compiler/runtime file hashes, and the
source patch against the recorded Git revision. LLVM reuse verifies compiler
source identity, benchmark source identity, and LLVM bytes before linking the
changed Rust runtime. Failed snapshots may be incomplete and must be discarded.

The comparison uses only saved executables. It checks all answers, warms both
variants, then alternates their execution order for three sample pairs. CPU,
memory, and GC perform 16 repetitions per sample; I/O performs four. JSON retains
every elapsed time, checksum, repetition count, executable hash, source identity,
and position in its pair. Speedup is the before median divided by the after
median. These runs isolate successive runtime changes; the regular runner still
provides the native Chez reference. Preserve the source patches alongside any
checked-in ablation reports so each variant can be reconstructed.

The [2026-10-09 local-storage comparison](results/2026-10-09-local-storage.json)
starts from clean commit `10e9296`. The next comparisons add
[borrowed strings](results/2026-10-09-string-borrow.json), then
[singleton result reuse](results/2026-10-09-single-result.json). Each compares
saved binaries in the same idle measurement window. Three-pair median speedups
are shown as **native / WASI**; these are before/after improvements, not Chez ratios.

| Added change | CPU | Memory | I/O | GC |
| --- | ---: | ---: | ---: | ---: |
| Direct uncaptured locals | 1.20 / 1.33 | 2.65 / 2.23 | 1.09 / 1.04 | 1.24 / 1.23 |
| Borrow strings during inspection | 1.01 / 1.02 | 0.99 / 1.00 | 1.01 / 1.03 | 1.00 / 1.01 |
| Reuse storage for singleton results | 1.03 / 1.07 | 1.05 / 1.07 | 0.99 / 1.06 | 1.02 / 1.06 |

String borrowing removes needless copies but establishes no material speedup in
these samples. Singleton reuse improves CPU and memory in every sample pair;
its native I/O and GC differences remain inconclusive. Three samples describe
this host and workload, not a universal performance guarantee. The cumulative
patches against `10e9296` reconstruct [local-only](results/2026-10-09-local-only.patch),
[local-borrow](results/2026-10-09-local-borrow.patch), and
[local-borrow-single](results/2026-10-09-local-borrow-single.patch).

## Workloads

| Program | Fixed work per repetition | Checksum per repetition |
| --- | --- | ---: |
| `cpu.scm` | Naive recursive Fibonacci at 22, 23, 24, and 25 | 4204971 |
| `memory.scm` | Sieve through 100000, retain prime list, summarize gaps | 454934628 |
| `io.scm` | Search 64 documents separately for five literal phrases | 207395 |
| `gc.scm` | Build 128 cyclic binary trees; retain the last eight | 5460492 |

The CPU case checks its result with an independent iterative Fibonacci oracle,
known values, and recurrence identities. The timed computation remains recursive
and deliberately inefficient, exposing arithmetic and procedure-call costs.
Its inputs are fixed. A future compiler may legitimately precompute them: checking
a checksum detects wrong answers but does not prohibit valid constant folding.

The memory case allocates a boolean vector, mutates composite flags, then builds
an ascending list of all primes. Its summary includes count, sum, last prime,
twin-prime count, and largest gap. Small inputs are checked against independent
trial division; the full result is checked against fixed values on every pass.
This is allocation and traversal work, not a claim to saturate memory bandwidth.
Immutable summary records also produce garbage while the prime list stays live;
a subsequent length check keeps the whole list reachable during summarization.

The I/O case processes documents in filename order, reopening each document for
each of the five queries in order and closing it before the next open. It reads
every file to EOF in 4096-character chunks. A retained suffix
handles matches crossing chunk boundaries; advancing one character after a
match counts overlaps. Small checks cover absent, whole-string, overlapping,
and split matches, including one-character reads. `read-string` and
`string-contains` perform the bulk work in Rust. That deliberately leaves less
Scheme work for a future optimizer to improve and makes this a useful comparison
with the CPU case. The runtime currently loads a text input file when opening
it; results therefore include its eager decoding and allocation costs.

Files are read through the normal operating-system page cache. Repeated runs
typically use cached data. This measures sequential file management, buffered
text input, and native search; it does **not** measure cold storage throughput.
Do not flush system caches or substitute a different corpus during a comparison.
Ports close after each successful search. Runtime errors terminate the standalone
program; the current Scheme subset does not provide exception unwinding.

The GC case keeps parent pointers in its binary trees, so discarded trees contain
cycles. A ring preserves eight roots while newer trees displace old ones. Explicit
collections occur every 32 trees and before checking the retained trees. The
check walks child links, verifies parent identity, depth, leaves, and node labels,
and compares sums against an arithmetic-series oracle. GC time covers root
gathering, marking, and sweeping. The cumulative maximum is not treated as an interval
maximum. The clock encloses both statistics snapshots, keeping the reported GC
interval inside the elapsed interval. Allocation thresholds influence collection
counts, so report the runtime revision alongside these measurements.

## Frozen corpus

`corpus/` contains 64 fictional field notebooks plus one short boundary-test file,
about 322 kB of text. All text was written for this repository; no external data
or license is needed. `SHA256SUMS` fixes the exact bytes. The generator is retained
only to explain and audit the fixture:

```sh
python3 benchmarks/generate-corpus.py
```

The generator is never invoked by the runner. A corpus revision changes the
benchmark and must update its manifest, expected answers, and recorded baseline
together. One search pass reads 1,609,295 ASCII characters, finds 2,534 matches,
and computes a weighted checksum of 207,395. The weights include both document
and query indices, helping detect order changes that an unweighted count would miss.

The benchmark modules intentionally repeat a few short argument and reporting
helpers. Each remains independently readable and executable; a shared benchmark
framework would add imports and hide the small measured operation. More elaborate
statistics, concurrency, adaptive workloads, and production search algorithms
would obscure this initial baseline.

## Cross-language LTO

`benchmarks/lto` compares ordinary release, Rust-only fat LTO, and shared
Scheme/Rust linker LTO on native and WASI targets. It builds all variants before
rotating execution samples and retains linked LLVM bitcode for inspection.
See the [experiment and allocation-design boundaries](../doc/lto-experiment.md)
for tool requirements, flags, timing scope, and the distinction from a future
static builtin representation.

## Fixed-layout runtime

See the [v3 runtime report](../doc/runtime-v3.md) for the matched 32-bit
before/after comparison and its raw samples. Historical native tables above
use 64-bit GNU/Linux and must not be treated as the same target.

The later [chapter-4 stack report](../doc/stack-vm.md) compares the reusable
Scheme stack with the frozen ABI 2 runtime at `03d02cf`, keeping the same
32-bit native and WASI targets. Its
[raw measurements](results/2026-10-09-ch4-stack.json) retain six rotated samples
per implementation, exact source/artifact hashes, and Chez and Chibi ratios.
These measure ordinary release builds without LTO. Scheme/LLVM/Cargo compilation
and process startup are excluded; Node may still optimize Wasm during a fresh
process's timed execution.

## Chibi comparisons

`benchmarks/chibi` compares saved native/WASI Snail executables with Chibi and
Chez on the same CPU, memory, and I/O program bodies. First build the ordinary
benchmark artifacts, then run the comparison:

```sh
benchmarks/run cpu memory io --target native --snail-only --samples 1
benchmarks/run cpu memory io --target wasm --snail-only --samples 1
benchmarks/chibi --snail-directory build/benchmarks --json build/chibi.json
```

Set `CHIBI`, `CHEZ`, and `NODE` if their executables are not on `PATH`. Optional
`--lto-directory build/lto/bin` adds saved shared-LTO CPU/memory executables
from `benchmarks/lto`. All builds finish before the comparison rotates execution
order. Each implementation gets one warmup and four measured samples, with
16 repetitions for CPU/memory and four for I/O. Timers exclude parsing,
compilation, startup, and output. Every answer uses the existing checksum checks.

The [recorded comparison](results/2026-10-09-chibi.json) uses Chibi 0.12's default
execution settings and Chez 10.4.1 at safe optimization level 2. Chibi's R7RS
clock measures wall time in milliseconds; the other clocks are monotonic.
Chibi and Chez are host-native 64-bit builds, while Snail is 32-bit. The I/O
adapter converts Chibi's substring-search cursors to character indices; its
port/search implementation differs from Rust's. GC is omitted because Chibi
does not supply the reclamation counter required by the canonical check.

These initial fixed-layout results put ordinary native32 Snail 20.1× behind
Chibi on CPU and 14.0× on memory, but 7.0× ahead on I/O. Shared LTO reduces the
CPU/memory gaps to 15.2× and 10.7×. See the runtime report for the full table and
any subsequent isolated fixes; these saved artifacts retain their original data.
The subsequent [lazy-error fix](results/2026-10-09-lazy-errors.json) reduces
ordinary native32's gaps to 14.8× Chibi on CPU and 11.1× on memory. Its report
holds LLVM fixed and changes only three eager error constructions in Rust.

## Numeric VM instructions

The [numeric instruction ablation](../doc/numeric-instructions.md) compares
unchanged `e570708` with Rust dispatch cleanup and the new binary numeric VM
instructions on Fibonacci. Five rotating rounds of 64 repetitions, pinned to
one core, give 1.488415 s before and 0.449323 s after: 3.31× faster, 0.975×
Chibi's time and 15.75× Chez's. These are native execution times, excluding
compilation and startup. [Raw samples and artifact/source hashes](results/2026-10-09-numeric-instructions.json)
retain the runtime-only ablation too. This experiment does not include IIFE
inlining, allocator changes, type inference, or shared LTO.
