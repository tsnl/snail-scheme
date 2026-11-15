# Snail-Scheme

Snail-Core is a typed functional language with Scheme syntax that compiles to
WasmGC. It has structs, enums, pattern matching, typeclasses with generic
instances, Koka-style effect rows with handlers, and wire types with stable
schema identities. The compiler is written in Snail-Core and compiles itself; Chibi
Scheme runs its source to start the first bootstrap.

```scheme
(import
 (snail core base)
 (snail core io))

(: fibonacci (impl (Fn I64 -> I64)))
(define (fibonacci n)
  (if (< n 2) n (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))

(display (fibonacci 30))
(newline)
```

## Getting started

```sh
nix-shell
make fetch
./snail build . siegework
./snail dev .
```

The root `project.datum` describes the whole repository, with `siegework` and
`hearsay` browser targets. `./snail dev .` (`make dev`) builds and serves
them as you edit, and `./snail lsp` serves an editor that opens the
repository: [`editors/zed`](editors/zed) is a Zed extension for it.

Compiler contributors can also inspect and execute individual source files:

```sh
./scripts/snail-tool run examples/fibonacci.sld
./scripts/snail-tool compile -o build/fibonacci.wasm examples/fibonacci.sld
./scripts/snail-tool wat examples/effects.sld
```

Chibi Scheme, Rust and Node 26.4 or later are required. `shell.nix` provides
them from the nixpkgs revision CI uses, and `.devcontainer/` packages the
same tools for podman. [Getting started](doc/getting-started.md) covers
both, other package managers and Windows, and the checks. `make fetch`
downloads the Rust crates once; builds and tests then run offline.

Programs link with Rust scalar services and run under WASI. The
first run bootstraps the compiler, which takes about a minute: Chibi runs
its source once, and the compiled compiler then rebuilds itself whenever
the source changes.

## Siegework

[Siegework](apps/siegework) is a colony game written in Snail-Core: explore a
seeded map, wire an energy network across it, and destroy three nests
before their attacks destroy your hub. It runs in the browser with WebGPU.
**[Play it online](https://tsnl.github.io/snail-scheme/play/siegework/)**,
or build it:

```sh
make site
python3 -m http.server 4191 --directory build/siegework
```

While you change it, `./snail dev .` (or `make dev`) serves the game at
<http://127.0.0.1:8000/siegework/>. Hearsay runs at
<http://127.0.0.1:8000/hearsay/>. The service reads the root `project.datum`,
rebuilds whenever a source changes on disk, whatever wrote it, and relinks
the changed libraries into the open page, which keeps the game and the
camera. In Zed, the extension in [`editors/zed`](editors/zed) highlights,
indents and formats Snail Scheme, and `snail lsp` reports each saved build's
diagnostics where they arise and gives a name's type and definition.

The [development workflow](doc/book/snail-core/toolchain.md) still needs
durable-state reload; the [typed-state API](doc/book/snail-core/state.md)
remains under review.

## Reading on

- [The book](https://tsnl.github.io/snail-scheme/) gathers the guides below
  with the player's guide and tutorials; `make pages` builds it with the
  game into `build/pages`.
- [The language chapters](doc/book/snail-core/index.md) describe terms, types,
  macros and the standard library as implemented.
- [The compiler architecture](doc/book/snail-core/compilers.md) follows a program
  through the passes, linking and incremental caches.
- [Projects and targets](doc/book/snail-core/projects.md) defines inert descriptions,
  directory outputs and artifact bundles.
- [The development toolchain](doc/book/snail-core/toolchain.md) explains the native
  project service, the language server and the editor grammar.
- [GitHub issues](https://github.com/tsnl/snail-scheme/issues) track open work.

[Apache-2.0](LICENSE)
