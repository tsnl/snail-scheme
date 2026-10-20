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

`inventory.scm` records final checked numeric values, before specialization:

```sh
chibi-scheme -I bootstrap tests/lofi-literal-widths/inventory.scm \
  "$PWD" "$PWD/examples/fibonacci.sld" /tmp/fibonacci-literals.scm
```
