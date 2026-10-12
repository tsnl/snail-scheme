# General specialization on the five largest Chez gaps

The new specialization pass makes **no material overall execution improvement**
on this subset: the geometric mean of baseline/candidate median times is
**1.0006x**. Individual medians move from 1.5% less elapsed time to 1.6% more.
The candidate remains 14.40–31.96x slower than Chez on these selected workloads.
All 60 clean executions pass, including full output-byte checks for `cat`.
This is a capability and correctness refactor, not a demonstrated solution to
these performance gaps. The compiler PRs remain unmerged.

## Execution results

One preliminary execution and three retained executions per system and workload;
medians are seconds. A negative change means less candidate elapsed time.

| Workload | Baseline V8 | Candidate V8 | Change | Chez | Candidate / Chez |
| --- | ---: | ---: | ---: | ---: | ---: |
| cat | 22.610323 | 22.373621 | -1.05% | 0.699943 | 31.96x |
| lattice | 24.957931 | 24.943233 | -0.06% | 1.158755 | 21.53x |
| wc | 12.341537 | 12.429108 | +0.71% | 0.650613 | 19.10x |
| graphs | 12.312918 | 12.515446 | +1.64% | 0.764624 | 16.37x |
| deriv | 6.103570 | 6.010764 | -1.52% | 0.417413 | 14.40x |

| Workload | Baseline observed min–max | Candidate observed min–max |
| --- | ---: | ---: |
| cat | 22.597349–22.644783 | 22.361906–22.425935 |
| lattice | 24.916335–25.010396 | 24.924300–24.960295 |
| wc | 12.324857–12.370766 | 12.407306–12.513477 |
| graphs | 12.288896–12.339736 | 12.398948–12.530998 |
| deriv | 5.999129–6.110991 | 6.003410–6.043677 |

[Every retained duration](execution-summary.json) includes Chez ranges and
artifact sizes. The small `deriv` improvement has overlapping observed ranges;
three observations do not establish a confidence interval or a stable ranking.
The large Chez gaps persist regardless of these small movements.

This report compares the frozen Wasm-only baseline `5373766` with compiler
`d2770ab`. The code PR tip `79bf941` has identical compiler, runtime, and host
sources; it adds only a separately executed callback-order regression. Both
builds use the default Binaryen optimization and the same Rust runtime, Node
engine, host, benchmark corpus, inputs, and harness. The five workloads were
selected for their previous gaps against Chez, not as a representative suite.

## What changed

The stack replaces the restricted i32 emitter with conditional lambda inference,
a bounded resolved-IR-to-resolved-IR specialization pass, and concrete scalar or
WasmGC-reference storage in the shared Wasm visitor. Explicit `All` variables
remain rigid when checking the original body. Copies substitute concrete types
after that check and preserve lexical assignment contracts and original call
instantiation decisions. Generic entries remain available for unknown calls.

These mechanisms now cover integers, floats, booleans, characters, and references.
They do not preserve container element types or specialize on callback identity.
Mutable cells, closure environments, and foreign boundaries retain generic
storage. Copy limits are eight per source lambda and 256 per linked module.
Inferred-only tail targets conservatively retain generic results when the
emitter cannot establish the planned concrete call contract.

Pre-link WAT from a fixture that passes linked execution confirms raw
integer/float/reference results and compatible float/reference tail transfers. That establishes implemented
coverage, not the amount of hot code specialized in these five benchmarks.
Their checked plans contain 28, 36, 35, 49, and 28 copies respectively. All their
planned result representations are boolean, closure reference, text reference,
or generic `eqref`; `wc` also has numeric loop-argument copies. These are static
plan entries, not dynamic calls, live emitted workers, or allocation counts.

## Measurement scope

All experiment-owned compilation and correctness jobs stopped before execution timing. Each of
the three systems ran one discarded preliminary execution and three measured
executions per workload, rotating order on CPU 5. Every execution used a fresh
process and the original input. The upstream timer excludes compilation and
process startup; default V8 tiering stays enabled. Every run checks the upstream
result, and every `cat` run additionally checks the complete output SHA256.
There is no instrumentation in these comparative binaries.

Compile cost is a separate alternating comparison of complete linked `graphs`
builds, with existing Rust caches and a warm file cache. Each fresh Chibi process
uses the frozen source path and recipe; only output paths change. Every resulting
Wasm binary must exactly match its frozen execution artifact. This measures
warm-cache build work, not first-time Rust setup or every compiler workload.

Three retained observations show ranges and medians, not confidence intervals.
These results do not measure the full 57-workload suite or establish how every
numeric workload behaves after removing the former i32 emitter.


## Compilation and size

The separate warm-cache `graphs` build comparison also passes all eight
artifact-hash checks. Retained full-build times are 13.500682, 13.501859,
13.500991 seconds for the baseline and 13.251244, 13.203889, 13.250556 seconds
for the candidate. Medians are **13.500991 versus 13.250556 seconds**, 1.85% less
candidate elapsed time in this one build workload.

The extra original-body checking pass is visible within that total: median
`ir-library->wasm` time increases from 0.247 to 0.509 seconds, and summed
`generate-library-functions` intervals increase from 0.117 to 0.192 seconds.
Scheme-module Binaryen optimization increases from 1.824 to 2.274 seconds.
Other phases change too; these observations do not causally assign the net build
change to any one pass. Trace intervals include one another and must not be
added as independent costs. [Build samples and trace summary](build-summary.json)
retain the complete timing scope.

| Workload | Baseline Wasm bytes | Candidate bytes | Static copies |
| --- | ---: | ---: | ---: |
| cat | 495,958 | 495,891 | 28 |
| lattice | 519,202 | 520,555 | 36 |
| wc | 504,909 | 512,465 | 35 |
| graphs | 528,898 | 532,624 | 49 |
| deriv | 504,575 | 504,619 | 28 |

`wc` grows about 1.5%; the other linked artifacts change by less than 1%.
The checked plan inspection and exact hashes are in
[candidate preparation](candidate-preparation.json), and the named
[representation checks](representation-evidence.json) refer to retained pre-link
fixture WAT. Binaryen may remove unused workers after that stage.

## Correctness and review

Validation covers `make test`, `make check`, linked backend and build suites,
the typing suite split into independent jobs, and 26 Rust tests plus formatting.
The typing jobs cover 67 guarded/optimized matrix cases and five larger fixtures,
35 static rejections, 21 folding cases, and two rejections before folding.
Six independent baseline/candidate runs additionally compare outputs, mutation,
closure identity, effect/error order, category-changing recursion, and exhausted
copy budgets with folding enabled and disabled. Seven small benchmark-builder
variants pass with the same checksum; their overlapping timings are discarded.

Focused behavioral review checked rigid source contracts, original instance
choices, mutable captures, cardinality, initialization, copy-budget fallback,
and proper tail calls. Regression coverage includes cases where strengthening
optimization facts must retain a runtime error and its position relative to
callee effects. The final code remains in an unmerged PR stack.

The [validation summary](validation.json) records each shard's scope. All checks
ran locally; GitHub reports no automated checks for the two code PRs. The raw
archive includes original logs, independently authored fixtures, baseline and
candidate observations, and the exact validation harnesses. Historical native
LLVM results are not part of this candidate comparison.

## What the remaining work is

The [separate five-workload investigation](../2026-10-12-v8-worst-five/README.md)
contains original-binary CPU/GC profiles, heavily instrumented constructor/call
counts, source mappings, V8 machine code, and representative Chez assembly.
Those observer runs are excluded from the clean comparisons here. Their large
constructor counts are reached requests, not a direct measurement of optimized
allocation or collector time.

The measured hotspots still suggest specific experiments:

- `cat` and `wc`: argument vectors, character boxing, root ownership operations,
  and the Rust character boundary. File calls are buffered. `write-char` also
  makes a temporary Rust string per character.
- `lattice` and `graphs`: known callback identities and their calling convention,
  closure environments, and checked container accesses. Knowing only `Procedure`
  or `Vector` does not expose the callback body or the vector's element type.
- `deriv`: the general `map` implementation's repeated traversal and allocation
  for a single input list, followed by its material collection cost.

These are proposals for controlled ablations, not implemented fixes. The one
completed `cat` environment-reuse ablation gives only 1.44% less elapsed time:
removing a prominent constructor request need not remove much execution cost.
The present comparison gives no evidence that replacing Wasm is necessary, and
no evidence that general type specialization by itself closes these gaps.

## Reproduction and artifacts

Use isolated checkouts of baseline `5373766d7d87851060950600f452722b0f92db53`
and candidate `d2770aba4ee4c6a4c855a39b146d5f939c7fc22f` (or the code-identical
`79bf941`). Initialize each pinned benchmark submodule and use the benchmark
Nix shell. The measured machine was an Intel Core Ultra 7 270K Plus, CPU 5,
with Node 24.19.0 / V8 13.6.233.17, Chez 10.4.1 safe level 2, Chibi 0.12,
Binaryen 132, and Rust 1.95.0. The pinned corpus is
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`.

Set `SPECIALIZATION_BASELINE` and `SPECIALIZATION_CANDIDATE` to those checkout
paths. From the evidence checkout root, prepare both matrices before timing:

```sh
export BINARYEN_CORES=1
REPORT=benchmarks/results/2026-10-12-general-specialization
python3 "$SPECIALIZATION_BASELINE/benchmarks/r7rs.py" \
  --output "$SPECIALIZATION_BASELINE/build/five-prepared" \
  --benchmarks cat lattice wc graphs deriv --systems snail-wasm chez \
  --rounds 3 --cpu 5 --prepare-only --build-timeout 900
python3 "$SPECIALIZATION_CANDIDATE/benchmarks/r7rs.py" \
  --output "$SPECIALIZATION_CANDIDATE/build/five-prepared" \
  --benchmarks cat lattice wc graphs deriv --systems snail-wasm \
  --rounds 3 --cpu 5 --prepare-only --build-timeout 900
python3 "$REPORT/repro/compare-frozen.py" \
  "$SPECIALIZATION_BASELINE/build/five-prepared/results.json" \
  "$SPECIALIZATION_CANDIDATE/build/five-prepared/results.json" \
  --output build/specialization-comparison --cpu 5 --rounds 3
unset WASM_MERGE SNAIL_REAL_WASM_MERGE
python3 "$REPORT/repro/compare-builds.py" \
  "$SPECIALIZATION_BASELINE/build/five-prepared/results.json" \
  "$SPECIALIZATION_CANDIDATE/build/five-prepared/results.json" \
  --output build/specialization-builds --benchmark graphs --cpu 5 --rounds 3
```

Choose an available CPU consistently, keep Node options identical, and stop
other experiment-owned builds and profiling during timing. Preparation excludes
runtime setup from execution measurement. The build comparison uses the local
Rust caches populated during preparation. It disables the linker capture wrapper
for both systems; every rebuilt artifact is checked against the frozen binary.

`raw-artifacts.tar.xz` retains the exact measured comparison JSON, stdout/stderr,
execution order, original harnesses, build traces, candidate Wasm and captured
linker inputs, source/host snapshot, checked specialization plans, and validation
evidence. The baseline binaries and separate profiling runs are in the
[baseline archive](../2026-10-12-v8-worst-five/raw-artifacts.tar.xz).
Archived commands retain their original absolute paths; use freshly prepared
reports for a new checkout. `SHA256SUMS` covers the published files, and the
archive's own manifest covers its regular files.
