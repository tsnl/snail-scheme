# Benchmark suite

Run the complete pinned R7RS suite by default:

```sh
git submodule update --init benchmarks/r7rs-benchmarks
nix-shell benchmarks/shell.nix
BENCH_CPU=2 make benchmark
```

`make benchmark` and `python3 benchmarks/r7rs.py` run the same 57 workloads
across Snail Wasm/V8, Chez, Guile, and Chibi. Original upstream inputs and three
rotating measured rounds are the defaults. Each successful case first receives
one discarded preliminary run. Compilation and process startup are excluded
from workload times.

The runner saves raw JSON, a CSV table, a Markdown index, and one SVG/PNG plot
per workload under `build/r7rs-report/`. Unsupported cases, failed builds,
incorrect answers, and timeouts remain in the matrix and cause a nonzero exit.
Regenerate reports from saved data without running workloads:

```sh
python3 benchmarks/r7rs.py --plot build/r7rs-report/results.json
```

`--count 1 --rounds 1` is an explicitly labelled smoke check, still covering
all workloads. `--systems` and `--benchmarks` select an explicit diagnostic
subset; ordinary benchmark commands never select a small showcase by default.
See [BENCHMARKS.md](../BENCHMARKS.md) for timing boundaries and coverage.

The explicit [five Rust/WASI references](wasm-reference/README.md) preserve the
algorithms and original inputs of `cat`, `lattice`, `wc`, `graphs`, and `deriv`.
Their [checked report](results/2026-10-13-wasm-five-reference/README.md) supplies
same-window Chez controls and separates the prior Snail measurement batch.

The [strict-source cat experiment](strict-cat/README.md) compiles a typed scalar
copy loop and compares it with the old generated loop and a hand-written Wasm
control using the same runtime. Its [checked report](results/2026-10-13-strict-source-cat/README.md)
retains complete source/artifact identities and separate functional validation.

The [strict kernel subset](strict-suite/README.md) measures eleven attempted
ports against original Chez programs and adds explicit Chez flonum controls.
Its [report](results/2026-10-13-strict-kernels/README.md) records ten passing
workloads, the default-stack Ackermann failure, and the remaining suite coverage.
The [strict-source wc report](results/2026-10-13-strict-source-wc/README.md)
separately measures character counting inside the original benchmark harness.

Later strict ports and their measurement checkpoints are tracked in the
[coverage inventory](strict-suite/capabilities.md): 34 measured workloads,
33 with paired Chez controls. The
[Tail report](results/2026-10-14-strict-tail-comparison/README.md) records
4.900 s for all 50 complete 4,460,056-byte file reversals: 5.173× original Chez
time, 2.712× adapted Chez and 22.658× Rust/Wasm. Every output byte and separate
retained-file work checks pass; line I/O, storage and reclamation differences
remain explicit. The preceding
[Mazefun report](results/2026-10-14-strict-mazefun-comparison/README.md) records
0.629 s for all 10,000 complete 11 × 11 mazes: 1.619× faster than original
Chez, 1.425× faster than adapted Chez, and 3.691× faster than this Rust/Wasm
reference. Complete predicates pass; persistent Rc/GC and layout differences
remain explicit. The preceding
[Ray report](results/2026-10-14-strict-ray-comparison/README.md) records 0.129 s
for all 50 complete renders: 6.584× faster than original Chez and 6.181× faster
than the adapted source on Chez; Rust/Wasm is 2.387× faster than Snail.
Complete images and separate retained-work diagnostics pass. The
[Destruc report](results/2026-10-14-strict-destruc-comparison/README.md) records
3.382× original Chez time, 1.344× adapted Chez and 1.167× Rust/Wasm for all
4,000 original invocations and the complete ten-row predicate. Adapted Chez
itself takes 2.517× original Chez time; source/ownership changes remain explicit.
The
[Lattice report](results/2026-10-14-strict-lattice-comparison/README.md) records
1.647× original Chez time and 1.815× Rust/Wasm time for the original count ten,
problem 44 and result 120549, with source/storage differences documented. The
[Puzzle report](results/2026-10-14-strict-puzzle-comparison/README.md) records
1.157× original Chez time and 2.434× Rust/Wasm time. The
[String block comparison](results/2026-10-14-string-block-comparison/README.md)
improves the original Unicode workload 5.04×. Separate
[size controls](results/2026-10-14-string-size-controls/README.md) expose 2–22%
overhead on smaller growth/copy inputs; the representation remains under review.
The preceding
[runtime comparison report](results/2026-10-14-strict-runtime-comparisons/README.md)
adds full symbolic differentiation and complex Mandelbrot, plus callback and
collector-policy ablations.

The [restored LLVM/Immix comparison](results/2026-10-14-current-wasm-llvm/README.md)
runs four current optimized Wasm artifacts on both V8 and native LLVM. It records
three native wins, one V8 win, and the archived emitter/capacity failures at that
checkpoint. A later [String layout comparison](results/2026-10-14-string-block-native-comparison/README.md)
changes that workload's winner: V8 runs the improved Wasm 2.27× faster. The
earlier reports used an isolated emitter. The first production
[native64 Ray comparison](results/2026-10-14-native64-ray-comparison/README.md)
uses the restored production build command, mandatory Binaryen optimization,
checked C linkage and the shared Rust runtime. For all 50 original renders,
native takes 0.193 s versus 0.128 s on V8 (1.512× the time); complete images and
separate file/iteration diagnostics pass on both targets.
The matched [empty-constructor comparison](results/2026-10-14-empty-variant-ray/README.md)
then shares immutable zero-field cases: V8 improves from 0.127 s to 0.095 s,
and native from 0.194 s to 0.093 s, with all 36 complete images verified.
Native allocation requests fall from 35.0 million to 2.30 million in separate
diagnostic runs. This reaches approximate parity on Ray; the independent
[Mazefun comparison](results/2026-10-14-native64-mazefun-comparison/README.md)
still records native at 1.869× V8's time on its frozen common program.

The [Nucleic comparison](results/2026-10-14-strict-nucleic-comparison/README.md)
records 0.220574 s on V8 for all 50 original searches, 3.359× faster than original
Chez. Native takes 0.297789 s, 1.350× V8 time. All 20 full-count observations and
329 source/artifact identities pass; this is a workload result, not a suite-wide
speed claim.

The [complete Nucleic preparation](results/2026-10-14-strict-nucleic/README.md)
preserves all 50 searches, the full coordinate database and original ratio
predicate. Complete ordered-solution and mutation probes pass in both Chez
controls, raw/optimized linked Wasm and actual native execution. Its archive
separates diagnostic compiler work from performance measurements.

## Compiler throughput

[`compile-self.py`](compile-self.py) separately measures the compiler compiling
its own frozen Scheme sources, checking every output byte against Chibi. Its
implementation preparation, process startup, assembly, and linking are outside
the timer. See [the compiler benchmark](../BENCHMARKS.md#compile-the-compiler).

The [global interner report](results/2026-10-11-symbol-interner/README.md)
separates the interner improvement from the native heap policy and compares
Fibonacci execution with Chez and Chibi. It preserves frozen compiler inputs,
validated outputs, profiles, and heap controls.
The [native lowering audit](results/2026-10-11-native-lowering/README.md) uses
restored default heap growth and separates LLVM lowering, allocation policy,
Binaryen preprocessing and GC costs. Its small constructor prototype remains
experimental because its measured effects are mixed.
The [compiler simplification report](results/2026-10-10-compiler-simplification/README.md)
records the preceding shared binding analysis and typing workloads.
The earlier [visitor comparison](results/2026-10-10-visitor-typing/README.md)
records the cost of passing type facts directly through the visitor. [`compare-compilers.py`](compare-compilers.py)
requires identical output between implementations; the historical
[indexing report](results/2026-10-10-compiler-indexes/README.md) uses that stricter check.
The [call experiment](calls/README.md) keeps the throwaway flow/inlining pass in a
patch with measurements and reproduction instructions. [`render-studio.py`](render-studio.py) renders the
[studio scene](../BENCHMARKS.md#studio-scene) and reports its elapsed time.

## Historical workloads and visual showcase

The standalone Fibonacci and prime-sieve runners are retired. The CPU fixture
and Chez program builder remain inputs to the explicit typing diagnostics below.
Their measurements remain in [`results/`](results/) and
[the historical native benchmark notes](../doc/native-benchmarks.md).
[`reproduce.py`](reproduce.py) reproduces an older experiment in its pinned
historical checkout; it is not the default benchmark command.

[`render-studio.py`](render-studio.py) renders the separate deterministic
[studio scene](../BENCHMARKS.md#studio-scene). It is a visual showcase, not a
replacement for running the full suite.

## Typing and i32 specialization

The [historical complete-program comparison](results/2026-10-11-symbol-interner/README.md#running-fibonacci-on-snail-chez-and-chibi)
uses the same emitted WAT for native and Wasm and includes Chez and Chibi on
both Fibonacci workloads. Run `python3 benchmarks/typing/compare-schemes.py`
inside the benchmark Nix shell for the current Wasm-only comparison. The native
comparison is reproducible on the LLVM archive branch.

The [previous runtime refresh](results/2026-10-10-compiler-simplification/README.md#runtime-measurements)
measures recursive i32 Fibonacci at 0.173772 s (2.26× faster than
untyped Scheme), three-parameter tail Fibonacci at 0.114204 s (2.53×),
and boxed occurrence typing at 0.029675 s (1.64× faster than guarded).
The isolated tail worker remains 32.5% slower than checked C-to-Wasm.
The following tables retain the earlier production baseline for comparison.

The [implemented checker and optimizations](../doc/typing-prototype.md) were
measured at commit `e3d916657357e8fb0a64a075fdb3161d3e24e5d3` with no tracked
source changes. These October 10 measurements use an Intel Core Ultra 7 270K
Plus, Node 24.19.0, Clang 22.1.8, and Binaryen 132. Eight rotating rounds run on
logical CPU 2 after one discarded full run per variant. Every sample starts a
fresh process, runs untimed correctness checks, and verifies its checksum.
Compilation and process startup are excluded; V8's default tiering remains
enabled. The tail workload also performs a full in-process warmup, described below.

### Recursive Fibonacci with two parameters

The Fibonacci workload uses two uncurried arguments, `n` and `offset`. The base
case returns `(+ n offset)` and both recursive calls retain `offset`; it is not
an unused argument. Timed calls use offset zero, inputs 22–25, and 256 repetitions,
with checksum `1076472576`. The integration suite also tests a nonzero offset.
This differs from the older one-argument, 64-repetition measurements below.

| Fibonacci variant | Median seconds |
| --- | ---: |
| Untyped, guarded | 0.392100 |
| Untyped, check elimination | 0.392312 |
| ExactInteger signature, guarded | 0.499025 |
| ExactInteger signature, check elimination | 0.392319 |
| i32 signature, guarded | 0.472806 |
| i32 signature, check elimination, boxed | 0.472713 |
| **i32 signature, specialized** | **0.173662** |
| Native C, `-O3` | 0.068725 |
| Native C, checked result range | 0.107269 |
| Native C, `-fno-optimize-sibling-calls` | 0.104731 |
| C-to-Wasm, `-O3` | 0.095643 |
| C-to-Wasm, checked result range | 0.171902 |

The specialized workload is **2.26× faster than untyped Scheme**, **2.72× faster
than boxed i32**, and within about 1% of checked C-to-Wasm. The
annotation is `(-> i32 i32 i32)`; it means checked signed 32-bit arguments and
result, with widened intermediates, not wrapping arithmetic. Check elimination
alone is neutral for untyped and boxed i32 Fibonacci. For ExactInteger it removes
21% of elapsed time relative to the guarded variant, restoring roughly the
untyped baseline. Fewer emitted checks do not necessarily mean faster execution.

Snail executes the complete Scheme workload through the production WasmGC
pipeline. Native C uses the same weighted outer loop and a separately compiled
kernel, without LTO. C-to-Wasm uses the same kernel on the same Node engine,
with a JavaScript outer loop; that driver differs from the Scheme workload.
Every timed input is in range, including for unchecked C. The checked C kernel
widens addition and tests the i32 result range, but uses abort/trap on failure;
it is a performance control, not a replacement for Scheme error behavior.

Specialized Snail still takes **2.53× native C's time**, or **1.62× checked native
C's time**. Inspection of Clang's assembly shows that unchecked C turns one
recursive branch into a loop with an accumulator. Checked C retains two calls
and the result-range test; disabling sibling-call optimization on unchecked C
also brings its time close to checked C. An i32 signature alone cannot prove
that all Fibonacci inputs avoid overflow. Removing these tests or reassociating
the recursion requires preserving failure behavior or proving tighter input
bounds. The current pass does neither for this non-tail recursion. The checked C-to-Wasm comparison
also shows a remaining target/backend difference from native C; individual
costs have not been profiled. No native Snail executor is measured here.

### Tail Fibonacci with three parameters

The efficient version carries both accumulators through an uncurried tail call:

```scheme
(: fibonacci (-> i32 i32 i32 i32))
(define (fibonacci n a b)
  (if (< n 2)
      (if (<= n 0) a b)
      (fibonacci (- n 1) b (+ a b))))
```

All three parameters are used. Returning `b` at one avoids computing an unused
next accumulator, allowing F46 to succeed without first overflowing on F47.
The tests also check nonstandard seeds, F47 failure, and a million iterations
with zero accumulators. Self tail calls lower to a Wasm loop: all operands are
saved before any parameter is replaced, then checked narrowing establishes the
next iteration's i32 domains. Proper tail recursion bounds stack use; it does
not establish that an accumulator fits the declared numeric range.

Each timed sample repeats the weighted inputs 22–25 **1,048,576 times**: 4,194,304
top-level Fibonacci calls and 94,371,840 self tail updates, with checksum
`4409231671296`. Every implementation first executes the same number of
repetitions untimed in that process and validates the warmup checksum. This is
in addition to the discarded fresh-process run. The recursive Fibonacci and
occurrence workloads retain their small in-process correctness checks instead
of this full warmup; reports record `warmup_repetitions` explicitly.

| Tail Fibonacci variant | Median seconds |
| --- | ---: |
| Untyped, guarded | 0.287597 |
| Untyped, check elimination | 0.289357 |
| ExactInteger signature, guarded | 0.348353 |
| ExactInteger signature, check elimination | 0.294258 |
| i32 signature, guarded | 0.310597 |
| i32 signature, check elimination, boxed | 0.311953 |
| **i32 signature, specialized, complete Scheme workload** | **0.117819** |
| **Specialized i32 worker, JavaScript driver** | **0.058404** |
| Native C, `-O3` | 0.009597 |
| Native C, checked argument ranges | 0.033144 |
| Native C, `-fno-optimize-sibling-calls` | 0.063777 |
| C-to-Wasm, `-O3` | 0.013884 |
| C-to-Wasm, checked argument ranges | 0.043914 |

The complete specialized workload is **2.46× faster than untyped Scheme** and
**2.65× faster than boxed i32**. Its time is still **2.68× checked C-to-Wasm** and
**3.55× checked native C**. The isolated worker takes **1.33× checked C-to-Wasm's
time**. This worker measurement exports the existing pure i32 function from a
benchmark-only module and uses exactly the same JavaScript driver as C-to-Wasm.
It bypasses the boxed Scheme entry and outer driver; runtime initialization
finishes before timing. It does not add a compiler API or measure the full
Scheme program. Both C versions use matching three-argument source kernels;
native compilation keeps driver and kernel in separate translation units,
without LTO. Checked C widens arithmetic and checks entry ranges, with different
failure behavior from Scheme; the timed inputs all succeed.

The isolated worker and complete program have different performance histories.
The [earlier `return_call` implementation](results/2026-10-10-typing-tail-calls-fibonacci.json)
measured 0.096455 seconds for the worker and 0.101298 for the complete program.
The current worker is faster, but **the complete Scheme workload regressed**.
The base-case layout and warmup policy also changed, so these historical reports
do not isolate the loop transformation's effect. With the current compiler but
[without full in-process warmup](results/2026-10-10-typing-tail-tiering.json), the
times were 0.060522 and 0.121440. Full warmup does not remove the gap. Diagnostic
runs with V8's baseline compiler disabled reduced complete-program time to about
0.099 seconds, indicating sensitivity to tiering. Those two-run diagnostics are
not a full profile. The boxed driver, calls across representation boundaries,
and engine code generation remain further work; their individual costs have
not been established.

### Occurrence check elimination

The occurrence workload alternates the arms of `(U String <box>)`, reading a
preallocated eight-character string and a record containing 13. At 512
repetitions it performs 5,120,000 loop iterations, 10,240,000 union-dispatch calls,
and checks checksum `107520000`:

| Occurrence variant | Median seconds |
| --- | ---: |
| Guarded | 0.129638 |
| **Check elimination, boxed** | **0.064886** |

This is **2.00× faster**, with no representation specialization. The optimized
module uses known-string and known-record access helpers. It retains required
field-result, bounds, and overflow checks. The reports also count helper call
sites in emitted user/library workers before Binaryen: single-value calls fall
from 729 to 281 here. Those are static sites, exclude checked entry wrappers,
and are not counts of checks executed or surviving optimization.

The optimized time is essentially the prototype's 0.065398 seconds. The larger
speedup ratio comes from the guarded path's higher cost after correcting typed
tail-result enforcement, rather than another improvement to the optimized path.

### Reports and reproduction

Raw samples, source hashes, artifact hashes/sizes, commands, and tool versions
are in the earlier [recursive Fibonacci report](results/2026-10-10-typing-production-fibonacci.json),
[tail Fibonacci report](results/2026-10-10-typing-production-tail-fibonacci.json),
and [occurrence report](results/2026-10-10-typing-production-occurrence.json).
The historical prototype [Fibonacci](results/2026-10-10-typing-fibonacci.json) and
[occurrence](results/2026-10-10-typing-occurrence.json) reports remain available.
An intermediate design that ran a result-check helper on every return regressed
boxed Fibonacci to 0.770757 seconds; its
[Fibonacci](results/2026-10-10-typing-return-checks-fibonacci.json) and
[occurrence](results/2026-10-10-typing-return-checks-occurrence.json) reports record
why it was replaced. The final emitter checks local returns inline and creates
one shared checking context only when a guarded tail transfer requires it. The
[measurement script](typing/measure.py) contains the build commands. With the
tools in [doc/backend.md](../doc/backend.md), Clang, Python 3, and `taskset`:

```sh
python3 benchmarks/typing/measure.py --output /tmp/typing-fibonacci.json
python3 benchmarks/typing/measure.py --workload tail-fibonacci --output /tmp/typing-tail-fibonacci.json
python3 benchmarks/typing/measure.py --workload occurrence --repetitions 512 --output /tmp/typing-occurrence.json
scripts/test-typing
```

Use `--cpu` for an available logical CPU and `--output` to save a new report.
`TYPING_CC` selects native Clang; `TYPING_WASM_CC` selects Wasm Clang. The script
unwraps Nix's native Clang wrapper for Wasm so native linker/hardening flags do
not leak into that target. The guarded mode disables optional type optimizations,
the boxed mode enables check elimination, and the optimized mode also enables
i32 specialization. All modes enforce the same declared type contracts.

## Historical native LLVM CPU experiment

The [LLVM code-generation ablation](results/2026-10-10-llvm-codegen.json)
measures the bounded Wasm-to-LLVM Fibonacci fixture with x86-64 and BDWGC:
unchanged output **0.046632s**, static boolean objects **0.035495s**, cold
out-of-line numeric fallbacks **0.029078s**, and both changes **0.026140s**.
Eight rotating CPU2 rounds check the same work and exclude compilation/startup.
All 43 numeric and tail-call checks pass with the combined changes.
[`reproduce.py`](reproduce.py) rebuilds this historical comparison in a worktree
at its recorded revision and generates plots from checked samples. The transformations were LLVM-level prototypes; they are not
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

The builders for this historical report and the retired standalone allocation
workload belong to their recorded revisions. Reproduce those snapshots using
[the historical native benchmark notes](../doc/native-benchmarks.md).
The default R7RS suite includes allocation and IO workloads. WasmGC does not
expose portable collection counters; compiler throughput can also be inspected
with the always-on [Chromium traces](../doc/tracing.md).
