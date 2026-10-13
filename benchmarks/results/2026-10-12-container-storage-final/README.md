# Container and field storage: measured benefits and regressions

Concrete storage helps the allocation/access kernels but the final API head
`b218ce2` is **6.51% slower** across the five selected real workloads: geometric
candidate/baseline elapsed ratio **1.0651**. Lattice regresses about 25% and graphs
about 8%. These are selected workloads, not a full-suite result. A separately
measured generated-WAT pair-reader experiment at ordinary checkpoint `22c2006`
recovers about 3% in graphs and does not help lattice; it is a diagnostic, not a
production change or an API-head speedup.

The old baseline is `f07d1eb12f7c7234463a606a09190325a3c906b5`, whose production
code equals `d4f0d4203a8adc9cd1f1f338d991da31794ae725`. Ordinary field/vector/binding
storage is frozen at `22c2006f64c5ea322bd77ae080e007e625534d25`; the later explicit
Array/Storage interface is frozen at `b218ce27cd5f7a157b68a450899c6805f041e856`.
Sources, original inputs, Node binary and host scripts match where the experiment
compares identical Scheme source. Ordinary builds reuse the same verified Rust
runtime. The API layer has its own recorded runtime hash.

## Primary final API-head original-five results

| Workload | Old s | Final API head s | Chez s | API/old |
| --- | ---: | ---: | ---: | ---: |
| cat | 20.250026 | 21.014144 | 0.696717 | 1.0377 |
| lattice | 16.257771 | 20.358708 | 1.164074 | 1.2522 |
| wc | 10.453222 | 10.246147 | 0.647350 | 0.9802 |
| graphs | 7.732137 | 8.369200 | 0.764933 | 1.0824 |
| deriv | 2.155066 | 2.142225 | 0.418194 | 0.9940 |

All 60 executions passed, with one discarded preliminary and three retained
observations per cell. The selected-five API/Chez geometric elapsed ratio is
13.616. [clean-api-five-summary.json](clean-api-five-summary.json) retains all
samples, ranges, original inputs and module/source/tool provenance. Cat's API
range is 20.602–21.261 s versus old 20.235–20.271 s; deriv ranges overlap.
Final API and earlier ordinary observations are independent batches and are not
mixed. Both use the guarded cat output check and the clean methods below.

## Clean original-five results at the ordinary checkpoint

| Workload | Old s | Ordinary on s | Chez s | On/old |
| --- | ---: | ---: | ---: | ---: |
| cat | 20.352641 | 20.662006 | 0.695766 | 1.0152 |
| lattice | 16.156802 | 20.569047 | 1.161834 | 1.2731 |
| wc | 10.498335 | 10.450251 | 0.648438 | 0.9954 |
| graphs | 7.714572 | 8.365014 | 0.763813 | 1.0843 |
| deriv | 2.198597 | 2.134742 | 0.417621 | 0.9710 |

All 60 executions passed: one discarded preliminary and three retained
observations per cell, balanced variant order, original corpus counts. Every
execution is a fresh default-tier Node/Chez process; the preliminary is not an
in-process warmup. Node uses CPU 5 affinity, a plain host and no profiler, probes
or GC flags. Other build/test jobs were held idle for each clean window.
Ranges and all retained samples are in [clean-five-summary.json](clean-five-summary.json).
For example, cat's old range is 20.323–20.483 s and ordinary range 20.634–21.183 s.
Small differences should retain the three-observation scope.

The guarded executed harness deletes `cat.output` before every invocation and
then verifies all 4,460,056 bytes against the original input SHA-256
`2994b446dfb07d7cf324fb6aa32d519b3f0bd53a582268714adf08df5f45b8d3`.
Its SHA-256 is `22ac750e3aff9925c10b4d7363487c170fa8c2a0fb0d52ea1d2619aba6b69a47`.
Only this executed version is retained for reproduction; the old unguarded
baseline-worktree helper was not used for these observations.

Final linked module sizes old/on are cat 505,755/510,591 bytes, lattice
560,327/560,087, wc 527,224/536,085, graphs 576,156/578,704 and deriv
531,774/533,600. Size alone does not establish hot-code size or runtime cost.

## Native storage kernels and small-value controls

| Kernel | Old s | Ordinary off s | Ordinary on s | Old/on | Off/old |
| --- | ---: | ---: | ---: | ---: | ---: |
| F64 vector update | 0.303979 | 0.379276 | 0.065369 | 4.650× | 1.248× |
| I64 vector update, values above i31 | 0.556248 | 0.758925 | 0.211511 | 2.630× | 1.364× |
| Small-integer/i31 update | 0.352659 | 0.722641 | 0.365427 | 0.965× | 2.049× |
| Boolean update | 0.419032 | 0.832948 | 0.278370 | 1.505× | 1.988× |
| Shared mutable F64 cell | 0.423689 | 0.421541 | 0.102540 | 4.132× | 0.995× |
| Managed pair vector, numeric car updates | 0.532570 | 0.638117 | 0.132561 | 4.018× | 1.198× |
| F64 append, direct | 0.478127 | 0.478969 | 0.468994 | 1.019× | 1.002× |
| F64 append, opaque | 0.456984 | 0.458013 | 0.454098 | 1.006× | 1.002× |
| I64 append, direct | 0.421442 | 0.431615 | 0.415868 | 1.013× | 1.024× |
| I64 append, opaque | 0.429283 | 0.429421 | 0.416370 | 1.031× | 1.000× |

These are kernel seconds: construction and complete final checksums are outside
the timer. Process seconds include startup, module compilation, construction
and checking and are retained separately. Arrays have 65,536 elements; common
counts were selected by discarded baseline pilots and then frozen across
variants. All 142 executions passed (22 pilots, 30 preliminaries, 90 retained).
Configs, process results and ranges are in [clean-micro-summary.json](clean-micro-summary.json).

The old/off regressions are material. The supported
`(storage-optimizations-enabled #f)` control disables inferred concrete lowering
and also changes shape-driven copies/call selection and optimizer output. Public
wrappers and closure-environment structs remain shared conventions. It is a
broad compiler control, not a pair-only or pure payload-only intervention.

The i31 control uses small exact values already represented without a fresh
integer box in generic storage; it is about 3.6% slower than the old compiler.
Boolean values also use shared singleton objects. Their gain is not evidence of
removing one allocation per Boolean element. No retained-heap size claim is
made from type widths or constructor requests.

Append was already a bulk-copy operation in the old compiler. Generic append
copies references to existing numeric objects and need not allocate a new
numeric box per copied slot. Reached native array copies therefore do not predict
the strong update-loop gains. Here bulk append changes little.

## Separately frozen explicit Array/Storage follow-up

| F64 update interface | Off s | On s |
| --- | ---: | ---: |
| Ordinary source at 22c2006 | 0.379889 | 0.065385 |
| Same ordinary source at b218ce2 | 0.311596 | 0.065368 |
| Explicit Array F64 at b218ce2 | 0.083724 | 0.040231 |

Matched i31 off/on seconds are 0.722020/0.365692 at 22 and
0.373788/0.364539 at the API layer. Enabled ordinary controls match closely.
The large off-mode recovery is observed; its cause is unresolved. Static
projections find identical normalized raw update bodies but different final
inlining of single-value checks. That does not quantify their contribution.

Explicit F64 direct append off/on is 0.462071/0.462919 s; opaque append is
0.452267/0.453721 s. Ordinary API-layer append remains about 0.457–0.470 s.
No uniform typed-over-opaque append win is established. All 72 executions passed,
with frozen counts from the ordinary microkernel batch and three retained per
cell. [clean-api-summary.json](clean-api-summary.json) contains every cell/range.

Explicit Array contracts remain native even when the ordinary optimization flag
is off. API-vs-ordinary source also changes annotations, worker interfaces and
calling conventions, so it is not a one-change storage isolation. Cold numeric
initialization uses checked generic vector writes because its ordinary numeric
expression infers Number; timed typed writes remain F64. Initial fixture source
rejections and attempted corrections are retained separately from successful
builds. The redundant general API fixture's unresolved type-argument rejection
is retained, not reported as a passing run; broader correctness uses the archived validation
bundle's 60 successful linked Array tests.

## Reached representation evidence

The ordinary set has 18 on/off modules, 40 linked small-input correctness checks
and 30 separate counter checks. The API set has 10 modules, 30 kernel-specific
checks and 20 counter checks. Direct, opaque (both runtime-selected branches)
and dynamic apply paths are checked; apply is excluded from the bounded timing
matrix. Full element checks verify copy freshness, overlap, shallow reference
identity, aliases, mutation and scalar sentinels outside timing.

| Source role, small inputs | Actual enabled Wasm evidence |
| --- | --- |
| F64/I64 numeric vector | Reached `(array (mut f64))` / `(array (mut i64))`, 32 reads and 32 writes at size 8, rounds 3, including initialization/checks |
| Boolean data vector | Reached `(array (mut i32))`; Binaryen canonicalizes its final name to `$text`, despite its source being Boolean data |
| Managed reference vector | Reached `(array (mut (ref $pair)))`; native bulk copy preserves element identity and shallow mutation aliases |
| Shared F64 cell | Reached mutable F64 struct payload, shared by updater and observer; update returns unspecified |
| Numeric pair fields | All 9 reached user pair-constructor requests (1 seed + 8 elements) in the corrected loop use native I64/F64 payloads; 33 car reads and 24 writes |
| Record fields | Coverage reaches a record payload with mutable I64/F64 fields and retains identity through an alias |
| Captures/bindings | Reached native environment fields and shared readiness/cell structures; physical helpers separately check early reads and failed RHS retaining the old value |
| Explicit Array F64 | Native construction/get/set and 6 native array.copy requests per 3 append rounds survive direct, opaque and apply boundaries in both flag modes |

Actual type definitions and reached sites are retained in
[micro-shape-summary.json](micro-shape-summary.json) and the archive. Names cannot
establish source-object identity: Binaryen merges identical physical types.
One-field numeric structures can denote boxes or canonicalized captures; source
roles and contexts must be mapped before calling them scalar boxes.

Counts cover whole invocations, including initialization and checks, but exclude
constant global initializers. They increment before operands evaluate and are
**reached requests**, including potentially failed/aborted operands. They are
not completed operations, materialized V8 allocations or causal time fractions.
Instrumentation changes engine optimization; all its durations are excluded.

Preparation caught a recursive target mismatch at superseded 4de272c: the first
pair iteration used the native copy but later iterations entered an unscanned
generic body. Corrected ordinary code records the emitted target and bridge
dependencies. Exact 0c5574a and 22 probes agree on solved/emitted recursive target 295
and all native user iterations. Superseded artifacts and interrupted graphs
preparation are diagnostic history, not successful final observations.

## Regression controls and the pair-reader experiment

| Workload, new independent batch | Old s | Ordinary off s | Ordinary on s | WAT split s |
| --- | ---: | ---: | ---: | ---: |
| lattice | 16.084084 | 48.908180 | 20.450333 | 20.543681 |
| graphs | 7.770063 | 14.912774 | 8.390588 | 8.145002 |

All 32 executions passed. These observations are independent of the original
five batch; their medians are not mixed. The split first reproduces byte-identical
unchanged controls at every captured build stage, then rewrites only pair-reader
factoring in pre-Binaryen WAT using the same pipeline. Constructors, layouts,
selected callers, raw carriers and error paths remain in scope. Final shape
checks show context-dependent optimization: lattice retains its general reader
boundary, while graphs exposes boxed fast paths and an unused typed fallback.
Reached constructor and indirect counts equal on/split exactly; this does not
establish identical physical allocations.

Graphs' on range is 8.314–8.441 s versus split 8.122–8.195 s: a 1.0302× ratio,
about 2.93% less elapsed time. Split still takes about 4.83% longer than old.
Lattice ranges overlap and the median changes by +0.46%. This bounds the tested
mechanism; it does not explain all residual slowdown or establish an API-head fix.
[regression-summary.json](regression-summary.json) retains full ranges/sources.

Counter evidence sharply differs by workload. Lattice reaches only 160 typed pair-constructor requests
versus 23,518,721 boxed pair-constructor requests, but reaches 1.836 billion generic car and
794 million cdr helper entries. Its eqv entry count is exactly 2,051,078,150 in
old/on. Graphs reaches 101,303,886 native I64-car pair constructors plus 3,915
managed-vector-car pairs and 2,219,629 boxed pairs. Native fields execute there.
Broad off adds many generic callbacks: lattice indirect requests rise from
685,124,754 on to 2,786,349,444 off; graphs from 392,341,822 to 653,517,541.

[regression-counts-summary.json](regression-counts-summary.json) breaks requests
down by actual type/operation and context, including eqref carrier arrays,
closures, cells and environment structs. Legacy vector arrays carried public
data, arguments and environments; they cannot all be called argument vectors.
New `$slots` may also be canonicalized with other identical arrays.
[constructor-class-deltas.json](constructor-class-deltas.json) retains signed
class changes with all constructor operations summed, including small controls.

## CPU samples and GC traces

Six separate default-tier executions collect CPU profiling and GC tracing
together, without request probes, over complete processes. All predicates pass.
Scope includes initialization/checks; observer timings are not clean timings.
[sampling-summary.json](sampling-summary.json) retains precision intervals and
top sampled functions, with raw profiles/logs in the archive.

GC interval allocation sums old/on/split are 53.239/51.916/51.916 GB for lattice
and 64.874/62.537/62.536 GB for graphs. These V8 trace counters include startup,
exclude final uncollected bytes and Rust allocations inside linear memory, and
do not partition Scheme allocation classes. They do not show increased scoped
allocation volume at the slower ordinary checkpoint.

Lattice's rounded pause sums are 31.6/19.1/20.7 ms, with rounding intervals
17–411/11–440/12–441 ms. Included scavenge phase sums are 260/282/285 ms;
thousands of tiny events round to pause=0.0. Graphs' pause sums 349/391/396 ms
have intervals 264–479/313–508/317–512 ms. Do not add scavenge to pause, interpret
zero-rounded pauses as free, or equate these stop-the-world walls with total GC
CPU: concurrent/background work is outside that duration.

Mapped hot contexts are Scheme library member-by/memq, lattice lex-first/check,
and graph comparison/permutation callbacks. Binaryen inlines eqv into the old
member worker more extensively; changed self-sample attribution to eqv does not
prove added comparator work. Counts show equal eqv requests. Sample fractions
are unweighted sampled stacks over whole processes, not causal cost fractions.
Original/final identities, import-adjusted function indices and WAT excerpts are
retained in [wat/regression/source-map.md](wat/regression/source-map.md).
[profile-function-map.json](profile-function-map.json) maps named sampled frames
to final import-adjusted Wasm indices without treating samples as time fractions.

Remaining generic paths can reflect heap-loaded values, mutation, copy budgets
or unknown callback origins. The builtin specialization pass tracks known named
procedure identities and directly applied lambdas; earlier diagnostics identified
literal callback operands that remained generic. Other passes can establish call
targets, so this is not a blanket classification of every anonymous lambda in the
final pipeline. Quote payload precision and remaining generic-read boundaries
are hypotheses for future work, not measured causes established here.

Graphs' ordinary preparation took about 626.6 s under concurrent work. Trace
intervals place about 514 s around copy emission/module assembly and about 0.8 s
in the final storage solve. Raw WAT has 235 specialized entries plus 2532 ordinary
nested functions. This suggests emission scalability work; a particular linear
capture/cell lookup bottleneck is unproven. No controlled compilation-speed ratio
is claimed from preparation durations.

## Validation and reproduction

The archived validation bundle records ordinary unit/check/build/backend/
storage/typing checks and API unit/Rust/Array plus broad build/backend/storage/
typing checks. It separates superseded fixture failures from successful runs,
including the disjoint serial/parallel API typing groups. No production source
was changed by the measurement work.

[manifest.json](manifest.json) records every archived logical file and its hash,
frozen compiler snapshots, tool/host/module provenance and the archive checksum.
[artifacts.tar.xz](artifacts.tar.xz) is 45,613,504 bytes, SHA-256
`6c4a5421436a8f12450d06bf086fc311d0a300b92da60337c10d62e4bb69806d`.
It preserves sources/modules, exact commands/tools, original inputs, all raw
records, profiles, counters, patches, failed attempts and validation logs. Cat
payload duplicates are excluded; verified byte sizes/checksums remain.

Restoration verified all 1,931 unique blobs (1,043,716,098 uncompressed bytes)
and 4,772 logical files, then preflighted 24 frozen full-workload cases, 30
ordinary microkernel cells and 18 API cells. It did **not** repeat clean timings.

```sh
python3 benchmarks/results/2026-10-12-container-storage-final/repro/run-frozen.py \
  --output /tmp/snail-container-storage-restored
```

After separately coordinating a quiet host, add `--run-clean final-five` to
repeat the frozen final API/Chez comparison. Other choices are `ordinary-five`,
`micro`, `api` and `regression`; microkernel replays use the original frozen
counts without recalibration. Each invocation requires a new output directory.
The default command verifies/restores/preflights only. The exact clean drivers
and preparation scripts are archived; no rebuild is needed for frozen runs.
