This is a focused behavioral brief for an independent explanation. Do not inspect
repository files, implementations or diffs. Explain the model, then give detailed
pseudocode, invariants, boundary cases and unresolved assumptions.

The task is a one-off diagnostic investigation of an already frozen and validated
WasmGC quicksort program. There is no proposed shared profiler or compiler change.
The input to fixture generation is its optimized textual Wasm and its existing
Node execution adapter. Outputs are diagnostic textual and binary Wasm fixtures,
exact patches, a map from each construction site to its original function and
location, and an adapter that exposes counts after executing the original program.

One diagnostic must count entries to every defined function and every struct or
array construction instruction without changing operand evaluation order, result
values, source control flow or the original exports. A count is an entered
instruction request, including one whose operand subsequently traps, rather than
proof that an engine physically allocated an object. Added numeric state must not
retain Scheme references or invoke JavaScript in the hot path. Setup and workload
counts must be separable: initialization installs procedures and generates the
random base vector before the workload. Instrumentation may change optimization,
register pressure and execution time; those times are diagnostic only.

A second fixture changes only the representation of data captured by private
partition scan helpers. Those helpers do not escape their partition invocation.
The pivot is immutable during that invocation. The fixture may pass their data as
parameters instead of constructing private closure scaffolding, while preserving
every scan comparison, guard needed for valid index access, crossing swap,
restoration of the last pivot, and smaller-partition-first recursive order. Reads
after a crossing swap must use the then-current vector contents. Initialization
and outer sort contexts remain intact. This is a fixture for a fixed closed
program and valid initialized calls, rather than a transformation of arbitrary
Scheme closures. Its removed readiness checks and altered calling convention are
part of the intervention. Repeated unsigned-index checks are also removed, and
the first width check of the second scan index precedes the first index's read.
These checks preserve results for valid initialized inputs, but their
simplification and ordering must be included in the combined intervention.
A time difference cannot isolate allocation cost.

The canonical workload creates 10000 values with the unchanged six-state RNG
before timing, then maps each element into a fresh vector and sorts it 2500 times.
The final adjacent-pair predicate executes after the repetitions. It must retain
the original map initialization writes and per-element copy costs. Separate small
cases cover empty and singleton inputs, duplicates, both input orders, equal
values and early inversion checks. Full-value checks compare expected length and
every value, verify the input was preserved, and require a distinct nonempty
result vector. Incorrect values and incorrect expected lengths must be rejected.

The evidence consumer reads archived CPU profiles, GC trace output, generated
machine code, construction counters and validation results. It must preserve
their different observation scopes. CPU self samples and GC traces cover the
whole process; there are no workload anchors. The GC allocated field represents
the current pre-GC object size minus the prior post-GC size, and excludes the tail
after the final collection. Pause fields are rounded. Static machine allocation
paths establish retained generated instructions; instrumented path frequencies
come from a different binary and do not identify original tier transitions or
precise physical allocation totals. A first CPU profile overlapped another
diagnostic and remains archived with that limitation. An initial feature flag
combination produced a binary unsupported by the pinned Node and also remains
archived as a failed attempt. No comparative speed claim is authorized.
