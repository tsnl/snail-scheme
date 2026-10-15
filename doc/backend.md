# WebAssembly and native backends

The compiler emits WasmGC. Binaryen optimizes the Scheme module, links the common
Rust-to-Wasm library and selected platform handlers, then optimizes the complete
module. The engine collects Scheme objects; the current installed Wasm host is
Node.js. The [native backend](native.md) mechanically lowers optimized program
Wasm through LLVM and links the same Rust implementations with the in-house GC.
Both production outputs require Binaryen; the native target is 64-bit only.

## Build and run

```sh
nix-shell
rustup target add wasm32-wasip1
chibi-scheme -h512M -I src build.scm
node --no-warnings scripts/run-wasi.mjs build/snail-scheme.wasm examples/fibonacci.scm
chibi-scheme -I src examples/rust-interop/build.scm
```

Chibi remains the bootstrap host. The built command accepts `-I DIRECTORY`,
`-IDIRECTORY`, `--help`, and `SCRIPT [ARGUMENT ...]`. Script arguments remain
literal, including empty strings. An ordinary script runs its forms once and
returns zero on normal completion. A build can explicitly select a zero-argument
`main`, which runs after initialization and must return an integer in 0..255.
A helper named `main` does not change ordinary script behavior.

Binaryen is required. The Nix shell supplies its complete tool suite. Otherwise
install [Binaryen](https://github.com/WebAssembly/binaryen/releases/tag/version_132)
on PATH. `WASM_AS`, `WASM_OPT`, `WASM_DIS`, and `WASM_MERGE` override individual
executables. Compiler startup checks all four before compiling; help works
without them. `CARGO` and `NODE` select Cargo and the command host.
Rust/Cargo must have the `wasm32-wasip1` target and offline dependencies available.
`rust-toolchain.toml` requests stable Rust and rustfmt. Historical measurements
record exact tool versions separately.

## Compiler and build APIs

| Library / operation | Result |
| --- | --- |
| `(snail-scheme compiler)` `source-file->wasm(root, input)` | Complete in-memory Wasm datum; no process execution. |
| `source-file->wat-file(root, input, output)` | Write that unlinked module. |
| `(snail-scheme build)` `build-wasm(root, input, output)` | Compile, link, optimize, and atomically publish. |
| `compile-wasm(root, input, directory, output)` | Compile into a caller-owned workspace and return its dependency artifact. |
| `build-runtime(root)` | Installed runtime companion, or a Cargo-built Wasm library. |
| `link-wasm(wat, runtime, output)` | Link an already emitted Scheme module with a platform. |
| `run-wasm(root, module, arguments)` | Execute Node/WASI and return the process status. |
| `run-script(root, script, arguments)` | Build and execute an ordinary temporary Wasm script. |

Compiler and build operations require a `with-chromium-trace-to` scope. Paths
are explicit and relative to the caller's working directory. Optional compilation
arguments are foreign declarations, project library directories, and selected
entry, in that order. Foreign declarations can map a Scheme name to a module
with a `snail:NAME` export, or use `(NAME "MODULE" "EXPORT")` explicitly.
`(snail-scheme effects)` supplies selected platform bindings; see
[effect interfaces](book/effects.md).

For nonstandard libraries, project search directories precede `src/`. The first
existing file wins, and its parse errors do not fall through. `(scheme ...)`
always resolves to the bootstrap library. The frontend loads and expands located
syntax into identity-based IR, then emits Wasm. Type annotations and measured
check elimination are described in [typing](typing-prototype.md).

## Build ownership

Builds own private workspaces. Protected inputs are checked before work and
before publication. Failure preserves the last published artifact and reports
retained intermediates. A completed artifact and its dependencies are published
as one generation through one relative symlink. The Node runner resolves that
payload once; later dependency lookup stays in the selected generation.
See [generation and packaging](build-artifacts.md).

Generators also run as linked Wasm programs. Their result is located Scheme
syntax and an explicit dependency graph. Chibi and the compiled command use the
same build recipe; Chibi supplies bootstrap process operations, and Node supplies
the compiled command's build effects. Subprocess arguments never pass through a
shell. Build tools receive EOF; executed scripts inherit standard input.

Cargo reuses `build/wasm-runtime`. The Rust library is a reactor; the entry calls
its initializer once, then initializes the selected environment, then Scheme.
The common library and default WASI implementations currently share one linear
memory. Selected provider modules must honor that memory and root ABI.

## Representations and ownership

Scheme heap values are WasmGC objects. Small exact integers and symbol/character
immediates use `i31ref`; larger signed integers use boxed i64. Exact integers
beyond signed 64-bit, general rationals, and `call/cc` remain unsupported.
An extension borrows an i32 argument-vector root and returns one owned i32 root.
Rust's `Root` keeps values reachable across allocation and callbacks. Accessors
return owned roots; dropping one releases its table slot. See [the ABI](book/abi.md).

Ports own host resources. Explicit close provides timely cleanup; the JS
finalization hook holds only resource kind and ID, never the watched wrapper.
Fatal diagnostics and traps terminate the command. Discard a failed instance;
there is no recoverable exception or continuation protocol across Rust frames.

## Validation and measurements

```sh
make test
make check
cargo test --offline
cargo fmt --all -- --check
scripts/test-backend
scripts/test-build
scripts/test-effects
scripts/test-generation
scripts/test-self-host
scripts/test-typing
scripts/test-binaryen
scripts/test-chromium-trace
scripts/test-native
scripts/test-strict-io
scripts/book build
```

Backend checks execute linked Wasm, including diagnostics, streams, callback
roots, and finalizers. The compiled-command check executes scripts and rebuilds
the command as Wasm. The provider check executes two clock implementations and
rejects incompatible bindings. Formatting and compilation alone are insufficient.

[Benchmarks](../BENCHMARKS.md) describe the full pinned R7RS suite, compiler
baseline, failures, and reproducibility. Historical native comparisons remain
separate from the restored [native implementation and contracts](native.md).

## Actor prototype

`scripts/build-actor INPUT.sld OUTPUT.wasm` compiles one library and the portable
S-expression codec, links the current Rust library and WASI platform, and always
runs Binaryen. Value exports become same-instance ABI functions; macros are
excluded. The Node host in `runtime/actors.mjs` creates a separate process for
each instance and exposes connection-owned calls. See
[the actor example](../examples/actors/README.md); `scripts/test-actors` executes
linked Wasm and `scripts/test-ui` exercises the separate Chibi HTTP prototype.
