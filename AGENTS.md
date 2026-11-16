# Working on `snail-scheme`

`CLAUDE.md` is a symlink to this file; edit `AGENTS.md`.

Make the implementation educational to read. Follow the program from located
syntax through resolved IR, WasmGC, and the Rust scalar services.
Keep each pass's inputs, outputs, and decisions visible in its module.

- `snail-scheme` is a statically-typed Scheme successor. Its macros expand
  into one typed language; it does not implement R7RS or a separate dynamic
  Scheme compatibility layer.
  Every library that ships lives under `src/`, with paths matching library
  names and `.sld` sources: the core under `src/snail/core/`, the shell built
  on it under `src/snail/shell/` (#566),
  and the compiler among them at
  `src/snail/shell/compiler/`, written in `snail-scheme` importing only
  `(snail core base)`, `(snail core table)` and `(snail core io)`, so it
  compiles itself.
  Host-specific code lives only under `host/`: `chez/` for stage 0,
  `native/` for Node, `browser/` for the page. Editor support lives under
  `editors/`: the tree-sitter grammar and the Zed extension. Rust
  crates live in `crates/`. No program or library may depend on
  JavaScript: hosts beyond Node and the page, such as wasmtime and
  workerd, are the long-term direction
  ([Runtimes](doc/book/runtimes/index.md#direction)). Surface macros expand away before checking. See
  [the language chapters](doc/book/snail-scheme/index.md).

- Stage 0 loads an explicit library closure through `host/chez/load.scm`:
  the host's `base`, `table`, `io` and `forms`, the build driver, and the
  compiler's own libraries. The loader translates the library envelope to
  native Chez libraries and erases typed forms. It rejects application
  libraries outside that closure; adding a dependency is a deliberate edit
  to the loader. Test support has its own allowance in test mode. The
  compiler reads record fields with `(● record label ...)`; stage 0 maps
  that form to the same mutable record slots. Stage 0's one product is the
  stage 1 command line, `bootstrap/cli.sld`, built by `scripts/bootstrap`,
  which also holds the engine that links every per-library program; the
  command line builds everything else: scripts, run as
  `./snail-scheme run --target node FILE`, and the root project's targets. Every project build writes
  one module per library into the sharded store `build/.snail-store` and
  names them in `TARGET.manifest.datum`.
  The test harness also compiles through stage 0's driver.

- Every record is a heap object and every field is mutable. Primitive
  numbers and booleans remain unboxed. Keep ordinary compiler passes pure
  by convention and by their effect signatures. Every value may be shared,
  and the Wasm engine's collector reclaims it: there are no linear types,
  reference counts, finalizers or borrows, and no ownership pass.
- Top-level definitions bind functions. Values are local to functions or
  explicit state objects; there are no lazy global caches or initialization
  guards. Preserve typed define headers and `(Fn ... → ...)`.
  A direct lambda definition remains function code with an inferred type.

- Use type checking to prove invariants that enable optimization. Preserve
  evidence about representations, effects and foreign boundaries
  through lowering, so later passes can act on established facts. Keep runtime
  checks where those facts cannot be proved statically.
- Effect handlers are headed for generalized evidence passing, as Koka does:
  a handler becomes evidence threaded as a parameter, the way a class
  constraint already is, and an operation becomes an ordinary call through it.
  This is deliberately not stack switching. JSPI is a browser mechanism with
  no native counterpart, so building on it would give the two hosts different
  semantics for the same program; evidence passing is a translation, needs no
  runtime support, and reuses machinery the compiler already has for
  typeclasses. The consequence is the continuation tier: one-shot and
  delimited by its handler. `resume` is an ordinary `Fn`, so it is
  first-class — a scheduler can hold it and call it later as a thunk, which
  is how tasks are effects (`src/snail/shell/task.sld`) — and its frames run
  at most once: a second call panics. Multi-shot continuations are out of scope, since
  they require every frame to be reachable twice and would be paid for by code
  that never captures one. The lowering is evidence passing: every
  function takes `$ev`, the handlers in scope, as its first parameter, and
  `handle` extends it for its body (`src/snail/shell/compiler/wasm.sld`,
  "Effect handlers"). One-shot `resume` is implemented on the same
  translation: a yield returns through each frame, saving the rest of it
  as a closure, and calling `resume` runs those closures ("Control",
  "Frames" and "Resuming").
  Handlers are never specialized: the worklist does not key on a handler, so
  an operation always walks the evidence list. Performing an effect is
  meant to be rare and relatively expensive, the heavyweight way to
  interact with the world, so most logic stays pure functional code.
- Parse, don't validate: turn syntax and external data into structured values
  whose construction establishes the required invariants. Carry that evidence
  forward instead of returning a Boolean and repeatedly checking the same raw
  data. Keep unsafe assumptions explicit at the boundary that introduces them.
- Prefer threading pass state through functions and returning the new value.
  A signature without `! mut` proves that the function does not mutate its
  arguments. Field reads are pure; callers still share mutable objects.
  Use `! mut` for mutation that belongs to a
  boundary — the runtime, a host, a cache with one owner — not for the
  convenience of a pass that could carry its state. When threading would
  nest a function six deep, name the sequence with a local binding form, as
  `threading` does in `src/snail/shell/compiler/core.sld`, rather than
  reaching for a cell. The checker went from 58 `! mut` signatures to none
  at no cost in speed; the count per module is worth watching.
- Prefer cohesive single-file modules with named sections. A large file can
  explain one subject well; extract a file only for a substantial new subject.
- Put each Scheme import specification and record field on its own line.
  Name pure field replacements `<accessor>-set`, without a trailing `!`;
  reserve `!` for mutation.
- Write section headers as `;; ---- Title ----` in Scheme,
  `// ---- Title ----` in Rust, with sentence
  case and a blank line on each side.
  Keep unit tests in a final `Tests` section of their implementation module.
  Each tested compiler module exports one `test-<module>` entry point under
  the `snail-tests` feature; test cases and helpers stay private. Test
  `snail-scheme` libraries with programs and their expected output. Keep
  integration fixtures, runners, and shared assertion support in `tests/`.
- Target **ten lines of logic per function**. Name complete operations, not
  fragments introduced to meet a count. Exhaustive dispatch, data definitions,
  atomic VM transitions, and tests may be longer when keeping them together
  exposes their contract.
- Use concrete data and direct control flow. Helpers should establish a useful
  guarantee, with effects apparent at the call site. Avoid
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
- Chez is stage 0 of the bootstrap: it must keep running the compiler's
  source, so the compiler avoids behavior the two hosts would disagree on,
  such as integer overflow and the order of table keys.
- Update the relevant [book chapter](doc/book/SUMMARY.md) when contracts or
  module responsibilities change; the
  [compiler tour](doc/book/snail-scheme/compilers.md) lives there. Track open
  work in [GitHub issues](https://github.com/tsnl/snail-scheme/issues).
  Keep proposed APIs explicitly distinct from implemented behavior. Do not
  duplicate the book in proposal documents or progress trackers.

Work inside `nix-shell`, which provides the pinned tools CI uses (`shell.nix`,
pinned by `npins/`), Binaryen's `wasm-opt` among them. NixOS is the primary
development platform. On a system without Nix, use the Nix devcontainer
(`.devcontainer/`) and run `nix-shell` inside it
([getting started](doc/getting-started.md)).

Run the relevant checks locally and have them pass before pushing. A local
run answers in minutes what CI answers in tens of minutes, and it reproduces
a failure as many times as a fix needs; pushing to see what breaks spends
that time for a worse report. Push when a change is verified, not to find out.

Relevant checks are `make test`, `make check`,
`cargo test --manifest-path crates/snail-scheme-support/Cargo.toml --offline`, and
`cargo fmt --manifest-path crates/snail-scheme-support/Cargo.toml --all -- --check`, and the
same two for `crates/snail`. Changes to the native
executable or to how compiles and programs run must also pass
`make test-wasmtime`. Stage 0 rebuilds the command line whenever its
source changes; compiler changes must also pass `make test-chez`,
which runs the source on Chez, and `make bootstrap`, which rebuilds from
Chez alone.
Backend changes should execute linked Wasm; compilation alone does not test
target behavior. `(snail shell format)` is the formatter shared by `snail-scheme lsp`
and `snail-scheme format`; `make test` checks its CLI and every tracked
Scheme file. Browser changes should be seen running:
`node tests/browser/page.mjs URL SCREENSHOT` drives headless Chromium.

## Applications

An application is a script, `src/apps/NAME/main.scm`. Build it with
`./snail-scheme build --target browser src/apps/NAME/main.scm` and serve its
output directory, `build/src/apps/NAME/main`, with any static HTTP server; point
`tests/browser/page.mjs` at it to see a change. Edit in any editor; in Zed,
install `editors/zed` as a dev extension for `snail-scheme lsp`'s diagnostics
on save, formatting, hover and definitions. Each build first runs the
producers of the `generate-library` recipes it reaches, so Hearsay builds
too; its producers run every time. What matters when writing code:

- Keep what should survive a page reload in the application's Save.
- Libraries are checked one at a time, so an importer's use never decides a
  definition's type: give exported functions typed headers.
- A program runs with `./snail-scheme run . RUN-TARGET`.
- Builds in one checkout keep private compiler scratch under `build/snail-run/`.
  Public `snail-scheme run` executes its completed project generation in the caller's
  working directory after removing build scratch. Rebuilding the command line
  takes an exclusive lock on `build/lock`, so `make test` may run beside a
  build.
- The project suites (in `make test`) cover builds, and `tests/browser/`
  (`make test-browser`, needs `CHROMIUM`) covers the pages. `tests/lsp.mjs`
  and `tests/tree-sitter.mjs` cover the editor support. See
  [the development toolchain](doc/book/snail-scheme/toolchain.md).
