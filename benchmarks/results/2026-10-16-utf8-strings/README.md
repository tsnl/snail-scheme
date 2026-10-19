# UTF-8 string storage

On unchanged canonical `bv2string`, UTF-8 strings and operations on encoded byte
spans reduce median time by **6.1× on V8** and **10.1× natively** against a fresh
baseline. This measures the complete representation and primitive change, not
storage width alone. It covers one workload; the 57-workload report remains the
whole-suite reference.

## Measurements

Median guest seconds, one warmup and five measured fresh processes per route:

| Route | Baseline | UTF-8 | Baseline / UTF-8 |
| --- | ---: | ---: | ---: |
| SFIR / V8 | 2.281844 | 0.373352 | 6.112 |
| SFIR / native | 6.143090 | 0.608705 | 10.092 |
| Chez original | 0.467426 | 0.468240 | 0.998 |
| Chez adapted | 0.470159 | 0.470265 | 1.000 |
| Rust / Wasm | 0.043367 | 0.043315 | 1.001 |
| Rust / native | 0.026450 | 0.026501 | 0.998 |

The candidate takes 20.3% less time than original Chez on V8, and 30.0% more
time natively. It still takes **8.62× Rust/Wasm** and **22.97× Rust/native** time.
All four repeated comparator medians move by less than 0.2%. The remaining Rust
gap has not been isolated by this experiment.

All **72 scheduled executions passed**, comprising 12 warmups and 60 samples.
[comparison.json](comparison.json) retains every sample, median and ratio.
Each route runs 100 outer iterations, each with a short round trip followed by
1,000 pseudorandom ASCII bytevector round trips with maximum length 1,000. The
Rust implementation also validates UTF-8 and allocates independent buffers;
it is an idiomatic implementation, not an instruction-for-instruction port.

## What changed

Strings own packed UTF-8 bytes, a scalar count, used byte count and an invisible
cached scalar boundary. Conversion validates/counts once and copies encoded
bytes; substring and string copying copy byte spans, and equality compares valid
UTF-8 bytes. The old path repeatedly decoded and encoded through four-byte
character storage. The optimized guest module shrinks from 9,317 to 6,051 bytes.

Character indices still count Unicode scalars. ASCII indexing is direct;
non-ASCII indexing can scan from the nearest cached boundary or endpoint.
Width-changing mutation may shift a suffix and grow capacity. Repeated such
mutations can be quadratic. Mutable copies own independent storage, aliases
retain the same owner identity, and overlapping copies preserve source contents.
These tradeoffs are part of the [string contract](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/doc/book/sfir/types.md).

This change does not optimize closure captures. The separately documented
capture-by-copy semantics and hidden initialization cells do not establish a
closure performance gain.

## Revisions and protocol

| Role | Revision |
| --- | --- |
| Fresh baseline, including the landed compiler pass refactor | `c3ee7617bcf57d92fa48770c1232c59e4b4ca0cd` |
| Measured UTF-8 implementation | `268206be680747439ec90fd9a2b6c39685ca01f7` |
| Implementation after rebasing onto #273/#274 | `ec738290410ad4d4d379bd6af95ea4dd86936e40` |
| Final implementation after rebasing onto #276 | `9866b566` |

The canonical SFIR, Chez and Rust sources, inputs and specification are
unchanged between these revisions. Older bytevector/string timings used a
different compiler and are not the baseline for these ratios. Mandatory Binaryen
and its existing inlining policy remain enabled. Each campaign verifies that
native lowering consumes the same optimized guest Wasm as V8.

The rebase adds the closure documentation (#273) and integer default-initializer
fix (#274). No SFIR/string compiler or benchmark source changed during rebase.
Re-emitting each frozen benchmark module through the fixed native emitter
produces byte-identical LLVM; the evidence records both hashes. The fix is needed
for large literal coverage, but does not change this benchmark's native output.

A final rebase includes #276's compiler-host hash map. Host tests passed again,
and recompiling `bv2string` produced byte-identical raw and optimized Wasm to
the measured candidate. [rebase-validation.json](rebase-validation.json) records
the final implementation revision and artifact hashes.

The full baseline campaign ran first, from 10:33:17 to 10:35:33 UTC on October 16,
2026; the candidate followed from 10:36:11 to 10:37:42 UTC. Routes rotate by round
within each campaign, pinned to CPU 2. Guest monotonic timers cover the repeated
workload and complete final predicate, including V8 tiering during execution.
Input/setup, output formatting and final resource cleanup are excluded.

**These are uninstrumented measurements on an uncoordinated shared desktop.**
Task-owned builds and tests finished before timing, but other compiler/native
jobs were observed. This was not a machine-wide quiet interval. Repeated controls
support the large effects; small differences are not statistically conclusive.
The host is an Intel Core Ultra 7 270K Plus on x86-64 Linux, using `intel_pstate`
with the `powersave` governor. Recorded tools include Node 24.19.0, Chez 10.4.1
and Binaryen 132. Exact executable hashes and host snapshots are archived.

An earlier baseline launch omitted the parent's `SNAIL_NATIVE_SUPERVISOR`
setting. All 36 attempts failed before guest execution with `captured command
requires a built native process supervisor`. That attempt is retained separately
and contributes no timings. A fresh baseline preparation and complete new
schedule produced the successful baseline above; neither successful schedule
retries or discards samples. The [harness instructions](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/sfir/README.md)
now show the required parent environment setting.

## Validation and evidence

- All 322 SFIR integration cases, `make test` and `make check` passed.
- Raw Wasm, optimized Wasm and native execution round-tripped all 1,112,064
  Unicode scalar values against Rust's encoding oracle.
- Linked text, reader, writer and public build checks passed.
- New overlap, cursor and ownership cases, plus a large mixed-Unicode literal,
  passed native execution with collection forced at every allocation.
- The language book builds. The native static-default regression was fixed
  and tested separately in #274.

[evidence.tar.gz](evidence.tar.gz) retains original manifests, timing plans,
measurement summaries, all command/process records and raw streams for the 72
successful executions and 36 failed launches, validation statuses, native/Wasm
parity records, host observations and selected test results. It excludes compiled
binaries, toolchain copies and repeated workload input trees. Manifests retain
their hashes and original absolute paths; the archive is evidence, not a portable
toolchain bundle. Preparation records may still say `not-measured`: the later
timing summaries are authoritative for measurement status.

`evidence-files.sha256` inside the archive checks its members; the adjacent
[SHA256SUMS](SHA256SUMS) checks the archive and comparison file. Reproduce using
the [timing protocol](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/sfir/README.md#clean-timing-protocol), selecting
`--benchmarks bv2string` at each recorded compiler revision. Declare actual host
conditions when using `--quiet-window`; this experiment's field explicitly
records the absence of coordinated machine-wide quiet.
