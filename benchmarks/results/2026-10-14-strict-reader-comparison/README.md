# Complete Sum1 and Read1 comparison

All **112** planned fresh-process executions passed. Each system/workload has
one predetermined discarded run and seven retained runs. Sum1 keeps **25**
complete reads of its 100,000-number file; Read1 keeps **2,500** complete reads
of its five-datum source file. Every counted worker's real file I/O and final
result predicate remain inside the workload clock. No sample was replaced or
removed beyond the fourteen planned discards.

Production Snail/V8 takes **2.621× original Chez time for Sum1** and **8.450×
for Read1**. Against adapted Chez, which executes the same Scheme reader body,
the ratios are **1.074×** and **1.850×**. The Rust controls use narrower/different
parsers and storage; their times do not establish equal general-reader work.

## Sum1

| Implementation | Workload median (s) | Retained range (s) | / original Chez | Process median (s) | Process range (s) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Snail / production Wasm / V8 | 1.054333 | 1.042859–1.145890 | 2.621× | 1.082637 | 1.070281–1.173083 |
| Snail / native-final Scheme module / V8 | 1.123597 | 1.109527–1.142664 | 2.793× | 1.153710 | 1.136690–1.170426 |
| Snail / native | 1.100904 | 1.090853–1.102799 | 2.737× | 1.103135 | 1.092960–1.105432 |
| Original source / Chez | 0.402220 | 0.400884–0.403448 | 1.000× | 0.433357 | 0.430949–0.435859 |
| Adapted source / Chez | 0.981268 | 0.979210–0.985777 | 2.440× | 1.012253 | 1.009586–1.017883 |
| Rust / optimized Wasm / V8 | 0.195842 | 0.195282–0.198509 | 0.487× | 0.221191 | 0.218643–0.224196 |
| Rust / native | 0.128344 | 0.128228–0.132522 | 0.319× | 0.131441 | 0.129904–0.135023 |

## Read1

| Implementation | Workload median (s) | Retained range (s) | / original Chez | Process median (s) | Process range (s) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Snail / production Wasm / V8 | 2.703861 | 2.692044–2.748346 | 8.450× | 2.734618 | 2.722717–2.777909 |
| Snail / native-final Scheme module / V8 | 2.785069 | 2.754926–2.830623 | 8.703× | 2.815868 | 2.786946–2.861165 |
| Snail / native | 3.098514 | 3.094080–3.135636 | 9.683× | 3.102328 | 3.097041–3.138729 |
| Original source / Chez | 0.320001 | 0.318642–0.321775 | 1.000× | 0.351963 | 0.351131–0.354802 |
| Adapted source / Chez | 1.461438 | 1.457267–1.508452 | 4.567× | 1.493378 | 1.489884–1.541489 |
| Rust / optimized Wasm / V8 | 0.439175 | 0.432263–0.462348 | 1.372× | 0.464245 | 0.458046–0.486768 |
| Rust / native | 0.352189 | 0.350472–0.352537 | 1.101× | 0.354753 | 0.352692–0.355669 |

All table ranges are observed minima and maxima of seven retained samples,
not confidence intervals. `summary.json` retains full precision and ratios for
every system. Production V8 takes 5.384× this Rust/Wasm control's Sum1 time and
6.157× its Read1 time. Native Snail takes 8.578× native Rust time for Sum1 and
8.798× for Read1. Those comparisons include the parser/representation differences
below. Adapted Chez takes 2.440× original Chez time for Sum1 and 4.567× for Read1.

With the **same native-final Scheme module**, native takes **0.980× common-module
V8 time for Sum1** and **1.113× for Read1**. Only that Scheme module is identical;
Rust scalar providers, target libraries, linkage and optimization opportunities
differ. These ratios do not isolate a collector, allocation or engine cost.

## Frozen compiler, module and tool identities

Compiler/library basis is `4176e304a0d329af62787f2cfaabb1f72816c3e8`, above
`87d22a4675eb6b79c466a67e04632e1b95b04c5d`. **Native retains that earlier allocator
basis.** Later split/inline allocator improvements on the publication stack are
outside this comparison. Preparation is commit `3c47998`; the launch dependency
correction is `2aee881`. Their integrated counterparts are `a6b39c6` and
`25e3a78`; integration does not substitute freshly built artifacts into this run.
Upstream suite revision is `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`.

| Workload | Production linked Wasm SHA-256 | Exact native-final Scheme Wasm SHA-256 |
| --- | --- | --- |
| sum1 | `9a57746e747678c1ff85b8b8d63f8ddf8e832ccd9f8e761edf526a46303b1b5f` | `2fc8bd4337237ee9af6c3af7a4b16d32a615309cfe8133acaf5897196328ff3b` |
| read1 | `2f80eb5611d557a4364aa1d911176dfeb943d539cfd36a24bc3fd32cef188639` | `e7ead840c0be14fa89ce28a10f4e9a313e40256e6ece630f27e72b45b5b9da8d` |

The corrected [plan](../2026-10-14-strict-reader-timing-correction/timing-plan.json)
has SHA-256 `f23d33d0620bc56698f4519aa4b2e03e9e11e5440d1c9fd4e1417e6a5eaf90f3`;
its [runner](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-strict-reader-timing-correction/measure-seven.py) has
SHA-256 `e2ddab6bec989227cf9b639fd98f16ad75dfced6e11b414395a2ca3d0645ccfd`.
It verifies 111 identities before every sample and after the campaign. These
include the selected executables, both native-final modules, generated LLVM,
provider objects and Wasm, Rust archive, source/input/configuration files,
control programs and host glue. All production Scheme Wasm and the timed Rust
Wasm passed through mandatory Binaryen optimization; raw outputs remain in
preparation evidence.

Tools are Node 24.19.0 / V8 13.6.233.17-node.51, Chez 10.4.1, Binaryen 132,
Rust 1.95.0 (LLVM 22.1.2), and clang/LLD 22.1.8. Exact commands, tool binaries,
target-library identities and tool-version output are frozen. Rust is built
from the unchanged reference sources, with native and `wasm32-wasip1` artifacts
validated separately before timing.

## Source, result and I/O boundaries

The [preparation report](../2026-10-14-strict-reader-preparation/README.md)
retains the complete original sources, counted reversible edits, all successful
and failed preparations, complete stream observations and retained generated
work. The source kernels preserve original ordering, aliases, loops, opacity
calls and predicates. Real configuration parsing occurs during setup before the
clock. Every workload iteration opens its unchanged file, reads through EOF and
closes it inside the clock. The final predicate follows the full count loop.

Sum1 keeps the original operand order, 0.0 initial sum and `1e-9` tolerance.
Its sequential binary64 result is `15794.97500000012`, bits
`4669908993664929039`; the independent decimal sum is `15794.975`. Read1 keeps
its simultaneous `do` updates, including the original counter, and returns the
complete final `(should return this list)` datum after reading all five datums.
The typed numeric domain is I64/binary64 with documented complex components;
this is not an unrestricted Scheme numeric-tower comparison.

Counts 1, 2 and the full canonical counts pass across raw/optimized Wasm, native,
original Chez and adapted Chez. Complete canonical stream observations cover
300,000 semantic fields for Sum1 and 16,576 for Read1, each with a final count
marker. They cover **one complete input invocation**, not internal traces of all
25/2,500 iterations. Full-count I/O cycles/results, changed-file repeated calls,
negative predicates, immediate malformed-input boundaries and retained loop
inspection supply the repeated-work checks. The native-final V8 control also
passes complete results and full-count file-boundary validation.

Adapted Chez uses the identical kernel edits and exact Scheme reader/datum
bodies, with typed products/refs represented by vectors and scalar services
implemented by Chez. Its character, number and symbol operations differ from
the production Rust scalar services. Original Chez remains the unchanged
algorithm/reader reference. Both controls agree on every tested canonical
field; arbitrary unsupported forms and all Unicode-version classifications are
outside the equivalence claim.

Rust Sum1 scans whitespace-separated text into f64 without a general datum
reader. Rust Read1 buffers the whole UTF-8 file into `String`, builds `Vec<char>`
and owns `Atom(String)` / `Vec<Datum>` values. It does not convert numeric atoms
into Scheme numeric objects or intern symbols. Its complete canonical stream
is independently interpreted through the recorded serialization/observer
boundary. All native/raw-Wasm/optimized-Wasm complete outputs and full counts
pass before timing. These are useful algorithm/layout controls with different
allocation and reader contracts.

Snail strings store I32 Unicode scalars; this frozen native backend already
packs numeric arrays, including four-byte character elements, with eight-byte
references. Both production targets reuse the same Rust scalar-service source.
Native timing removes the diagnostic opacity counter but retains the foreign
call. Existing resource/array release and root-depth bookkeeping remains at its
normal production basis. No new GC/heap overrides were applied, and equal
allocations are not claimed.

## Read1 performance hypotheses

These are **source-based hypotheses, not measured attribution**. Adapted Chez
is already 4.567× original Chez, so substantial cost accompanies the shared
reader algorithm and representation before the remaining 1.850× Snail/V8 gap.
The [retained-work evidence](../2026-10-14-strict-reader-preparation/retained-work.md)
shows the parser and worker loops survive optimization.

- `read-word` builds a mutable Unicode buffer and then a substring. For an
  ordinary symbol atom, `atom-token` calls `string->number`, `identifier?` and
  `string->symbol` in sequence. Each uses `stage-text`, copying the complete
  token through scalar calls into a fresh owned Rust text handle. The Rust
  service uses a checked `BTreeMap` handle lookup; symbol interning also uses a
  stable table. Avoiding redundant transfers is a concrete candidate to test.
- Each `read-char` / `peek-char` resolves a checked scalar port handle, and
  whitespace classification calls another scalar service. Adapted Chez uses
  Chez's native character-port operations. Rust input is buffered with
  `BufReader`; this is **not** a claim of one syscall per character. Production
  linked Wasm can inline some scalar calls, so source call counts are not a
  measured machine-level overhead estimate.
- Container parsing builds a reversed temporary list and then constructs the
  final datum pairs. A mutable Datum pair contains two explicit Ref fields;
  token/result variants and per-token buffers add other allocation paths.
  These paths remain visible in optimized code, but allocation counts and GC
  shares have not been measured. Chez vectors and native runtime objects have
  different headers, collection and optimization behavior.

The common-module native/V8 Read1 ratio is 1.113×, much smaller than either
system's gap to original Chez. Native-only allocator behavior therefore cannot
explain the full original-Chez comparison. Sum1's smaller 1.074× V8/adapted-Chez
gap also makes the symbol/container-heavy path worth isolating. No profiling,
new timing or production optimization was added during packaging.

## Timer, host and launch lineage

The campaign ran serially on CPU 5 of an Intel Core Ultra 7 270K Plus from
2026-10-14 19:12:00 UTC to 19:14:18 UTC. Immediate before/after snapshots retain
model, topology, affinity, load and frequency policy. `intel_pstate` / powersave,
800–5,500 MHz policy bounds and turbo enabled were unchanged. Instantaneous
frequency varied; it was not pinned. Other agents held builds, guests,
profiling, compression and publication during the 137.831-second window.
The OS file cache was uncontrolled and warmed by preparation/discards.

Each retained process is fresh. One discard round precedes seven retained
rounds; rotations place each system in every within-round position exactly
once. Sum1's 56 processes precede Read1's 56. V8 uses its default tiering; a
fresh process is neither cold storage nor a prewarmed V8 instance. Per-process
timeout is 120 seconds. Every process exited normally and cleanup found no
executing owned group members.

V8's workload clock surrounds the bench export call including argument/ABI
transition. Native uses `CLOCK_MONOTONIC` around its bench call. Chez retains
the original timed harness, and Rust its original `Instant` boundary including
initial result construction and final assertion. Configuration/module startup
precedes each workload clock; output formatting and cleanup follow it. The
reported process clock also includes startup, capture, intermediate record
writes, leader reaping and bounded group cleanup. No process-clock ratio is
presented as pure startup cost.

The first launch under the superseded plan stopped on a missing Python
supervisor dependency **before any sample process started**. Its zero-sample
campaign, traceback, release and immediate policy snapshots remain in the
[correction evidence](../2026-10-14-strict-reader-timing-correction/README.md).
The corrected freeze includes the full local import closure, checks callable
contracts and module origins in default verification, and uses a new output
path. All benchmark artifacts, sample order, exclusions and timing boundaries
are unchanged. The completed 112 processes form one new complete campaign,
not replacement samples selected from a failed measurement set.

`measurements/` retains every raw record plus the complete campaign and
immediate host snapshots. `package.py` independently rechecks output framing,
commands, environments, order and cleanup, and recomputes all medians/ranges.
The separately written [root review](independent-review.json) independently
checks all 112 records and 111 frozen hashes; its [script](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-strict-reader-comparison/independent-review.py)
hardcodes the original preparation paths. That review validates records and
flags, while live process ownership and quiet-window release come from the
owned terminal session recorded in `quiet-window.json`.

`artifacts.tar.xz` freezes the selected replay inputs, raw records and launch
correction; `manifest.json` identifies every member and external tool. Every
member is re-read and hashed after compression. The original preparation
archive remains unchanged. Archive `frozen/` paths are relative to the original
worktree, while plans retain their original absolute paths; relocating and
executing a new campaign requires a newly verified path mapping and quiet
window, not just extraction. This report adds two measured workloads; historical
reports keep their original coverage basis.
