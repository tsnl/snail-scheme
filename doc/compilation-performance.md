# Compilation measurements

These measurements separate the compiler host, parser costs, and output toolchain.
The 2026-10-09 combinator change replaces `pmap`'s temporary parser with a direct
result transformation and `tuple`'s chain of temporary parsers with a local loop.
Reader/result behavior is unchanged, including failure identity and reentrancy.

## Host and build mode

`./snail-compile` runs the compiler under Chibi. Compiling `compile.scm` and then
running it executes Scheme through the generated code and Rust runtime instead.
Run mode defaults to a debug Rust runtime; place `--release` before `--` to
benchmark the generated compiler with an optimized runtime:

```sh
./snail-compile examples/fibonacci.scm /tmp/fibonacci.ll --timing
./snail-scheme src/snail-scheme/compile.scm --release -- . examples/fibonacci.scm /tmp/fibonacci.ll --timing
```

The second command first builds the compiler executable. Its forwarded
`--timing` measures that executable compiling Fibonacci; it excludes building
the compiler itself. A later Cargo invocation still has to turn its LLVM output
into an executable. Generated LLVM receives O2 even when the Rust runtime is
debug-built.

After the combinator change, the generated compiler was executed in native
release, native debug, and WASI release builds. All emitted Fibonacci LLVM
byte-identical to Chibi's output. Native release took 4.249 s, native debug
41.514 s, and WASI release 6.494 s in these single validation runs. These
demonstrate the build-mode distinction; they are not before/after optimization
benchmarks.

## Combinator ablations under Chibi

The baseline is `6d57821`, with immutable grammar values already in place.
Five fresh-process samples per variant used the same 16,801-character
`bootstrap/scheme/base.sld`. Execution order rotated between variants. Parsing
excludes imports, grammar initialization, and file reading; each parsed result
was compared with Chibi's reader afterward.

| Variant | Median parse seconds | Reduction from baseline |
| --- | ---: | ---: |
| Baseline | 1.902 | — |
| Direct `pmap` | 1.720 | 9.6% |
| Direct `tuple` | 1.439 | 24.3% |
| Both | 1.411 | 25.8% |

The benefits overlap because the old `tuple` repeatedly constructed `pmap`
parsers. The combined change removes those parser constructions and intermediate
success results while preserving the original child failure object.

Compiling a frozen copy of the compiler sources to LLVM with the normal Chibi
entry point took **23.637 s before and 16.563 s after**, a **29.9% reduction**.
These are medians of three alternating fresh-process samples, including startup
and LLVM file output, excluding Cargo. All six LLVM files were byte-identical.

| Chibi compiler stage | Before, seconds | After, seconds |
| --- | ---: | ---: |
| Entry parsing | 0.035 | 0.012 |
| Expansion, including imported-source parsing | 18.402 | 11.658 |
| Lowering | 0.078 | 0.069 |
| LLVM emission | 4.794 | 4.449 |

The [raw report](../benchmarks/results/2026-10-09-parser-combinators.json) records
individual samples, source hashes, diagnostic probes, and their limitations.
Instrumentation materially changed Chibi's allocation/GC behavior on this
workload: the detailed profiling harness even suggested an end-to-end regression
that did not occur through the normal entry point. Diagnostic timings identify
work to inspect; the uninstrumented entry point supplies latency comparisons.

## Numeric-start guard under Chibi

The next change adds one non-consuming check before the numeric grammar. Its
possible first characters are ASCII decimal digits, `#`, `+`, `-`, and `.`.
Candidates still run the original grammar; the guard preserves signed specials,
complex numbers, radix/exactness prefixes, and number-versus-symbol boundaries.
Both parsers remain immutable values constructed once during library loading.

Individual alternatives already reject `hello` at its first character. The
cost is retrying that character through nested choices: an instrumented count
found **31 character checks and 72 parse-result constructions** in one call to
the original numeric-spelling parser, without advancing its reader. The guard
reduces this to **one check and two results**. An ordinary identifier attempts
the numeric grammar twice, once as a possible number and again in the identifier
rule's exclusion. Parsing `hello` as an atom therefore drops from 88 checks and
200 results to 28 checks and 60 results. These counts come from separate
diagnostic copies; timing runs contain no instrumentation.

The baseline is `f1838c2`, with both combinator improvements already applied.
Five alternating fresh-process pairs used the same `base.sld` as above. Three
alternating pairs compiled a frozen copy of the baseline compiler sources with
the normal Chibi entry point, excluding Cargo. All six LLVM outputs were
byte-identical and the output passed LLVM verification.

| Workload | Before, seconds | After, seconds | Reduction |
| --- | ---: | ---: | ---: |
| Parse `bootstrap/scheme/base.sld` | 1.396 | 0.513 | 63.3% |
| Compile frozen compiler sources to LLVM | 16.949 | 10.265 | 39.4% |

Stage medians for that full compilation were:

| Chibi compiler stage | Before, seconds | After, seconds |
| --- | ---: | ---: |
| Entry parsing | 0.013 | 0.004 |
| Expansion, including imported-source parsing | 11.422 | 4.690 |
| Lowering | 0.084 | 0.076 |
| LLVM emission | 5.053 | 5.009 |

The generated native compiler with the release Rust runtime took **4.158 s
before and 2.613 s after** to compile a frozen Fibonacci input to LLVM, a
**37.2% reduction** across three alternating pairs. These times exclude building
the compiler executable and exclude Cargo compilation of its LLVM output. The
updated compiler also ran successfully on `wasm32-wasip1` (5.358 s in a single
validation run, including Node startup). All native and WASI outputs matched
Chibi's Fibonacci LLVM byte for byte.

Regression tests cover rejection at a noninitial source position, unprefixed
`inf.0`/`nan.0`/`i` as symbols, and existing numeric spellings and boundaries.
A differential probe compared 8,039 inputs through `s-number`, `s-symbol`,
`s-atom`, and the number/symbol literal predicates. Values, success/failure,
remainders, source locations, and unchanged-reader identity all matched.
The [raw report](../benchmarks/results/2026-10-09-numeric-start.json) records the
samples, diagnostic methods, comparison corpus, and source hashes.

## LLVM emission and named fields

The next baseline is `ef7861d`, including the numeric-start guard. A frozen copy
of those compiler sources produces 28,262 VM instructions and 4,349 distinct
dispatch destinations. Two repeated operations in LLVM emission were avoidable:

- Handler names were converted from symbols to character lists, mapped from
  hyphens to underscores, and rebuilt at every call site. Eight fixed spellings
  now describe the existing instruction ABI directly.
- Each dynamic destination searched an ever-growing list for duplicates. A
  fresh bitmap makes this linear for the lowerer's dense labels, with list
  membership retained for sparse hand-built programs. First-occurrence order
  stays unchanged; dispatch phi predecessors are not deduplicated.

`named-tuple` now runs its fields directly and collects only named values,
removing intermediate `pmap` results, tuple values, and the filtering pass.
It remains immutable and reentrant. Each field parser is captured at construction;
its name is read after success, preserving the old behavior even if a caller
mutates a descriptor. Child failures are returned unchanged and later fields
are not run.

Five parser pairs and three full-compilation samples per variant ran sequentially
in fresh Chibi processes. Every variant used the **same active source path**;
the input corpus and its paths were held fixed separately. This matters because
Chibi's allocation/GC behavior varied with source layout, paths, and profiling.
All twelve compiler outputs were byte-identical and passed LLVM verification.
Compilation wall time includes startup and file output, and excludes Cargo.

| Variant | Compiler sources to LLVM, median seconds |
| --- | ---: |
| Baseline | 10.567 |
| Direct named-field collection only | 10.233 |
| LLVM changes only | 6.957 |
| Both, with split expansion timings | 6.525 |

The combined reduction is **38.2%**. LLVM emission falls from **5.344 s to
1.491 s**. Standalone `base.sld` parsing improves only modestly, **0.513 s to
0.499 s** (2.7%); most of this round's gain comes from LLVM emission.

The new `--timing` output separates `import-parse` from `expand`. It accumulates
library-loader intervals locally to one compilation, including path construction,
file reading, parsing, and the single-library declaration check. Recursive
imports and expansion of library bodies happen outside the loader. Subtracting
these intervals from expansion before rounding avoids double counting; disabled
timing bypasses the counter and clocks entirely.

| Current Chibi compiler stage | Median seconds |
| --- | ---: |
| Entry parsing | 0.004 |
| Imported-source loading/parsing | 3.918 |
| Expansion excluding that loading/parsing | 0.613 |
| Lowering | 0.080 |
| LLVM emission | 1.491 |

The fixed corpus is important: compiling the changed compiler sources rather
than the frozen baseline took 9.022 s in a separate single Chibi run. That is a
capability check with different input, not an ablation of the implementation.

### Generated compiler and radix-prefix correction

A release-built native compiler compiling the frozen Fibonacci input takes
**2.662 s before and 2.496 s after**, a **6.2% reduction** across three alternating
pairs with the final runtime. This measures execution of the generated compiler;
it excludes building that compiler and compiling its LLVM output with Cargo.
An earlier ablation, before the runtime correction below, measured 2.658 s for
the baseline, 2.630 s with only the emitter changes, and 2.447 s with both Scheme
optimizations. Keep these two batches separate rather than mixing their medians.

The larger capability check exposed an existing runtime bug: `string->number`
rejected explicit radix prefixes, so the generated compiler could not read
`#x10ffff` in `syntax-parser.sld`. The runtime now recognizes `#b`, `#o`, `#d`,
and `#x` case-insensitively and borrows the remaining string without cloning it.
A prefix overrides a valid supplied default radix, as specified by
[R7RS section 6.2.7](https://small.r7rs.org/attachment/r7rs.pdf). Numeric types and
existing overflow-error behavior are unchanged; this is not a complete R7RS
numeric implementation. Unit tests cover signs, boundaries, malformed and
non-ASCII input, explicit-radix overrides, and decimal-float gating. The bootstrap
fixture exercises prefixes on native and WASI targets under GC stress.

With that correction, the generated compiler compiles the complete frozen
compiler source corpus to LLVM **byte-identical to Chibi's output on both native
and WASI**. These single capability checks took 38.028 s native and 55.167 s WASI.
WASI compilation of Fibonacci took 5.360 s including Node startup. The native
compiler also compiled its own changed sources, matching Chibi byte for byte
(38.548 s in a single check). The normal build remains hosted by Chibi.

### Simplification and rejected experiments

Independent explainers modeled named-field collection, dispatch destinations,
and timing ownership before comparison with the implementation. The resulting
code keeps each invariant local: parsers own no mutable cache, the emitter owns
its short-lived bitmap, and one expansion owns its timing counter. The fixed
handler-name cases, destination-collection loop, and expansion timing operation
can exceed the 10-line target deliberately: splitting the exhaustive mapping or
scattering a traversal or clock/counter lifetime would obscure their contracts.
Test fixtures also keep complete scenarios together.

Other candidates were measured and discarded:

- A direct whitespace scanner made the parser slower in the initial probe.
  Direct literal scanning offered a small benefit without enough justification
  for more specialized parser code.
- Explicit integer-to-string conversion before LLVM output improved isolated
  emission, but regressed normal full compilation from 10.921 s to 33.551 s.
  The interaction with the surrounding Chibi workload remains unexplained;
  the isolated result is insufficient evidence to land it.
- Extracting phase helpers to shorten intermediate-value lifetimes did not
  establish a time or peak-memory improvement in the exploratory runs.

The [raw report](../benchmarks/results/2026-10-09-compiler-throughput.json)
contains accepted ablations, exploratory samples, source hashes, reproduction
scripts, and measurement limitations. A contended exploratory parser batch was
discarded and rerun; it is not used for the reported comparison.

## Next candidates

1. **Imported-source parsing remains the largest cost.** It accounts for about
   3.92 s of the 6.53 s frozen-corpus run; actual expansion is about 0.61 s.
   Further work should profile allocations in this path against the normal
   compiler entry point before changing parser structure. A versioned syntax
   cache is a possible separate project, requiring invalidation and preserved
   locations; no cache is introduced here.
2. **Investigate remaining LLVM output allocation.** The large dispatcher now
   deduplicates dense labels linearly. Output formatting still deserves profiling,
   but the rejected numeric conversion demonstrates why full-program checks
   must decide whether a micro-optimization helps. Lowering remains too small
   to prioritize.

Chibi GC is significant in the diagnostic run, but single probes with 16 MiB
and 64 MiB initial heaps did not establish an overall speedup. Cargo currently
uses a fresh target directory per CLI invocation. A native release build probe
that changed only an LLVM comment took 0.801 s with fresh build directories and
0.665 s with dependencies reused (three paired samples). On this host, that
saving is much smaller than the numeric-start improvement above.

## Reproduction

Run timings sequentially, using a fixed input corpus and several fresh processes:

```sh
chibi-scheme -I src benchmarks/parser-time.scm bootstrap/scheme/base.sld
./snail-compile src/snail-scheme/compile.scm /tmp/compiler.ll --timing
chibi-scheme -I src benchmarks/compile-profile.scm "$PWD" examples/fibonacci.scm /tmp/fibonacci.ll
```

The parser probe prints elapsed microseconds after checking its result. The
compiler profile is Chibi-specific and reports inclusive wall/GC observations;
do not add nested LLVM sections together or compare these instrumented totals
with the normal compiler's times. To compare revisions, freeze the source being
compiled separately from the compiler implementation used to compile it.
