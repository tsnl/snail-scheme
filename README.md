# `snail-scheme`

> Rewrite in progress; the previous implementation lives on branch `v3`.

A small Scheme compiler library, hosted by Chibi. Ordinary Scheme scripts choose
what to compile, where to write it, and whether to run it. There is no compiler
CLI mode parser or separate Rust driver.

```sh
nix-shell
chibi-scheme -I src build.scm
make test
scripts/test-build
scripts/test-backend
```

The checked-in [build.scm](build.scm) compiles and runs Fibonacci:

```scheme
(import (scheme base) (snail-scheme build))
(build-wasm "." "examples/fibonacci.scm" "build/fibonacci.wasm")
(run-wasm "." "build/fibonacci.wasm" '())
```

Copy or edit that script, or write your own. A build script is free to read
`command-line`, import project libraries, generate several artifacts, or skip
execution. Run it with `chibi-scheme -I /path/to/snail-scheme/src your-build.scm`.
The root argument above identifies the Snail checkout; input and output paths
are relative to the script's working directory. `run-wasm` returns the program's
exit code; the script decides whether to pass it to `exit`.

For explicit stages, import `(snail-scheme compiler)` as well:

```scheme
(define runtime (build-runtime "."))
(source-file->wat-file "." "examples/fibonacci.scm" "build/fibonacci.wat")
(link-wasm "build/fibonacci.wat" runtime "build/fibonacci.wasm")
```

The compiler emits WasmGC. Binaryen assembles, links, and optimizes it with the
Rust runtime. There is **one root Cargo crate**, containing the runtime and its
AWI/tracing modules under `src/`. Cargo reuses the precompiled runtime across
Scheme programs and rebuilds it when Rust inputs change. All current Rust
services are built into that runtime; independent extension packaging is deferred.
See the [Rust callback example](examples/extension/README.md).

Chibi, Cargo/rustc with `wasm32-wasip1`, Binaryen with WasmGC/tail-call support,
and a compatible Node are required. `CARGO`, `WASM_AS`, `WASM_MERGE`, `WASM_OPT`,
and `NODE` override build tools. Chromium traces are always written under
`build/traces/`; `SNAIL_TRACE_DIR` overrides the destination.

The compiler stays Chibi-hosted. Running build scripts with Snail itself and
switching the build to self-hosting are later milestones. Native translation
of the linked Wasm is being integrated separately; the currently landed bounded
Wasm-to-LLVM experiment is not a general native build route.

This is R7RS-inspired, not fully R7RS compliant. `call/cc` is currently
unsupported. Single-shot delimited continuations are planned; reusable
multi-shot continuations are not a goal. See [TODO.md](TODO.md).

Use `make format` and `make check` for Scheme formatting and `cargo fmt` for
Rust. Unit tests live in implementation modules; integration programs and
runners live in `tests/` and `scripts/`. See [TOUR.md](TOUR.md),
[doc/backend.md](doc/backend.md), and [BENCHMARKS.md](BENCHMARKS.md).

The libraries in `src/snail-scheme/` separate source locations (`source.sld`),
the character reader (`reader.sld`), general parser combinators (`parser.sld`),
syntax records and accessors (`syntax.sld`), syntax parsing (`syntax-parser.sld`),
pattern matching and dispatch (`pattern.sld`), macro expansion (`expand.sld`),
and resolved IR records (`ir.sld`).
`pmap` transforms parser values;
ordinary Scheme `map` operates on lists. The historical parser inspection code lives in `cli.sld` and `main.scm`;
compiler build operations live in `(snail-scheme build)`.
Character predicates live in `common.sld`. Syntax rules match the input directly,
using `tuple`, `repeat`, and `pmap` to assemble spellings from character results.
Direct reader access stays in the parser primitives. Separate `s-number` and
`s-symbol` rules check token boundaries with `not-followed-by`, so `12abc` and
`hello#t` cannot split into smaller atoms. Booleans, characters, and dotted tails
also require a delimiter or EOF after their spelling.

`chain` takes an initial parser followed by binders that receive each successful
value and return the next parser. `pmap` transforms a successful result directly.
`tuple` threads the reader through its parsers and collects positional values;
`named-tuple` accepts `(symbol . parser)`
pairs, conventionally written with quasiquote, and returns an association list.
Use `(cdr (assq 'name fields))` to retrieve a named value. Keys must be unique
symbols, except `_`, whose parser runs but whose value is discarded.

`string->reader` and `list->reader` take a filename followed by their contents;
`file->reader` loads a file by path. Apply `(s-file reader)` to parse a complete
file, then check `parse-result-ok?` before extracting `parse-result-value`.
The result contains a list of syntax objects; trailing intertoken space and EOF
are handled by `s-file`. Source locations and the reader in a failed parse result
retain the filename.
