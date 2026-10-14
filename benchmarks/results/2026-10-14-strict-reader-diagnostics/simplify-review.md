# Focused explanation review

Scope is the new `diagnose.py` and `analyze.py` modules. Production reader,
compiler and provider implementations are outside this review. A fresh,
history-free explainer received the behavioral brief through the parent agent:
observe frozen full-count executions, retain raw evidence and boundaries,
validate result/file/resource behavior, and separate samples, counters and
native statistics from clean timing. It did not inspect the implementation.

The useful model has one additive observation mode, one bounded process
transaction and one interpretation pass. The comparison with implementation
kept the original benchmark call and final predicate in their original position;
moving validation beyond the profiler stop would change the observed work.
Each mode states its actual boundary. GC occurrence and later delivery remain
separate. CPU start/stop acknowledgements remain visible rather than assuming
perfect alignment between inspector and host clock domains. Inclusive recursion
counts a complete frame once per sample; unresolved Wasm names stay unresolved.

The critique confirmed that checking aggregate file counts is insufficient:
analysis verifies every worker's complete character count, EOF and close.
Provider counters cannot establish production timing equivalence; native
cumulative statistics include initialization/setup. Missing GC observations must
remain unavailable. A small refinement made timeout, execution failure,
identity-verification failure and cleanup failure distinct in the process
transaction. Completed successful raw evidence was preserved unchanged.

The harness uses direct mode-specific additions with exact source erasure,
rather than a generic observer or supervisor framework. Longer functions retain
coherent operations: the exhaustive scalar-counter callback updates one call's
file/token state atomically; `host_changes` exposes each mode's complete edits;
`execute` owns launch, persistence and cleanup together; `sample_weights` keeps
exclusive/inclusive recursion policy together; archive packaging owns its full
manifest transaction. These exceed the ten-line target because splitting them
into forwarding helpers would obscure their contracts. The small validation
functions keep their complete record invariants together for the same reason.

Verification executes the unchanged linked Wasm in Node, the separate provider
with JS counters in Node, and the frozen native binaries with normal collector
policy. All eight full-count predicates pass. Exact host erasure, 111 frozen
identities before/after each process, every worker's EOF/close cycle, profile
trees/boundary markers, raw-output identities and every archive member are
checked. No further simplification is supported without replacing concrete
observation or ownership boundaries with additional machinery.
