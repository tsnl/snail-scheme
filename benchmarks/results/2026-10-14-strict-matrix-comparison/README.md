# Complete Matrix comparison

All **56** planned fresh-process executions passed. Seven predetermined samples
from the first round are discarded; each median below uses seven retained
processes, each performing the unchanged **2,500** complete searches with five
columns and invariant size five. The complete ordered five 6-by-5 matrices are
checked. No sample was replaced or removed.

| Implementation | Median workload seconds | Retained range | Median process seconds |
| --- | ---: | ---: | ---: |
| Snail / production Wasm / V8 | 0.705711 | 0.701784–0.715511 | 0.729759 |
| Snail / native-final Wasm / V8 | 0.700726 | 0.699039–0.702965 | 0.726318 |
| Snail / native | 1.901276 | 1.890884–1.906404 | 1.903374 |
| Original source / Chez | 0.476001 | 0.475010–0.478845 | 0.506609 |
| Adapted source / Chez | 0.483595 | 0.482915–0.485378 | 0.514275 |
| Rust / native | 0.859275 | 0.856010–0.875435 | 0.861860 |
| Rust / Wasm / V8 | 1.622901 | 1.606197–1.668991 | 1.647962 |

Production Snail/V8 takes **1.483× original Chez time**, **1.459× adapted Chez
time**, and **0.435× this Rust/Wasm control's time** (2.300× faster). Adapted
Chez takes 1.016× original Chez time. Using the **identical native-final Wasm
module**, native Snail takes **2.713× V8 time**. Native Snail takes 2.213× this
native Rust control's time. These descriptive results do not isolate a collector,
allocation, code-generation or representation cost.

## Two Wasm identities make the engine comparison explicit

The native build starts from production optimized Scheme Wasm, then performs
additional Wasm optimization before generating LLVM. Parent review identified
this distinction before timing. The superseded six-system plan was never run;
the accepted seven-system plan retains both V8 artifacts.

Production V8 uses SHA-256
`f047b9cfbebd9127dfde44fb28efd80a9f3da1bd736352218e05e5f325013f46`.
The exact native-final Wasm is 39,444 bytes, SHA-256
`dfb9d40d9544334b3328aa041cbff50d30f40b28a65fc6bb690ea0e62f7e31cd`.
Only the second V8 row and native Snail use that same final module. The native
executable has SHA-256
`f5209b3e8833647312ae29f118188517a0451e252f82702cf6be3352bfb139ee`.
The final Wasm, LLVM, provider object, runtime Rust archive and build record are
frozen and checked. All production Scheme Wasm passes through Binaryen.

The non-counting native provider differs from its validation provider only by
removing opacity-counter increments. Both original external opacity calls remain
in each invocation. The final native executable passes full count before timing;
the same native-final module also passes an additional V8 count-2,500 correctness
run with exactly 5,000 opacity calls.

## Source and correctness boundaries

The [preparation report](../2026-10-14-strict-matrix-preparation/README.md) retains
the complete 805-line original, attribution, all attempts and 30 reversible
source edits. Compiler basis is `3dcce402047a02ef10c92bf6f005ad45f139e2da` and
upstream suite revision is `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Input
SHA-256 is `94ba158dbb0ff1582db6ff64d7e865369576b69fd48fa0e8f374200422bcca8a`.
No production compiler or library change is part of this port. Later native
array-storage changes are outside this frozen comparison.

The complete modular arithmetic, row/subset enumeration, lazy permutation
callbacks, maximality tests, recursive search, mutable prime chain and ordered
answer collection remain. Tagged cursor/reply, GCD and answer alternatives make
the source's mixed values concrete; refs retain boxes and mutable prime tails.
The adapted Chez kernel text is identical to the strict kernel. Its compatibility
operations and runtime representation still differ. The GCD eta expansion may
change closure allocation before optimization; equal allocation is not claimed.

Original/adapted Chez, raw/optimized Wasm and native pass counts 1, 2 and 2,500.
Seventy complete observation comparisons cover independent small searches,
arithmetic, row spaces, callback/enumeration order, mutable aliases, collector
cap transitions and repeated calls. Sixty predicate checks include changed,
missing, extra and reordered values plus nonpositive counts. Expected diagnostic
failures preserve text and terminal statuses. A separate Chez audit checks 32
immutable-spine/state identities; strict physical immutable-spine identity is
not claimed. The canonical observation covers one invocation's full answers and
prime chain, **not every internal operation of all 2,500 searches**. Full-count
executions, opacity counts and retained loop/call paths provide distinct evidence.

The numerical domain is bounded I64 arithmetic for this workload, not an
arbitrary Scheme numeric tower. The four message symbols become a closed integer
protocol, not a general symbol implementation. Invalid adapted messages retain
the procedure/format text and explicitly print the message code.

## Rust and allocation limits

The unchanged Rust source passes its two existing tests and complete canonical
plus four independently modeled small results on native, raw WASI and optimized
WASI. The selected Rust/Wasm is the explicit-feature Binaryen-optimized artifact;
raw output remains a correctness control. Rust is a separately validated
algorithm/layout control, not an identical adapted-source control.

Rust retains modular row reduction, dependency filtering, signed-permutation
maximality, recursive search and complete answer construction. Persistent rows
and matrices use `Rc`; prime chains, inverse tables and partitions use vectors.
Methods/enums replace the closure protocol, vector prefixes replace part of
subset construction, and mutable `Best`/`VecDeque` replaces Scheme state products
and answer lists. Rust computes only the needed inverse coefficient rather than
the source's three-value GCD callback. It explicitly drops the tester and uses
reference counting, while Scheme collection and optimizer liveness differ.
The zero-count initial result and unused message/error paths also differ.
Canonical/small ordered output agreement does not establish arbitrary failing
input, full internal trace, lifetime or allocation equivalence.

Scheme coefficients and Rust coefficients are I64/i64; Rust dimensions/counts
use native 64-bit or WASI 32-bit `usize`. The validated inputs fit both. The frozen
native executor uses eight-byte array slots, including I64 inverse entries;
WasmGC objects, native object padding and Rust `Rc` layouts differ. Static
retained-work excerpts show search/payload construction and all outer loops.
They are not dynamic allocation counters, and legal intermediate elimination
is not evidence of equal allocation.

## Reviewed clocks and quiet window

The [plan](../2026-10-14-strict-matrix-preparation/timing-plan.md) and
[runner](../2026-10-14-strict-matrix-preparation/measure-seven.py) were reviewed
before release. Runner SHA-256 is
`b69b2e7806684d73a8760c50a54e4e3fbeb3a770f6bb58d0190849cea7bb3da5`;
plan SHA-256 is
`27ad980f6dfbae3702fd5dd20f7eda357eb3fc849a34161e80f4001ddaccddec`.
All 59 identities passed before each sample and at completion. The plan's
awaiting-release status remains its original preflight state; the explicit
release and completed execution are recorded separately.

The 56 processes ran serially on CPU 5, with default V8 tiering. After one
discarded complete round, seven rotations put every system in every retained
position once. Other agents held heavy execution; no builds, source edits,
compression or archive replay overlapped the clean clocks. The one campaign
ran from 17:06:13 to 17:07:11 UTC on 2026-10-14. Its parent launch duration was
58.164 seconds, distinct from individual process and workload clocks.

Both V8 clocks surround `bench(2500)` and the host's flag assertion. Native
times `bench`, including the complete guest predicate. Both Chez programs use
the original integer-jiffy interval, including the final predicate and ending
`current-second` read. Rust starts after input/expected parsing and includes its
loop, `black_box` calls and full result assertion before `report` reads elapsed
time. Input setup, loading/instantiation and all terminal output are outside the
workload clocks. The process clock includes startup, capture, final group
cleanup and leader reap. Full timer details remain in the reviewed plan.

Immediate before/after snapshots both report **Intel Core Ultra 7 270K Plus**,
`intel_pstate`, `powersave` governor and `performance` energy preference, with
800,000–5,500,000 kHz policy bounds on CPU 5. They do not establish a fixed
operating frequency. The older preparation snapshot is also retained. Requested
Node/debug/preload and actual native-GC overrides were absent; inherited locale,
library path and timezone were checked throughout.

Every sample required zero exit status, empty stderr, exact canonical output,
finite nonnegative elapsed time and no executing member of its owned group.
The 300-second deadline was never reached. Cleanup tolerates a vanished leader
and handles descendants after normal exit as well as timeout; zombie/dead states
count as stopped. Every group check passed. Rust's historical CSV label is
`rust-wasm` on both targets; frozen commands identify their actual execution.

## Evidence and replay

`measurements/` contains the campaign and all 56 raw records. `summary.json`
independently recomputes medians, ranges and ratios from exact output framing;
`host-before.json`, `host-after.json`, `host-launch.json` and `quiet-window.json`
record policy and coordination. The archive contains selected artifacts, native
final build inputs, plan/runner, complete expected input and raw measurements.
External executable identities remain explicit in its manifest.

```sh
python3 benchmarks/strict-suite/replay.py /tmp/matrix-comparison-replay \
  --report benchmarks/results/2026-10-14-strict-matrix-comparison
```

Preparation and comparison archives are separate. Earlier reports and artifacts
are unchanged. The parent integration updates combined historical coverage; this
single-workload campaign is not a fresh whole-suite result.
