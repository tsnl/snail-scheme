# Focused Mazefun explanation and source review

Scope: `mazefun_port.py`, its narrow `measure.py` integration and associated
documentation/evidence. The compiler, host and landed frontend were unchanged.
The pinned [simplify skill](../../../.agents/skills/simplify/SKILL.md) guided the
review. A fresh independent explainer, with no inherited history or file/tool
access, completed the behavioral explanation and informed debate before this
finishing pass. The behavioral brief is archived at
`evidence/original-review/mazefun-behavioral-brief.md`.

The following findings are a summary supplied in the parent agent's handoff.
They are not a verbatim transcript; no separate transcript file was available.
The source, patches and probes make the findings independently assessable.

The coordinate itself is the open alternative of `Cavity`, rather than a second
wrapper around a coordinate payload. Every position list contains coordinates.
Cell writes reuse the exact new label, and structural coordinate comparison is
the original cavity identity test. Dimensions have a distinct product role.
The result representation must distinguish initial false, error, complete grid
and invalid expected data; a count or checksum cannot replace the grid.

Flooding must gather neighbors from the cave passed into that invocation. Its
persistent write supplies the starting cave to a left fold, and each recursive
flood supplies the cave for the next neighbor. Changing neighbor enumeration to
read an updated cave would change this dataflow. Copying persistent prefixes,
sharing suffixes and using the coordinate label directly preserve the original
list operations. The two/four-operand append helpers copy each leading spine
once, with a shared final tail. The map helper runs its callback before the tail;
a right-fold substitute would change callback evaluation order.

The actual Scheme reader is necessary to distinguish false spellings, escaped
interned error symbols, arbitrary valid expected datums and malformed input.
Every proper nested mark list must survive decoding in full, including empty
and ragged lists. Boolean marks are invalid. Classifying other datums as an
invalid sentinel preserves the answer, but cannot claim identical invalid-datum
predicate cost. Classification must occur before timing while every positive
invocation and the final complete valid-grid predicate stay inside it.

These invariants support concrete value roles, direct coordinate labels and an
explicit map. They rule out a strict right-fold substitute, mutable array or
union-find replacements and a digest-only predicate. The design retains original
shuffle, removal, fold and flood recursion. No whole-program cleanup was needed.

This finishing pass read the complete original kernel and typed patch, checked
complete-program reversal, and verified that the ready driver/adapter snapshots
match the source commit exactly. Seventeen original definitions, including
local recursion helpers, remain byte-identical. The remaining changes have
visible representation or boundary purposes. Both Chez forms share the same
adapted kernel and helpers; source differences are disclosed in the report.

The Python functions over the ten-line target were reviewed explicitly:

- `coordinate_roles` and `kernel` keep their finite, counted source substitutions
  together so each changed source role and required occurrence count is visible.
- `specification` keeps the complete external reader transaction, input failure
  decision, decoded scalar data and reader provenance together. Its returned
  specification carries the exact decoder source, tool hash, input and output.
- `chez_probe`, `original_datum` and `harness_fixtures` are bounded test builders,
  exhaustive expected-kind decoding and explicit fixture data.
- `build_mazefun_probes`, `mazefun_observations` and `validate_mazefun_outputs`
  keep their four-form build/compare sequence and complete test coverage visible.

These exceptions are cohesive operations or tests. Splitting them into forwarding
helpers would mainly move the protocol and fixture bookkeeping. The Scheme
helpers are short structural recursions; original kernel functions retain their
source structure. This pass made documentation/evidence changes and preserved
the validated generator bytes. It stopped when no further semantic simplification
was justified within the bounded scope.

The identity limitation is explicit. Fifteen assertions per Chez form observe
actual list and coordinate identity. The first strict identity diagnostic tried
to export managed references and failed the existing scalar export contract.
The successful strict probes export scalar complete values/traces only; the
report does not mislabel those as direct Wasm identity observations. Immutable
list recursion and concrete cons lowering remain additional static evidence.

Validation includes 228 behavior executions, two sharing executions with 30
assertions, fourteen additional reader boundary cases, unchanged generated
sources/specifications for thirty existing ports, `make test`, `make check`,
Python compilation and an exact optimized-artifact observer. The observer proves
full repeated work remains for the canonical and invalid-expectation cases,
within the limits stated in the retention report. No clean measurements were run.
