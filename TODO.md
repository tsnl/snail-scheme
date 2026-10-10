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
  - [x] Rust runtime with tagged words, fixed object layouts, and precise nonmoving GC
  - [x] Link generated LLVM objects through Cargo for native and WASI executables
  - [x] Run an entry-point file by default; `-o` builds without running
  - [x] Invoke Cargo automatically and expose compiler/runtime/GC timings
  - [x] CPU, memory, IO, and GC benchmark programs with checked results
- [ ] Runtime representation and collection boundaries
  - [x] Measure native/WASI cross-language LTO against Rust-only LTO and Chez
    ([experiment](doc/lto-experiment.md))
  - [x] Replace instruction safepoints with owned allocation capabilities;
    root call inputs before acquisition and results before the next acquisition
    ([allocation contract](doc/rust-interop.md#allocation-capability))
  - [x] Port `v3` builtin layouts to 32-bit values, documenting unavoidable changes
    to immediate float32 values and C++-specific header/container representation
  - [x] Keep ordinary builtin access static; reserve a shared extension-object
    vtable mechanism for foreign payloads and use `gc_mark` for tracing
  - [ ] Preserve an explicit runtime-provided allocation ABI for generated LLVM
  - [ ] Remove avoidable host allocation and frame handling from ordinary calls;
    profile against Chibi as well as Chez before adding type inference
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
- [ ] Hosted compiler throughput ([measurements](doc/compilation-performance.md))
  - [x] Profile parser construction, allocation, and backtracking on bootstrap libraries
  - [x] Report imported-source parsing separately from expansion in compiler timings
  - [x] Remove repeated handler-name construction and quadratic dense-label deduplication
  - [ ] Reprofile remaining imported-source parsing and LLVM output costs
- [ ] Switch the compiler's build to self-hosting after capability validation
