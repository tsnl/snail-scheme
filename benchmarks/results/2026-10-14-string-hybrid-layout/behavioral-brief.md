# Behavioral brief for a fresh String explainer

Do not inspect repository files, implementation, diffs, earlier reviews or other
agents' discussions. Use no tools. First explain the required behavior at a high
level; then give direct pseudocode, invariants, edge cases and unresolved
assumptions. Focus on the simplest sufficient model and explain each proposed
stage or piece of state. Performance claims require measurement.

The compiler lowers an already resolved and concretely typed Scheme String into
WasmGC. Scheme compilation remains hosted by Chibi. This task concerns only the
private String representation and its primitive operations, plus focused
integration fixtures and reproducible workload controls. Frontend type rules,
source operations, Unicode semantics and other concrete collections are fixed.
Private backend representations may differ without introducing source Top values
or changing source type checking.

A String is a fixed-length sequence of Unicode scalar values with identity and
write permission. Character values already reach this pass as valid scalars,
including zero, accented characters, combining marks, supplementary characters
and U+10FFFF. No ASCII narrowing or byte-only representation is permitted.
String length counts scalars. Fresh construction, copying, substring and append
produce independently mutable values, including fresh empty values. Passing a
String through a local, closure, reference cell, concrete record or explicit Top
roundtrip preserves identity and mutation visibility. Literal values are readonly
and rooted module constants; equal literal occurrences may share identity.

Primitive operations are make-string(length, fill), string-length(value),
string-ref(value, index), string-set!(value, index, character),
string-copy!(target, at, source, start, end), and identity comparison. Higher level
copy, append, substring and equality are Scheme operations built on these
primitives. Source operands have already been evaluated once, in their required
order, into native rooted slots before primitive execution. All new heap objects
and references must remain traced by WasmGC while subsequent allocations run.
The implementation must not add a separate manual/native ownership runtime.

Lengths and indices enter as I64. Construction accepts lengths from zero
through 4,294,967,294 subject to engine allocation capacity; reject negative or
larger values before narrowing. Element access requires zero <= index < length.
Copy requires 0 <= at <= target length, 0 <= start <= end <= source length, and
end - start <= target length - at. Check the target's permission even for an empty
copy. All checks must complete before the first write, so any failed copy leaves
the entire target unchanged. Narrowing cannot make 2^32, a negative index, or a
huge length appear valid.

Copy must behave as if the original source range were saved first. Copies
within the same identity may overlap in either direction. Distinct newly mutable
Strings never share mutable payload storage. A same-identity copy to the right
must preserve future source reads; a copy to the left must preserve the other
unread part. Exact payload edges, partial final allocations, zero-length values
and empty valid ranges need explicit consideration. Representative cases are
capacity four with ten scalars, copying [0, 8) to offset two, copying [2, 10) to
offset zero, a range crossing two allocation edges, a range invalid only near its
last edge, and an empty range at the logical endpoint.

Explicit Top conversion already stores a semantic String witness separately
from the managed payload. Projection must reject a Vector Char even when an
engine canonicalizes identical physical array layouts; String -> Top -> String
must preserve the same identity. Private backing references are never exposed
through source operations or the external scalar-only ABI.

The concrete allocation shape must keep scalar payload allocations bounded for
large Strings while avoiding unnecessary allocations for short Strings. This is
a general representation decision, never a benchmark-specific rule. The existing
unchanged full workload repeatedly appends two copies of the current String,
forms two fresh substrings, concatenates them, and replaces the retained value;
it includes all writes, copying and result checks. Small parameter controls of
that same workload and separate runtime string-ref and string-set! loops are
required, since a copying improvement does not establish scalar access cost.
Large-workload throughput must be retained without hiding short-operation costs.
Exact clean timing occurs only in a coordinated CPU window.

Choose a direct behavioral model; distinguish required invariants from optional
representation choices and engine facts that remain unknown. Do not design
other collections, frontends, string views or adjacent runtime features.
