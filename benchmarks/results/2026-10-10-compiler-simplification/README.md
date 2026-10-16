# Shared compiler binding analysis

Typing, closure analysis, and constant evaluation now share the declaration scan's
assignment and initializer information. Six repeated IR walks disappear, and the
partial evaluator keeps one list of unavailable bindings. Type facts still pass
through the visitor and immutable scopes. Initialization-order analysis and the
bounded interpreter retain their separate responsibilities.

## Compiler measurements

| Compiler host | Before | After | Change in time |
| --- | ---: | ---: | ---: |
| Chibi | 14.789 s | 14.408 s | -2.6% |
| Snail Wasm / V8 | 10.661 s | 10.061 s | -5.6% |
| Snail native | 31.901 s | 31.429 s | -1.5% |

![Compiler comparison](comparison.svg)

These are three rotating measured rounds after one discarded run per case, on
logical CPU 2. Chibi's measured ranges are disjoint; Wasm and native ranges overlap.
The table describes these samples, not a performance guarantee. All 24 outputs
are byte-identical across both implementations and all three hosts, and the WAT
references pass Binaryen validation. Chibi remains the supported compiler host.

The timer includes parsing, library loading, checking, lowering, trace events,
and WAT writing. It excludes process startup, compiler preparation, assembly,
and linking. After the change, median WAT writing times are 0.122 s on Chibi,
0.182 s on Wasm/V8, and 0.257 s native. Serialization is a small part of this run.
Task-owned builds and tests had finished before measurement; unrelated system
activity remains possible.

The before compiler and common input are frozen at `40e0297`; the after compiler
is frozen at `dbc63b6`. Its compiler sources match review commit `f9047de`.
The later benchmark-harness fixes do not change compiler sources. The before
compiler predates the immutable `All` bounds cleanup; this unannotated corpus
does not exercise polymorphic constraint solving. Focused typing tests cover it.
This input differs from the earlier
[visitor comparison](../2026-10-10-visitor-typing/README.md), so compare absolute
times within each report.

[results.json](results.json) records every sample, execution order, stage time,
command, tool version, and source/artifact hash. The unchanged
[measurement harness](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-10-visitor-typing/measure.py) is identified by its
hash in the report. [archives.json](archives.json) identifies the exact source
archives: the before tree reuses the earlier report's `after-source.tar.gz`, and
the final tree is [after-source.tar.gz](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-10-compiler-simplification/after-source.tar.gz).

## Runtime measurements

Eight rotating measured rounds follow one discarded run per variant on CPU 2.
Every run verifies its checksum. Compilation and process startup are excluded;
V8's default tiering remains enabled. These refresh the cumulative review stack;
they do not isolate the binding-summary refactor's effect on runtime.

The `boxed` mode disables i32 specialization. The runner checks actual function
definitions before measuring each variant, distinguishing export references from
function definitions. Relinking the isolated tail worker has an explicit trace
scope. Earlier published production measurements predate the mode regression.

### Recursive Fibonacci, two uncurried parameters

| Variant | Median seconds |
| --- | ---: |
| Untyped Scheme, check elimination | 0.392489 |
| ExactInteger, check elimination | 0.392383 |
| i32, boxed | 0.472970 |
| i32, specialized | 0.173772 |
| Checked C-to-Wasm | 0.172001 |
| Checked native C | 0.107317 |

Specialization is **2.26× faster than untyped Scheme** and about
**1% slower than checked C-to-Wasm**. Each sample runs inputs 22–25 with 256
repetitions and checksum `1076472576`. [fibonacci.json](fibonacci.json) retains
all 12 variants, samples, and artifacts. It was measured at `dbc63b6`.

### Tail Fibonacci, three uncurried parameters

| Variant | Median seconds |
| --- | ---: |
| Untyped Scheme, check elimination | 0.289442 |
| ExactInteger, check elimination | 0.291552 |
| i32, boxed | 0.311632 |
| i32, specialized | 0.114204 |
| Isolated Snail i32 worker | 0.058253 |
| Checked C-to-Wasm worker | 0.043965 |
| Checked native C | 0.033151 |

The complete specialized Scheme workload is **2.53× faster than
untyped Scheme**. The isolated worker is **32.5% slower than checked
C-to-Wasm**, using the same JavaScript driver. The complete Scheme workload also
includes its boxed entry and outer driver, so keep those measurements distinct.

Each sample performs 4,194,304 top-level calls and 94,371,840 tail updates after
an equally sized in-process warmup, with checksum `4409231671296`.
[tail-fibonacci.json](tail-fibonacci.json) retains all 13 variants and records
the harness fixes at `503d5a0`. No native Snail executor is measured here.

### Occurrence typing, strings and records

| Variant | Median seconds |
| --- | ---: |
| Guarded | 0.048713 |
| Check elimination, boxed | 0.029675 |

Check elimination is **1.64× faster**, without representation
specialization. Both modes use 256 repetitions and checksum `53760000`.
[occurrence.json](occurrence.json) records the same compiler sources as the other
workloads, with the corrected harness at `503d5a0`.

## Reproduce

Use the review checkout's Nix shell and benchmark runners. For the compiler
comparison, create two isolated worktrees and overlay the respective source
archives in their roots. Prepare each compiler in a fresh output directory:

```sh
nix-shell benchmarks/shell.nix --run 'BINARYEN_CORES=1 python3 benchmarks/compile-self.py \
  --systems chibi snail-wasm snail-native --rounds 1 --cpu 2 \
  --timeout 600 --build-timeout 1500 --output build/prepared'
```

After both preparations finish, compare them on an otherwise idle host:

```sh
nix-shell benchmarks/shell.nix --run 'BINARYEN_CORES=1 \
  python3 benchmarks/results/2026-10-10-visitor-typing/measure.py \
  --before /path/to/before/build/prepared --after /path/to/after/build/prepared \
  --output /tmp/compiler-comparison --cpu 2 --rounds 3'
```

Run the runtime workloads from the final review checkout, without either overlay:

```sh
nix-shell benchmarks/shell.nix
BINARYEN_CORES=1 python3 benchmarks/typing/measure.py --workload fibonacci --rounds 8 --cpu 2 --output /tmp/fibonacci.json
BINARYEN_CORES=1 python3 benchmarks/typing/measure.py --workload tail-fibonacci --rounds 8 --cpu 2 --output /tmp/tail-fibonacci.json
BINARYEN_CORES=1 python3 benchmarks/typing/measure.py --workload occurrence --rounds 8 --cpu 2 --output /tmp/occurrence.json
```

Choose an allowed CPU on the measurement machine. The runtime reports contain
full source manifests, source-diff hashes, tool versions, and artifact hashes.
The compiler source archive excludes build products. These observations are
local evidence rather than CI performance thresholds.
