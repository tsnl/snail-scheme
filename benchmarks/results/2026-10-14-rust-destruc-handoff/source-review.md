# Frozen Destruc source and lifetime audit

This bounded audit inspects the original destructive-list benchmark and its
unchanged Rust module. It does not refactor the implementation or establish a
new fresh independent no-file explanation/debate. That mutable-list cohort review
remains pending. The exact artifact and its45-file build source snapshot are
preserved; the current integrated destructive module has the same hash.

The procedure begins with ten empty rows. For each descending i, if the first
row is empty it ensures every row has its one empty-payload seed and appends m
new empty-payload cells. Otherwise it visits the nine adjacent row pairs in
order. It finds source and target half lengths, writes the first source half
minus its final retained cell, detaches the actual suffix, writes the target's
first half, and replaces the following cell's tail with that suffix. A zero
source half empties the source row and returns an empty suffix. Rust retains
these loops, cell writes and destructive tail transfers; it does not calculate
the known final rows directly or replace the row cells with a value array.

Rust's outer ten rows are Vec<Option<Box<Cell>>> slots rather than ten mutable
outer cons cells. Each inner Box cell carries an Option<usize> payload and an
owned successor; None payload denotes the original empty-list head value and
is distinct from an empty row link. The strict adaptation uses nominal mutable
nodes with separate head/tail Ref fields and an empty/integer Item variant.
These different containers, tags, field widths and allocator policies change
physical costs. No equal-allocation interpretation is claimed.

Inner rows are disjoint initially. A source split partitions one row's spine;
its retained prefix stays in that row, and its detached suffix is transferred
to a distinct target prefix. The overwritten target suffix becomes unreachable.
By induction, rows remain disjoint, even though their cells move between rows.
Unique Box ownership therefore represents the benchmark's transfers without
copying suffix cells, reference counting or a general mutable-pair arena. The
existing native unit test checks a split returns the actual original suffix
pointer. This does not support arbitrary externally aliased/cyclic pair inputs.

The original set-cdr! form leaves argument-expression evaluation order open.
The frozen strict kernel makes source splitting precede destination traversal
with explicit let*. Rust matches that mutation order, but scans target length
before splitting the source, while strict scans it afterward. Disjoint rows make
those lengths independent and the final values agree. Growth also evaluates
allocation before linking it to the old row, so Rust's append helper traverses
after allocating the suffix. No claim is made that every independent read has
the identical chronological position in all implementations.

Rust promptly destroys discarded Box chains; Scheme removes references and
reclaims through GC. Each previous Rust invocation result survives construction
of its replacement, then drops inside timing. Exact optimized Wasm shows the
final owned rows and materialized Datum survive clock capture and Result/CSV
printing, then drop afterward. A Box destructor follows its successor recursively;
this differs from Scheme GC/stack behavior for much larger unsupported sizes.

The existing final predicate converts every row into a generic Datum, converting
integer heads to decimal strings and empty heads to empty-list datums, then
compares the entire nested structure with supplied input. This materialization
is inside Rust timing, once after4000 invocations; original Scheme equal? walks
its actual returned rows directly. Result/CSV formatting and final-result cleanup
follow the clock. Both input dimensions and each returned complete vector are
black_box boundaries; no additional timed complete-output audit is introduced.

Historical actual Node/Wasm and original Chez checks pass the original4000 by
(600,50) input, including every row/value. A separate original Chez oracle keeps
the full procedure body unchanged, removes only final run-benchmark invocation,
and appends untimed write calls. Twelve shapes plus a repeated small invocation
compare every Rust output element/row length with that oracle, including zero
iterations, zero allocation width, empty payloads and odd/even split sizes.
Actual frozen Rust and original Chez reject same-size first-value corruption,
last-row truncation and replacement of an empty payload with an integer.
These33 executions are correctness evidence, not performance observations.

Nonnegative Wasm32 usize count/parameters, owned acyclic rows and canonical
integer syntax bound this reference's domain. Nonpositive outer count behavior,
unbounded Scheme arithmetic, alternate numeric spellings in expected datums,
arbitrary pair aliasing and very deep destructor stacks are not claimed
equivalent. Complete printed values/row lengths are observed in actual Wasm;
a full identity/allocation/mutation-order trace from that binary is not claimed.
