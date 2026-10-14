# Complete Matrix preparation

The complete Matrix benchmark is prepared for strict Snail on V8 and the actual
native backend, unchanged original Chez and identically adapted-kernel Chez.
The unchanged Rust reference also passes on native and raw/optimized Wasm. Rust
is a separately disclosed algorithm and layout control, not the same source
program. This report contains correctness and artifact evidence, without clean
performance measurements or a measured-coverage increase.

The compiler basis is `3dcce402047a02ef10c92bf6f005ad45f139e2da`. The upstream
suite is `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. The original input remains
**2,500 invocations**, **5 columns**, invariant size **5**, and the complete
ordered list of **five 6-by-5 matrices**. Expected values are read before the
worker; they are used only by the result predicate. Both original opacity calls
remain in each invocation. Binaryen optimization is mandatory for production
Scheme Wasm, including the artifact consumed by the native backend.
Exact source, input, adapter and preparation hashes are recorded in
[`source-identities.json`](source-identities.json); selected execution artifacts
and tools are checked by [`timing-plan.json`](timing-plan.json).

## Source correspondence

All 805 original lines, the attribution to Andrew Wright, comments and complete
kernel are retained. The 30 counted edits in `adaptation-ledger.json` reverse
exactly to the original kernel. Complete-source and kernel patches distinguish
representation edits from the surrounding benchmark adapter. The typed kernel
is byte-identical in the strict and adapted Chez programs.

Rows and matrices remain persistent lists. A lazy permutation cursor keeps the
original dispatch closure, its captured past/future lists and callback order.
The four source messages become the closed integer codes 0 through 3; tagged
replies distinguish the current object, next cursor and remaining object list.
Absence is an explicit variant. An invalid code still emits the procedure name,
original format text and code before trapping. The original Chez diagnostic
uses a symbol; the adapted diagnostic explicitly names a message code. This is
a closed protocol, not general symbol support or arbitrary-symbol equivalence.

Mutable boxes become refs. The prime chain uses a concrete node with a mutable
tail ref, preserving the original head/last-node aliases and append order.
The best-result state becomes a product of size, result count and answer list;
answers distinguish matrix payloads from the literal `"..."`. All search,
finite-field arithmetic, subset/row enumeration, maximality checks, continuation
calls and collector transitions remain in the source. The 3,000th equal-size
result prepends the marker; later equal-size results retain the existing list.

The extended-GCD negative-input branch originally returns an improper pair
without calling its continuation. A tagged negative result preserves both
fields and the skipped callback. Ordinary results wrap the callback value.
The outer pure helper binding is eta-expanded to meet the polymorphic value
restriction. This can change closure allocation before optimization; equal
allocation is not claimed. The inverse table retains signed Bezout coefficients,
not only least nonnegative residues.

Numbers are explicitly I64. Integer Euclidean division and remainder retain
their original branches; unary negation and nonnegative integer exponentiation
are ordinary typed helpers. This port establishes the bounded integer workload,
not the source's unrestricted numeric tower, rational inputs, arbitrary large
integers or overflowing dimensions. Omitted `do` results become Unit. Existing
strict products, variants, closures, lists and refs suffice; no production
compiler or library change is included.

Original Chez uses the unchanged kernel and harness. Adapted Chez uses the same
kernel edits and small representation helpers, with native standard list and
numeric operations where Chez already supplies those bindings. Its boundary
converts expected answers to variants before timing and compares every ordered
matrix, row and element. It preserves the original initial false result for a
nonpositive count. The strict host reads the complete expected shape and values
before timing, then returns the full predicate's integer flag.

## Correctness evidence

Original/adapted Chez, raw/optimized Scheme Wasm and actual native each pass
counts 1, 2 and the unchanged 2,500. The Wasm validation host and counting native
provider observe exactly 5,000 opacity calls at full count. A separately
compiled non-counting native provider also passes 2,500; its optimized Wasm input
is byte-identical, and its provider differs only by removing counter increments.

Fourteen observation fixtures pass on all five Scheme paths, for 70 complete
sequence comparisons. These cover the full ordered canonical answer and prime
append chain for one invocation, repeated calls, four smaller searches, signed
Euclidean arithmetic, determinant bounds, positive/negative extended GCD,
permutation and subset order, shared mutable identities, row spaces, collector
cap transitions, partition comparisons and search callback order. The canonical
observation is **not a full internal trace of all 2,500 searches**. Separate
full-count executions, opacity counts and retained-work inspection establish
the outer workload boundary.

An independent Python model enumerates normalized signed rows and all subsets
for the small cases. Finite-field ranks and exhaustive signed row/column
permutations determine the complete maximal answers independently of the source
search. The row-space oracle checks rank and span using reduced bases; it does
not demand that the source's ordered echelon representation become RREF.
The collector fixture reaches its cap by 2,998 actual transitions, then checks
the entire list through counts 2,999, 3,000 and 3,001. This exercises the helper's
reachable state transitions without claiming that the canonical search reaches
the cap.

Twelve predicate fixtures pass on all five paths, including changed, missing,
extra and reordered matrix/row/element values, the wrong answer variant, and
zero/negative-count false results. Five invalid-message executions retain their
diagnostics and fail with terminal nonzero statuses. They are expected failures,
not timeouts. Strict probes check shared element refs and mutable prime-tail
identity. A supplemental original/adapted Chez audit checks 16 immutable-spine
and state identities per system. Physical immutable-list spine identity is not
claimed as an observed strict-backend property.

The unchanged Rust reference passes its two existing tests, complete count-2,500
output and the four independent small cases on native, raw WASI and optimized
WASI: 15 complete ordered-result checks. Both raw and optimized Rust artifacts
and commands are retained. The optimized artifact uses the established explicit
engine-supported Binaryen feature set. Rust internal canonical search traces
are not compared.

## Rust and platform limits

Rust retains modular row reduction, dependency filtering, signed-permutation
maximality, recursive search and complete answer construction. Its persistent
rows and matrices use `Rc`, while prime tables, inverses and partitions use
vectors. A vector prefix replaces part of subset construction, methods/enums
replace the closure message protocol, and `VecDeque` plus mutable `Best` replaces
Scheme's answer list and state products. Its inverse calculation tracks only
the needed coefficient; Scheme retains the original three-value GCD callback.
Unused message/error paths and the general Scheme numeric domain are absent.
Rust drops owned values explicitly; Scheme collection and optimizer liveness
can reclaim values differently. These controls do not establish equal
allocation, equal lifetime or arbitrary failing-input equivalence. In
particular, Rust count zero starts with an empty answer deque; Scheme starts
with false.

Strict numeric rows use I64. Rust coefficients also use i64, but dimensions and
counts use `usize` (64 bits native, 32 bits WASI); the validated inputs fit both.
WasmGC objects, native tagged objects and Rust `Rc` objects have distinct layouts.
This frozen native backend uses eight-byte array slots. Matrix's numeric inverse
vectors already contain I64 values; this report does not include later native
array-storage changes. Rust's historical `rust-wasm` output label is used by
both targets; the artifact and recorded command identify the actual target.

[Retained-work inspection](retained-work.md) records the optimized Scheme Wasm,
native LLVM and Rust Wasm/native call paths. Keeping source payload construction
does not force every intermediate allocation to survive a legal optimization.
Static allocation sites are not dynamic allocation counters.

## Attempts, review and replay

The archive retains the small capability probe, all four kernel compile attempts,
all five full preparation attempts and the separate alias audit. Initial kernel
attempts exposed missing adapter `caar`, unary-minus and polymorphic-value
contracts. Full attempt 1 hit Chez's prohibition on redefining imported standard
bindings; attempt 2 hit an I64/Unit mismatch in a probe branch; attempt 3 exposed
unspecified argument evaluation order in the probe's three `read` calls.
Sequential reads corrected that harness defect. Attempt 4 passed the initial
canonical and observation checks. **Attempt 5 is authoritative** and adds all
negative predicates, diagnostics, non-counting native, Rust and supervision
checks. No failed attempt was replaced or treated as a successful measurement.

Each preparation build/run owns a process group with a recorded deadline,
stdout/stderr, terminal status and executing-descendant check. Supervision tests
cover a vanished leader, a leader that leaves a child after closing pipes and
an intentional timeout. All three finish without executing descendants. The
timeout is recorded separately from compiler failure. Preparation process clocks
include capture and cleanup; they are diagnostic provenance only.

The [focused simplify review](simplify-review.md) records the fresh no-history,
no-files behavioral explanation and one informed critique. Source, input,
toolchain, generated artifacts, exact commands and all attempted records are
retained in `artifacts.tar.xz` with per-file `manifest.json`. Restore and verify
them without running a benchmark. The recorded archive replay verified all
1,462 files successfully:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/matrix-replay \
  --report benchmarks/results/2026-10-14-strict-matrix-preparation
```

The [six-system timing plan](timing-plan.md) freezes commands, clock boundaries,
identity checks and process order. It requires a separately granted quiet window.
