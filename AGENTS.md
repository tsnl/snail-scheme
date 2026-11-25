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
  crates live in `crates/`. Comparisons with other implementations live
  under `benches/`, each in an environment of its own. No program or
  library may depend on JavaScript: hosts beyond Node and the page, such
  as workerd, are the long-term direction
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
  and the command line builds everything else as scripts, run as
  `./snail-scheme run --target node FILE`. Every build writes one linked
  module, `NAME.wasm`, which `--release` also optimizes; a Node build
  wraps it in an npm package, and making an executable of that is left to
  Node's tools.
  Stage 0 does nothing else: the test suite builds its programs with the
  command line (`tests/run.mjs`), and only the compiler's unit tests run on
  Chez (`tests/unit.scm`).

- Every record is a heap object and every field is mutable. Primitive
  numbers and booleans remain unboxed. Keep ordinary compiler passes pure
  by convention. Ordinary values may be shared and the Wasm engine's
  collector reclaims them. The [scoped ref prototype](doc/book/snail-scheme/values.md#call-scoped-refs)
  enforces call-scoped access to explicitly owned locals.
- A top-level `(define name value)` is a cached thunk: its initializer runs
  at most once, on the first read, performs nothing, and every read
  shares the result. `(define (name parameter ...) ...)` is shorthand for
  defining a lambda, and a lambda takes the same typed header. Preserve
  typed headers and `(Fn ... → ...)`. A lambda that annotates nothing has
  its type inferred.

- Use type checking to prove invariants that enable optimization. Preserve
  evidence about representations and foreign boundaries
  through lowering, so later passes can act on established facts. Keep runtime
  checks where those facts cannot be proved statically.
- There are no effect declarations, no handlers and no effect rows
  ([#877](https://github.com/tsnl/snail-scheme/issues/877)). What a
  function may do to the world is in what it is handed. A **capability**
  is an ordinary value, usually a record of functions (`OutputPort`,
  `Gpu`) called through its fields, `((● out write-string) text)`, that a
  function is handed, may keep and may pass on. `main` asks
  for what it needs by its parameters' types, and its target provides each
  (`src/snail/target/`, "Entries" in `src/snail/shell/compiler/expand.sld`).
  The host's capabilities are made from the one `Host` a target holds
  (`(standard-output host)`), so only code handed a `Host` can acquire one.
  Take what a function uses as a parameter. `unsafe-host` makes that
  authority from nothing: a target calls it, and nothing else should.
  Changing a value is not a capability: whoever holds a record may write
  it, and nothing in a type says whether a call writes, reaches the host
  or suspends ([capabilities](doc/book/snail-scheme/capabilities.md)).
- Suspension is three functions, `make-prompt`, `with-prompt` and `suspend`:
  one-shot, delimited by its `with-prompt`, and in no type. `resume` is an
  ordinary `Fn`, so it is first-class — a scheduler can hold it and call it
  later as a thunk, which is how tasks wait (`src/snail/shell/task.sld`) —
  and its frames run at most once: a second call panics. A prompt that
  answers `Never` is an exception, which is how every pass reports a source
  error. Multi-shot continuations are out of scope, since they require every
  frame to be reachable twice and would be paid for by code that never
  captures one. This is deliberately not stack switching. JSPI is a browser
  mechanism with no native counterpart, so building on it would give the two
  hosts different semantics for the same program; the lowering is a
  translation and needs no runtime support: a yield returns through each
  frame, saving the rest of it as a closure, and calling `resume` runs
  those closures (`src/snail/shell/compiler/wasm.sld`, "Control", "Frames",
  "Prompts" and "Resuming"). Since no type says which calls may suspend,
  preparation computes it for the whole specialized program
  (`src/snail/shell/compiler/prepare.sld`, "Suspensions").
- Parse, don't validate: turn syntax and external data into structured values
  whose construction establishes the required invariants. Carry that evidence
  forward instead of returning a Boolean and repeatedly checking the same raw
  data. Keep unsafe assumptions explicit at the boundary that introduces them.
- Prefer threading pass state through functions and returning the new value.
  No signature says whether a function mutates its arguments, so the
  convention has to carry it: callers share mutable objects, and a function
  that writes is named with a trailing `!`. Keep mutation for a boundary —
  the runtime, a host, a cache with one owner — not for the convenience of
  a pass that could carry its state. When threading would nest a function
  six deep, name the sequence with a local binding form, as `threading`
  does in `src/snail/shell/compiler/core.sld`, rather than reaching for a
  cell. The checker writes nothing, at no cost in speed; the count of
  `set!` and `!` per module is worth watching.
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
  such as integer overflow and the order of table keys. Chez evaluates a
  top-level value where it is defined, so in the compiler's source a value
  comes after everything its initializer uses; `make bootstrap` fails with
  "undefined variable" when one does not.
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

Measure performance from traces ([Traces](doc/book/snail-scheme/toolchain.md#traces)):
`SNAIL_TRACE=FILE` on Node, `TRACE=FILE node tests/browser/page.mjs ...`
for a page, opened in Perfetto. Benchmark from the spans the code already
has, not from timers added for one measurement. The host's spans stay in
the checked-in code: the scheduler's turns, GPU submits and reads, and
each pass on the device. Add a span with `span` or `traced`
(`host/browser/trace.mjs`) where time passes from one party to another,
and keep it.

Relevant checks are `make test`, `make check`,
`cargo test --manifest-path crates/snail-scheme-support/Cargo.toml --offline`, and
`cargo fmt --manifest-path crates/snail-scheme-support/Cargo.toml --all -- --check`.
Stage 0 rebuilds the command line whenever its
source changes; compiler changes must also pass `make bootstrap`, which
rebuilds from Chez alone and checks that Chez and the compiled compiler
emit the same text for it.
Backend changes should execute linked Wasm; compilation alone does not test
target behavior. `(snail shell format)` is the formatter shared by `snail-scheme lsp`
and `snail-scheme format`; `make test` checks its CLI and every tracked
Scheme file. Browser changes should be seen running:
`node tests/browser/page.mjs URL SCREENSHOT` drives headless Chromium.
Show what a change looks like on its pull request with the `gh attach`
extension (`gh extension install sudosubin/gh-attach`):
`gh attach SCREENSHOT -R tsnl/snail-scheme --markdown` uploads it as a
GitHub attachment and prints the image's Markdown, for the body or a
comment. It uses a browser's GitHub session on the machine, and GitHub
shows the file's name, so name the file for what it shows.
GPU changes should run on a device: `make test-gpu` runs the GPU checks on
Node's, through Dawn on Vulkan (lavapipe on a machine without a GPU, as
CI is), and `make test-browser` on the page's, SwiftShader in headless
Chromium.

## Applications

An application is a script, `src/apps/NAME/main.scm`. Build it with
`./snail-scheme build --target browser src/apps/NAME/main.scm` and serve its
output directory, `build/src/apps/NAME/main`, with any static HTTP server; point
`tests/browser/page.mjs` at it to see a change. Edit in any editor; in Zed,
install `editors/zed` as a dev extension for `snail-scheme lsp`'s diagnostics
of each open script and library, formatting, hover and definitions. Each build first runs the
producers of the `generate-library` recipes it reaches, so Hearsay builds
too; its producers run every time. What matters when writing code:

- Keep what should survive a page reload in the application's Save.
- A dataset is a library to import, such as `(datasets mipnerf360 bicycle)`:
  its recipe reads the files into the machine's cache, `~/.cache/snail-scheme`,
  pinned by digest, and the build links them into the program
  ([datasets](doc/book/libraries/datasets.md)).
- A program's entry is its `main`, and the parameters of `main` are the
  capabilities it asks its target for: `(define (main (out OutputPort)
  (gpu Gpu)) ...)`. A top level holds definitions alone.
- Libraries are checked one at a time, so an importer's use never decides a
  definition's type: give exported functions typed headers.
- A program runs with `./snail-scheme run --target node FILE`.
- Builds in one checkout keep private compiler scratch under `build/snail-run/`.
  Public `snail-scheme run` executes its completed generation in the caller's
  working directory after removing build scratch. Rebuilding the command line
  takes an exclusive lock on `build/lock`, so `make test` may run beside a
  build.
- The script suites (in `make test`) cover builds, and `tests/browser/`
  (`make test-browser`, in the shell's Chromium on Linux) covers the pages. `tests/lsp.mjs`
  and `tests/tree-sitter.mjs` cover the editor support. See
  [the development toolchain](doc/book/snail-scheme/toolchain.md).
