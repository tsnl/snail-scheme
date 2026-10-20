# Working on Lofi

Make the implementation educational to read. Follow the program from located
syntax through resolved IR, WasmGC, and the Rust scalar services.
Keep each pass's inputs, outputs, and decisions visible in its module.

- Languages are libraries: keep language definitions and compiler libraries
  under `src/`, with paths matching their library names and `.sld` sources.
  Lofi's typed kernel and the initial `(scheme base)` share hygienic
  `syntax-rules` expansion, library resolution and the backend. Surface macros
  expand away before ordinary checking; procedural transformers and self-hosting
  remain deferred. Chibi hosts `(lofi compiler bootstrap)` through `bootstrap/`;
  product sources import the public `(lofi compiler)`. See [the language
  book](doc/book/lofi/index.md).

- Use type checking to prove invariants that enable optimization. Preserve
  evidence about representations, ownership, effects and foreign boundaries
  through lowering, so later passes can act on established facts. Keep runtime
  checks where those facts cannot be proved statically.
- Parse, don't validate: turn syntax and external data into structured values
  whose construction establishes the required invariants. Carry that evidence
  forward instead of returning a Boolean and repeatedly checking the same raw
  data. Keep unsafe assumptions explicit at the boundary that introduces them.
- Prefer cohesive single-file modules with named sections. A large file can
  explain one subject well; extract a file only for a substantial new subject.
- Put each Scheme import specification and record field on its own line.
  Name pure field replacements `<accessor>-set`, without a trailing `!`;
  reserve `!` for mutation.
- Write section headers as `;; ---- Title ----` in Scheme,
  `// ---- Title ----` in Rust, with sentence
  case and a blank line on each side.
  Keep unit tests in a final `Tests` section of their implementation module.
  Each tested Chibi-hosted module exports one `test-<module>` entry point under
  the `snail-tests` feature; Lofi standard libraries export theirs
  unconditionally because compiled Lofi has no feature flags. Test cases and
  helpers stay private. Keep integration
  fixtures, runners, and shared assertion support in `tests/`.
  Inactive test sections must remain readable by the Chibi compiler host.
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
  Wasm engines trace managed references. Rust scalar providers own external resources
  behind explicit handles. Resource cleanup must not retain its managed wrapper.
- Keep the compiler hosted by Chibi until a separate self-hosting milestone.
- Update [TOUR.md](TOUR.md) when module responsibilities change. Keep proposed
  APIs distinct from implemented behavior in documentation and TODOs.

Relevant checks are `make test`, `make check`,
`cargo test --manifest-path src/runtime/Cargo.toml --offline`,
`cargo test --manifest-path tools/host/Cargo.toml --offline`,
`cargo fmt --manifest-path src/runtime/Cargo.toml --all -- --check`,
`cargo fmt --manifest-path tools/host/Cargo.toml --all -- --check`,
`scripts/test-backend`, and `scripts/test-build`.
Backend changes should execute linked Wasm; compilation alone does not test target
behavior. See [doc/backend.md](doc/backend.md) for tools.
