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

The updated generated compiler was executed in native release, native debug,
and WASI release builds. All emitted Fibonacci LLVM byte-identical to Chibi's
output. Native release took 4.249 s, native debug 41.514 s, and WASI release
6.494 s in these single validation runs. These demonstrate the build-mode
distinction; they are not before/after optimization benchmarks.

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

## Next candidates

1. **Reject impossible numeric starts early.** An ordinary identifier tries the
   numeric grammar once as a possible number and again inside the identifier
   rule. A temporary, immutable first-character check reduced the same parse
   from 1.459 s to 0.523 s in three paired samples after the combinator changes.
   The existing syntax tests passed. This prototype is recorded, but is not part
   of the combinator change.
2. **Reduce repeated library parsing.** The `expand` timer includes loading and
   parsing imported libraries. In a diagnostic compiler-source run, actual
   expansion took 0.608 s versus 12.034 s for those reads and parses. A
   versioned cache of located library syntax could avoid repeated work across
   invocations, but needs source/version invalidation and preserved locations.
3. **Profile LLVM emission for larger programs.** It accounts for about 4.45 s
   when generating the compiler's LLVM. The large dispatcher and destination
   list deserve attention; changing line breaks alone did not help in a probe.
   Lowering is currently too small to justify prioritizing it.

Chibi GC is significant in the diagnostic run, but single probes with 16 MiB
and 64 MiB initial heaps did not establish an overall speedup. Cargo currently
uses a fresh target directory per CLI invocation. A native release build probe
that changed only an LLVM comment took 0.801 s with fresh build directories and
0.665 s with dependencies reused (three paired samples). On this host, that
saving is much smaller than the remaining parser opportunity.

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
