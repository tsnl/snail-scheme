# Lofi integration contracts

`../../scripts/test lofi-integration` checks every compiler case in
`cases.json`. Each case names one authored `.sld` fixture. The runner verifies
that the two inventories agree, compiles with the direct Lofi frontend, and
executes both the raw diagnostic module and mandatory-Binaryen optimized module.
`run.mjs` preserves the original assertions, including ordered scalar observers
on the same instance after an expected `WebAssembly.RuntimeError`.

`string-utf8-storage` exercises cached scalar boundaries, width-changing
mutation and overlap in both directions, unused backing capacity, and independent
copies. The older `string-blocks` fixtures retain their original large Unicode
inputs and range checks; their names describe the former storage layout.

Every overload alternative now declares its complete signature. The former
`overload-inferred-*` fixtures are named `overload-declared-*` and retain their
ordinary helper inference, class proofs, result selection and initialization
checks. The declared signatures make the former row-cycle and executable-storage
readiness failures valid programs. Five additional rejection cases cover unsigned
lambdas, named implementations, mixed families, unused alternatives and imported
extensions.

Five former detached-signature tests now explicitly check rejection of syntax
removed from Lofi. They do not establish the old detached-declaration rules.
`overload-macro` and `data-hygiene` retain their runtime overload and nominal-scope
assertions through authored declarations. Additional `macro-*` and `scheme-*`
fixtures exercise hygienic expansion, imported private helpers, lexical and type
scopes, repetition, generated definitions and the initial Scheme forms.
`string-literals` uses the fixed `String` type spelling and retains all literal,
identity and storage assertions; its former imported type alias is absent.

A normal compiler rejection must identify the selected fixture and match its
specific expected diagnostic on the same line. A timeout, signal termination or
remaining owned process cannot satisfy a negative contract. Each invocation owns
a process group and retains its terminal status and complete captured streams.
This uses the existing arithmetic-runner cleanup policy; there is no new test
framework. Compilation and execution records are correctness evidence, not clean
performance measurements.

The adjacent `../lofi-extern` and `../lofi-io` fixtures retain their original
custom hosts. Their runner commands are `scripts/test lofi-extern` and
`scripts/test lofi-io`. The extern fixture's former macro-produced local foreign
binding is now explicit and distinct from its surrounding parameter.

## Library integration fixtures

The adjacent `lofi-bytes`, `lofi-extern`, `lofi-integer`, `lofi-io`,
`lofi-numbers`, `lofi-reader`, `lofi-text`, and `lofi-write` directories retain the
custom Node and Rust hosts and independent data oracles. Scalar trigonometry remains
in `../lofi-math.sld` with its existing Node/Rust hosts. Their corresponding commands
are `scripts/test lofi-<name>`.

These runners compile static target sources. They may generate input values,
malformed byte streams and independent expected answers. Scheme datum streams
remain Scheme data, and external Chez oracle programs remain `.scm` files.
Neither is a target-language elaborator.

The Integer runner imports the ordinary `test-integer` entry point at production
radix and at radix 4. The latter build uses the authored
`../lofi-integer/small-radix/lofi/integer.sld` override. A read-only comparison
requires the complete override to equal the production library except for the
two exact `radix` and `limb-bits` declarations. Separate build outputs and a check
of the emitted production-radix constant verify that the library selection
actually differs. No source file is rewritten during execution.

The bytevector literal boundary uses two authored fixtures, containing exactly
10,000 and 10,001 bytes. The first still checks every stored value on both Wasm
forms; the second must fail at the literal's source location.

The Number boundary checker uses frozen external Chez controls under
`../lofi-numbers/chez`; it writes test data without creating Scheme program
syntax. It checks their source identities, exact scalar-formatting bytes,
token ownership failures and complete reader streams. Optional canonical
Sum1, Read1 and Parsing controls come from static benchmark files. These
correctness runs do not provide clean performance measurements.

The Chez provenance retains its original library freeze and separately names
reviewed compatible snapshots. A run must match one complete snapshot; it
records the chosen profile and current input hashes. The scalar-extension and
borrowed-stdin review covers existing numeric and owned-file reader operations,
not the new scalar APIs, standard input, or unchanged initialization costs.

`scripts/test backend` also runs `lofi-numbers --domain` separately, including
the Rational and Number module assertions. Historical Scheme-only diagnostics
require their recorded source checkouts; their old active runners are retired.

## Focused clarity review

The pinned [simplify workflow](../../.agents/skills/simplify/SKILL.md) used a fresh
explainer without repository access, followed by informed critique. It supported
retaining the existing Node trap observers and independent oracles, made the
removed-syntax coverage explicit, and prompted process-completion and actual
small-radix selection checks. A generalized test framework and a runtime source
rewriter were unnecessary.
