# Complete Sum1 and Read1 preparation

Both complete upstream workloads pass correctness preparation on raw linked
Wasm, mandatory Binaryen-optimized linked Wasm, the actual native backend,
untouched original Chez and adapted Chez. The separately prepared controls add
V8 running each exact native-final Scheme module and unchanged Rust programs on
native, raw Wasm and optimized Wasm. No clean timing result is claimed here.
Historical measured coverage remains 37 of 57 workloads, 36 paired with Chez.

The compiler/library basis is `4176e30` in this isolated worktree, above
`87d22a4675eb6b79c466a67e04632e1b95b04c5d`. This retains the earlier native
allocator; later allocator changes on the publication stack are not silently
substituted into one arm. The upstream suite revision is
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`.

| Workload | Original count | Unchanged worker input | Original expected result |
| --- | ---: | --- | --- |
| sum1 | 25 | `inputs/sum1.data`, 1,100,000 bytes, 100,000 decimal numbers | `15794.975`, absolute tolerance `1e-9` |
| read1 | 2,500 | `inputs/parsing.data`, 28,300 bytes, five complete datums | `(should return this list)` |

The observed sequential binary64 sum is `15794.97500000012`, bits
`4669908993664929039`; all Scheme and Rust result observations agree exactly.
The independent decimal sum is `15794.975`. The Read1 data file is the complete
original source fixture, including every earlier datum; the worker still reads
through EOF and returns the final datum.

## Source and typed boundaries

`reader_ports.py` retains the complete original kernels, comments, copyrights,
worker calls and counts. Counted edit ledgers reverse to the source. A read
returns a typed value, EOF or error; the adapter raises returned syntax errors
immediately at the original `read` expression, before a later read can run.
Sum1 unwraps real-valued numbers for the original left-to-right binary64 sum,
starting at `0.0`. It keeps the original operand order and tolerance predicate.
This is the canonical real-number domain, not a general numeric-tower port.

Read1 keeps the original `do` bindings and simultaneous updates: new `x` is the
next read, new `y` is the old `x`, and the original unused `i` increments remain
in source and the inspected generated loop. Empty input returns Datum `#f`.
The outer loop also starts with Datum `#f`, preserving the zero-count Read1
result. Sum1's zero-count numeric predicate still fails. Every worker crosses
the original pathname-opacity boundary exactly once.

The real strict reader parses all three canonical `input.txt` datums during
setup before the clock, including the expected datum. Every counted worker
then opens, reads and closes its data file inside the clock. The final original
predicate runs after all workers and remains inside the clock. Setup parsing,
module initialization and terminal cleanup are separate from worker I/O.
No expected-datum host service, pre-parsed constants or benchmark-name reader
fast path is used.

Adapted Chez executes the identical edited kernel and the exact Scheme bodies
of `(snail datum)` and `(snail read)`. A local compatibility boundary represents
typed products and refs with Chez vectors, erases annotations, and implements
the explicit scalar services with Chez characters, interned symbols and checked
native numbers. Original Chez uses its own reader and unchanged kernel. The
compatibility layer is a control representation, not the production runtime:
token ownership uses consumed vectors, numeric conversion uses Chez
`string->number`, and Unicode character classifications follow Chez's database.
The complete canonical streams and the listed edge cases agree; arbitrary
out-of-domain error wording and every Unicode-version classification are not
claimed equivalent.

The [implemented library contract](../../../doc/strict-reader.md) explicitly
bounds numbers, syntax, equality and identity. Exact numbers fit I64; inexact
components use binary64. Rational/bignum values, datum labels, cycles and case
directives remain unsupported. Malformed number tokens do not become symbols.
Strict symbols have stable runtime-lifetime identities independent of legacy
literal-root initialization. Exact/inexact values and signed zeros differ under
datum equality, while all NaNs are equivalent under the selected contract.

## Correctness evidence

The authoritative core freeze is `build/strict-reader-ports-attempt6`. Counts
1, 2 and the original 25/2,500 pass on all five Scheme paths. The instrumented
WASI host checks the ordered open/read/EOF/close cycle and complete byte count
for every worker, with exactly one setup input close and no successful-worker
dependence on terminal cleanup. Native records the corresponding resource
release counts. These are correctness runs, not clean samples.

Twenty-one edge fixtures run across the five Scheme paths: wrong predicates,
missing/extra/reordered/dotted expected results, empty files, comments, Unicode,
false final values, order-sensitive floating sums, exact radix integers,
nonnumeric input, malformed tokens and zero counts. Separate probes change
the real file between two calls, compare complete result traces, and verify
that the second call observes the changed content. A malformed number followed
by an invalid UTF-8 sentinel checks immediate error ordering on raw/optimized
Wasm and native. The first error is the malformed token, not a later read.

The exact adapted-Chez parser is also compared against the original native Chez
reader on every canonical datum field: 300,000 semantic fields for Sum1 and
16,576 for Read1. Each recorded stream includes one extra final count marker.
The earlier [reader-library evidence](../2026-10-14-strict-reader-library/README.md)
provides the matching raw/optimized/native complete-stream observations and
30 valid streams, 51 syntax errors, three UTF-8 errors, repeated EOF, mutable
pair aliases, independent strings and stable symbol checks. Internal traces
cover one complete input invocation; they are not full 25/2,500-invocation
internal traces. The full-count programs, per-worker I/O observations and
[retained code paths](retained-work.md) establish the repeated-work boundary.

`build/strict-reader-controls-attempt2` freezes the non-counting native timing
provider and the remaining comparison artifacts. The exact native-final Scheme
modules run on V8 with a separately pruned Rust/WASI provider. Only the Scheme
module is identical between this V8 arm and native; Rust provider targets,
linkage and optimizer opportunities differ. The provider's reversible export
table edit removes unused legacy entry points before mandatory optimization.
Interface checks retain exactly the required scalar exports and reject legacy
Scheme-root imports. Complete canonical/changed-file results and full-count
file boundaries pass on this extra path. Final timing-host, wrong-predicate and
provider-error/cleanup checks are retained separately in
`build/strict-reader-controls-validation-attempt1`.

## Rust and storage differences

The unchanged Rust sources are useful controls with explicitly different
representations. Sum1 scans whitespace-separated number text and parses f64;
it does not implement the general Scheme reader. Read1 buffers the whole file
as UTF-8 `String`, builds `Vec<char>`, and constructs owned `Atom(String)` and
`Vec<Datum>` values. It performs neither Scheme numeric-object conversion nor
symbol interning. Earlier datums are released as the reader proceeds. Scheme
uses typed numeric/symbol variants, recursive datum pairs and explicit refs;
its strings store I32 Unicode scalars. This native compiler already uses packed
numeric arrays, including four-byte string scalars, and eight-byte references.
Headers, ownership and collection still differ.

Rust native/raw-Wasm/optimized-Wasm all pass counts 1, 2 and the full original
counts. Separate reversible observation edits compare all 100,000 parsed f64
bit patterns in Sum1. For Read1, the observer serializes each Rust datum and the
independent Chez observer compares every semantic field with the original
canonical stream. This validates the canonical interpretation through that
serialization boundary; it does not give Rust a general Scheme datum contract.
Wrong expected values fail all three Rust controls. The selected timed Rust
Wasm is the recorded Binaryen-optimized artifact. The toolchain and raw artifacts
remain archived. Six existing Rust reference-library tests also pass.

Native timing removes the diagnostic opacity-counter increment while retaining
the foreign call. Native's existing `released_resources`, `released_arrays`,
`root_depth` and `peak_root_depth` bookkeeping remains at its default production
basis; no new heap or GC overrides are applied. Neither source correspondence
nor these checks imply equal allocation counts or an isolated GC comparison.

## Frozen plan and failures

[The plan](timing-plan.md) and [standalone runner](measure-seven.py) specify 112
serial fresh processes: one discarded plus seven balanced retained samples for
each of seven systems, separately for each workload. All original inputs,
selected artifacts, module/provider glue, runtime archive and tool identities
are frozen. The default runner only verifies identities. Clean clocks require
the coordinated quiet-window release; preparation and incidental command times
do not count as benchmark measurements.

All attempts remain separate. The earliest standalone extraction attempt retains
its helper snapshot and the subsequent missing-file command record; its initial
generation traceback was not separately captured. Earlier failures include the initial Scheme-body
extraction anchor, an R6RS control's unavailable `gensym`/`define-values`, blank
lines in Read1's configuration, lost execute permission during artifact reuse,
and the adapted-Chez zero-count initial-value mismatch. The first standalone
provider pruning failed because Binaryen's export-list parser interpreted angle
brackets in legacy export names; the successful attempt uses the checked export
table edit. A timing-entry template mismatch and an overly narrow static count
of f64 additions were corrected before the freeze; their exact snapshots/errors
are retained. The extra f64 addition converts elapsed seconds, while the worker
addition remains in its input loop.

Builds and guests use bounded owned process groups. Normal exit and timeout
cleanup kill surviving group members and check for no executing descendants;
the timing runner additionally reaps the leader in its final cleanup. Expected
failures are explicit nonzero exits, never accepted timeouts. Every preparation
build and guest handle is terminal. `manifest.json` and
`archive-verification.json` inventory and verify the complete preparation
archive: 2,937 files, 46,796,564 compressed bytes, all member hashes verified.
The bounded archive process exited successfully with no executing descendants.
The earlier committed library archive is referenced by identity and is not
rewritten here.
