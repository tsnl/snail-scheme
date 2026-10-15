# Focused input and Tail review

The pinned simplify skill was applied to new input behavior in `src/snail/io.sld`
and `src/strict_io.rs`, and the bounded Tail adapter/host. Existing compiler
passes and preceding port algorithms were outside the refactoring scope.

A fresh no-history explainer received only a behavioral brief, with no files,
diffs, helper names or existing decomposition. The brief specified scalar-only
Rust/Scheme calls, explicit close/trap cleanup, Unicode/EOF/line-ending behavior,
bounded String storage, linear construction without per-character allocation,
and the original complete Tail workload. The parent retained implementation,
inspection and verification responsibility.

The resulting model separates owned host files, one shared public handle state,
host lookahead, a private Scheme line buffer and the reversed retained line list.
There is no Scheme reference in Rust and no second file reader in Scheme.
Geometric String growth was preferred over reversed `List Char` accumulation:
both are linear, but the latter adds a GC node for every input scalar.

The informed critique corrected two initial suggestions. Idempotent raw close
would weaken the established foreign-call contract; the existing shared Ref
instead changes to the closed sentinel before raw close, while raw absent IDs
remain errors. The original nested callbacks also close output before input,
so that order remains visible in source and file traces. Monotonic IDs prevent
stale callers from acquiring a later resource without retaining tombstones.

Starting a line with an empty String adds no flag: its capacity is its length.
It avoids a 64-character scratch buffer for an empty line and shares the exact-fit
return rule. Growth occurs only when a new content character needs room. EOF or
a terminator after a full buffer therefore succeeds without unnecessary growth.
Capacity saturates at 4,294,967,294; I64 arithmetic safely represents the doubled
bounded values. CR peeking preserves non-LF lookahead. A decoding error after CR
fails that read immediately, unlike the next-call error after LF; no pending-CR
state was introduced to change that existing host behavior.

Rust errors end registry borrows and drop detached ports before reporting a
fatal error because Wasm traps do not run Rust destructors. Scheme traps use the
existing terminal host cleanup boundary. A new generic resource framework,
public string-builder object, per-character lists, separate list reversal,
extra closed/EOF flags, and a host bulk-tail implementation were rejected.

The line loop remains a coherent exhaustive EOF/LF/CR/content dispatch slightly
above ten formatted logical lines. File registry helpers and public operations
remain small complete operations. Longer fixtures and Python validation loops
keep setup, raw execution record, complete-value check and failure evidence
together; splitting them into forwarding stages would obscure that contract.
Existing upstream benchmark functions retain their original structure.

The independent model and implementation now agree at each ownership, read,
growth, finish and close boundary. Actual Wasm/native tests and complete Tail
outputs support those invariants. The pass stopped there; no cosmetic refactor
or broader compiler cleanup was needed. The WASI audit's buffering limitation
is stated separately from the source-level read-all-before-output guarantee.
