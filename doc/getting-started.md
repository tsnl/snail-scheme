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
| Chibi Scheme, with its libraries | 0.12 | Running the compiler's source for the first bootstrap, and the build scripts. |
| Binaryen | 132 | `wasm-as`, `wasm-opt` and `wasm-merge` assemble, optimize and link modules. |
| Rustup | Rust 1.95.0 | The runtime services linked into every program, and the assembler. `rust-toolchain.toml` names the version and the `wasm32-wasip1` target, which rustup installs on first use. |
| Node.js | 26 | Running programs under WASI, and `./scripts/snail-tool serve` and `./scripts/snail-tool watch`. |
| Emacs | 31 | The Scheme formatter, which `make check` runs and `make test` tests. |
| nixfmt | 1.4 | `make check`'s formatting of `shell.nix`. |
| mdBook | 0.5.4 | `make pages`, the book. |
| Chromium | | `make test-browser` and `tests/browser/page.mjs`. Set `CHROMIUM` to its path when it isn't `chromium`. |

The first five compile and run programs; the rest run the checks and build
the site. Distribution packages often lag behind: an older Binaryen may lack
WasmGC support or `wasm-merge`, and an older Chibi may lack libraries the
compiler uses. The [source recipes](#source-recipes) build the versions CI uses.

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

Each block installs what its packages provide. Commands marked unverified
haven't been run on that system.

<details>
<summary>Ubuntu 24.04 — apt</summary>

```sh
sudo apt update
sudo apt install git curl ca-certificates build-essential cmake ninja-build python3 emacs-nox
```

Ubuntu's Chibi and Binaryen packages are older than CI's: build both from
the [source recipes](#source-recipes). Install Node 26 from
[nodejs.org](https://nodejs.org/en/download) and rustup from
[rustup.rs](https://rustup.rs/). Unverified.

</details>

<details>
<summary>Fedora — dnf</summary>

```sh
sudo dnf install git curl ca-certificates gcc gcc-c++ make cmake ninja-build python3 emacs-nox rustup
rustup-init
```

Build Chibi and Binaryen from the [source recipes](#source-recipes), and
install Node 26 from [nodejs.org](https://nodejs.org/en/download) if Fedora
doesn't package it yet. Unverified.

</details>

<details>
<summary>Arch Linux — pacman</summary>

```sh
sudo pacman -Syu --needed base-devel git curl cmake ninja python emacs-nox binaryen rustup nodejs
```

Arch's `nodejs` and `binaryen` follow upstream releases. Build Chibi from
the [source recipe](#source-recipes). Unverified.

</details>

<details>
<summary>macOS — Homebrew</summary>

```sh
xcode-select --install
brew install git make chibi-scheme binaryen node rustup emacs
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
```

Follow Homebrew's instructions for putting rustup on your `PATH`. Unverified.

</details>

### Source recipes

<details>
<summary>Chibi Scheme 0.12</summary>

Needs a C compiler and Make. This installs Chibi and its libraries in
`~/.local`, as the [upstream instructions](https://github.com/ashinn/chibi-scheme/tree/0.12)
describe:

```sh
mkdir -p ~/.local/src
git clone --depth 1 --branch 0.12 https://github.com/ashinn/chibi-scheme.git ~/.local/src/chibi-scheme-0.12
make -C ~/.local/src/chibi-scheme-0.12 PREFIX="$HOME/.local"
make -C ~/.local/src/chibi-scheme-0.12 PREFIX="$HOME/.local" install
export PATH="$HOME/.local/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
```

</details>

<details>
<summary>Binaryen 132</summary>

Needs CMake, Ninja, Python 3 and a C++ compiler, and takes several minutes.
The [release](https://github.com/WebAssembly/binaryen/releases/tag/version_132)
also has prebuilt archives; either way, keep its tools together on `PATH`.

```sh
mkdir -p ~/.local/src
git clone --depth 1 --branch version_132 --recurse-submodules https://github.com/WebAssembly/binaryen.git ~/.local/src/binaryen-132
cmake -S ~/.local/src/binaryen-132 -B ~/.local/src/binaryen-132/build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF -DCMAKE_INSTALL_PREFIX="$HOME/.local"
cmake --build ~/.local/src/binaryen-132/build
cmake --install ~/.local/src/binaryen-132/build
export PATH="$HOME/.local/bin:$PATH"
```

</details>

## On Windows

Use WSL2 with Ubuntu, so the scripts and Chibi's subprocesses run on Linux.
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
./scripts/snail-tool run examples/scheme-fibonacci.sld
```

`make fetch` downloads the Rust crates in each `Cargo.lock` once; builds and
tests then run offline. The first run bootstraps the compiler, which takes
about a minute: Chibi runs the compiler's source once, and the compiled
compiler then rebuilds itself whenever its source changes. The first program
prints `832040`. The second is the same program in Scheme, compiled through
`(scheme base)`, and prints `75025` and two more lines.

## The checks

```sh
make test          # the formatter, the compiler, the programs and the games
make check         # formatting
cargo test --manifest-path crates/snail-core-support/Cargo.toml --offline
cargo test --manifest-path crates/snail/Cargo.toml --offline
make test-chibi    # the suite with the compiler's source running on Chibi
make bootstrap     # the compiler rebuilt from Chibi alone, to a fixpoint
make test-browser  # hot reload and the IDE in headless Chromium
```

CI runs the first four, and `cargo fmt --check` on both crates. A change to
the compiler also needs `make test-chibi` and `make bootstrap`, and a change
to the browser host or the IDE `make test-browser`. The [tour](book/snail-core/compilers.md)
introduces the compiler.
