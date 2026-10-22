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
rustup target add wasm32-wasip1
./lofi run examples/fibonacci.sld
./lofi compile -o fibonacci.wasm examples/fibonacci.sld
./lofi wat examples/effects.sld
./lofi watch examples/fibonacci.sld   # runs it again after each edit
```

Chibi Scheme, Binaryen, Cargo and Node 26 are required; `shell.nix` provides
them from the nixpkgs revision pinned in `npins/sources.json`, the same one
CI uses. The devcontainer in `.devcontainer/` packages that environment with
Chromium for rootless podman:

```sh
podman build -t snail-scheme -f .devcontainer/Containerfile .
podman run --rm -it -v "$PWD":/workspace:Z -w /workspace snail-scheme
```

In a new checkout or container, `make fetch` downloads the Rust crates
once; builds and tests then run offline.

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
python3 -m http.server 4191 --directory build/siegework
```

While you change it, `./lofi serve apps/siegework` serves it at
<http://127.0.0.1:8000/>, rebuilds only the libraries you edit, and relinks
them into the open page, which keeps the game and the camera. `make ide`
builds the same loop into a page with an editor, in `build/ide`.

## Reading on

- [The book](https://tsnl.github.io/snail-scheme/) gathers the guides below
  with the player's guide and tutorials; `make pages` builds it with the
  game into `build/pages`.
- [The language guide](doc/language.md) describes the language as implemented.
- [The compiler tour](TOUR.md) follows a program through the passes.
- [The redesign](doc/redesign.md) records the design and what remains.

[Apache-2.0](LICENSE)
