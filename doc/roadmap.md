# Roadmap

The active goal is a complete, understandable SFIR compiler and benchmark suite.
[The language contract](sfir.md) defines the target; [the tour](../TOUR.md)
describes the implementation. Chibi continues to host the compiler.

## Current SFIR migration

- [x] Land the SFIR language design before implementation (PR #225).
- [ ] Make `snail-sfir` the sole product command and remove Scheme compilation,
  interpretation, macro expansion and the legacy emitter.
- [ ] Complete the direct located-syntax → resolved IR → inference → concrete
  specialization → WasmGC pipeline, with visible contracts between passes.
- [ ] Retain explicit storage, positional calls, typed externs and library
  specialization; reject unresolved representations instead of adding a fallback.
- [ ] Retire obsolete Scheme-only examples, commands and documentation. Keep
  `build.scm` outside this migration and historical measurements identifiable.
- [ ] Validate the public command, imported libraries, error paths and actual
  linked Wasm/native execution. Compilation alone is insufficient.
- [ ] Complete all 57 bare SFIR benchmark ports with canonical inputs,
  algorithms and result predicates. Keep absent ports and failing targets visible.
- [ ] Measure SFIR, original/adapted Chez controls and Rust, recording native
  versus Wasm separately. Freeze sources, tools, inputs and artifacts; separate
  compile time, clean execution time and instrumented diagnostics.
- [ ] Repeatedly simplify measured compiler and runtime bottlenecks. Preserve
  type evidence and ownership invariants; use independent explanations and
  execution checks to justify each substantial rewrite.

The [corpus manifest](../benchmarks/sfir/corpus.json) tracks source presence,
validation and measurement independently. Pre-migration strict-Scheme results
are historical evidence, not a current SFIR score.

## After the migration

- Broaden typed foreign interfaces and additional 64-bit native targets only
  with ABI and actual target validation. Native remains a mechanical lowering
  of Binaryen-optimized Wasm.
- Add optional affine grades and `Drop` using type evidence to establish cleanup
  obligations. `Top` stays unrestricted; affine values need an explicit shared
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
