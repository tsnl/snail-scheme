# Working on Snail-Scheme

Make the implementation educational to read. Follow the program from located
syntax through expanded HIR, stack instructions, LLVM, and the Rust runtime.
Keep each pass's inputs, outputs, and decisions visible in its module.

- Prefer cohesive single-file modules with named sections. A large file can
  explain one subject well; extract a file only for a substantial new subject.
- Target **ten lines of logic per function**. Name complete operations, not
  fragments introduced to meet a count. Exhaustive dispatch, data definitions,
  atomic VM transitions, and tests may be longer when keeping them together
  exposes their contract.
- Use concrete data and direct control flow. Helpers should establish a useful
  guarantee, with ownership and effects apparent at the call site. Avoid
  forwarding layers, generic callback frameworks, and speculative abstractions.
- Take inspiration from [Per Vognsen's Bitwise](https://github.com/pervognsen/bitwise)
  and [Resin's discussion](https://github.com/tsnl/resin/blob/main/doc/bitwise.md):
  representations explain operations, and control flow teaches the problem.
  Adapt those principles to Scheme and Rust rather than copying architecture.
- Use the pinned [simplify skill](.agents/skills/simplify/SKILL.md) for focused
  explanation and refactoring of newly written modules. Keep backend cleanup
  within those modules; preserve the structure of the landed frontend.
- Keep GC and slot-lifetime invariants beside the code that relies on them.
  Allocation alone never collects. Generated code loads a source before a
  service can resize its storage, and publishes live values before a safepoint.
- Keep the compiler hosted by Chibi until a separate self-hosting milestone.
  Type inference follows the working, measured backend baseline.
- Update [TOUR.md](TOUR.md) when module responsibilities change. Keep proposed
  APIs distinct from implemented behavior in documentation and TODOs.

Relevant checks are `make test`, `make check`, `cargo test --offline`,
`cargo fmt --all -- --check`, `scripts/test-backend`, and `scripts/test-cli`.
Backend changes should execute both native and WASI cases; compilation alone
does not test target behavior. See [doc/backend.md](doc/backend.md) for tools
and [benchmarks/README.md](benchmarks/README.md) for reproducible measurements.
