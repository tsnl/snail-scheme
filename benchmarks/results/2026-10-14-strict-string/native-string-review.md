# Native String design and focused simplification

The fresh explainer used Sol 6.1 at maximum reasoning with no inherited history,
tools or file access. It received the public String/Unicode/copying contract and
the complete original workload, with both native and nominal-wrapper options.
Its independent model separated object writability from character storage and
identified aliases, empty-copy permissions, complete pre-write range checks,
fresh empty results, source lifetimes and payload-retention evidence.

The parent then supplied inspected compiler facts: Vector Char already is a
native i32 GC array; Top checks a semantic witness; String/literal syntax already
exists in the frontend; and managed-reference externs remain unsupported. The
debate tested a one-array encoding with a private permission word. The explainer
confirmed that it supplies the same state without an additional wrapper and
highlighted the U32_MAX logical-index wrap hazard. Logical offsets now reject
values above U32_MAX - 1 before adding one. Raw length uses unsigned widening.

The representation and primitive boundary directly follow that refined model:
one private array, one literal registry, one checked allocation, one all-or-trap
copy operation, and direct character conversion checks. Scheme owns append,
substring, fresh copy, content equality and list conversions. No frontend edits,
generic builder framework, hidden source-adapter wrapper, substring views or
ASCII-only representation were introduced.

The parent reviewed the implementation and fixtures. The complete native-copy
emitter, exhaustive primitive/layout dispatch, worker construction and module
assembly remain above the ten-line target where splitting would obscure one
operation or its complete alternatives. New library operations each stay below
that target. Long fixtures keep related ownership/failure observations together.

Twelve new contracts pass in raw and optimized actual Node execution, including
Unicode boundary conversions, opaque primitive values, literal alias protection,
empty mutation permissions, operand effects, failure atomicity, overlap, and
String/Vector Char witness separation. make test, make check, and all twenty
native-boundary contracts pass. The full 283-contract suite was started on the
frozen compiler sources; its final status is recorded separately after completion.

This is independent behavioral explanation/debate plus parent-owned code and
test review. It is not an independent source-code audit. Further case conversion,
normalization, grapheme indexing and reference-valued imports are outside this
bounded capability.
