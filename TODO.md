# TODO

- [x] CLI args parser
- [x] Parser and parser combinator
- [ ] Syntax
  - [x] Syntax
  - [ ] Syntax parser
    - [x] Parse most of Scheme
    - [x] Parse `#%-*` identifiers
  - [x] Datum pattern matcher
- [ ] IR
  - [x] Untyped, fully expanded Scheme records in `ir.sld`
  - [x] Transient scope environments passed through `expand.sld` recursive descent
  - [ ] Phase-aware resolution to shared definition identities
  - [x] IR construction using the datum pattern matcher
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
- [x] WebAssembly backend baseline
  - [x] Rename simplified HIR to IR and retain independent library containers
  - [x] Emit WasmGC directly; retire MIR, LLVM emission, and managed Scheme stack
  - [x] Use real tail calls, direct fixed workers, closure adapters, and GC references
  - [x] Build and link Rust as Wasm through an application Wasm interface (AWI)
  - [x] Invoke Cargo automatically; source runs, `-o` builds, `--emit-wat` inspects
  - [x] Rust extension example with retained roots and reentrant Scheme callbacks
  - [x] Explicit resource close plus browser/Node finalizer host shim
  - [x] Compile compiler sources while keeping Chibi as the build host
  - [x] Run the newly compiled compiler to generate and execute a second program
  - [x] Rebaseline complete CPU program against Chez and Chibi, excluding compilation
  - [ ] Rebaseline memory and string workloads on the new backend
  - [ ] Browser runner with a WASI adapter; finalizer shim itself uses standard JS
- [ ] Independent Wasm-to-native executor
  - [x] Bounded two-pass Wasm-to-LLVM experiment with BDWGC and numeric measurements
  - [x] Compare Wastrel; record its register-clearing/toolchain overhead separately
  - [ ] Extend binary translation to full linked programs: arrays, tables, memory,
    indirect calls, structured branches, host imports, and remaining numeric ops
  - [ ] Implement the host finalizer import with BDWGC and deferred resource cleanup
  - [x] Experimental `cont.new`, `resume`, and `suspend` decoding/lowering for i64 entries
  - [ ] Complete standard stack-switching operations and signatures
  - [ ] Single-shot delimited continuations and coroutine language API
  - [x] Experimental suspend/resume GC tests, consumed tokens, and nested delimiters
  - [x] Experimental foreign-call barriers; actual Rust suspension remains unsupported
  - [ ] Explicit suspension-safe Rust APIs
  - [ ] Cancellation and compatible Rust unwinding before abandoning Rust frames
- [ ] Continuation semantics
  - [x] Diagnose absent `call/cc` / `call-with-current-continuation` in Wasm backend
  - [ ] Document single-shot API and cancellation once implemented
  - Reusable multi-shot continuations are not a goal. The
    [stack-switching proposal](https://github.com/WebAssembly/stack-switching/blob/main/proposals/stack-switching/Explainer.md)
    supplies single-shot, delimited continuations, not reusable snapshots.
  - Wastrel revision `ad0b577df0773a1fc825b2a2455e23bf03ea9dcc`, tested
    October 10, 2026, lists stack switching as an aim and lacks these instructions.
- [ ] Rust interop and embedding ([AWI](doc/rust-interop.md))
  - [ ] Version/instance checks for externally stored raw handles
  - [ ] Generic extension resource-kind registration and release callbacks
  - [ ] Native host finalization equivalent to the JS shim
  - [ ] Recoverable error/trap boundaries and explicit instance shutdown
  - [ ] Rust host embedding example distinct from the Rust-in-Wasm extension example
  - [ ] Test cleanup cycles; a resource rooting its own wrapper needs explicit release
- [ ] Type inference and optimization after the measured executable baseline
  - [ ] Closed-world lattice analysis, occurrence typing, strict annotations
  - [ ] IR-to-IR elaboration/specialization and redundant check elimination
  - [ ] Measure complete optimized programs against the baseline
- [ ] Hosted compiler throughput
  - [x] Cache-free parser rule construction and direct parser combinator execution
  - [x] Simplify expansion matching and preserve frontend behavior
  - [ ] Reprofile current parse/expand/WAT emission with Chromium traces
- [ ] Switch the compiler build to self-hosting after capability validation

The previous Dybvig-stack/MIR/LLVM baseline and its measurements remain in Git
history and historical documents; it is not the current production backend.
