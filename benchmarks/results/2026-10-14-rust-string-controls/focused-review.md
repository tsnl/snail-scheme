# Focused String control review

The bounded scope is `benchmarks/string-reference-controls/src/main.rs` and its
three probe/oracle files in `tests/`. Canonical reference implementations and
the compiler are outside this review. Two fresh Sol6.1 max explainers received
neutral behavioral briefs without inherited history or file access. The owner
inspected code, debated their models, made edits and executed the checks.

The first explanation describes four independently owned growth results:
formatted first, overlapping suffix copy, overlapping prefix copy and fresh
concatenation. Release of the old root follows first construction; the three
intermediates survive until final construction. Byte/u32 width and initialization
policy vary while input, iteration counts, operation order and final predicate
remain fixed. Growth returns its final buffer, and the whole trial buffer is
opaque before length sampling.

Informed critique rejected returning a record of all intermediates from timed
growth: it would change their observable lifetime and the compiled return ABI.
Separate post-timer audits can retain those buffers for observation without
imposing that work on timing. Compile-time allocation policies keep the four
specializations explicit. The emitted optimized artifact was inspected rather
than inferring retained zero writes from Rust source syntax.

The second explanation separates primary correctness from transformed-artifact
diagnostics. Selected allocation counters include the trial seeds; calloc's
internal allocator calls must not be counted twice. The zero-fill count records
the original reached fill operation under a selected-call marker. This marker
relies on single-threaded, synchronous allocation with no callback. A successful
complete run is required because an increment before a trapping instruction
would not establish successful execution of that instruction.

Informed debate retained exact text recovery after instrumentation removal and
the unmodified reassembly execution gate. The explainer also requested complete
payload checks on both transformed artifacts. Those checks have now passed for
six thresholds in all four modes: 48 actual Node/Wasm executions. Neither a
matching length nor exact instrument removal alone establishes those contents.

The primary full-count checks also compare every element of a separate extra
trial, together with the four one-growth buffers. The original Chez grow/trial
bodies provide complete independent observations at the same boundaries and
threshold500000. These post-timer computations are additional observations,
not the last timed output. Interior corruption with unchanged lengths and
truncation are rejected by the actual payload oracle.

Both explanations distinguish fresh owned allocations from fresh physical
pages, logical fill byte volumes from physical traffic, process RSS from guest
live payload, and WASI.start resource brackets from the workload timer. Audit
executions inside a WASI.start bracket add their own work and must be labeled.
No diagnostic duration is a performance sample.

The resulting implementation directly represents these operations. The longer
Rust timing functions keep start, complete count loop, final expected equality,
stop/report and optional post-timer audit together. Exhaustive CLI dispatch and
complete test cases remain cohesive. Python's complete Chez oracle operation,
atomic text instrumentation with exact recovery, paired artifact preparation and
ordered checking, and report construction are deliberate ten-line exceptions;
splitting them into generic callback machinery would hide their ordering and
provenance. Short ownership/copy operations remain concrete and named.

The pass stopped after these contracts were visible and checks passed. No
additional runtime refactor was justified. Existing full-suite review cohorts
remain separate and explicitly pending.
