# Full-input Mazefun comparison

Snail/V8 takes **0.629 seconds** for all 10,000 original 11 × 11 maze
constructions and the complete supplied grid predicate. It is **1.619× faster
than original Chez**, **1.425× faster than the adapted source on Chez**, and
**3.691× faster than this Rust/Wasm reference**. This is one workload and one
measurement window; Rust's reference counting and the different concrete data
layouts are material differences.

| Implementation | Median workload seconds | Retained range | Time / Snail | Median process seconds |
| --- | ---: | ---: | ---: | ---: |
| Snail / V8 | 0.628972 | 0.628016–0.649436 | 1.000× | 0.653507 |
| Original source / Chez | 1.018415 | 1.016946–1.024678 | 1.619× | 1.049957 |
| Adapted source / Chez | 0.896422 | 0.892392–0.897360 | 1.425× | 0.927172 |
| Rust / Wasm / V8 | 2.321359 | 2.301613–2.332119 | 3.691× | 2.345216 |

All twenty invocations passed. Each implementation receives one excluded fresh
process and four retained processes in cyclic order on logical CPU 5. No sample
was replaced or removed. Snail's retained range spans about 3.4%; the medians
summarize these four observations, not an uncertainty estimate or whole-suite
performance guarantee.

## Fixed programs, input and timing boundaries

The source and input remain pinned to upstream
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. The original input is unchanged:
count 10,000, dimensions 11 and 11, and the complete 121-cell `_`/`*` grid.
Its SHA-256 is
`38c693aaa745e91ed261ff5c4e4999126ab70c6d4c4b55c61510ba0eef3b3644`.
The frozen spec is checked against the actual Chez reader's recorded stdin and
stdout before execution. Every process receives those original input bytes;
the strict host uses their previously decoded scalar spec.

The [strict preparation](../2026-10-14-strict-mazefun/README.md) supplies the
original and adapted Chez programs, optimized Wasm, complete predicate and
separate retained-work probes. Its compiler basis is
`53008a43e75cc1d1c3d6844ab923807389b84149`; later integration rebuilt byte-identical
raw and optimized programs. The
[corrected Rust handoff](../2026-10-14-rust-mazefun-handoff/README.md) supplies
artifact `4e1f45f9c925dde00788408ab97b262c77c7201967c7b49768970bcd50efd885`,
with its full supplied-datum predicate. The historical Rust artifact is not timed.
Binaryen optimization is retained for the strict Wasm program. Node uses its
default V8 tiering, without instrumentation or special compilation/GC flags.

Workload clocks exclude process startup, program loading, module initialization
and input decoding. They include every repeated construction and the final
complete predicate. The strict host requires return value `1`; Rust must print
the entire canonical grid and its exact CSV label; each Chez variant must print
its exact benchmark label and successful timing record. Nonzero status, stderr,
`INCORRECT`, malformed framing or an invalid time fails the trial. Raw stdout
and stderr are persisted before decoding or validation.

The separate parent process clock includes launch through process completion,
including startup and terminal output/cleanup. Rust's final result is dropped
after its workload clock stops; intermediate and prior-result cleanup happens
inside the timed loop. GC implementations have different liveness and
reclamation schedules. The two clocks must not be mixed when computing ratios.

## What differs between implementations

The strict port keeps persistent lists, copied prefixes and shared suffixes,
original shuffle order, ordered flooding and complete result construction.
Coordinates/dimensions use concrete I64 products, and finite symbols/pair roles
become closed variants; output marks use Bool. The adapted Chez control runs the
same kernel/helpers with vector products/variants. It takes about 12% less time
than original Chez here, so source representation changes explain part of the
original-source comparison. Snail also wins against that adapted control.

Rust preserves the functional maze algorithm using persistent `Rc` cave,
shuffle and result lists, inline coordinates/wall values, and temporary vectors
for neighbors, IDs, hole collection and output mapping. Some pure construction
callbacks run in reverse while producing the same ordered lists. UTF-8 symbol
printing, product layouts, allocation and destruction schedules differ. These
measurements do not isolate reference counting, GC or any individual layout as
the cause of the Rust gap.

The preceding preparation reports contain complete value/order/sharing probes
and separate optimized-Wasm observers. They retain 10,000 maze calls, 600,000
shuffle/piercing operations, 12.5 million flood entries and complete final
predicate work. Those are diagnostic execution-site counts, not physical V8
allocation counts or measurements of the uninstrumented timing binaries.

## Reproducibility and scope

The frozen protocol and raw observations are in
`matched-measurements/mazefun-freeze.json` and
`matched-measurements/mazefun.json`. All **887 frozen identities** match before
and after the campaign. Tools are Node 24.19.0, Chez 10.4.1, Binaryen 132 and
Rust 1.95; the manifests retain executable identities and exact build provenance.
Agent-controlled builds, tests, profiling and compression were paused during
timing. Residual GitHub metadata requests and other system/desktop activity
remain disclosed in the quiet-window record.

`manifest.json` and `artifacts.tar.xz` retain frozen sources, hosts, binaries,
inputs, decoder provenance and raw outcomes. `replay-check.json` records separate
full-count correctness executions from restored paths; their durations are not
clean samples. External tools, dynamic libraries and Rust sysroot/dependency
binaries are not vendored, so restoration is not a portable self-contained build.
Use the recorded external tools and relocated commands.

```sh
python3 benchmarks/strict-suite/replay.py /tmp/mazefun-comparison-replay \
  --report benchmarks/results/2026-10-14-strict-mazefun-comparison
```

Historical strict measurements now cover **32 of 57 workloads**, with **31 paired
Chez comparisons**. This inventory combines documented checkpoints; it is not a
complete rerun on the current compiler.
