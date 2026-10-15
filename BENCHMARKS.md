# Benchmarks

**The default benchmark is the entire pinned 57-workload R7RS suite.**
Runtime comparisons exclude compilation and process startup. The separate
[compiler benchmark](#compile-the-compiler) measures compilation itself.

## Run the R7RS suite

The runner uses all 57 workloads from
[ecraven's R7RS benchmarks](https://github.com/ecraven/r7rs-benchmarks), derived
from the Larceny, Gabriel, and Gambit suites. A pinned
[submodule](benchmarks/r7rs-benchmarks) supplies the unchanged benchmark bodies
and correctness predicates. The suite covers allocation, lists, arrays,
strings, IO, numeric computation, and control
flow. Initialize the submodule once:

```sh
git submodule update --init benchmarks/r7rs-benchmarks
```

With Rust/Cargo and the `wasm32-wasip1` target installed:

```sh
nix-shell benchmarks/shell.nix
BENCH_CPU=2 make benchmark
```

`make benchmark` and `python3 benchmarks/r7rs.py` select every workload with
its original upstream input. Default participants are Snail Wasm/V8, Chez,
Guile, and Chibi. Programs compile through `(snail-scheme build)`, including the
required Binaryen optimization. Missing tools and failed builds remain visible.

The [October 12 comparison](benchmarks/results/2026-10-12-native-v8/README.md)
completed all requested attempts for archived Native, V8, and Chez with three
measured rounds. Native passed 48/57, V8 47/57, and Chez 57/57. Among the 47
common successes, V8 won 37 with a 2.00× geometric-mean speedup. This conditional
comparison is not a score for the full suite. Compiler self-compilation took
3.769 s on V8 and 16.829 s on Native; outputs were byte-identical.
The report preserves exact inputs, hashes, failures, and an interrupted earlier
five-system run separately. These are pre-migration baseline measurements.

The strict compiler's [current coverage inventory](benchmarks/strict-suite/capabilities.md)
records measurements for 28 of 57 workloads at their respective compiler
checkpoints, including 27 paired Chez comparisons. The latest
[Puzzle comparison](benchmarks/results/2026-10-14-strict-puzzle-comparison/README.md)
takes 1.157× original Chez time and 2.434× Rust/Wasm time. The
[String storage controls](benchmarks/results/2026-10-14-string-storage/README.md)
show that element width and zeroing do not explain its entire Rust/Wasm gap;
allocation diagnostics remain separate from clean timings.
The preceding [complete-program comparisons](benchmarks/results/2026-10-14-strict-runtime-comparisons/README.md)
cover symbolic differentiation and complex Mandelbrot. The strict ports preserve the original
inputs and repetition counts while documenting their source and representation
adaptations. This is separate from the historical complete-suite runner above.

A separate [current-Wasm LLVM/Immix experiment](benchmarks/results/2026-10-14-current-wasm-llvm/README.md)
executes identical optimized Wasm on both backends. LLVM wins String by 2.19×,
permutations by 2.55× and quicksort by 1.12×; V8 wins complex Mandelbrot by 1.79×.
The permutation result requires a 1 GiB native arena, and deriv cannot compile
through the archived emitter. This is a bounded experiment, not a suite result.

For a smoke check of the entire suite on the reference implementations:

```sh
python3 benchmarks/r7rs.py --systems chez guile chibi --count 1 --rounds 1 --timeout 30
```

`--count` replaces only the upstream iteration count and labels the result as a
**smoke run**. Normal runs keep original inputs. `--timeout` and
`--build-timeout` bound each process, including its descendants. All builds
finish before measurement; successful programs get one discarded preliminary
run followed by rotating measured rounds.

The runner writes JSON, CSV, and a Markdown index under `build/r7rs-report/`,
with a separate SVG/PNG bar chart for each benchmark in `plots/`. Each chart
uses its own zero-based time axis; compare heights within a chart. The index
links every benchmark to its plot.
Every requested cell remains visible, including build errors, incorrect answers,
timeouts, and unavailable implementations. It exits nonzero for failures;
`--allow-failures` permits exploratory runs without changing their recorded
status. Interrupted runs retain incomplete JSON and cannot produce a final plot.
Use `--plot PATH` to regenerate reports from saved data. There is no aggregate
score that silently drops failed benchmarks.

Suite reports stay under `build/`; historical measurements and compiler
comparisons are checked in. Unsupported Scheme libraries or features remain
explicit build failures; integration does not imply that Snail passes the full suite.

### Correctness and coverage

The October 11 native check of main `724cdd6` attempted all 57 workloads with
original inputs. None reached execution: 56 stopped at missing `(scheme read)`;
`mbrotZ` stopped earlier at missing `(scheme complex)`. These are the first
reported blockers, not a complete list of remaining implementation work.
There are no Snail runtime medians for that suite check.

The standard-library implementation's October 11 native correctness smoke check
attempted the same 57 unchanged program bodies, preserving algorithm inputs and
setting only the iteration count to one. It built 56 programs and passed 45
upstream result checks, including `mbrotZ`, FFT, ray pixels, and the file/reader
workloads. Five cases require unsupported `call/cc`; `pi`, `chudnovsky`, and
`compiler` exceed the exact integer range. `takl`, `earley`, `graphs`, and `equal`
hit the 60-second smoke timeout. This validation used native `-O1` without LTO
to shorten builds, so its times are not performance comparison results. That native configuration is historical; current benchmark commands execute Wasm.

The report retains all requested cases, including unsupported libraries and
language features. A successful harness invocation is not evidence that every
Snail case ran. There is no suite-wide speedup when cases are missing.

The upstream `ray` workload also checks every rendered pixel against the
reference image checksum. Its output is under
`build/r7rs-report/cases/ray/<system>/outputs/ray.output`. The complete suite
runs this case along with the other 56 workloads.

Historical single-workload results and their original reproduction commands
are archived in [the native benchmark notes](doc/native-benchmarks.md).

### Studio scene

![Scheme studio ray trace](benchmarks/images/studio.png)

[`studio.scm`](benchmarks/studio.scm) renders colored materials, soft shadows,
and two reflection bounces. The image above is a 960 × 576 Chez reference
render with nine camera rays per pixel and 64 fixed area-light samples.
The scene and sampling are deterministic. Reproduce it with:

```sh
nix-shell benchmarks/shell.nix
python3 benchmarks/render-studio.py --width 960 --samples 3
```

The wrapper writes the actual PPM pixels and a PNG preview under `build/studio/`.
It prints elapsed time including process startup and PPM output, excluding
compilation and PNG conversion. This render took 125.34 seconds on our host
with Chez; that single observation is not an implementation comparison.
Use `--system guile` or `--system chibi` to run the same Scheme program on another
reference implementation; `--width 32 --samples 1` provides a quick check.
This visual showcase is separate from the upstream `ray` timing workload and
has no published Snail timing yet.

## Compile the compiler

The compiler passes child facts through the visitor, with immutable binding
scopes and no expression caches. The historical October 10 simplification shares binding
metadata across checking, closure analysis, and constant evaluation:

| Compiler host | Before | After | Change in time |
| --- | ---: | ---: | ---: |
| Chibi | 14.789 s | 14.408 s | -2.6% |
| Snail Wasm / V8 | 10.661 s | 10.061 s | -5.6% |
| Snail native | 31.901 s | 31.429 s | -1.5% |

![Compiler simplification](benchmarks/results/2026-10-10-compiler-simplification/comparison.svg)

Three rotating measured rounds follow one discarded run per case. All 24 outputs
are byte-identical across both implementations and all three hosts. Wasm and
native sample ranges overlap; these are modest observed changes. See the
[method, runtime refresh, and frozen sources](benchmarks/results/2026-10-10-compiler-simplification/README.md)
and [raw report](benchmarks/results/2026-10-10-compiler-simplification/results.json).
Chibi remains the supported compiler host. WAT writing takes 0.12–0.26 seconds;
compiler preparation and linking are outside the timer.

The earlier [visitor comparison](benchmarks/results/2026-10-10-visitor-typing/README.md)
records the cost of removing expression caches on a different frozen input.
The [indexing experiment](benchmarks/results/2026-10-10-compiler-indexes/README.md)
remains historical evidence. Neither expression caches nor the subsequent HAMT
proposal are in the review stack.

A separate [direct-call and inlining experiment](benchmarks/calls/README.md)
finds a modest benefit from calling known primitive adapters, a larger gain on
a focused native callback workload from closure analysis, and regressions from
raising the global inlining threshold. It does not support a general 5–10× gain.

### Earlier compiler corpus

The measurements below use an earlier, smaller compiler and its original native
pipeline. Their absolute timings are not comparable with the fixed-input
optimization comparison above.

![Compiler self-compilation times](benchmarks/results/2026-10-10-compiler-current/compiler-self.svg)

Three measured rounds on October 10 at commit `5721de9` give medians of
**2.250 seconds for Snail Wasm/V8**, **6.103 seconds for Snail native**, and
**17.400 seconds for Chibi**, on CPU 2 of an Intel Core Ultra 7 270K Plus.
All twelve preliminary and measured outputs match byte for byte.
The [raw measurements](benchmarks/results/2026-10-10-compiler-current/results.json)
retain every sample, tool version, command, and source/artifact hash.
The earlier [Wasm comparison](benchmarks/results/2026-10-10-compiler-self/results.json)
at `dcd5de7` used the previous compiler and tracing implementation.

[`compile-self.py`](benchmarks/compile-self.py) runs Snail's compiler on its own
full Scheme source and imported libraries. It first freezes the sources and
builds the compiler, then times source parsing, library loading, WAT emission,
and file output. The current compiler requires tracing: nested trace work is
included, while opening and finalizing the trace file are excluded. Process
startup, building the compiler executable, assembly, and linking are outside
the timer. Every output must match the assembled, validated Chibi-hosted
reference byte for byte.

```sh
python3 benchmarks/compile-self.py --cpu 2
```

The default comparison is Chibi-hosted versus the compiled Wasm compiler:

```sh
python3 benchmarks/compile-self.py --systems chibi snail-wasm \
  --rounds 3 --output build/compiler-all-report
```

Each case gets one discarded preliminary run and rotating fresh-process
samples on one CPU. The runner records commands, source/artifact hashes, raw
times, and failures in `results.json`, and generates `compiler-self.svg`/`.png`.
Missing tools,
timeouts, or differing output fail the comparison and remain in the report.
Choose a fresh output directory for each run; `--plot PATH` regenerates charts
from saved JSON. Chibi bootstraps the Wasm command; see the
[build guide](doc/book/builds.md) for rebuilding it with Snail.

## Language scope

Snail is not fully R7RS compliant. Reusable, multi-shot continuations are outside
the intended language; the current backend rejects `call/cc` entirely. Single-shot
delimited continuations and coroutines are planned, and other conformance gaps
remain. Unsupported continuation workloads stay visible in the suite report.
See [the roadmap](TODO.md) and [backend guide](doc/backend.md).

[The benchmark guide](benchmarks/README.md) retains historical measurements,
other workloads, and compiler-latency results.
