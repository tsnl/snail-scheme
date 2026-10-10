# TODO

The compiler stays Chibi-hosted. Current behavior is described in [TOUR.md](TOUR.md);
this list contains work that has not landed.

- [ ] Finish the native executor for the complete Rust-linked Wasm program
  - Scheme Wasm-to-LLVM translation and BDWGC host services
  - Deferred resource finalization outside Wasm execution
  - Native execution checks and matched CPU measurements
- [ ] Rebaseline the allocation workload on the current backend
- [ ] Browser runner with a WASI adapter
- [ ] Source mappings for generated Wasm and native debugging
- [ ] Frontend conformance
  - Complete the syntax parser's remaining R7RS forms
  - Phase-aware resolution to shared definition identities
  - Retain `syntax-rules` repetition extents, including empty and variable-free repetitions
  - Diagnose unbound literal identifiers and missing imported auxiliary keywords
  - Handle interacting macro-generated binders
- [ ] Rust interop and embedding ([AWI](doc/rust-interop.md))
  - Version/instance checks for externally stored raw handles
  - Resource-kind registration and release callbacks
  - Recoverable errors/traps and explicit instance shutdown
  - Rust host embedding example
  - Test cleanup cycles; a resource rooting its wrapper needs explicit release
  - Revisit independent extension packaging when needed
- [ ] Single-shot delimited continuations and coroutines
  - Wasm stack switching and a Scheme API
  - Explicit suspension-safe Rust APIs and cancellation/unwinding
  - Reusable multi-shot continuations are not a goal; `call/cc` is unsupported today
- [ ] Type inference and optimization after the measured executable baseline
  - Closed-world lattice analysis, occurrence typing, strict annotations
  - IR-to-IR elaboration/specialization and redundant check elimination
  - Measure complete optimized programs against the baseline
- [ ] Reprofile hosted parsing, expansion, and Wasm emission with Chromium traces
- [ ] Switch the compiler build to self-hosting after capability validation
