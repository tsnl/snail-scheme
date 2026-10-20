# Working on Lofi

Make the implementation educational to read. Follow the program from located
syntax through resolved IR, WasmGC, and the Rust scalar services.
Keep each pass's inputs, outputs, and decisions visible in its module.

- Languages are libraries. The compiler lives in `src/lofi/compiler/` and is
  written in typed Lofi importing only `(lofi base)`, `(lofi table)` and
  `(lofi io)`, so it compiles itself. Chibi runs the same source with
  `-I host/chibi -I src`; `host/chibi/` implements those libraries and erases
  the typed forms, and is the only place host-specific code may live. The
  standard library lives in `lib/`, a search root Chibi never loads, with
  paths matching library names and `.sld` sources. Surface macros expand away
  before checking. See [the language guide](doc/language.md) and
  [the redesign](doc/redesign.md).

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
- Put each Scheme import specification and struct field on its own line.
  Name pure field replacements `<accessor>-set`, without a trailing `!`;
  reserve `!` for mutation.
- Write section headers as `;; ---- Title ----` in Scheme,
  `// ---- Title ----` in Rust, with sentence
  case and a blank line on each side.
  Keep unit tests in a final `Tests` section of their implementation module.
  Each tested compiler module exports one `test-<module>` entry point under
  the `snail-tests` feature; test cases and helpers stay private. Test Lofi
  libraries with programs and their expected output. Keep integration
  fixtures, runners, and shared assertion support in `tests/`.
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
- Chibi is stage 0 of the bootstrap: it must keep running the compiler's
  source, so the compiler avoids behavior the two hosts would disagree on,
  such as integer overflow and the order of table keys.
- Update [TOUR.md](TOUR.md) when module responsibilities change. Keep proposed
  APIs distinct from implemented behavior in documentation and TODOs.

Relevant checks are `make test`, `make check`,
`cargo test --manifest-path src/runtime/Cargo.toml --offline`, and
`cargo fmt --manifest-path src/runtime/Cargo.toml --all -- --check`.
Backend changes should execute linked Wasm; compilation alone does not test
target behavior. Browser changes should be seen running:
`node tests/browser/page.mjs URL SCREENSHOT` drives headless Chromium.
