# Numeric literal representation

Run `chibi-scheme -I bootstrap -I tests tests/lofi-literal-widths/check.scm`.
Every attempt retains commands, located rejection diagnostics, inference traces
and actual raw/optimized Wasm outcomes under `build/lofi-literal-widths`.
Execution verifies the effect before either the result or trap.

`defaults.sld` checks I32 and F64 synthesis, direct `ann`, direct `def` and `let`
annotations, an I64 value outside I32's range, exact source-to-F32 rounding,
overload selection and an Any roundtrip. `any-projection.sld` stores an ordinary
integer literal in Any and must trap when projected as I64.

The rejection fixtures stop before specialization. Call operands, function
results, blocks, branches, overloads, constructors and references cannot select
another literal width. Nested annotations and arithmetic results cannot convert
an already typed number. A bare large integer also fails inside Any.

The focused simplify review used a fresh independent no-files explanation and
behavioral debate. Literal construction owns the two direct selection rules;
ordinary expectations still help infer lambda parameters and other nonliteral
expressions. Removing all expected-type propagation would change unrelated
typing behavior and was rejected. The existing exact numeric decoder remains
responsible for source precision and representation bounds.

The [source migration ledger](migration.json) records prior located numeric types, unchanged
spellings and explicit I64/F32 annotations. Existing direct selectors are left
alone. It covers static corpus and library sources, target fixtures and generated
contract source strings. Inference inventories establish numeric representation;
they do not establish fresh benchmark correctness or performance. Historical
benchmark freezes and measurements remain unchanged.

The ledger covers 13,177 prior located literals in 395 static or embedded source
records. It adds 5,556 inventoried annotations and records 20 separately reviewed
annotations in host-generated test programs. All 349 previously accepted source
checks pass. The supplemental 173 rejection checks retain their failures;
13,175 completed literal constructions match their prior widths and target
values. The remaining two literals intentionally overflow before construction.

`inventory.scm` records final checked numeric values, before specialization:

```sh
chibi-scheme -I bootstrap tests/lofi-literal-widths/inventory.scm \
  "$PWD" "$PWD/benchmarks/lofi/ack/main.sld" /tmp/ack-literals.scm
```

The migration comparison normalizes F32 and F64 values to their actual IEEE bits.
The supplemental logger recorded values before rounding; four raw host values
in `literal-source-precision.sld` consequently differ from the final values.
Checking the unchanged fixture with the pre-policy precision compiler gives the
same 19 target values as the migrated fixture. This preserves the earlier exact
decimal fix, including its F32 tie boundary, F64 rounding, largest finite value
and smallest subnormal.

The historical [validation evidence](validation.json), recorded before the native
backend was retired, retains the complete checks, attempts and artifact hashes.
At that checkpoint the 315 target contracts and public CLI, library, native,
instance and recursive-group suites passed. Canonical
benchmark runtime validation and new timing campaigns remain separate work.

An additional [artifact comparison](artifact-parity.json) checks `ack`, `fibfp`,
`array1` and `cat`. Their raw and Binaryen-optimized Wasm bytes are identical
before this policy, after the isolated migration, and after integration with the
class-evidence and Any-projection fixes. This checks emitted code for those four
programs; it is not a new benchmark timing campaign.
