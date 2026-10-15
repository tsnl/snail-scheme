# Lattice source comparison

This bounded audit compares the historical Rust port with the original R7RS
source at revision85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1. The Rust module is
unchanged from the historical five-case port and is byte-identical to the
current integrated lattice.rs. No Rust implementation or frozen binary changed.
This source-to-source inspection is independent of the original port author;
it is not a newly completed no-file behavioral explainer/debate or a complete
structural-output test. The historical fresh-explainer pending status remains
visible in results.json.

The original `lexico` is a componentwise partial order, despite its name.
It finds the first non-equal component direction, then requires every remaining
component to be equal or have that same direction. Rust's fixed-direction scan
implements the same decision: unequal directions or any incomparable component
return Uncomparable; equal components preserve the current direction. Low/high
symbols become false/true level payloads. Recursively owned sequence elements
replace nested proper lists and per-lattice comparator closures.

Original maps-1 scans the persistent partial assignment twice to collect images
of smaller and larger source elements. Candidates must respectively dominate
all smaller images and be dominated by all larger images. Rust preserves those
two scans, candidate order, Less/Equal and More/Equal tests and early constraint
failure. Neither implementation memoizes comparisons or precomputes an order
table. The lists/vectors of valid candidates are completed before recursive
search, so Rust does not fuse the filter with branch traversal.

Both searches extend a persistent assignment at its head for each candidate.
The original uses an inner source/target pair plus an outer pair pointing to
the previous assignment; Rust combines those fields in one Rc<Mapping> node.
The prior tail is shared, and both source and target element identities are
retained. At enumeration leaves, mapping-sequence traverses this reversed
assignment and copies target references in that order, matching `(map cdr pas)`.
Rust's outer result vectors preserve branch order when extending from child
vectors, corresponding to the source's mapped child results and apply append.
The original may share the last result-list tail; Rust moves references into
contiguous vectors and does not preserve that list-spine sharing. Target elements
and nested result sequence identities remain shared through Rc.

Count-only leaves return one. Both complete a collection of child counts and
sum it. Rust uses u64 vector entries and an iterative sum, while Scheme builds a
linked count list and sums recursively with exact integers. This preserves the
canonical recursion/branch work and mathematical result, but changes collection
layout, allocation, summation association and stack behavior. All canonical
subcounts fit the Rust domain; no unbounded-integer claim is made for the much
larger optional problems45/54/55.

Each invocation constructs l2, maps l2 to itself to construct l3, then maps l3
to itself to construct l4. It executes all four discarded counts in source order
before the selected problem. The canonical selector44 counts l4 to itself,
returning120549. Rust uses explicit black_box for each discarded count, for the
problem input and for the returned count. Exact optimized Wasm inspection shows
these calls and the complete search retained. Lower lattices are not cached or
constructed outside the clock. No timed complete-structure validation was added.

The source's closures, lattice wrapper pairs, mutable selection-list reversal,
linked appends and generic map calls become direct Rust enum comparison,
vector construction and monomorphized iteration. Scheme owns reclamation through
GC; Rust reference counts and promptly destroys temporary vectors/assignment
nodes. These are meaningful representation, allocation and call-cost differences,
not equivalent instruction counts. The search algorithm and asymptotic structure
are preserved; this audit does not erase those storage/control differences.

Sequence comparison assumes elements from the same lattice, hence matching
lengths and nested shapes. Outside that domain Rust zip ignores a short side,
whereas the original can error when its right list is too short; Rust also
panics for mixed level/sequence shapes. Rust parses count/problem/expected as
nonnegative Wasm32 usize and counts as u64; Scheme numeric domains are wider.
Count0 and malformed/unsupported input behavior is not claimed equivalent.

The historical full-count runs establish count10/problem44/result120549 for
this exact artifact. New bounded linked checks establish problem33/result10
and a complete problem44 invocation, plus rejection of wrong11 and120548 in
both the unchanged Rust Wasm and original Chez artifact. A later reader-expanded
checkpoint also passed count1/problem44 and wrong120548, but its binary hash is
different and it is recorded separately. Neither the scalar predicate nor this
source audit is a complete l3/l4 payload or pairwise-comparison oracle. That
limitation is explicit; no broader implementation/review work is started here.
