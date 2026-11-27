# `snail-scheme`

**`snail-scheme` is a statically-typed Scheme successor.** It compiles to
WasmGC, and has structs, enums, pattern matching, typeclasses with generic
instances, capabilities passed as values, one-shot suspension, and wire types with stable
schema identities. The compiler is written in `snail-scheme` and compiles itself; Chibi
Scheme runs its source to start the first bootstrap.

```scheme
(import
 (snail core base)
 (snail core io))

(define (fibonacci (n I64)) (→ I64)
  (if (< n 2) n (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))

(define (main (out OutputPort)) (→ Unit)
  (display out (fibonacci 30))
  (newline out))
```

## Getting started

```sh
nix-shell
make fetch
./snail-scheme build --target browser src/apps/siegework/main.scm
```

Siegework and Hearsay are scripts, `src/apps/NAME/main.scm`, and
`./snail-scheme lsp` serves an editor that opens the repository: [`editors/zed`](editors/zed) and [`editors/vscode`](editors/vscode)
are extensions for Zed and VS Code.

A script runs for an explicit target. The tool finds its workspace by looking
upward for `snail-scheme-workspace.datum`. A workspace can extend a local
base, and both contribute libraries under `src/`.

```sh
./snail-scheme run --target node examples/fibonacci.sld
./snail-scheme build --target node --release examples/fibonacci.sld
./snail-scheme wat --target node examples/capabilities.sld
```

Chibi Scheme, Rust and Node 26.4 or later are required. `shell.nix` provides
them from the nixpkgs revision CI uses, and `.devcontainer/` packages the
same tools for podman. [Getting started](doc/getting-started.md) covers
both, other package managers and Windows, and the checks. `make fetch`
downloads the Rust crates and npm packages once; builds and tests then run
offline. A Node build is an npm package, which runs wherever it is copied.

Programs link with Rust scalar services and run under WASI. The
first run bootstraps the compiler, which takes about a minute: Chibi runs
its source once, and the compiled compiler then rebuilds itself whenever
the source changes.

## Siegework

[Siegework](src/apps/siegework) is a colony game written in `snail-scheme`: explore a
seeded map, wire an energy network across it, and destroy three nests
before their attacks destroy your hub. It runs in the browser with WebGPU.
**[Play it online](https://tsnl.github.io/snail-scheme/play/siegework/)**,
or build it:

```sh
make site
python3 -m http.server 4191 --directory build/src/apps/siegework/main
```

Rebuild with `make siegework` and reload the page to see a change;
`build/src/apps/hearsay/main` serves Hearsay the same way. In Zed, the extension in [`editors/zed`](editors/zed) highlights,
indents and formats `snail-scheme`, and `snail-scheme lsp` reports each saved build's
diagnostics where they arise and gives a name's type and definition.

The [typed-state API](doc/book/snail-scheme/state.md) remains under review.

## Reading on

- [The book](https://tsnl.github.io/snail-scheme/) gathers the guides below
  with the player's guide and tutorials; `make pages` builds it with the
  game into `build/pages`.
- [The language chapters](doc/book/snail-scheme/index.md) describe terms, types,
  macros and the standard library as implemented.
- [The compiler architecture](doc/book/snail-scheme/compilers.md) follows a program
  through the passes, linking and incremental caches.
- [Workspaces and builds](doc/book/snail-scheme/workspaces.md) defines workspaces,
  directory outputs and embedding one build in another.
- [The development toolchain](doc/book/snail-scheme/toolchain.md) explains the
  commands, the language server and the editor grammar.
- [GitHub issues](https://github.com/tsnl/snail-scheme/issues) track open work.

[Apache-2.0](LICENSE)
