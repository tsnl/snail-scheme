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
| Git, a POSIX shell and GNU Make | | The checkout, `./snail-scheme` and the Makefile. |
| Chez Scheme | 10.4.1 | Running the compiler's source for the first bootstrap, and the build scripts. |
| Rustup | Rust 1.95.0 | The runtime services linked into every program, and the assembler/linker. `rust-toolchain.toml` names the version and the `wasm32-wasip1` target, which rustup installs on first use. |
| Node.js | 26 | Running programs under WASI. |
| nixfmt | 1.4 | `make check`'s formatting of `shell.nix`. |
| mdBook | 0.5.4 | `make pages`, the book. |
| Binaryen | 132 | `wasm-opt`, which optimizes a release build (`--release`, `make site`). |
| tree-sitter CLI | 0.26.11 | `make test`'s check of the editors' grammar, which also needs a C compiler. |
| Chromium | | `make test-browser` and `tests/browser/page.mjs`. The shell provides it on Linux; elsewhere, set `CHROMIUM` to a Chromium or Chrome. |
| The `webgpu` package | 0.6.2 | WebGPU on Node: Dawn's `dawn.node`, which `package.json` pins and `make fetch` installs from npm, for `host/native/gpu.mjs` and `make test-gpu`. On Linux it needs the Vulkan loader and a Vulkan driver for the GPU. |
| The `@napi-rs/canvas` package | 1.1.1 | Images on Node: a 2D canvas over Skia, which `package.json` pins and `make fetch` installs from npm, for `decode-image` in `host/native/gpu.mjs`. It is MIT, and asks nothing of the system. |

The first four compile and run programs, including the Scheme formatter used
by `make check`; the rest format Nix, build or test the site, and test the
editors' grammar. `CHEZ` can
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
every tool above except the GPU's driver, which is the system's, and, on
macOS, Chromium, which nixpkgs builds for Linux alone. `npins update
nixpkgs` moves the pin.

## With the devcontainer

`.devcontainer/` builds that environment from the `nixos/nix` image. With rootless podman, the container's root is your own
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
./snail-scheme run --target node examples/fibonacci.scm
```

`make fetch` downloads the Rust crates in each `Cargo.lock` and the npm
packages `package-lock.json` pins once; builds and tests then run offline. The first run bootstraps the command line, which
takes a source compilation with Chez followed by self-compilation, and then
the command line builds the script into `build/examples/fibonacci` and runs
it on Node. The command line rebuilds itself whenever its source changes.
The example prints `832040`. A script's runtime work is its top-level
statements, or its `main` function; libraries contain functions, types and
pure compile-time values.

## The checks

```sh
make test          # the formatter, the compiler, the programs and the games
make check         # formatting
cargo test --manifest-path crates/snail-scheme-support/Cargo.toml --offline
make bootstrap     # the compiler rebuilt from Chez alone, to a fixpoint
make test-browser  # browser interfaces in headless Chromium
make test-gpu      # the GPU checks on Node, on the machine's GPU or on lavapipe
```

CI runs the first three, `make test-gpu` on lavapipe, Mesa's Vulkan on the
CPU, and `cargo fmt --check` on the crate. A change to
the compiler also needs `make bootstrap`, a change
to the browser host `make test-browser`, and a change to the `Gpu`'s
hosts or the graphics and tensor libraries both browser and GPU checks. The [tour](book/snail-scheme/compilers.md)
introduces the compiler.
