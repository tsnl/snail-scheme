# Getting started

The compiler runs on Linux and macOS. On Windows, use WSL2. There are three
ways to get the tools:

- **Nix** gives exactly the tools CI uses.
- **The devcontainer** packages that same environment for podman.
- **Your package manager**, with source recipes for the tools it lacks.

Whichever you pick, finish with [the first run](#the-first-run).

## The tools

| Tool | CI's version | Used for |
| --- | --- | --- |
| Git, a POSIX shell and GNU Make | | The checkout, `./snail` and the Makefile. |
| Chez Scheme | 10.4.1 | Running the compiler's source for the first bootstrap, and the build scripts. |
| Rustup | Rust 1.95.0 | The runtime services linked into every program, and the assembler/linker. `rust-toolchain.toml` names the version and the `wasm32-wasip1` target, which rustup installs on first use. |
| Node.js | 26 | Running programs under WASI, and `snail dev`. |
| nixfmt | 1.4 | `make check`'s formatting of `shell.nix`. |
| mdBook | 0.5.4 | `make pages`, the book. |
| Chromium | | `make test-browser` and `tests/browser/page.mjs`. Set `CHROMIUM` to its path when it isn't `chromium`. |

The first four compile and run programs, including the Scheme formatter used
by `make check`; the rest format Nix and build or test the site. `CHEZ` can
name a particular Chez executable; it defaults to `scheme`. The pinned Nix
environment supplies the version used by CI.

## With Nix

```sh
git clone https://github.com/tsnl/snail-scheme.git
cd snail-scheme
nix-shell
```

`shell.nix` takes its nixpkgs from the revision pinned in
`npins/sources.json`, which CI and the devcontainer also use, and provides
every tool above except Chromium. `npins update nixpkgs` moves the pin.

## With the devcontainer

`.devcontainer/` builds that environment with Chromium added, from the
`nixos/nix` image. With rootless podman, the container's root is your own
user, so files written in the mounted checkout stay yours:

```sh
podman build -t snail-scheme -f .devcontainer/Containerfile .
podman run --rm -it -v "$PWD":/project:Z -w /project snail-scheme
```

An editor that opens devcontainers runs `make fetch` when it creates the
container. With plain podman, run it yourself once. CI builds the image with
podman and checks it whenever its inputs change.

## With a package manager

Install the tools in the table using your platform's packages, then check their
versions against the repository's pinned environment. Use the executable from
Chez Scheme, rather than another interpreter also named `scheme`; set `CHEZ`
if necessary. The compiler's explicit stage-zero adapter handles its library
syntax and typed forms. No R7RS library installation is needed.

Node must support WasmGC and WebAssembly tail calls. Rustup reads the pinned
Rust release and Wasm target from `rust-toolchain.toml`. If a platform's packages
are older, the Nix environment is the reproducible route used by CI.

## On Windows

Use WSL2 with Ubuntu, so the scripts and Chez's subprocesses run on Linux.
In an administrator PowerShell:

```powershell
wsl --install -d Ubuntu-24.04
wsl --list --verbose
```

If the distribution shows version 1, convert it with
`wsl --set-version Ubuntu-24.04 2`. Microsoft's
[installation guide](https://learn.microsoft.com/en-us/windows/wsl/install)
covers the rest. Then, in the Ubuntu terminal, follow the Ubuntu or Nix
instructions above. Clone into your Linux home directory, such as
`~/snail-scheme`, so the scripts see Linux paths and permissions.

## The first run

From the checkout:

```sh
make fetch
./scripts/snail-tool run examples/fibonacci.sld
```

`make fetch` downloads the Rust crates in each `Cargo.lock` once; builds and
tests then run offline. The first run bootstraps the compiler, which takes
a source compilation with Chez followed by self-compilation. The compiled
compiler rebuilds itself whenever its source changes. The example prints
`832040`. Runtime work belongs in its `main` function; libraries contain
functions, types and pure compile-time values.

## The checks

```sh
make test          # the formatter, the compiler, the programs and the games
make check         # formatting
cargo test --manifest-path crates/snail-core-support/Cargo.toml --offline
cargo test --manifest-path crates/snail/Cargo.toml --offline
make test-chez    # the suite with the compiler's source running on Chez
make bootstrap     # the compiler rebuilt from Chez alone, to a fixpoint
make test-wasmtime # linked programs on the native Wasmtime host
make test-browser  # hot reload and the IDE in headless Chromium
```

CI runs the first four, and `cargo fmt --check` on both crates. A change to
the compiler also needs `make test-chez` and `make bootstrap`, and a change
to the browser host or the IDE `make test-browser`. The [tour](book/snail-core/compilers.md)
introduces the compiler.
