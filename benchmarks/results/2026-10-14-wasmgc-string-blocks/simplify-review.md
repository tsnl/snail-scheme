# Focused String storage explanation and debate

Scope: the newly changed Unicode String section and physical layout/module
assembly in strict-wasm.sld, its three integration fixtures and TOUR.md. The
frontend, typeclass design, existing vector operations and other backends stay
outside this focused refactoring.

A fresh Sol 6.1 maximum-reasoning explainer received no conversation history,
repository files, implementation or diffs. It used no tools. Its neutral brief
specified concrete Unicode String behavior, owned fresh copies including empty
results, literal permissions, identity/Top witnesses, rooted references,
operand ordering, checked I64 bounds, full pre-write validation, overlap and the
unchanged full workload. It described a fixed-length scalar sequence with
identity and write permission, then proposed fresh flat storage for short
strings and chunked storage for long strings. It explicitly left performance,
engine thresholds and chunk capacity unresolved.

In the informed debate, the implementation owner supplied inspected facts:
operands are already held in rooted locals, existing String used an i32 array
with a permission word, array.copy provided complete range checks and memmove,
the layout registry determines concrete signatures, and Top checks a semantic
witness. The debate challenged a direct-first-block owner with an optional
remaining-block directory, removal of a separate storage-kind field, backward
copying for every rightward same-owner copy, and bounded native span copies.

The refined model requires only permission, unsigned length, first array and
optional directory. For capacity C, the first array has min(length,C) cells;
lengths at most C omit the directory, and longer strings have
`(length - 1) >> log2(C)` remaining-block slots. Interior arrays are full and the
last array contains the exact remainder. Computing the directory count occurs
only in the long-string branch, excluding zero-length subtraction underflow.
Rooted backing locals and installed directory entries keep all arrays alive
before the completed owner is published.

Four unsigned I64 comparisons establish the complete copy contract before
narrowing: at <= target length, end <= source length, start <= end, and
end-start <= target length-at. Unsigned comparison rejects negative values;
unsigned extension preserves lengths above I32_MAX. Permission is checked even
for an empty copy. Copy loops do no block lookup when remaining length is zero.

Forward spans use the smaller remaining room in both current blocks. Backward
spans use the room preceding each exclusive end, subtract that bounded span,
then copy from the resulting starting cursors. Those cursors stay in the blocks
selected by the old ends minus one. Descending spans protect future reads for
rightward self-overlap; ascending spans protect leftward overlap. A native span
retains array.copy's memmove behavior within one block. Reversing a disjoint
rightward same-owner copy remains correct, so no overlap boolean is needed.
The debate traced capacity four, length ten, both overlap directions, exact
boundaries, short final blocks and destination/source ranges that would fail
after an earlier span without complete prevalidation.

Comparison with the implementation maps these operations directly to the
physical type declarations, immutable owner construction, checked indexing,
complete copy validation, separate directional span loops and rooted literal
constants. The implementation owner inspected the code and fixtures; the
explainer did not perform a source-code audit. Allocation construction, complete
copy validation/dispatch, directional VM copy loops, literal initialization and
the exhaustive module/layout dispatch exceed the ten-line target where keeping
one complete operation exposes its guarantee. Other new helpers describe one
complete read, write, index, block, room or bounded-span operation.

Rejected alternatives include an explicit storage-kind field, a directory for
every short string, substring views, shared mutable backing, byte-only scalars,
and a new native ownership runtime. These either add redundant state/allocation
or violate the stated contract. The pass stops with each storage operation and
its invariants visible in one cohesive module; no further semantic simplification
is supported by this review. The chosen capacity and added short-string owner
remain performance tradeoffs to measure.
