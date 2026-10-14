# Prepared paraffins and gcbench strict ports

Both source ports pass canonical correctness and separate structural checks.
**Paraffins has passed independent review and awaits coordinated timing. Gcbench is
canonical-correctness-ready, but its intended live-heap retention is unproven on
both strict and Chez and its measurement remains blocked.** This report contains
no performance samples, medians or speedup claims.

| Workload | Unchanged canonical input and predicate | Preparation status |
| --- | --- | --- |
| paraffins | 10 repetitions, n = 23, result 5,731,580 | Reviewed and ready for coordinated source-program timing; optimized payload removal is disclosed below. |
| gcbench | 1 repetition, stretch depth 20, always-true outer predicate | Correctness ready; intended tree/temporary-allocation overlap is not established. |

The full input files are retained, including paraffins' unread alternative
workload and gcbench's unused output datum. [Preparation](prepared.json) freezes
source files, both Wasm artifacts, both Chez controls and all commands. The
adapted Chez kernel text is identical to the strict kernel text. The original
Chez programs and outer wrappers remain unchanged.

Paraffins replaces symbol/tagged-vector radicals and products with closed
`H`/`C` and `BCP`/`CCP` variants. Numeric partition vectors, generation order,
symmetry bounds, recursive loops and accumulation order are unchanged. Its
adapted Chez helpers use corresponding tagged-vector constructors, including one
allocated `H` per invocation in place of the original symbol.

Gcbench preserves top-down child assignment and bottom-up construction. Its
adapted record stores two explicit child `Ref` cells and two I64 padding fields:
three source objects per node instead of one, plus one `Nil` sentinel per
invocation instead of the original immediate integer zero. The adapted Chez
control uses the same record/cell change. Compiler closure storage and optimized
layout are additional costs; these source counts are not dynamic allocation
measurements. Base-two exponentiation is expressed with I64 multiplication;
`inexact` converts I64 to F64, and otherwise ignored loop/base results become
Unit. These changes preserve the canonical and bounded validation inputs.

All gcbench diagnostic text and print sites are retained. Strict uses scalar
host calls and synchronous Node writes; Chez retains normal formatting/display.
Formatting allocation, host-call overhead and buffering differ. They remain
inside the canonical workload at the original sites and are not claimed to have
equal costs.

[Correctness](correctness-summary.json) records **86 preparation outcomes**, plus
**two passing raw/optimized Wasm checks** added during independent review:
26 positive raw/optimized Wasm checks, 16 expected Wasm rejections, 10 canonical
Chez checks, and 34 structural Chez checks/rejections. Paraffins runs counts 1,
2 and the original 10 at n = 23; gcbench runs counts 1 and 2 at depth 20. Complete
paraffin encodings at n = 1, 2, 4, 6, 8 and 10 compare every product and recursive
child against the original program, with independent arity/carbon/product-count
checks. Both Chez controls and Wasm reject changed, shortened and extended
expected structures. The canonical outer predicates run once after all repetitions
and observe only the final result; gcbench retains its in-kernel array consistency
check at the original site during every invocation.

Gcbench probes at depths 6 and 8 traverse every node and every array element,
check the order and multiplicity of completed-tree observations, reject malformed
shape and padding, and check independent child mutation. The event stream also
contains array and edge-case checks; it does not trace individual allocations or
every internal construction step. First, middle, last, short and
long expected-array changes fail. Expected lengths never determine the workload
size. These probes run in separate modules/processes. The canonical modules
export only `bench` and `main`; no deep validation or supplemental reader keeps
fields alive in the timed artifact. Correctness-run durations in command records
are not performance observations.

[Static inspection](retention-audit.json) identifies retained and removed work in
the exact canonical optimized binaries. Paraffins retains partition computation,
nested enumeration, the radical table, fieldless radical/list allocations,
product-list spines, final length traversals and repetition. Binaryen removes
`BCP`/`CCP` objects, product-list head fields, radical child edges and unused tags.
This is valid optimization of the count-producing source program. Later timing
must not be described as a comparison of equal allocation or collector work.

Gcbench retains recursive tree construction, child stores/reads, F64 array
allocation/fill, construction loops and diagnostics. It legally removes unused
padding fields. More seriously for its intended workload, the optimized
long-lived tree is passed directly to `Populate` and is not rooted afterward;
the final empty-sentinel check folds away. The array survives until its final
numeric read. The original source's `(eq? longLivedTree '())` is also necessarily
false for its constructed record, so it provides no portable rooting guarantee.
This audit establishes strict's lost root; it does **not** establish that either
Chez control retains the intended graph. Ordinary correctness cannot settle
that lifetime question.

A separately reviewable proposal is an opaque reference boundary around the
transient-allocation phase, shared with adapted Chez. It must consume the actual
tree root and array, not a folded tag. Verification must establish allocation
before the temporary work, a root through that work, and intact reachable child
edges until the final consumption. A final call alone may allow pure allocation
to move; two boundaries may be necessary. Typed GC extern signatures, Binaryen's
closed-world contract and layout preservation need separate compiler/ABI review.
An opaque Chez procedure created before timing is a possible control, also
requiring verification. Extra calls, host crossings and any representation cost
must be disclosed. This proposal is **not implemented or measured here**. The archive also contains
[parent-produced hand-written Wasm experiments](reference-boundary-proposal.json)
showing typed reference calls, allocation motion past an unpinned collection,
and a bounded before/after-call variant. Their commands, outputs and initial
feature-flag failure are retained. They are neither Scheme compiler support nor
a proof of gcbench retention; they contain no timing.

All **52 compiler files** match
`af02dac81890a00dad92a0a564664ff59aaca102` byte-for-byte. Driver source is frozen at
`8051bdd35d1bb1f74616609f6f20c8fca7d8959d`; preparation ran immediately before that
commit and its source/host hashes match exactly. [Identity](compiler-identity.json)
separates those facts from the checkout HEAD at preparation time.
[Environment](environment.json) records Chibi 0.12, Node 24.19.0, Binaryen 132 and
Chez 10.4.1 with the normal level-2 Chez build. There are no compiler changes in
this port task. [Regression evidence](prior-port-regression.json) confirms all 19
previous input specifications and generated strict sources are identical.

[History](preparation-history.json) records the corrected preparation issues.
The archive retains the earlier paraffins module whose supplemental export
prevented payload removal, as evidence for separating the final probes.
[Replay](replay-check.json) verifies all archived files and executes eight bounded
raw/optimized Wasm and original/adapted Chez checks. Restore with:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-data-ports-replay \
  --report benchmarks/results/2026-10-13-strict-data-ports
```

[Independent review](independent-review.json) combined a fresh no-files Astra
explanation, critical debate, and parent inspection of the kernels, adapters,
driver and all 213 original archive members. It accepted the existing runtime
implementation. A separate witness passes on raw and optimized Wasm and verifies
fresh child Ref cells across two independently constructed nodes; its source,
binaries, WAT, trace and results are in `review/parent-port-review/` in the archive.
All 213 earlier members remain byte-identical; the archive now has 220 files.
The [neutral behavioral brief](simplify-behavioral-brief.md) is preserved. Long validation
routines enumerate complete integration checks; source adapters and Scheme
helpers otherwise remain small direct operations. No broad suite, timing,
publishing or landing was performed by this task. The capability inventory
separates implemented nominal data support, prepared ports, remaining source work
and preceding measured coverage; these two ports add no measured coverage yet.

The [timing plan](timing-plan.json) prepares only paraffins: one discarded trio
and three retained rotating trios, with fresh optimized-Wasm, original-Chez and
adapted-Chez processes pinned to CPU 5. The restored timing directory has passed
all artifact and driver hash checks; gcbench remains excluded. Existing validation
durations suggest about 33 seconds for the batch, with a 90-second quiet window
reserved for scheduling variation. Timing has not started and requires the
parent's explicit coordination.
