# TODO

- [x] CLI args parser
- [x] Parser and parser combinator
- [ ] Syntax
  - [x] Syntax
  - [ ] Syntax parser
    - [x] Parse most of Scheme
    - [x] Parse `#%-*` identifiers
  - [x] Datum pattern matcher
- [ ] HIR
  - [x] Untyped, fully expanded Scheme records in `hir.sld`
  - [x] Transient scope environments passed through `expand.sld` recursive descent
  - [ ] Phase-aware resolution to shared definition identities
  - [x] HIR construction using the datum pattern matcher
  - [x] Basic imports, exports, and lexical scoping
  - [x] Connect expansion to the command-line launcher
- [ ] Macro expansion
  - [x] Initial `syntax-rules` pattern/template engine
  - [x] Connect datum matching to source locations and literal binding lookup
  - [ ] Retain repetition-site extents in transformer plans, including empty
    and variable-free repetitions
  - [ ] Design default errors for unbound `syntax-rules` literals and macros
    imported without their bound auxiliary keywords; relax these checks in
    strict R7RS mode
  - [x] Single-step macro expansion, `macroexpand-1`
  - [x] Expand supported core forms in context
    - [x] Handle `define-syntax`, `let-syntax`, and `letrec-syntax`
    - [x] Reserve direct definitions and discover body bindings before expression construction
  - [ ] Broader R7RS conformance, including interacting macro-generated binders
- [x] Executable backend baseline
  - [x] Lower expanded HIR to Dybvig-style stack VM instructions
  - [x] Emit LLVM instruction handlers and unrolled control flow from Scheme
  - [x] Rust runtime with tagged words, boxed object traits, and precise nonmoving GC
  - [x] Link generated LLVM objects through Cargo for native and WASI executables
  - [x] Run an entry-point file by default; `-o` builds without running
  - [x] Invoke Cargo automatically and expose compiler/runtime/GC timings
  - [x] CPU, memory, IO, and GC benchmark programs with checked results
- [ ] Rust interop and embedding ([design](doc/rust-interop.md))
  - [ ] Scoped native-call context, checked conversions, and GC-free allocating calls
  - [ ] Static Rust library exporting Scheme-callable functions, tested on native and WASI
  - [ ] Declarative Scheme export metadata, explicit native registration, and generated
    Cargo dependencies with persistent lock resolution and one runtime package identity
  - [ ] Durable roots with VM ownership, generation checks, and shutdown semantics
  - [ ] Archive generated objects for Rust library consumers; separate program
    initialization from repeated invocation and namespace generated symbols
  - [ ] Rust embedding example that registers a Rust library, calls Scheme repeatedly,
    and keeps a rooted result between calls, on native and WASI
  - [ ] Rooted native callbacks with explicit reentrancy and temporary-root lifetimes
  - [ ] Define managed allocation quotas and recoverable failure boundaries before
    promising bounded native calls; distinguish quota errors from host allocator OOM
  - [ ] Checked traced edges for custom Rust objects and an object-tracing derive macro
- [ ] Type inference and optimization after the executable baseline
  - [ ] Design closed-world lattice analysis and function specialization
  - [ ] Expose specialized arithmetic, known calls, and local value flow to LLVM;
    preserve a checked dynamic fallback ([baseline diagnosis](doc/performance-baseline.md))
  - [ ] Add occurrence typing and strict annotations incrementally
  - [ ] Compare optimizations against the native/WASI benchmark baseline
- [ ] Switch the compiler's build to self-hosting after capability validation
