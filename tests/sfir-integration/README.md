# SFIR integration contracts

`../../scripts/test-sfir-integration` checks all 307 retained compiler cases in
`cases.json`. Each case names one authored `.sfir` fixture. The runner verifies
that the two inventories agree, compiles with the direct SFIR frontend, and
executes both the raw diagnostic module and mandatory-Binaryen optimized module.
`run.mjs` preserves the original assertions, including ordered scalar observers
on the same instance after an expected `WebAssembly.RuntimeError`.

The case identities and original source hashes are recorded in `migration.json`.
The source base was `78734dd`; the subsequent compiler checkpoint `6983894` changes
inference scheduling and removes the old gradual emitter. A disposable converter
outside the repository performed the one-time syntax migration. It is neither
shipped nor invoked by a runner. Target fixtures contain explicit lambdas,
attached signatures, lexical blocks, simultaneous `let`, recursive definitions,
and two-branch conditionals. Existing constants and mutable operations remain.

Five former detached-signature tests now explicitly check rejection of syntax
removed from SFIR. They do not establish the old detached-declaration rules.
`overload-macro` and `data-hygiene` retain their runtime overload and nominal-scope
assertions through authored declarations; they no longer test macro expansion.
`string-literals` uses the fixed `String` type spelling and retains all literal,
identity and storage assertions; its former imported type alias is absent.

A normal compiler rejection must identify the selected fixture and match its
specific expected diagnostic on the same line. A timeout, signal termination or
remaining owned process cannot satisfy a negative contract. Each invocation owns
a process group and retains its terminal status and complete captured streams.
This uses the existing arithmetic-runner cleanup policy; there is no new test
framework. Compilation and execution records are correctness evidence, not clean
performance measurements.

The adjacent `../sfir-extern` and `../sfir-io` fixtures retain their original
custom hosts. Their runner commands are `scripts/test-sfir-extern` and
`scripts/test-sfir-io`. The extern fixture's former macro-produced local foreign
binding is now explicit and distinct from its surrounding parameter.

## Library integration fixtures

The adjacent `sfir-bytes`, `sfir-extern`, `sfir-integer`, `sfir-io`,
`sfir-numbers`, `sfir-reader`, `sfir-text`, and `sfir-write` directories retain the
custom Node and C hosts and independent data oracles. Scalar trigonometry remains
in `../sfir-math.sfir` with its existing Node/C hosts. Their corresponding commands
are `scripts/test-sfir-<name>`.

These runners compile static target sources. They may generate input values,
malformed byte streams and independent expected answers. Scheme datum streams
remain Scheme data, and external Chez oracle programs remain `.scm` files.
Neither is a target-language elaborator.

The Integer runner imports the ordinary `test-integer` entry point at production
radix and at radix 4. The latter build uses the authored
`../sfir-integer/small-radix/sfir/integer.sfir` override. A read-only comparison
requires the complete override to equal the production library except for the
two exact `radix` and `limb-bits` declarations. Separate build outputs and a check
of the emitted production-radix constant verify that the library selection
actually differs. No source file is rewritten during execution.

The bytevector literal boundary uses two authored fixtures, containing exactly
10,000 and 10,001 bytes. The first still checks every stored value on both Wasm
forms and native64; the second must fail at the literal's source location.

The Number boundary checker uses frozen external Chez controls under
`../sfir-numbers/chez`; it writes test data without creating Scheme program
syntax. It checks their source identities, exact scalar-formatting bytes,
token ownership failures and complete reader streams. Optional canonical
Sum1, Read1 and Parsing controls come from static benchmark files. These
correctness runs do not provide clean performance measurements.

The Chez provenance retains its original library freeze and separately names
reviewed compatible snapshots. A run must match one complete snapshot; it
records the chosen profile and current input hashes. The scalar-extension and
borrowed-stdin review covers existing numeric and owned-file reader operations,
not the new scalar APIs, standard input, or unchanged initialization costs.

`scripts/test-backend` also runs `test-sfir-numbers --domain` separately, including
the Rational and Number module assertions. Historical Scheme-only diagnostics
require their recorded source checkouts; their old active runners are retired.

## Focused clarity review

The pinned [simplify workflow](../../.agents/skills/simplify/SKILL.md) used a fresh
explainer without repository access, followed by informed critique. It supported
retaining the existing Node trap observers and independent oracles, made the
removed-syntax coverage explicit, and prompted process-completion and actual
small-radix selection checks. A generalized test framework and a runtime source
rewriter were unnecessary.
