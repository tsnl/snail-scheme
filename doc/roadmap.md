# Roadmap

The [TODO tracking issue](https://github.com/tsnl/snail-scheme/issues/11)
coordinates project work. This repository copy preserves the implementation
follow-ups added after that issue was created.

The compiler stays Chibi-hosted. Current behavior is described in [TOUR.md](../TOUR.md);
this list contains work that has not landed.

- [ ] Complete the strict native compiler and measure the entire benchmark suite
  - Preserve the language contracts in [the strict core guide](../doc/strict-core.md)
  - Extend the [arithmetic/list measurements](../benchmarks/results/2026-10-13-strict-kernels/README.md)
    and [vector measurements](../benchmarks/results/2026-10-13-strict-vector-array1/README.md)
    without shortening inputs, hiding failures, or claiming unmeasured gains
  - Hold the entire project to an educational standard: each module explains
    its data, inputs, outputs, decisions, and required invariants
  - Simplify extensively, including complete module rewrites when warranted;
    repeat independent explanation, critique, rewriting, and execution checks
    until the remaining complexity has a concrete behavioral purpose
  - Keep source initialization, concrete specialization, representation,
    and execution visibly distinct; avoid hidden fallback representations
  - Update the tour and contracts as responsibilities change, preserve measured
    artifacts, and keep the implementation in a reviewable draft PR stack
- [ ] Follow up the [57-workload comparison](../benchmarks/results/2026-10-12-native-v8/README.md)
  - Reduce measured compiler allocation churn and repeated single-value handling
  - Investigate V8 `ack` stack exhaustion and `equal` timeout separately from GC
  - Retain original inputs and all failures when measuring improvements
- [ ] Browser loader and browser implementations of selected effect interfaces
- [ ] Node spawn/connect, serialization, supervision, and asynchronous host effects
  - Follow the recovered [runtime contracts](../doc/book/runtime-contracts.md)
  - Keep terminal CLI faults distinct from recoverable connection failures
- [ ] Independently packaged Wasm providers and explicit shared-resource domains
- [ ] Source mappings for generated Wasm
- [ ] Frontend conformance
  - Complete the syntax parser's remaining R7RS forms
  - Phase-aware resolution to shared definition identities
  - Retain `syntax-rules` repetition extents, including empty and variable-free repetitions
  - Diagnose unbound literal identifiers and missing imported auxiliary keywords
  - Handle interacting macro-generated binders
- [ ] Rust interop and embedding ([ABI](../doc/rust-interop.md))
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
- [ ] Extend [type checking](../doc/typing-prototype.md)
  - Complete an operational soundness proof and optimization simulation
  - Higher-order interfaces, variadic signatures, and multiple-value result types
  - Typed local generative records and parameterized records
  - Broaden primitive signature coverage and runtime blame diagnostics
  - Broaden recursive generic groups beyond matching positional type parameters
  - General representation specialization and measured monomorphization
  - Investigate boxed i32 guard costs and broader workload performance
  - Keep [the full proposal](../doc/occurrence-typing.md) distinct from implemented behavior
- [ ] Reprofile hosted parsing, expansion, and Wasm emission with Chromium traces
- [ ] Switch the compiler build to self-hosting after capability validation
