# V8 costs in the five largest Chez gaps

The five slowest Snail/V8 workloads relative to Chez reproduce their gaps on
Wasm-only compiler revision `5373766d7d87851060950600f452722b0f92db53`. The dominant
evidence is repeated work in argument vectors, closure adapters, checked value
operations, and Rust root handling. Collection is a material cost for `deriv`,
but the other profiles spend most sampled execution in those operations.
These measurements make no production changes.
The subset was selected from the five largest V8/Chez ratios in the
[complete prior matrix](../2026-10-12-native-v8/results.json); it is not a
representative suite average.

## Clean execution measurements

Original pinned R7RS inputs, one discarded preliminary execution, then three
rotating V8/Chez rounds on CPU 5. Compilation and fresh-process startup are
outside the upstream timer. Each timing passed the upstream result predicate.
Final `cat` output also matched all 4,460,056 input bytes in both systems; the
two V8 diagnostic executions independently repeated that byte check.

| Workload | V8 median s | Observed min to max s | Chez median s | V8 / Chez |
| --- | ---: | ---: | ---: | ---: |
| cat | 22.801494 | 22.655781 to 23.106456 | 0.704918 | 32.35 |
| lattice | 25.360399 | 25.293428 to 25.478179 | 1.169895 | 21.68 |
| wc | 12.366205 | 12.267868 to 12.488872 | 0.651656 | 18.98 |
| graphs | 12.512510 | 12.493064 to 12.640564 | 0.771317 | 16.22 |
| deriv | 6.042332 | 5.965004 to 6.094850 | 0.418318 | 14.44 |

[Clean summaries](clean-summary.json) retain every measured duration, Chez
ranges, input/output hashes, and the source revision. The complete matrix,
commands, tool versions, hashes, outputs, and execution order are archived.

## Separate allocation and profiling diagnostics

Every workload also ran once with its **original binary** under V8's 1 ms CPU
sampler and GC trace, and once with heavily instrumented Wasm under those same
observers. The latter counts function entries, host imports, indirect call
sites, and constructor sites. No optimization pass follows probe insertion.
Every diagnostic run passed its output checks. These durations are retained
as observer overhead data and are not comparative timing samples.

| Workload | V8 heap traffic GB | Chez allocated GB | Reached Wasm constructor sites billions | Reached indirect calls billions | GC self samples % |
| --- | ---: | ---: | ---: | ---: | ---: |
| cat | 37.473 | 0.058 | 1.115 | 0.000001 | 2.87 |
| lattice | 138.773 | 1.161 | 3.575 | 2.812 | 2.39 |
| wc | 59.726 | 0.030 | 1.699 | 0.0000005 | 7.33 |
| graphs | 118.707 | 7.420 | 2.794 | 0.687 | 4.45 |
| deriv | 68.095 | 8.161 | 2.040 | 0.590 | 25.53 |

Allocation columns have different measurement scopes. V8 sums object-heap
growth between GC events across the complete Node process, including startup;
final uncollected allocation and Rust allocations inside Wasm linear memory
are absent. Chez's `sstats-difference` surrounds `load` of the frozen program,
including initialization and result checking but excluding process startup.
The large volume differences are evidence of heap traffic, not exact normalized
allocation ratios or a count of live Scheme values.

V8's [`GCTracer::PrintNVP`](https://github.com/nodejs/node/blob/v24.19.0/deps/v8/src/heap/gc-tracer.cc)
computes `allocated` from pre-collection object bytes minus the previous
post-collection object bytes. It prints `pause` at 0.1 ms precision and the
included `scavenge` phase at 0.01 ms precision. For `cat`, 19,602 scavenges sum
to a misleading 3.6 ms of printed pauses; rounding allows total pause time
between 2.15 and 983.70 ms. Its printed scavenge phases sum to 470.89 ms, with
a rounding interval of 372.88 to 568.90 ms. They are included phases, not a
second cost to add to pauses. Background GC CPU time is outside those pause
durations. [Diagnostic summaries](diagnostics.json) retain these bounds for
all five cases.

Sample percentages count sampled stacks across the whole process; they are
unweighted sample frequencies, not exact cost fractions. Constructor probes
increment before operands evaluate, so they count reached requests, including
a request whose operand exits early. Constant global initializers are excluded.
V8 may also optimize away a requested object, and probes can change optimization.

## What the generated work explains

**cat:** The generated `catport` let body (`function132`, Wasm index 142)
occupies 30.64% of original-binary self samples. Read/write wrappers, extension
lookup, root operations, and argument-length decoding are also prominent.
For 223,002,800 copied characters, probes reach 892,013,500 fixed vector
constructors, 223,002,801 character atom constructors, 1,561,020,763 `abi_root`
invocations, and approximately one `dlmalloc`/`dlfree` pair per character.
Only 27,301 WASI reads and 27,267 WASI writes occur: the ports are buffered.
The gap therefore involves work per character above the buffered file calls.

**wc:** The generated `wcport/loop` let body (`function133`, index 159) has
30.34% of samples; the read wrapper has 21.27%. Besides 223 million input
character constructors, the repeated character comparisons introduce
403,414,500 further atom constructor requests. There are 1.072 billion fixed
vector requests and about three `abi_root` invocations per input character. The
comparison path therefore adds overhead beyond the shared input-port cost.

**lattice:** The generated Scheme library routine `member-by`
(`function28`, index 125) accounts for 43.46% of samples. It is the bootstrap
implementation used by `memv`, including expanded `case` tests. It calls a
generic comparator through an argument vector. Probes count 2.051 billion
`eqv` and primitive comparator entries, 2.812 billion indirect calls, 3.115
billion vector requests, 227 million closure requests, and 202 million cell
requests. `lexico/lex-first` and `lex-fixed/check` are the next major source
contexts. The workload repeatedly exercises generic symbol comparison,
callback, capture, and result-checking paths.

**graphs:** `cmp-next-vertex` and its inner loop together occupy 30.13% of
samples; the generated `member-by` routine adds 14.35%. Checked vector access
(`primitive63`) has 995 million entries. The run reaches 2.177 billion fixed
vector requests, 345 million closure requests, 165 million cell requests, and
687 million indirect calls. The source's permutation continuations and
callbacks create substantial environment and adapter work alongside graph
element accesses.

**deriv:** Generated Scheme library `map/loop` and `map-one` together have
39.75% of samples; the user `deriv` worker has 6.60%. The current general `map`
builds a list of input lists and maps `car` and `cdr` over it even for one input
list. The full invocation reaches 77 pair, 88 fixed vector, and 24 dynamic
vector constructors per outer derivative iteration, plus capture and helper
requests; shared `hide` scaffolding is included. GC has 25.53% of this traced
run's samples, and profiling/tracing raises its internal duration to 7.23 s
from the clean median of 6.04 s. Both extra traversal/call work and allocation
are visible here; this profile does not separate their causal contributions.

[Source mappings](source-mapping.json) preserve emitter function numbering,
import-inclusive Wasm indices, parameters, and named lexical contexts. Expanded
`let` locations refer to the macro definition, so context is retained to identify
the originating benchmark routine. [Readable hot WAT](hot-wat) contains each
major function. Full WAT and V8 TurboFan machine code are in the raw archive;
[assembly commands](machine-code-commands.json) record eager optimizing-tier
compilation of the exact original binaries, with no workload execution.

## What Chez demonstrably does differently

[Separate Chez statistics](chez-statistics.json) use the same compiled safe
optimization-level-2 binaries and original inputs. The
[`statistics` and `sstats-difference` APIs](https://cisco.github.io/ChezScheme/csug10.3.0/system.html)
report allocated bytes, collection count, and collector CPU/real durations.
These runs report dramatically less
managed allocation, while `graphs` still allocates 7.42 GB and spends about
0.101 s in collection. The difference is not simply that Chez avoids allocation.

[Representative Chez code](chez-code) contains an actual 639-byte buffered
character-copy procedure and a 79-byte checked generic callback procedure at
safe level 2, with Unicode, callback, and error checks. The character path
advances buffer fields and forms immediate character values; the callback
passes values in registers and jumps through the checked closure entry.
These are small representative procedures, **not the five benchmark binaries**,
so their sizes and instructions illustrate mechanisms without establishing
benchmark-wide cost attribution. The exact capture source, bytes, decoding,
commands, source version, and scope are retained.

## One measured environment-allocation ablation

The copied ports in `catport` stay constant through the character loop, but its
optimized Wasm reconstructs their two-element environment vector on every
recursive call. A program-specific WAT ablation replaces that one vector with
the existing environment. It still evaluates and drops the original two
operands, preserving their checks, local updates, and evaluation order. It
changes no character operations, argument vectors, or Rust/port code.

The control is an unmodified disassemble/assemble roundtrip of the same frozen
binary. Both artifacts use the same explicit Wasm features and receive no
further Binaryen optimization. In a build-free CPU-5 window, each ran one
discarded preliminary execution and three rotating measured executions with
the full original input. All eight executions matched the complete output-byte
SHA256.

| Artifact | Retained seconds | Median seconds |
| --- | --- | ---: |
| WAT roundtrip control | 22.696425, 22.636908, 22.874399 | 22.696425 |
| Reuse unchanged environment | 22.510486, 22.370319, 22.344782 | 22.370319 |

This removes one reached vector allocation per copied character and gives a
1.015x observed speedup, or 1.44% less elapsed time. This particular allocation
therefore accounts for little of the measured 32x Chez gap. The result does
not assign a cost to the other allocations, checks, or root operations; those
remain separate experiments. This is a diagnostic modification to one frozen
program, with no production compiler/runtime change.

[Raw measurements and summaries](cat-environment-ablation) retain every result,
artifact hashes, both Wasm binaries and WAT forms, the exact measured scripts,
and the two earlier output-only validation runs. Those earlier runs overlapped
build work and are excluded from the timing comparison. From the checkout root:

```sh
REPORT=benchmarks/results/2026-10-12-v8-worst-five
python3 "$REPORT/repro/cat-environment-ablation.py" \
  build/v8-worst-five/cases/cat/snail-wasm/program.wasm \
  --reader "$REPORT/repro/instrument-wasm.py" --output build/cat-env-artifacts
python3 "$REPORT/repro/measure-cat-ablation.py" \
  build/v8-worst-five/results.json build/cat-env-artifacts \
  --output build/cat-env-measurements --cpu 5 --rounds 3
```

## Further controlled experiments

1. Measure the shared Rust boundary separately from file decoding: preserve the
   same character sequence and buffered calls while varying argument-vector
   creation, slot ownership, and character representation one at a time. A
   stack UTF-8 buffer experiment in `write-char` isolates the observed Rust
   allocation/free pair without changing the read side.
2. Keep the same Scheme checks and values while varying known callback calls
   between direct workers and uniform adapters. Use `member-by`, primitive
   comparison, and vector access counts to check what changed. This tests a
   general lowering policy rather than a workload rewrite.
3. Compare the current general `map` path with a semantics-equivalent single-list
   path, holding the surrounding algorithm and `hide` unchanged. Pair/vector
   counters establish the removed work before clean runtime comparison.
4. For closure/cell-heavy contexts in `lattice` and `graphs`, vary environment
   construction separately from value checks. Preserve mutation and early
   capture invariants; compare constructor requests and managed allocation.

These four experiments remain proposals. The small environment-reuse result
above is the only measured ablation here; it establishes no production fix.

## Reproduction and retained artifacts

Start an isolated checkout of `5373766`, initialize the pinned benchmark
submodule, and use the repository benchmark Nix shell. Build and freeze before
measuring; the original run used Node 24.19.0, V8 13.6, Chez 10.4.1, Binaryen 132,
Rust 1.95.0, and a copied Rust target cache whose sources matched the prepared checkout.
Cargo still validated the local target before linking each program.

```sh
mkdir -p build/tools
cp benchmarks/capture-tool.py build/tools/capture-wasm-merge
chmod +x build/tools/capture-wasm-merge
export WASM_MERGE="$PWD/build/tools/capture-wasm-merge"
export SNAIL_REAL_WASM_MERGE="$(command -v wasm-merge)"
export BINARYEN_CORES=1
python3 benchmarks/r7rs.py --output build/v8-worst-five \
  --benchmarks cat lattice wc graphs deriv --systems snail-wasm chez \
  --rounds 3 --cpu 5 --prepare-only --build-timeout 900
python3 benchmarks/r7rs.py --measure build/v8-worst-five/results.json
python3 benchmarks/results/2026-10-12-v8-worst-five/repro/profile-five.py
python3 benchmarks/results/2026-10-12-v8-worst-five/repro/chez-statistics.py
```

Change CPU 5 to an available CPU before preparation. Diagnostics take their CPU
from the frozen report. Source mappings use `repro/map-functions.scm` with root
and source path arguments under `chibi-scheme -I src`.

`raw-artifacts.tar.xz` retains every successful clean/diagnostic invocation,
CPU profiles, GC logs, complete counter rows and types, original/instrumented
Wasm and WAT, captured linker inputs, frozen source/input/host files, and the
compiler/harness source snapshot. `SHA256SUMS` covers the published files.
