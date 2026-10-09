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

## Next candidates

1. **Profile LLVM emission for larger programs.** It now accounts for about
   5.01 s of the 10.27 s compiler-source run. The large dispatcher and destination
   list deserve attention; changing line breaks alone did not help in a probe.
   Lowering is currently too small to justify prioritizing it.
2. **Reduce repeated library parsing.** The `expand` timer includes loading and
   parsing imported libraries. In a diagnostic compiler-source run before the
   numeric-start guard, actual expansion took 0.608 s versus 12.034 s for those
   reads and parses. Reprofile after the guard before estimating further wins. A
   versioned cache of located library syntax could avoid repeated work across
   invocations, but needs source/version invalidation and preserved locations.

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
