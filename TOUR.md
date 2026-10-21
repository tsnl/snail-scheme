# A tour of the compiler

The compiler is a pipeline of five passes. Each pass consumes the previous
pass's output and nothing earlier:

```text
text ──read──▶ located syntax
     ──expand─▶ core program      unique names, resolved types, entity tables
     ──check──▶ typed program     every expression typed, instances chosen
     ──mono───▶ monomorphic program
     ──wasm───▶ WasmGC text ──Binaryen──▶ module, linked with the Rust runtime
```

Read [`examples/fibonacci.sld`](examples/fibonacci.sld), run
`./lofi wat examples/fibonacci.sld` to see the WebAssembly it becomes, then
read the passes in order. The [language guide](doc/language.md) describes the
surface they implement.

## The passes

All compiler modules live in `src/lofi/compiler/` and are written in typed
Lofi: they import only `(lofi base)`, `(lofi table)` and `(lofi io)`, so the
compiler can compile itself. Chibi Scheme runs the same source through
`host/chibi/`, which implements those three libraries and erases the typed
forms. `(lofi table)` is an immutable table, so a pass threads its tables
as values where their scope is clear, such as the checker's local types,
and keeps state that grows over a whole pass in a `Ref`.

- **[`read.sld`](src/lofi/compiler/read.sld)** turns text into `Syntax`:
  atoms, identifiers and forms, each with a `Loc`. It is a recursive descent
  over a vector of characters; a line table recovers line and column only
  when a location is needed. `compile-error` reports every diagnostic.
- **[`core.sld`](src/lofi/compiler/core.sld)** defines the data the later
  passes share: `Type` (with effect rows), `Scheme`, class `Evidence`, the
  `Expr` tree, `Pattern`s, declared entities (`DataType`, `Class`,
  `Instance`, `Effect`), the `Program`, the primitive table, and TypeId
  hashing for wire types. A `Program` is a value: the expander builds it in
  one cell, and the later passes read it without effects.
- **[`expand.sld`](src/lofi/compiler/expand.sld)** is the only pass that
  knows binding forms. It loads libraries, resolves every identifier through
  environments, and runs `syntax-rules`. Hygiene is renaming: each identifier
  a template introduces gets a mark that is unique to the expansion and, when
  unbound, resolves in the macro's own environment. Top levels expand in two
  passes so definitions may refer to later ones; local bodies are
  sequential. Declarations become entities in the program tables, derived
  wire instances are generated as ordinary instance syntax, and expressions
  become core `Expr`s with unique names.
- **[`check.sld`](src/lofi/compiler/check.sld)** is Hindley-Milner inference
  with effect rows. Unannotated top-level definitions are checked in
  dependency order (Tarjan's algorithm). Each instantiation records its type
  arguments and an evidence hole per class constraint. While items are
  checked, constraints are only recorded; a group of functions quantifies
  the metavariables nothing else still mentions. When the whole program is
  checked, literals default, and each class constraint is solved once,
  filling its hole. Rows unify as sets with open tails. Matches are checked
  with Maranget's usefulness algorithm. A function whose type forbids `mut`
  may mutate storage it allocates; once types are final, nothing it can
  reach from outside, its parameters, result or names it reads, may hold
  mutable storage.
- **[`mono.sld`](src/lofi/compiler/mono.sld)** starts from the program's
  statements and values and copies each reachable definition once per ground
  instantiation. A method reference becomes the instance method its evidence
  names, and definitions that only rename another, such as
  `(define + i64-add)`, are replaced by their target.
- **[`wasm.sld`](src/lofi/compiler/wasm.sld)** chooses representations and
  emits WebAssembly text. Scalars are Wasm numbers. An enum whose cases have
  no fields is an `i32`; other data are GC structs, and enum cases are final
  subtypes of a base holding the tag. Sequences are GC arrays. Functions are
  closures: a struct whose first field is a typed function reference, with
  captured variables in a subtype. Tail calls become `return_call`. Each
  effect has a global handler stack. All GC types share one recursion group.
- **[`compiler.sld`](src/lofi/compiler.sld)** composes the passes, from a
  program's path to WebAssembly text.

## Around the compiler

| Path | Responsibility |
| --- | --- |
| `lofi`, `scripts/lofi.scm` | The command line: `run`, `compile` and `wat`. |
| `host/chibi/lofi/` | The Chibi host: `forms` erases `struct`, `enum`, `match` and signatures; `base`, `table` and `io` implement the compiler's libraries with Chibi's; `build` runs Binaryen and Cargo to assemble, optimize and link a program. |
| `bootstrap/compile.sld` | The compiler's entry program when it runs as Wasm. |
| `lib/lofi/` | The standard library, written in Lofi. Chibi never loads it. |
| `lib/scheme/` | `(scheme compiler)`, which translates R7RS programs to Lofi libraries, and `(scheme runtime)`, their standard procedures. |
| `src/runtime/` | Rust services linked into every program: math, Unicode, float text, console and file I/O, panics. |
| `scripts/run-lofi.mjs` | Runs a compiled program under Node's WASI, in a worker with room for deep recursion. |
| `src/app/` | The browser host for `(lofi app)`: input with pointer ids, ticks, a WebGPU renderer (perspective or orthographic, glow, motion between ticks, translucent and revealed batches), the keyed HUD and saves. |
| `scripts/build-app.scm` | Packages an application, with its `public/` files, as a static site. |
| `apps/siegework/` | The example game: `grid` and `terrain` (the seeded land), `world` (state, wires, power and sight), `colony` (orders and work), `siege` (attacks and combat), `simulation` (`act`, `advance` and the journal), `game` (camera, selection and commands), `view` and `hud`. |
| `apps/hearsay/` | A design for a social simulation game and the prototypes that will test it; no code yet. |
| `examples/` | Small programs; the test suite runs them, and the book's tutorials show them. |
| `doc/book/`, `book.toml` | The book published on GitHub Pages; its chapters include the language guide, the redesign and Siegework's guide. |
| `tests/` | `run.scm` runs the unit tests, `tests/programs`, Siegework's scenarios and a headless game. |

## Checks

```sh
make test       # unit tests, programs, examples and Siegework
make check      # formatting
cargo test --manifest-path src/runtime/Cargo.toml --offline
make site       # Siegework in build/siegework
make pages      # the book, with Siegework at play/siegework/, in build/pages
```

`node tests/browser/page.mjs URL SCREENSHOT` opens a page in headless
Chromium with software WebGPU and saves a screenshot.
