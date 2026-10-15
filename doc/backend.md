# Building and testing SFIR

The compiler implementation runs in Chibi. Product inputs are `.sfir` files;
`build.scm`, Scheme elaboration and self-hosting are deferred.

`nix-shell` supplies Chibi, Chez, Node, Binaryen, LLVM and Rustup.
Install the Rust target used by the shared WASI runtime:

```sh
rustup target add wasm32-wasip1
./snail-sfir run examples/fibonacci.sfir
./snail-sfir run --target native examples/fibonacci.sfir
```

Binaryen is mandatory for both targets. The preflight checks `wasm-as`,
`wasm-opt`, `wasm-dis` and `wasm-merge`. Tool overrides are `CHIBI`, `NODE`,
`CARGO`, `WASM_AS`, `WASM_OPT`, `WASM_DIS` and `WASM_MERGE`; native builds also
use `LLVM_OPT`, `LLC` and `RUSTC`. An invalid override fails explicitly. Cargo builds the
runtime offline, so dependencies must already be available locally.

Native execution currently validates x86-64 Linux. It lowers the optimized
Wasm mechanically and links the same Rust externs, the native host, and the
in-house Rust collector. Rust providers export concrete `extern "C"` functions;
unsupported ABI spellings fail before linking. Cargo invokes Rust's bundled
`rust-lld` directly: no C compiler driver is required. The native executable
still uses the system C runtime and startup objects; `SNAIL_NATIVE_LIBC` and
`SNAIL_NATIVE_GCC` select those library directories on Nix. Coreutils supplies
ordinary file copying and hashing for the Scheme tools.
See [command options](options.md).

The Nix shell sets `RUSTC_WRAPPER` to `scripts/rustc-native`. This small Scheme
wrapper also supplies the native linker for Cargo's host build scripts during
Wasm builds. It preserves Cargo's selected compiler, explicit target and linker.
On x86-64 Linux outside the Nix shell, enable it from the checkout with
`export RUSTC_WRAPPER="$PWD/scripts/rustc-native"` before running Cargo directly.
SFIR native build commands configure their linker themselves.

## Checks

The reader checks use canonical data from the pinned benchmark submodule.
Initialize it before running the aggregate checks:

```sh
git submodule update --init benchmarks/r7rs-benchmarks
make test
make check
cargo test --offline
cargo fmt --all -- --check
scripts/test-build
scripts/test-backend
scripts/test-native
```

Host unit tests do not establish target behavior. Backend checks execute linked
Wasm, and native checks execute native code, including forced collection and
traps. The SFIR integration migration preserves the prior typed contracts while
removing Scheme syntax expansion from their runners.

Build helpers retain WAT, raw Wasm, optimized Wasm and trace files. Native build
directories also retain LLVM, commands and source hashes. Public compile commands
publish only a complete artifact; failed builds leave the previous output intact
and print the retained directory. Successful public runs remove their private
build files.

Benchmarks have their own [frozen protocol](../benchmarks/README.md). Record
compilation and execution separately; preserve failures and compare complete
matched workloads. Run clean timing samples without concurrent compilation,
profiling or forced-GC jobs.
