# Lofi

Lofi is a typed functional language with Scheme syntax that compiles to
WasmGC. It has structs, enums, pattern matching, typeclasses with generic
instances, Koka-style effect rows with handlers, and wire types with stable
schema identities. The compiler is written in Lofi and compiles itself; Chibi
Scheme runs its source to start the first bootstrap.

```scheme
(import
 (lofi base)
 (lofi io))

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
./lofi run examples/fibonacci.sld
./lofi compile -o build/fibonacci examples/fibonacci.sld
./lofi wat examples/effects.sld
./lofi watch examples/fibonacci.sld   # runs it again after each edit
```

Chibi Scheme, Binaryen, Rust and Node 26 are required. `shell.nix` provides
them from the nixpkgs revision CI uses, and `.devcontainer/` packages the
same tools for podman. [Getting started](doc/getting-started.md) covers
both, other package managers and Windows, and the checks. `make fetch`
downloads the Rust crates once; builds and tests then run offline.

Programs are linked with a small Rust runtime and run under WASI. The
first run bootstraps the compiler, which takes about a minute: Chibi runs
its source once, and the compiled compiler then rebuilds itself whenever
the source changes.

## Siegework

[Siegework](apps/siegework) is a colony game written in Lofi: explore a
seeded map, wire an energy network across it, and destroy three nests
before their attacks destroy your hub. It runs in the browser with WebGPU.
**[Play it online](https://tsnl.github.io/snail-scheme/play/siegework/)**,
or build it:

```sh
make site
python3 -m http.server 4191 --directory apps/siegework/build/site
```

While you change it, `./lofi serve apps/siegework` serves it at
<http://127.0.0.1:8000/>, rebuilds only the libraries you edit, and relinks
them into the open page, which keeps the game and the camera.
`./lofi dev --port 8001 apps/siegework` starts the native project compiler and
browser editor. It reads `project.datum`; saving writes disk, and one shared
watcher notifies both compiler and editor, including edits made by other tools.
The editor keeps highlighting, Scheme indentation, format-on-save and split
panes. Builds publish fresh diagnostic messages; located squiggles follow.
`make ide` starts this service for Siegework on port 8000.

Project builds and the native editor are implemented. The
[project and development workflow](doc/proposals/desktop-ide.md) still needs
application launches and reloads under `dev`; use `serve`/`watch` for those
until that integration lands. The [typed-state API](doc/proposals/typed-state.md)
remains under review.

## Reading on

- [The book](https://tsnl.github.io/snail-scheme/) gathers the guides below
  with the player's guide and tutorials; `make pages` builds it with the
  game into `build/pages`.
- [The language guide](doc/language.md) describes the language as implemented.
- [The compiler tour](TOUR.md) follows a program through the passes.
- [The redesign](doc/redesign.md) records the design, and the book's
  [roadmap](doc/book/roadmap.md) what is implemented and what remains.
- [The toolchain design](doc/toolchain.md) explains separate compilation,
  hot reload and the native project service with its browser editor.

[Apache-2.0](LICENSE)
