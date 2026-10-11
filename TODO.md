# TODO

The compiler stays Chibi-hosted. Current behavior is described in [TOUR.md](TOUR.md);
this list contains work that has not landed.

- [ ] Rebaseline the allocation workload on the current backend
- [ ] Make native allocation and GC throughput competitive with V8
  - Start from the [GC measurements and handoff](benchmarks/results/2026-10-11-prefault-heap/README.md): one compiler self-compilation allocates about 556 million objects / 16.34 GB, with only tens of MiB reachable.
  - Isolate allocation, explicit-root publication and barriers with the same generated LLVM; the resident bump control currently omits the custom collector's root protocol.
  - Measure a small allocation fast path with collection/refill out of line, constructor initialization without redundant zeroing, and fewer redundant root copies; these are unmeasured proposals.
  - Investigate compiler allocation churn and single-value handling alongside collection; the nursery spends about 1.2 s collecting in a 14.1 s compiler run.
  - Retain checked tail calls, Rust AWI roots, identity hashing and weak resource cleanup; keep nursery/Immix prototypes experimental until repeated native execution and performance checks justify integration.
  - Report heap preparation, resident memory and execution separately, with matching inputs and verified outputs. Parallel marking and Immix evacuation remain deferred.
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
- [ ] Extend [type checking](doc/typing-prototype.md)
  - Complete an operational soundness proof and optimization simulation
  - Higher-order interfaces, variadic signatures, and multiple-value result types
  - Typed local generative records and parameterized records
  - Broaden primitive signature coverage and runtime blame diagnostics
  - Broaden recursive generic groups beyond matching positional type parameters
  - General representation specialization and measured monomorphization
  - Investigate boxed i32 guard costs and broader workload performance
  - Keep [the full proposal](doc/occurrence-typing.md) distinct from implemented behavior
- [ ] Reprofile hosted parsing, expansion, and Wasm emission with Chromium traces
- [ ] Switch the compiler build to self-hosting after capability validation
