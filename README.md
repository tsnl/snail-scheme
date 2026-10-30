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

(: fibonacci (-> I64 I64))
(define (fibonacci n)
  (if (< n 2) n (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))

(display (fibonacci 30))
(newline)
```

## Getting started

```sh
nix-shell
make fetch
./snail build apps/siegework site
./snail dev apps/siegework
```

Compiler contributors can also inspect and execute individual source files:

```sh
./scripts/snail-tool run examples/fibonacci.sld
./scripts/snail-tool compile -o build/fibonacci.wasm examples/fibonacci.sld
./scripts/snail-tool wat examples/effects.sld
```

Chibi Scheme, Binaryen, Rust and Node 26.4 or later are required. `shell.nix` provides
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
python3 -m http.server 4191 --directory apps/siegework/build/site
```

While you change it, `./snail dev apps/siegework` (or `make ide`) serves the
browser editor at <http://127.0.0.1:8000/> and the game at
<http://127.0.0.1:8001/site/>. It reads `project.datum`, rebuilds only the
libraries you edit, and relinks them into the open page, which keeps the game
and the camera. Saving writes disk, and one shared watcher notifies both
compiler and editor, including edits made by other tools. The editor keeps
highlighting, Scheme indentation, format-on-save and split panes. Builds
publish fresh diagnostics with source points in saved buffers.

The Applications panel starts, stops and restarts named program targets. Accepted
builds replace affected wanted processes; failed builds leave them running.
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
  project service and browser editor.
- [GitHub issues](https://github.com/tsnl/snail-scheme/issues) track open work.

[Apache-2.0](LICENSE)
