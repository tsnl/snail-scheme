# Roadmap

The execution target is WasmGC. The LLVM backend and custom collector are removed;
completed native milestones below record historical work. Self-hosting targets
WasmGC on an engine such as V8 and remains a separate milestone.

The active goal is a complete, understandable Lofi compiler and benchmark suite.
[The language contract](lofi.md) defines the target; [the tour](../TOUR.md)
describes the implementation. Chibi continues to host the compiler.

The historical [self-hosting investigation](self-hosting.md) proposed
`snail run` and `snail build`, with reproducible Siegework measurements,
compiler compatibility blockers and staged bootstrap acceptance criteria.
The compiler port and command are not implemented yet.

## Align with the Lofi book

[PR #226](https://github.com/tsnl/snail-scheme/pull/226) replaces the initial
surface sketch with the [Lofi book](book/lofi/index.md). The earlier migration
below established the measured backend. The implemented surface and library
contracts, their execution evidence and remaining extensions are recorded below:

- [x] Resolve `def` and sequential `let` with the specified block scope,
  shadowing and source-order initialization. Scope an attached `All` over its
  initializer, including nested annotations.
- [x] Parse library-level `datatype`, `typeclass` and named `instance` bodies
  of `def`, check their kinds, and use `Any` at dynamic boundaries.
- [x] Introduce named `data`, `typeclass` and `instance` declaration forms.
  Splice library-level `begin` into its surrounding scope, including macro output;
  retain expression blocks and the earlier declaration syntax for compatibility.
- [x] Adopt `define-library`, concatenated body clauses and `(lofi base)`.
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
  Scheme-to-Lofi frontend may select them; Scheme frontend work remains deferred.
- [x] Infer recursive groups monomorphically, including annotated and phantom
  instantiations. Generalize after the group while preserving rigid contracts
  and the value restriction; retain source-order readiness checks.
- [x] Audit class obligations, value restriction, dynamic type identity, call
  ordering and proper tail recursion with [executable contract evidence](../tests/lofi-conformance-audit/README.md).
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
- [x] Execute compiled Lofi producers that construct a limited library syntax
  subset through typed builders and transfer owned structured data into Chibi.
  Preserve explicit receiving-context identities and separate output imports.
- [x] Execute source-level `generate-library` recipes with separate producer and
  application dependency maps, preparation-cycle diagnostics and explicit source
  context for caller-supplied foreign providers. See [source recipes](lofi-generation.md).
- [x] Complete library constructors and typed inspection views for book syntax,
  including explicit type identities, ordered local scopes, static declarations
  and the existing extern/overload extensions. Preserve the checked transfer boundary.
- [x] Add native loading with independent state, a checked scalar bridge and
  explicit providers (retired with the LLVM backend).
- [x] Expose explicit library maps, compilation, Wasm loading, independent state
  and checked scalar invocation to ordinary Lofi through an owned Chibi service.
  Return recoverable errors and retain separate provider linkage; see the
  [compiler service](lofi-compiler-service.md).
- [x] Return inspectable first-class `LofiLibrary` values from Lofi parsing using
  the constructive syntax API. Preserve local scopes, attached quantifiers,
  original numeric spellings and source locations through checked transfer;
  compile transformed values with explicit maps.
- [x] Revalidate the full corpus and compare clean timings after migration at
  frozen compiler `8e547bfb`; retain original failures and historical snapshots.
  The later packet-input campaign is separate from that full-suite freeze.

The book deliberately leaves foreign target interfaces and parts of the formal
calculus open. The [extension contract](book/lofi/extensions.md) documents typed
externs and fixed-arity ad-hoc overload declarations alongside named wrapping
and IEEE operations. Implementation restrictions and future adapters remain
distinct from the core language contract.

## Data graph serialization

The [data graph contract](book/lofi/types.md#data-graph-serialization) uses one
finite S-expression representation with readable text and compact binary
encodings. Types opt in through separate `Serialize` and `Deserialize` instances;
attached `deriving` clauses invoke ordinary declarative transformers.

- [x] Supply the complete named data declaration to each derive transformer,
  retain the type once, and splice generated declarations into library scope.
- [x] Generate concrete `Serialize` and `Deserialize` instances with checked
  field operations and stable named-library/type tags.
- [x] Encode scalar values without losing numeric widths or floating-point bits;
  keep symbols distinct from strings in text and compact binary.
- [x] Share traversal contexts across fields, preserving the identities of
  supported mutable storage and reconstructing reference/vector cycles with
  explicit `Default` element evidence.
- [x] Complete cross-encoding and target execution checks, including malformed
  inputs, shared/cyclic storage, numeric edge cases and unsupported fields.
- [x] Replace Siegework's handwritten codecs with derived instances, retaining
  application validation, compatibility checks and atomic durable commits.
- [ ] Add constrained generic instances and serialization derivation for
  parameterized data declarations. Keep procedures, closures, resources and
  arbitrary `Any` outside the supplied instance set.

## Current Lofi migration

- [x] Land the Lofi language design before implementation (PR #225).
- [x] Make `lofi` the sole product command and remove Scheme compilation,
  interpretation, macro expansion and the legacy emitter.
- [x] Complete the direct located-syntax → resolved IR → inference → concrete
  specialization → WasmGC pipeline, with visible contracts between passes.
- [x] Retain explicit storage, positional calls, typed externs and library
  specialization; reject unresolved representations instead of adding a fallback.
- [x] Retire obsolete Scheme-only examples, commands and documentation. Keep
  historical measurements identifiable. `build.scm` now demonstrates ordinary
  Chibi library composition from Lofi through Wasm to a linked native executable.
- [x] Remove the boxed Scheme-value runtime and wrapper-finalizer bridge. Keep
  scalar host services, explicit resource cleanup and native managed roots.
- [x] Validate the public command, imported libraries, error paths and actual
  linked Wasm/native execution. Compilation alone is insufficient.
- [x] Author all 57 bare Lofi benchmark ports with canonical inputs,
  algorithms and result predicates. The checked full57 freeze passes all native
  routes and 56 Wasm routes, preserving Ack's Wasm stack failure.
- [x] Measure Lofi, original/adapted Chez controls and Rust on the frozen full
  corpus, recording native versus Wasm separately. Preserve failed/unavailable
  routes, complete predicates, preparation costs and instrumented diagnostics.
  Report the Mperm timer correction as a distinct campaign.
- [x] Complete focused clarity reviews of [recursive inference](../tests/lofi-recursion/README.md),
  [literal construction](../tests/lofi-literal-widths/README.md),
  [arithmetic lowering](../tests/lofi-arithmetic/README.md) and
  [shared I/O ownership](../src/lofi/README.md). Retain independent explanations,
  rejected alternatives and target execution evidence for those concrete changes.
- [ ] Investigate the measured full57 bottlenecks and continue scoped compiler
  and runtime simplification with type/ownership evidence and execution checks.
  Completed reviews do not establish universal optimization or explain every slowdown.
- [x] Measure default arithmetic and direct native array access with unchanged
  inputs and repeated Chez/Rust controls in the
  [four-arm, six-workload ablation](../benchmarks/results/2026-10-15-arithmetic-array-ablation/README.md).
  Retain the inlining experiment as evidence: its GCbench recovery trades off
  against a substantial bytevector/string conversion regression.
- [ ] Bound recursive code expansion while preserving useful helper inlining.
  Measure both allocation-heavy and conversion-heavy workloads before changing
  the global policy; smaller Wasm alone does not establish faster execution.
- [x] Retire the LLVM backend and custom native collector; remove native root frames.
- [ ] Measure remaining Wasm allocation, redundant zero fills and repeated
  UTF-8 validation using the representation and execution contracts in that report.

The implementation migration landed in [PR #227](https://github.com/tsnl/snail-scheme/pull/227),
with frontend, integration, library, public-command and native execution checks.
[PR #228](https://github.com/tsnl/snail-scheme/pull/228) adds full Unicode string
folding through scalar services. The
[completed full57 report](../benchmarks/lofi/evidence/20261015-full57.md)
records 326 measured routes and 1,956 successful scheduled attempts at compiler
`8e547bfb`, with both Ack Wasm failures and primary Mperm name rejections retained.
Lofi trails Chez and Rust on all six aggregate comparisons. The later
[packet-input comparison](../benchmarks/lofi/evidence/20261015-input-packets.md)
measures one concrete I/O change separately; it is not a new full-suite result.
The earlier [six-case measurements](../benchmarks/lofi/evidence/20261015-clean-six.md)
remain historical. The compiler service produces and executes Wasm; native
loading has been retired with the LLVM backend.

The [corpus manifest](../benchmarks/lofi/corpus.json) tracks source presence,
validation and measurement independently. Pre-migration strict-Scheme results
are historical evidence, not a current Lofi score.

## After the migration

- Keep WasmGC as the execution target, using V8 as the primary runtime. Broaden
  typed host interfaces with explicit ABI and actual execution checks.
- Add optional affine grades and `Drop` using type evidence to establish cleanup
  obligations. `Any` stays unrestricted; affine values need an explicit shared
  wrapper to enter it. Borrow checking and stack promotion are separate work.
- Revisit platform effects, actors and heterogeneous targets on typed Lofi
  interfaces, without assuming that a resource can cross an ownership boundary.
- Add source mappings from emitted code back to located Lofi and future source
  frontends.

## Language libraries and future self-hosting

- [x] Put compiler and language libraries under `src/` with matching namespaces
  and `.sld` sources. Keep the public `(lofi compiler)` usable by product callers
  and the Chibi implementation under `(lofi compiler bootstrap)`.
- [x] Add hygienic declarative `syntax-rules` to Lofi, including imported and
  exported transformers, definition-site private bindings and nested repetition.
- [x] Implement an initial `(scheme base)` using those macros and the typed core.
- [ ] Extend Scheme beyond the documented typed subset: quoted data, general
  truthiness, mutation, richer runtime interfaces and other R7RS requirements.
- [ ] Specify procedural transformer evaluation and phase interfaces separately.
- [ ] Compile the Scheme implementation through the product pipeline, then retire
  Chibi at a distinct self-hosting milestone.

The earlier removal of the legacy expander remains historical migration work;
the current declarative expander is implemented in the shared library pipeline.
