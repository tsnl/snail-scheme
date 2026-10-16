# Roadmap

The active goal is a complete, understandable SFIR compiler and benchmark suite.
[The language contract](sfir.md) defines the target; [the tour](../TOUR.md)
describes the implementation. Chibi continues to host the compiler.

## Align with the SFIR book

[PR #226](https://github.com/tsnl/snail-scheme/pull/226) replaces the initial
surface sketch with the [SFIR book](book/sfir/index.md). The earlier migration
below established the measured backend. The implemented surface and library
contracts, their execution evidence and remaining extensions are recorded below:

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
- [x] Default numeric literals to I32/F64. Only a direct literal annotation or
  binding annotation selects another width; computed values require explicit
  conversion. Preserve existing source representations through audited annotations.
- [x] Decode numeric source spellings exactly, round once to the selected IEEE
  width and reject representation overflow at literal construction.
- [x] Check primitive numeric conversions, including integer narrowing and
  finite floating-point narrowing overflow, on Wasm and native.
- [x] Use wrapping I32/I64 and IEEE F32/F64 arithmetic by default on Wasm and
  native, with identical semantics for direct primitives, overloads and function
  values. Preserve literal, narrowing and division checks and exact Integer arithmetic.
- [ ] Add explicit overflow-checking arithmetic operations when needed. A future
  Scheme-to-SFIR frontend may select them; Scheme frontend work remains deferred.
- [x] Infer recursive groups monomorphically, including annotated and phantom
  instantiations. Generalize after the group while preserving rigid contracts
  and the value restriction; retain source-order readiness checks.
- [x] Audit class obligations, value restriction, dynamic type identity, call
  ordering and proper tail recursion with [executable contract evidence](../tests/sfir-conformance-audit/README.md).
  Selected boundary and rejection cases pass on raw/optimized Wasm, with
  targeted native execution. The audit records its coverage and limits;
  numeric policy and full-corpus validation remain separate work.
- [x] Separate parsing library data, resolving a supplied library map and
  filesystem discovery. Select an entry through its library's public interface,
  preserving private and re-exported binding identities in the Chibi-hosted API.
- [x] Compile a supplied map and public Entry into optimized Wasm bytes. Retain
  the existing scalar entry ABI and keep foreign-provider linking separate.
- [x] Extract a standalone Wasm-to-native package and one shared Rust runtime
  crate. Ordinary Chibi scripts explicitly compose compiler output, native
  lowering and Cargo linking; the compiler API remains Wasm-only.
- [x] Provide explicit Wasm loading, independent instantiation and checked scalar
  Entry invocation through a JavaScript host adapter, with provider checks before
  initialization and no callable instance after failed initialization.
- [x] Execute compiled SFIR producers that construct a limited library syntax
  subset through typed builders and transfer owned structured data into Chibi.
  Preserve explicit receiving-context identities and separate output imports.
- [x] Execute source-level `generate-library` recipes with separate producer and
  application dependency maps, preparation-cycle diagnostics and explicit source
  context for caller-supplied foreign providers. See [source recipes](sfir-generation.md).
- [x] Complete library constructors and typed inspection views for book syntax,
  including explicit type identities, ordered local scopes, static declarations
  and the existing extern/overload extensions. Preserve the checked transfer boundary.
- [x] Add native loading with independent state, a checked scalar bridge and
  explicit providers; see [the native adapter](sfir-native-loading.md).
- [x] Expose explicit library maps, compilation, Wasm loading, independent state
  and checked scalar invocation to ordinary SFIR through an owned Chibi service.
  Return recoverable errors and retain separate provider linkage; see the
  [compiler service](sfir-compiler-service.md).
- [x] Return inspectable first-class `SfirLibrary` values from SFIR parsing using
  the constructive syntax API. Preserve local scopes, attached quantifiers,
  original numeric spellings and source locations through checked transfer;
  compile transformed values with explicit maps.
- [x] Revalidate the full corpus and compare clean timings after migration at
  frozen compiler `8e547bfb`; retain original failures and historical snapshots.
  The later packet-input campaign is separate from that full-suite freeze.

The book deliberately leaves foreign target interfaces and parts of the formal
calculus open. The [extension contract](book/sfir/extensions.md) documents typed
externs and fixed-arity ad-hoc overload declarations alongside named wrapping
and IEEE operations. Implementation restrictions and future adapters remain
distinct from the core language contract.

## Current SFIR migration

- [x] Land the SFIR language design before implementation (PR #225).
- [x] Make `snail-sfir` the sole product command and remove Scheme compilation,
  interpretation, macro expansion and the legacy emitter.
- [x] Complete the direct located-syntax → resolved IR → inference → concrete
  specialization → WasmGC pipeline, with visible contracts between passes.
- [x] Retain explicit storage, positional calls, typed externs and library
  specialization; reject unresolved representations instead of adding a fallback.
- [x] Retire obsolete Scheme-only examples, commands and documentation. Keep
  historical measurements identifiable. `build.scm` now demonstrates ordinary
  Chibi library composition from SFIR through Wasm to a linked native executable.
- [x] Remove the boxed Scheme-value runtime and wrapper-finalizer bridge. Keep
  scalar host services, explicit resource cleanup and native managed roots.
- [x] Validate the public command, imported libraries, error paths and actual
  linked Wasm/native execution. Compilation alone is insufficient.
- [x] Author all 57 bare SFIR benchmark ports with canonical inputs,
  algorithms and result predicates. The checked full57 freeze passes all native
  routes and 56 Wasm routes, preserving Ack's Wasm stack failure.
- [x] Measure SFIR, original/adapted Chez controls and Rust on the frozen full
  corpus, recording native versus Wasm separately. Preserve failed/unavailable
  routes, complete predicates, preparation costs and instrumented diagnostics.
  Report the Mperm timer correction as a distinct campaign.
- [x] Complete focused clarity reviews of [recursive inference](../tests/sfir-recursion/README.md),
  [literal construction](../tests/sfir-literal-widths/README.md),
  [arithmetic lowering](../tests/sfir-arithmetic/README.md) and
  [shared I/O ownership](../lib/sfir/README.md). Retain independent explanations,
  rejected alternatives and target execution evidence for those concrete changes.
- [ ] Investigate the measured full57 bottlenecks and continue scoped compiler
  and runtime simplification with type/ownership evidence and execution checks.
  Completed reviews do not establish universal optimization or explain every slowdown.

The implementation migration landed in [PR #227](https://github.com/tsnl/snail-scheme/pull/227),
with frontend, integration, library, public-command and native execution checks.
[PR #228](https://github.com/tsnl/snail-scheme/pull/228) adds full Unicode string
folding through scalar services. The
[completed full57 report](../benchmarks/sfir/evidence/20261015-full57.md)
records 326 measured routes and 1,956 successful scheduled attempts at compiler
`8e547bfb`, with both Ack Wasm failures and primary Mperm name rejections retained.
SFIR trails Chez and Rust on all six aggregate comparisons. The later
[packet-input comparison](../benchmarks/sfir/evidence/20261015-input-packets.md)
measures one concrete I/O change separately; it is not a new full-suite result.
The earlier [six-case measurements](../benchmarks/sfir/evidence/20261015-clean-six.md)
remain historical. The compiler service produces and executes Wasm; native
loading remains a separate host adapter.

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
