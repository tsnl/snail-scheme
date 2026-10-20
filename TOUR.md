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

All compiler modules live in `src/lofi/compiler/` and run on Chibi Scheme.

- **[`shim.sld`](src/lofi/compiler/shim.sld)** gives Chibi Lofi's `struct`,
  `enum`, `match` and `:` forms, so the compiler is written in the same style
  as the programs it compiles. Structs become vectors tagged by their
  constructor.
- **[`read.sld`](src/lofi/compiler/read.sld)** turns text into `Syntax`:
  atoms, identifiers and forms, each with a `Loc`. It is a recursive descent
  over a vector of characters; a line table recovers line and column only
  when a location is needed. `compile-error` reports every diagnostic.
- **[`core.sld`](src/lofi/compiler/core.sld)** defines the data the later
  passes share: `Type` (with effect rows), `Scheme`, class `Evidence`, the
  `Expr` tree, `Pattern`s, declared entities (`DataType`, `Class`,
  `Instance`, `Effect`), the `Program` tables, the primitive table, and
  TypeId hashing for wire types.
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
  with Maranget's usefulness algorithm.
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
- **[`build.sld`](src/lofi/compiler/build.sld)** composes the passes and runs
  Binaryen and Cargo: assemble, optimize, and merge with the runtime.

## Around the compiler

| Path | Responsibility |
| --- | --- |
| `lofi`, `scripts/lofi.scm` | The command line: `run`, `compile` and `wat`. |
| `lib/lofi/` | The standard library, written in Lofi. Chibi never loads it. |
| `src/runtime/` | Rust services linked into every program: math, Unicode, float text, console and file I/O, panics. |
| `scripts/run-lofi.mjs` | Runs a compiled program under Node's WASI. |
| `src/app/` | The browser host for `(lofi app)`: input, ticks, a WebGPU renderer, the HUD and saves. |
| `scripts/build-app.scm` | Packages an application as a static site. |
| `apps/siegework/` | The example game: `grid`, `world` (all rules), `game` (input and camera) and `view`. |
| `examples/` | Small programs; the test suite runs them. |
| `tests/` | `run.scm` runs the unit tests, `tests/programs`, Siegework's scenarios and a headless game. |

## Checks

```sh
make test       # unit tests, programs, examples and Siegework
make check      # formatting
cargo test --manifest-path src/runtime/Cargo.toml --offline
make site       # Siegework in build/siegework
```

`node tests/browser/page.mjs URL SCREENSHOT` opens a page in headless
Chromium with software WebGPU and saves a screenshot.
