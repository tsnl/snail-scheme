# Both complete Boyer provers measured on seven systems

All 112 predetermined fresh processes passed across the two original full
workloads on compiler/library/runtime basis
`a7079746aa9c79c0cdcd10862a630fa7f2082134`. Each input keeps one invocation
at size 5, successful theorem evaluation and exactly **51,507,739 rewrites**.
Fourteen discarded warmups precede 98 retained observations. Independent raw
replay reproduced every frame, terminal/cleanup record and statistic.

| System | NBoyer median [min, max], seconds | SBoyer median [min, max], seconds |
| --- | ---: | ---: |
| Production optimized V8 | 11.950027 [11.888928, 11.990897] | 3.504130 [3.477071, 3.523674] |
| Native64, default growing GC | 10.299261 [10.289146, 10.324189] | 4.685959 [4.676147, 4.720491] |
| V8 on exact native-final Wasm | 11.909353 [11.842419, 12.038669] | 3.516283 [3.493888, 3.539988] |
| Original Chez | 0.887105 [0.881701, 0.897611] | 0.372582 [0.371107, 0.374323] |
| Exact adapted Chez | 8.047786 [8.039781, 8.067727] | 4.755614 [4.743708, 4.765730] |
| Rust native | 1.985137 [1.972399, 1.991037] | 0.725050 [0.720775, 0.731079] |
| Rust optimized Wasm | 6.208150 [6.104486, 6.215867] | 2.517642 [2.481794, 2.546171] |

Native takes **13.52% less time** than V8 on the exact native-final NBoyer Wasm,
and **33.26% more time** for SBoyer. Production V8 takes 13.471× original Chez
time for NBoyer and 9.405× for SBoyer. Native/identical-Wasm ratios are 0.864804
and 1.332646. These are descriptive ratios of medians from seven retained
observations per workload/system, with every sample included. They do not isolate a collector, engine or representation cost.

Adding these two workloads brings historical coverage to **49/57 measured**,
**48 paired with original Chez**, across individual compiler revisions rather
than a fresh full-suite rerun. The previous checkpoint was 47/46.

The [frozen plan](timing-plan.json) has SHA256
`b650443ae4e2069340561cda8937da9b7416c06090ea02f5b9f5adee751d6773`.
It fixes 112 fresh serial processes on CPU 5: one discarded warmup per
workload/system, followed by seven retained observations each. Each workload
uses seven cyclic rotations, placing every system in each retained position
once. Workload blocks alternate between rounds (four/three first blocks).
This balances positions within each workload, with no adjacency or exact
workload-order balance claim. Fresh processes transfer no guest V8 JIT state;
discarded warmups can warm machine/file caches only.

Seven systems are production linked Binaryen-optimized Scheme Wasm on V8,
mechanical native64, V8 on the exact native-final Wasm consumed by LLVM,
original Chez, the exact adapted Scheme kernel on Chez, Rust native and
Binaryen-optimized Rust Wasm. Native uses the current growing precise collector
with all policy knobs unset. No historical fixed reservation is selected.
Parent reviewed all four runner/preparation/freezer/replay modules and every frozen identity before explicitly releasing the quiet window. The clean runner 57880 reached actual terminal 0/chunk2a9fa4 before the parent ended that window. No builds or compression ran during it.

## Original work, current artifacts and reused evidence

All kernel definitions after the original harness and all 106 installed lemmas
remain, together with association-list lookup, directional unification,
substitution, rewriting and tautology search. Setup runs inside every worker
as in the original executable harness; the upstream comment calling it untimed
does not describe that harness. Quoted constants and three-datum configuration
reads precede the Scheme worker clock. Original rewrite counting is part of the
workload and its predicate. Only extra opacity-counter increments are absent
from the clean native provider.

Both full input files, original sources, upstream/adapted kernels, strict
programs and original-Chez controls regenerate byte-identically to the reviewed
historical preparation. Adapted Chez uses the same adapted prover kernel and
the exact current library prefix, with the historical/current patch retained.
Current Scheme/runtime/native and both Chez controls were freshly built and
executed. Rust binaries, full sources, lowered LLVM, original Binaryen commands
and prior small/negative/reset controls are retained author artifacts, freshly
executed at full size rather than rebuilt here.

The [historical preparation](../2026-10-14-strict-boyer-preparation/README.md)
uses compiler 6fd5ca4/driver 6f4a30e3. Its full ordered lemma/term streams,
identity/alias/unification/reset witnesses and complete work counts remain
separate evidence for the byte-identical source bodies. They were not repeated
as a new full counter campaign. Instrumented outputs and their clocks never
enter clean statistics. Failed ordering/capacity development attempts retain
their original compiler and policy provenance.

The implementation boundaries remain explicit: Scheme uses closed Datum terms,
mutable constructor-record vectors and typed Ref bindings. SBoyer reuses an old
pair exactly when both resulting fields retain their original identities.
Rust retains its separate Rc/indexed-constructor/vector representations,
native bit operations, tail loops and destruction schedule. It scans all input
datums before timing, while Scheme consumes the three used configuration values;
full original bytes are retained for every control. These are implementation
comparisons, not an isolated collector, representation or engine experiment.

## Fresh correctness and separate retention

Preparation 43414 completed actual exit 0/chunk75c08d. All 85 diagnostic commands
have complete raw captures, actual terminal statuses and quiescent original
groups. Both workloads passed all seven full comparison frames plus an extra
raw linked Wasm frame. Forty current small/reset/wrong-rewrite/zero-repetition
controls passed across raw/optimized/native and both Chez paths. Exact native
lowering inputs, scalar import/export closure, mandatory production/native
Binaryen stages, current source bytes and tool/import/library identities are
frozen. The source selector and actual stable Rust toolchain behind tool shims
are identified separately.

Four separate retention processes use the exact clean optimized Wasm/lowered
LLVM/provider/runtime inputs, with only a diagnostic C entry/output changed.
They force collections before and after a setup-only or full worker. All start
with the source-default 256 MiB initial region and no configured hard cap.

| Workload | Setup-only marked bytes / objects | Full post-return bytes / objects | Full diagnostic collections | Automatic final heap / growths |
| --- | ---: | ---: | ---: | ---: |
| NBoyer | 192,568 / 8,539 | 344,000 / 14,790 | 52 | 2 GiB / 3 |
| SBoyer | 192,584 / 8,540 | 344,016 / 14,791 | 38 | 1 GiB / 2 |

Collection-sampled diagnostic peak payload is 912,775,904 bytes for NBoyer and
252,313,048 bytes for SBoyer. These totals describe the separate diagnostic
entry and forced-collection root context. They are aggregate snapshots; even
equal totals would not prove identical survivors or absence of leaks. They do
not measure clean-run peak/RSS, total physical allocation or GC cost. Historical
fixed 2 GiB/1 GiB reservations and default-capacity failures remain old controls;
the fresh current collector grew to those final capacities automatically.

## Capture, environment and independent review

The runner records actual wait status before accepting complete result frames.
It owns the original process group through bounded cleanup, closes/fsyncs raw
stdout/stderr captures, then validates the full predicate/frame. Nonzero exit
invalidates a matching frame. A failed row aborts the attempt before another
row, preserving all data without replacement or trimming. Original-group checks
cannot establish absence of arbitrary escaped sessions; these frozen guests
are non-daemonizing. Interrupted, timeout, invalid-byte and descendant fixtures
retain actual captures/terminal records, including a valid-frame/exit7 rejection.

The environment identity is a frozen relevant-key map, not the full effective
child environment. It records toolchain, path, locale, loader and relevant
runtime controls, rejecting NODE_OPTIONS, LD_PRELOAD, GC and diagnostic overrides.
Unrelated ambient/session values stay in memory only. Explicit environment is
BINARYEN_CORES=1. The canonical map SHA256 is
`77feaf5e652eeb70e08915f1627b9b24b6140bf91cf6f42ad5bb4c7a6b38c17a`.

The [independent reviewer](review-raw.py) imports no runner. It derives both full
predicates from retained original inputs and independently checks schedule,
complete raw frames and statistics. Before timing it replayed all fourteen
canonical preparation frames and rejected 86 corruptions, actual exit 0/bf3f68.
After actual clean runner terminal, it independently read all 112 raw records,
all 1,014 frozen identities and every retained clock, reproducing both workload
summaries; actual e02db3 exited0. The [complete audit](independent-review.json)
retains every interpreted row and read-byte identity. The parent also independently replayed all 112 raw records, statistics and
1,014 identities without importing these scripts or executing guests; actual
`bab7a4` exited 0. Its [script](parent-raw-review.py),
[review](parent-raw-review.json) and [provenance](parent-raw-review-provenance.json)
are separate sidecars added after archive publication. The archive retains the
earlier report snapshot before those sidecars; raw captures are unchanged.
Recorded cleanup still cannot independently rule out escaped sessions. The fresh no-history/no-files model and informed debate are recorded
in [the focused review](simplify-review.md).

## Retained evidence and read-only replay

[The archive](artifacts.tar.xz), [manifest](manifest.json) and
[full archive verification](archive-verification.json) retain every clean raw
capture/record, current source/artifact snapshot, diagnostic frame, synthetic
failure fixture and historical preparation/ordering/capacity attempt. The
historical Git source snapshot verifies all 123 declared compiler/adapter/host
commitments. Its initial incomplete archival source-selection attempt omitted
a declared test fixture; that failed attempt and the corrected snapshot remain
separate. This was post-timing archival work, not a failed benchmark sample.
Cargo/Python caches and external Nix/selected-Rust-toolchain binaries are omitted;
exact tool/import/library identities remain recorded. Selected Rust paths are
mutable locations checked by digest, not bundled binaries.

The runner/reviewer keep the original absolute execution paths. Identity/raw
replay requires those restored paths and matching external tools; archive byte
verification itself needs no guest execution or external tool replay:

```sh
python3 benchmarks/results/2026-10-14-strict-boyer-comparison/package.py
python3 benchmarks/results/2026-10-14-strict-boyer-comparison/measure-seven.py
python3 benchmarks/results/2026-10-14-strict-boyer-comparison/review-raw.py \
  --campaign /tmp/snail-boyer-measurement-20261014/build/boyer-clean-a707974 \
  --expected-plan-sha256 b650443ae4e2069340561cda8937da9b7416c06090ea02f5b9f5adee751d6773 \
  --output /tmp/boyer-independent-replay.json
```

The first command fully decodes one XZ stream and checks every safe regular tar
member against the byte/mode manifest. The next two verify frozen identities
and independently reparse captures. None starts a benchmark guest. A new timing
attempt requires its own explicit coordinated quiet release and fresh output;
this report does not prescribe additional measurements.
