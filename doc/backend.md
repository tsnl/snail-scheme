# Building and testing SFIR

The compiler implementation runs in Chibi and emits Wasm from `.sfir` inputs.
Ordinary Scheme build scripts import that compiler and the separate
[Wasm-to-native package](../wasm-native/README.md) to compose native builds.
Scheme elaboration and self-hosting remain deferred.

`nix-shell` supplies Chibi, Chez, Node, Binaryen, LLVM and Rustup.
Install the Rust target used by the shared WASI runtime:

```sh
rustup target add wasm32-wasip1
./snail-sfir run examples/fibonacci.sfir
scripts/build-native examples/fibonacci.sfir build/fibonacci
build/fibonacci
```

Binaryen is mandatory for both execution routes. The preflight checks `wasm-as`,
`wasm-opt`, `wasm-dis` and `wasm-merge`. Tool overrides are `CHIBI`, `NODE`,
`CARGO`, `WASM_AS`, `WASM_OPT`, `WASM_DIS` and `WASM_MERGE`; native builds also
use `LLVM_OPT`, `LLC` and `RUSTC`. An invalid override fails explicitly. Cargo
builds the single runtime crate at `wasm-native/Cargo.toml` offline, so dependencies must
already be available locally. Rust `cfg` selects the Wasm or native runtime
implementation; filesystem and other scalar services share the same sources.

Repository Scheme scripts use explicit search roots:
`chibi-scheme -I "$repo/src" -I "$repo/wasm-native/scheme" SCRIPT ...`.
The standalone package needs only `-I "$package/scheme"` and installed Chibi/SRFI
libraries; its tests additionally use `-I "$package/tests"`.
`(wasm-native runtime-wasm)` builds and links the runtime's Wasm form without
importing native lowering. The compiler likewise imports only the neutral Wasm,
optimization and host utilities it needs from the package.

Native execution currently validates x86-64 Linux. It lowers the optimized
Wasm mechanically and links the same Rust externs, the native host, and the
in-house Rust collector. Rust providers export concrete `extern "C"` functions;
unsupported ABI spellings fail before linking. Cargo invokes Rust's bundled
`rust-lld` directly: no C compiler driver is required. The native executable
still uses the system C runtime and startup objects; `SNAIL_NATIVE_LIBC` and
`SNAIL_NATIVE_GCC` select those library directories on Nix. Coreutils supplies
ordinary file copying and hashing for the Scheme tools.
See [command options](options.md).

The Nix shell sets `RUSTC_WRAPPER` to `wasm-native/scripts/rustc-native`. This
small Scheme wrapper also supplies the native linker for Cargo's host build scripts during
Wasm builds. It preserves Cargo's selected compiler, explicit target and linker.
On x86-64 Linux outside the Nix shell, enable it from the checkout with
`export RUSTC_WRAPPER="$PWD/wasm-native/scripts/rustc-native"` before running Cargo directly.
Native build scripts configure their linker themselves.

[`build.scm`](../build.scm) is a small library-composition recipe. From any
working directory, with `repo` set to the checkout's absolute path:

```sh
chibi-scheme -I "$repo/src" -I "$repo/wasm-native/scheme" "$repo/build.scm" \
  "$repo" "$repo/examples/native/answer.sfir" answer \
  "$repo/examples/native/entry.rs" /tmp/sphere-answer
/tmp/sphere-answer
```

The executable prints `42`. The recipe's arguments are
`REPOSITORY SOURCE EXPORT RUST-ENTRY OUTPUT`; it compiles the selected public
export to Wasm, lowers those bytes to an object, and links the supplied Rust
entry point through Cargo.

## Checks

The reader checks use canonical data from the pinned benchmark submodule.
Initialize it before running the aggregate checks:

```sh
git submodule update --init benchmarks/r7rs-benchmarks
make test
make check
cargo test --manifest-path wasm-native/Cargo.toml --offline
cargo fmt --manifest-path wasm-native/Cargo.toml --all -- --check
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
