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

## Focused clarity review

The pinned [simplify workflow](../../.agents/skills/simplify/SKILL.md) used a fresh
explainer without repository access, followed by informed critique. It supported
retaining the existing Node trap observers and independent oracles, made the
removed-syntax coverage explicit, and prompted process-completion and actual
small-radix selection checks. A generalized test framework and a runtime source
rewriter were unnecessary.
