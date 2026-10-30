# Working on Snail-Core

`CLAUDE.md` is a symlink to this file; edit `AGENTS.md`.

Make the implementation educational to read. Follow the program from located
syntax through resolved IR, WasmGC, and the Rust scalar services.
Keep each pass's inputs, outputs, and decisions visible in its module.

- A language on Snail-Core is a set of libraries that expand into it: Scheme is
  macros and libraries over the typed language, not a second compiler.
  Every library that ships lives under `src/`, with paths matching library
  names and `.sld` sources: the core under `src/snail/core/`, the shell built
  on it under `src/snail/shell/` (#566),
  Scheme's under `src/scheme/`, and the compiler among them at
  `src/snail/shell/compiler/`, written in typed Snail-Core importing only
  `(snail core base)`, `(snail core table)` and `(snail core io)`, so it
  compiles itself.
  Host-specific code lives only under `host/`: `chibi/` for stage 0,
  `native/` for Node, `browser/` for the page, `ide/` for the editor. Rust
  crates live in `crates/`. No program or library may depend on
  JavaScript: hosts beyond Node and the page, such as wasmtime and
  workerd, are the long-term direction
  ([Runtimes](doc/book/runtimes/index.md#direction)). Surface macros expand away before checking. See
  [the language chapters](doc/book/snail-core/index.md).

- Stage 0 sees `bootstrap/chibi-include/` and nothing else: one symlink per
  library the compiler's load closure actually reaches — `host/chibi/`'s
  stage-0 `base`, `table`, `io` and `forms`, which erase the typed forms,
  plus the build driver, and the compiler's own directory. `src/` is not on
  Chibi's path, so no other library can enter the bootstrap by accident and
  `src/scheme/base.sld` cannot shadow the Scheme that runs stage 0. Reaching
  for a library that is not symlinked fails in `make test-chibi` and
  `make bootstrap` with `couldn't find import`; adding one is a deliberate
  edit to that directory.

- Use type checking to prove invariants that enable optimization. Preserve
  evidence about representations, ownership, effects and foreign boundaries
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
  delimited by its handler. `resume` is a linear closure, `FnOnce`, so it is
  first-class — a scheduler can hold it and call it later as a thunk, which
  is how tasks are effects (`src/snail/shell/task.sld`) — and the ownership checker proves it is
  called or dropped exactly once. Multi-shot continuations are out of scope, since
  they require every frame to be reachable twice and would be paid for by code
  that never captures one. The lowering is evidence passing: every
  function takes `$ev`, the handlers in scope, as its first parameter, and
  `handle` extends it for its body (`src/snail/shell/compiler/wasm.sld`,
  "Effect handlers"). One-shot `resume` is implemented on the same
  translation: a yield returns through each frame, saving the rest of it
  as a closure, and calling `resume` runs those closures ("Control",
  "Frames" and "Resuming").
- Parse, don't validate: turn syntax and external data into structured values
  whose construction establishes the required invariants. Carry that evidence
  forward instead of returning a Boolean and repeatedly checking the same raw
  data. Keep unsafe assumptions explicit at the boundary that introduces them.
- Avoid mutable state. Thread a value through the functions that change it
  and return the new one, so a signature without `! mut` is a proof that the
  pass is a function of its input, and a reader can never be looking at a
  stale cell. `Ref` and `! mut` are for mutation that genuinely belongs to a
  boundary — the runtime, a host, a cache with one owner — not for the
  convenience of a pass that could carry its state. When threading would
  nest a function six deep, name the sequence with a local binding form, as
  `learning` does in `src/snail/shell/compiler/check.sld`, rather than
  reaching for a cell. The checker went from 58 `! mut` signatures to none
  at no cost in speed; the count per module is worth watching.
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
  the `snail-tests` feature; test cases and helpers stay private. Test
  Snail-Core libraries with programs and their expected output. Keep
  integration fixtures, runners, and shared assertion support in `tests/`.
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
- Update the relevant [book chapter](doc/book/SUMMARY.md) when contracts or
  module responsibilities change; the
  [compiler tour](doc/book/snail-core/compilers.md) lives there. Track open
  work in [GitHub issues](https://github.com/tsnl/snail-scheme/issues).
  Keep proposed APIs explicitly distinct from implemented behavior. Do not
  duplicate the book in proposal documents or progress trackers.

Run the relevant checks locally and have them pass before pushing. A local
run answers in minutes what CI answers in tens of minutes, and it reproduces
a failure as many times as a fix needs; pushing to see what breaks spends
that time for a worse report. Push when a change is verified, not to find out.

Relevant checks are `make test`, `make check`,
`cargo test --manifest-path crates/snail-core-support/Cargo.toml --offline`, and
`cargo fmt --manifest-path crates/snail-core-support/Cargo.toml --all -- --check`, and the
same two for `crates/snail`. Changes to the native
executable or to how compiles and programs run must also pass
`make test-wasmtime`. The driver rebuilds the compiled compiler whenever the
compiler's source changes; compiler changes must also pass `make test-chibi`,
which runs the source on Chibi, and `make bootstrap`, which rebuilds from
Chibi alone.
Backend changes should execute linked Wasm; compilation alone does not test
target behavior. `(snail shell format)` reproduces `scripts/format-scheme` for
the IDE, and `make test` checks it on every tracked Scheme file; when Emacs's
rules change, change it to match. Browser changes should be seen running:
`node tests/browser/page.mjs URL SCREENSHOT` drives headless Chromium.

## Live reload

Iterate on applications with `./snail dev apps/NAME`, left running; `make
ide` starts it for Siegework. It serves the browser editor at
`http://127.0.0.1:8000/` and each browser target at
`http://127.0.0.1:8001/TARGET/`, rebuilds only the libraries an edit reaches,
about 100 ms for a function body in Siegework, and relinks them into each open
page, keeping the running state; point `tests/browser/page.mjs` at the
target's URL to see an edit land. Each build first runs the producers of the
`generate-library` recipes it reaches, so Hearsay serves too, rebuilding in
about 750 ms since its producers run every time. The book's
[application model](doc/book/snail-core/applications.md) gives the reload
rules; what matters when writing code:

- Module globals start over on a relink; only the application's state
  crosses, as it is while its type is unchanged and through `save` and
  `restore` otherwise, so keep what should survive an edit in the Save.
- Libraries are checked one at a time, so an importer's use never decides a
  definition's type: give constants their signatures.
- A program runs as a project's `run-target`, restarted from each accepted
  build; the editor's Applications panel starts and stops it. Save writes
  disk; the shared watcher drives compiler and editor updates, and an edit to
  a file a program links builds again once a build that links it is
  published.
- Builds in one checkout keep private compiler scratch under `build/snail-run/`.
  Public `snail run` executes its completed project generation in the caller's
  working directory after removing build scratch. Rebuilding the compiled
  compiler or development tools takes an exclusive lock on `build/lock`, so
  `make test` may run beside a server.
- The service is `src/snail/shell/project/service.sld`, which carries out the
  pure step of `src/snail/shell/development.sld`; it mounts each browser
  target with `(snail shell project bundle)`. The page's reload client is
  `host/browser/reload.sld`, and `relinkProgram` in `host/browser/load.mjs`
  relinks after the application's loop, a task that `host/browser/runtime.mjs`
  drives, saves, returns its state and settles. `tests/project-bundles.mjs`
  and the other project suites (in `make test`) cover the service, and
  `tests/browser/reload.mjs` and `tests/browser/ide.mjs` (`make
  test-browser`, needs `CHROMIUM`) cover the pages. See
  [the development toolchain](doc/book/snail-core/toolchain.md).
