# Quicksort benchmark behavior and constraints

Review a bounded addition to an existing strict-Scheme benchmark driver and its
Node host. The implementation is hosted by Chibi and executes compiled WasmGC.
The user requests faithful measurements of the pinned R7RS quicksort workload,
with original and adapted Chez controls. Do not inspect repository files,
implementation or diffs for the initial independent explanation.

The input contains four datums: repetition count 2,500, vector length 10,000,
random-value upper bound 1,000,000, and an unused symbol. Preserve the complete
canonical input and counts. In each fresh process, install the generator's
procedures, prepare a six-state binary64 seed, obscure the two scalar inputs and
comparison procedure, and generate one base vector before the workload timer.
Each timed iteration maps the identity procedure over every element into a
separate vector and sorts that copy in place. Preserve the upstream last-pivot
partition, crossing swap/restoration sequence and smaller-partition-first order.
Do not replace element mapping with bulk copying or alter the RNG equations.
The final timed predicate checks every adjacent pair and stops at the first
inversion. The canonical predicate uses a continuation only for that early false
return; an equivalent short-circuit form is permitted for this positive length.
The unused symbol has no role in the result predicate.

The static language stores homogeneous concrete values; it must not cast a
Boolean into a procedure. The upstream staged procedure bindings are initially
false but are assigned their real procedures before any generator invocation.
Preserve the observable initialization order and mutable seed reset/read
semantics. Numeric conversion may use native I64/F64 operations outside the RNG
arithmetic, whose bounded values remain within the native representation.

Preparation must execute raw and optimized Wasm with default Node behavior,
execute the original and adapted Chez programs, and preserve sources, inputs,
compiler/tools, binaries, commands and outputs. Check original vector size at
counts one, two and 2,500. Supplemental small cases compare every sorted value,
length, multiplicity and source preservation, including singleton, duplicates,
ordered, reversed and equal values. An empty sorting probe may extend beyond the
original positive-length predicate; empty vectors need no identity claim.
Reject changed, shortened and lengthened expected results. Check all values of
the generated canonical base vector against an independent binary64 reference,
and verify generator initialization, seed reset and seed reading. Independently
exercise inversions at the first, middle and last adjacent pair.

Keep source fidelity, static retained Wasm instructions, dynamic execution and
performance claims distinct. The canonical sortedness predicate does not prove
permutation preservation by itself; the supplemental checks provide bounded
correctness evidence. Opacity-call counts do not prove sorting, mapping or
allocation retention. Static inspection must follow the exact timed path,
identify per-iteration allocation and element mapping, recursive partition work,
and final adjacent validation, and distinguish untimed RNG initialization.
Do not claim V8 machine-code or dynamic instruction evidence from Wasm alone.

Clean timing begins only after artifacts and tools are frozen and a coordinated
quiet window is authorized. Use fresh processes, default V8 tiering, CPU 5, one
discarded full trio and three retained rotating trios. Save any invalid
observation and stop without shortened counts or replacement samples. A
complete comparison reports medians and ranges for strict, original Chez and
adapted Chez, identifies representation/helper/harness differences, and leaves
historical reports intact. Correctness runtimes are not performance samples.

Please explain the simplest sufficient high-level model, then give pseudocode,
state invariants, edge cases and unresolved assumptions. Challenge whether any
state or stage is unnecessary, while preserving the required original work and
measurement boundary. The parent owns code inspection, edits and checks.
