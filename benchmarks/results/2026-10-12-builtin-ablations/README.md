# Character output, ABI predicates and typed builtin ablations

Three bounded comparisons show improvements on the original selected workloads:
stack UTF8 encoding in `write-char` reduces the observed `cat` median by
**3.81%**; a subsequent requested-type ABI predicate reduces `cat` by **5.43%**
and `wc` by **4.89%** relative to the UTF8-only revision. A third checkpoint
adding typed builtin calls reduces `graphs` by **27.72%** and `wc` by **13.34%**
relative to the requested-kind revision, before the map/rest/callback changes.
Each median has only
**three retained observations**. The comparisons ran in separate windows; their
percentages are not multiplied into a claimed combined improvement.

| Independent change | Workload | Baseline median s | Candidate median s | Elapsed reduction |
| --- | --- | ---: | ---: | ---: |
| Temporary String → stack UTF8 | cat | 22.543793 | 21.684831 | 3.81% |
| Full classification → requested type predicate | cat | 21.546081 | 20.377088 | 5.43% |
| Full classification → requested type predicate | wc | 12.580415 | 11.965508 | 4.89% |
| Known builtin calls → typed intrinsics | graphs | 12.501697 | 9.035650 | 27.72% |
| Known builtin calls → typed intrinsics | wc | 12.044183 | 10.437998 | 13.34% |

| Change and variant | Every retained time, seconds | Observed min–max |
| --- | --- | --- |
| UTF8 baseline d2770ab | 22.445162018, 22.543792658, 22.686817832 | 22.445162–22.686818 |
| UTF8 candidate ca00972 | 21.491718553, 22.137453931, 21.684831498 | 21.491719–22.137454 |
| Requested-kind cat baseline ca00972 | 21.479586994, 21.562768999, 21.546080880 | 21.479587–21.562769 |
| Requested-kind cat candidate 910b185 | 20.377087874, 20.333047503, 20.666314994 | 20.333048–20.666315 |
| Requested-kind wc baseline ca00972 | 12.590302280, 12.580414796, 12.527390469 | 12.527390–12.590302 |
| Requested-kind wc candidate 910b185 | 11.972782405, 11.965508450, 11.902813138 | 11.902813–11.972782 |
| Intrinsics graphs baseline 910b185 | 12.501697432, 12.489592181, 12.510743707 | 12.489592–12.510744 |
| Intrinsics graphs candidate ff8b873 | 9.010889884, 9.035650446, 9.066061800 | 9.010890–9.066062 |
| Intrinsics wc baseline 910b185 | 12.010410411, 12.044183389, 12.407732842 | 12.010410–12.407733 |
| Intrinsics wc candidate ff8b873 | 10.233230766, 10.484963949, 10.437997736 | 10.233231–10.484964 |

All 40 executions passed their upstream result predicates. The 16 `cat`
executions also verified complete output contents with SHA256
`2994b446dfb07d7cf324fb6aa32d519b3f0bd53a582268714adf08df5f45b8d3`.
Each cat execution internally copies the 4,460,056-byte input 50 times. The second
comparison directly records input/output sizes on every execution; the first
retains each verified content hash and the canonical input size. Output payloads
are excluded from the archive. Every raw record preserves stdout, stderr,
return status, workload elapsed time and process duration separately.

## What the comparisons isolate

The UTF8 comparison uses baseline
`d2770aba4ee4c6a4c855a39b146d5f939c7fc22f` and candidate
`ca00972d1b3ad2ada3cc7a3bc8ddb40439da5d47`. Compiler/runtime hashes differ only in
`src/platform.rs`. Generated Scheme, optimized Scheme, entry and platform
modules are byte-identical. The character is encoded into a four-byte stack
buffer before the existing port write, keeping character conversion before
optional-port selection. Neither buffering nor Scheme ABI/root handling changes.

The requested-kind comparison uses ca00972 and its direct successor
`910b1858d286a37b125d31e973858564fc3093cf`. Production hashes differ only in
`src/abi.rs` and `src/snail-scheme/wasm-abi.sld`. Rust checks the requested value
category through the additive `is_kind` ABI; failure still uses full `kind`
classification for the error. For an extension, final WAT calls
`is_kind(handle, 14)` and executes its category-discriminator dispatch plus the
relevant extension reference test, avoiding unrelated shape tests on success.
This is a source/WAT mechanism; no machine-code inlining claim is made.

The typed-intrinsic comparison uses 910b185 and
`ff8b87346d4228842597843457418f8c3b91b332`. Its Rust runtime is unchanged.
The checkpoint adds concrete scalar/reference primitive lowering and the opt-in
unsafe library; ordinary Scheme calls retain checked boundaries and generic
entries. The production source hash differences are recorded in
[typed-intrinsics/preparation.json](typed-intrinsics/preparation.json). This
isolates that checkpoint from later one-list traversal, direct-rest and callback
identity changes. The old profiles show many vector-ref operations in `graphs`
and literal-character/argument operations in `wc`, but this comparison measures
the checkpoint as a whole, not separate causal costs of individual intrinsics.

| Frozen program | Bytes | Wasm SHA256 |
| --- | ---: | --- |
| d2770ab cat | 495891 | `a01a4d6d72bd85f501cdb9b9ac37f7c806995e6d85bc9b8e57324c01889bac87` |
| ca00972 cat | 495838 | `f5388b1ffa3c6f792c4361e9e8b166c8947e659d8f549202d7118c76be20ed74` |
| ca00972 wc | 512412 | `f9a14a22800a8eb70b466e6d9bc6e91373263e52160f3f8f0d533a85b5bb0d54` |
| 910b185 cat | 495652 | `11a56dc8c16b36cd683e194e55bd491ee6fb9661a9e5e880375df7bb89716213` |
| 910b185 wc | 512226 | `05bd4c6253f5d6c0d408849c546acab93981bf578d8bce0b0ec3383b5ee7d841` |
| 910b185 graphs | 532387 | `8e57c71ccd17eec5d978a762f79472fa311f03707bbe6c31954922f93c7d578e` |
| ff8b873 graphs | 536302 | `d3c439298fce3d16956b869f97ece8423ba0af88a13f14d9c5d9fa81e31b81f8` |
| ff8b873 wc | 512454 | `9c83fe85c351dad636adf285ad67205d5d060e87dad9a68fa0327a8edbaa9827` |

Preparation reused a private copied Rust cache in each isolated worktree.
Every prepared report freezes the complete compiler/runtime source hash map,
host, executable paths/tool hashes, input/source hashes, build recipe, settings,
captured linker inputs and module hashes. Comparability checks passed for the
original corpus revision, benchmark source and inputs, JavaScript host, harness,
Node binary and build environment. Source/module changes remain explicit.

The original profiles at `5373766` motivated these changes: approximately one
Rust allocation/free pair per copied character and frequent root extension
lookup. These clean comparisons establish the effects of the specific changes;
they do not supply new allocation counts or turn sampler frequencies into
causal cost fractions. Heavy diagnostics and the combined compiler's final
five-case comparison remain separate experiments.

## Timing and validation scope

Each comparison uses one discarded preliminary and three retained rotating
fresh-process executions per workload/variant, pinned to CPU 5. All
experiment-owned build/test jobs stopped before timing. Original corpus inputs
and default V8 tiering stay enabled. The upstream workload timer excludes
compilation, process startup and output checking. No CPU profiler, GC trace,
counter probes or forced optimizing-tier flags are active.

Node 24.19.0 uses V8 13.6.233.17-node.51. Preparation uses Chibi 0.12,
Binaryen 132, Rust 1.95.0, the same capture linker, and `BINARYEN_CORES=1`.
The prepared reports archived by [manifest.json](manifest.json) retain every
exact Nix executable path and hash. Build durations while other tests ran are
preparation records, not comparative compilation measurements.

These observations concern the selected workloads, not a suite
average or a confidence interval. ca00972's measured cat median differs between
windows. A combined improvement requires its own frozen direct comparison.

## Raw records and reproduction

[UTF8 records](write-char/results.json) and
[requested-kind records](requested-kind/results.json) and
[typed-intrinsic records](typed-intrinsics/results.json) retain all attempts,
including discarded preliminaries and execution order. Their summaries and
preparation records are adjacent. The 1.99 MB `artifacts.tar.xz` deduplicates
84 checked blobs containing eight frozen programs, their captured linker inputs,
host, original inputs, prepared reports, and relevant source files at
each revision. [manifest.json](manifest.json) maps original names to hashes and
contains the archive hash. No duplicate output files or profiler payloads are
included.

Use a Python environment with matplotlib (the benchmark Nix shell provides it).
The restoration script verifies the archive and every requested blob, preserves
the original prepared-report hashes, selects the original cases and adjusts
artifact locations, restores
the measured environment, and invokes the exact measured helper. Preflight
checks reject changed Node/Chez binaries, input/host/module bytes or settings.
Choose a quiet CPU and a new output directory:

```sh
python3 benchmarks/results/2026-10-12-builtin-ablations/repro/run-frozen-ablations.py \
  write-char --output /tmp/snail-repeat-write-char --cpu 5 --rounds 3
python3 benchmarks/results/2026-10-12-builtin-ablations/repro/run-frozen-ablations.py \
  requested-kind --output /tmp/snail-repeat-requested-kind --cpu 5 --rounds 3
python3 benchmarks/results/2026-10-12-builtin-ablations/repro/run-frozen-ablations.py \
  typed-intrinsics --output /tmp/snail-repeat-typed-intrinsics --cpu 5 --rounds 3
```

`--restore-only` prepares checked artifacts without executing them. The
standalone measured helpers, shared R7RS runner and original frozen-comparison
helper are preserved in [repro](repro/). The original live-worktree commands,
including tool environment and build recipes, are in [commands.json](commands.json).
