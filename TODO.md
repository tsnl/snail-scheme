# TODO

The compiler stays Chibi-hosted. Current behavior is described in [TOUR.md](TOUR.md);
this list contains work that has not landed.

- [ ] Follow up the [57-workload comparison](benchmarks/results/2026-10-12-native-v8/README.md)
  - Reduce measured compiler allocation churn and repeated single-value handling
  - Investigate V8 `ack` stack exhaustion and `equal` timeout separately from GC
  - Retain original inputs and all failures when measuring improvements
- [ ] Resolve [the measured storage regressions](benchmarks/results/2026-10-12-container-storage-final/README.md)
  before landing the storage layers
  - Final API head is 6.5% slower across the selected five workloads; lattice and
    graphs regress about 25% and 8% despite native payload kernel improvements
  - Isolate changed call selection and hot read/check boundaries; disabling
    inferred storage also changes specialization and cannot isolate payload cost
  - Profile copy emission and module assembly separately from the constraint solve
- [ ] Browser loader and browser implementations of selected effect interfaces
- [ ] Node spawn/connect, serialization, supervision, and asynchronous host effects
  - Follow the recovered [runtime contracts](doc/book/runtime-contracts.md)
  - Keep terminal CLI faults distinct from recoverable connection failures
- [ ] Independently packaged Wasm providers and explicit shared-resource domains
- [ ] Source mappings for generated Wasm
- [ ] Frontend conformance
  - Complete the syntax parser's remaining R7RS forms
  - Phase-aware resolution to shared definition identities
  - Retain `syntax-rules` repetition extents, including empty and variable-free repetitions
  - Diagnose unbound literal identifiers and missing imported auxiliary keywords
  - Handle interacting macro-generated binders
- [ ] Rust interop and embedding ([ABI](doc/rust-interop.md))
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
  - Broaden conditional recursive inference and specialization budget policy
  - Infer native payloads for literal pairs/vectors, which currently keep generic slots
  - Improve container precision across opaque factories and higher-order flows
  - Propagate immutable callback identity beyond named bindings
  - Measure general IR specialization across arithmetic and broader workloads
  - Keep [the full proposal](doc/occurrence-typing.md) distinct from implemented behavior
- [ ] Reprofile hosted parsing, expansion, and Wasm emission with Chromium traces
- [ ] Switch the compiler build to self-hosting after capability validation
