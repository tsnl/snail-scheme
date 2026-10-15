# Roadmap

The active goal is a complete, understandable SFIR compiler and benchmark suite.
[The language contract](sfir.md) defines the target; [the tour](../TOUR.md)
describes the implementation. Chibi continues to host the compiler.

## Align with the SFIR book

[PR #226](https://github.com/tsnl/snail-scheme/pull/226) replaces the initial
surface sketch with the [SFIR book](book/sfir/index.md). The earlier migration
below established the measured backend; it does not imply that the new surface
or library APIs are implemented. Work proceeds through these contracts:

- [x] Resolve `def` and sequential `let` with the specified block scope,
  shadowing and source-order initialization. Scope an attached `All` over its
  initializer, including nested annotations.
- [x] Parse library-level `datatype`, `typeclass` and named `instance` bodies
  of `def`, check their kinds, and use `Any` at dynamic boundaries.
- [x] Adopt `define-library`, concatenated body clauses and `(sfir base)`.
  Migrate shipped libraries, examples, tests and benchmark sources while
  preserving their algorithms, inputs and existing numeric representations.
- [x] Evaluate every instance method initializer in source order, including
  unused aliases. Type immediate lambda calls by the ordinary rank-one call
  rule; sequential bindings retain their own generalization rules.
- [ ] Default numeric literals to I32/F64. Only a direct literal annotation or
  binding annotation selects another width; computed values require explicit
  conversion. Check representation overflow at literals and runtime operations.
- [x] Infer recursive groups monomorphically, including annotated and phantom
  instantiations. Generalize after the group while preserving rigid contracts
  and the value restriction; retain source-order readiness checks.
- [ ] Audit class obligations, complete dynamic type identity, call ordering
  and proper tail recursion against the book, with executable boundary and
  rejection tests.
- [x] Separate parsing library data, resolving a supplied library map and
  filesystem discovery. Select an entry through its library's public interface,
  preserving private and re-exported binding identities in the Chibi-hosted API.
- [x] Compile a supplied map, public Entry and Target into optimized Wasm bytes
  or an unlinked x86-64 Linux object. Retain the existing scalar entry ABI and
  keep foreign-provider linking separate.
- [x] Provide explicit Wasm loading, independent instantiation and checked scalar
  Entry invocation through a JavaScript host adapter, with provider checks before
  initialization and no callable instance after failed initialization.
- [ ] Add native loading with independent state and make compiler/execution APIs
  available to SFIR. Implement library generation through an explicit checked
  data-transfer protocol; Scheme elaboration and macro staging remain deferred.
- [ ] Revalidate the full corpus and compare clean timings after migration.
  Retain the existing source and artifact snapshots as historical baselines.

The book deliberately leaves foreign target interfaces and parts of the formal
calculus open. Existing typed extern and ad-hoc overload declaration syntax also
needs an explicit migration contract; these facilities must not disappear as a
side effect of changing the core grammar. Implementation notes and specification
clarifications are updated alongside the corresponding changes.

## Current SFIR migration

- [x] Land the SFIR language design before implementation (PR #225).
- [x] Make `snail-sfir` the sole product command and remove Scheme compilation,
  interpretation, macro expansion and the legacy emitter.
- [x] Complete the direct located-syntax → resolved IR → inference → concrete
  specialization → WasmGC pipeline, with visible contracts between passes.
- [x] Retain explicit storage, positional calls, typed externs and library
  specialization; reject unresolved representations instead of adding a fallback.
- [x] Retire obsolete Scheme-only examples, commands and documentation. Keep
  `build.scm` outside this migration and historical measurements identifiable.
- [x] Remove the boxed Scheme-value runtime and wrapper-finalizer bridge. Keep
  scalar host services, explicit resource cleanup and native managed roots.
- [x] Validate the public command, imported libraries, error paths and actual
  linked Wasm/native execution. Compilation alone is insufficient.
- [ ] Complete all 57 bare SFIR benchmark ports with canonical inputs,
  algorithms and result predicates. Keep absent ports and failing targets visible.
- [ ] Measure SFIR, original/adapted Chez controls and Rust, recording native
  versus Wasm separately. Freeze sources, tools, inputs and artifacts; separate
  compile time, clean execution time and instrumented diagnostics.
- [ ] Repeatedly simplify measured compiler and runtime bottlenecks. Preserve
  type evidence and ownership invariants; use independent explanations and
  execution checks to justify each substantial rewrite.

The implementation migration landed in [PR #227](https://github.com/tsnl/snail-scheme/pull/227),
with frontend, integration, library, public-command and native execution checks.
[PR #228](https://github.com/tsnl/snail-scheme/pull/228) adds full Unicode string
folding through scalar services. The first [six clean measurements](../benchmarks/sfir/evidence/20261015-clean-six.md)
are complete; full-corpus validation and measurement remain ongoing.

The [corpus manifest](../benchmarks/sfir/corpus.json) tracks source presence,
validation and measurement independently. Pre-migration strict-Scheme results
are historical evidence, not a current SFIR score.

## After the migration

- Broaden typed foreign interfaces and additional 64-bit native targets only
  with ABI and actual target validation. Native remains a mechanical lowering
  of Binaryen-optimized Wasm.
- Add optional affine grades and `Drop` using type evidence to establish cleanup
  obligations. `Any` stays unrestricted; affine values need an explicit shared
  wrapper to enter it. Borrow checking and stack promotion are separate work.
- Revisit platform effects, actors and heterogeneous targets on typed SFIR
  interfaces, without assuming that a resource can cross an ownership boundary.
- Add source mappings from emitted code back to located SFIR and future source
  frontends.

## Deferred frontends and self-hosting

A later Scheme frontend may construct located SFIR ASTs inside `generate-library`.
It will perform elaboration and macro expansion, while SFIR owns checking and
optimization. Scheme code may depend on SFIR definitions and must check against
their types. Other languages can use the same boundary.

Cross-module macros, compile-time datum access, staged execution and self-hosting
are deliberately deferred. No Scheme compiler or interpreter is required by the
current goal. Older designs and implementation history remain in Git.
