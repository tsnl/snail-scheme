# Baseline workloads

These four standalone Scheme programs provide fixed work and checked answers
before type inference or other compiler optimizations are added. Each prints
exactly three lines: its title, a deterministic checksum, and elapsed milliseconds.
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

The runner compiles with Chibi, builds release executables through Cargo, verifies
the frozen corpus, and checks every program's output. Set `NODE` for the WASI
launcher if Node is not on `PATH`. Executables are copied to
`build/benchmarks/native/` and `build/benchmarks/wasm/`, so later Cargo builds do
not overwrite an earlier benchmark. `--no-build` runs those existing artifacts;
use it only when deliberately measuring that saved build.

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
program and target before recording samples.
Each invocation is a fresh process: warmup affects host caches, not a retained
Scheme heap or a JIT compiler.

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
