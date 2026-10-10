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

Project libraries can live outside this checkout. Supply ordered search directories
after the optional foreign declarations:

```scheme
(build-wasm "." "app/main.scm" "build/app.wasm" '() '("app/lib" "shared/lib"))
```

An import such as `(app helper)` searches `app/helper.sld` beneath each directory,
then falls back to the compiler's `src/`. Transitive imports use the same order.
Standard `(scheme ...)` libraries always come from `bootstrap/`.

For explicit stages, import `(snail-scheme compiler)` as well:

```scheme
(define runtime (build-runtime "."))
(source-file->wat-file "." "examples/fibonacci.scm" "build/fibonacci.wat")
(link-wasm "build/fibonacci.wat" runtime "build/fibonacci.wasm")
```

For native execution on x86-64 Linux, translate that same linked Wasm artifact:

```scheme
(import (snail-scheme native))
(wasm-file->native-file "." "build/fibonacci.wasm" "build/fibonacci")
(run-command "fibonacci" '("build/fibonacci"))
```

The Wasm-to-LLVM converter is Scheme compiler source. It translates the complete
module, including Rust; Clang/LLD and BDWGC produce the executable. `WASM_OPT`
and `CLANG` select tools. See [native execution](doc/native.md) for supported
features, GC ownership, and checks.

The compiler emits WasmGC. Binaryen assembles, links, and optimizes it with the
Rust runtime. There is **one root Cargo crate**, containing the runtime and its
AWI/tracing modules under `src/`. Cargo reuses the precompiled runtime across
Scheme programs and rebuilds it when Rust inputs change. All current Rust
services are built into that runtime; independent extension packaging is deferred.
See the [Rust callback example](examples/rust-interop/README.md).

Chibi, Cargo/rustc with `wasm32-wasip1`, Binaryen with WasmGC/tail-call support,
and a compatible Node are required. The development shell supplies `rustup` and
Python; `rust-toolchain.toml` requests Rust stable, rustfmt, and `wasm32-wasip1`.
Rustup installs missing components on first use (network access is needed then).
The stable channel is not a fixed-version benchmark toolchain. `CARGO`, `WASM_AS`,
`WASM_MERGE`, `WASM_OPT`, and `NODE` override build tools with executable paths,
not shell command strings. Chromium traces are always written under
`build/traces/`; `SNAIL_TRACE_DIR` overrides the destination.

The compiler stays Chibi-hosted. Running build scripts with Snail itself and
switching the build to self-hosting are later milestones.

This is R7RS-inspired, not fully R7RS compliant. `call/cc` is currently
unsupported. Single-shot delimited continuations are planned; reusable
multi-shot continuations are not a goal. See [TODO.md](TODO.md).

Failed builds leave the previous output intact and print the directory holding
their WAT/Wasm intermediates. Successful builds remove their temporary files.

Use `make format` and `make check` for Scheme formatting and `cargo fmt` for
Rust. Unit tests live in implementation modules; integration programs and
runners live in `tests/` and `scripts/`. See [TOUR.md](TOUR.md),
[doc/backend.md](doc/backend.md), and [BENCHMARKS.md](BENCHMARKS.md).
