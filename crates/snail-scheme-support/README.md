# The Rust runtime

`snail-scheme-support` is the runtime every program is linked with: console
and file I/O, directory and path operations, a monotonic clock, panic
reporting, and, behind Cargo features, what a program's libraries need of
crates.io — `unicode` (ICU4X's case mapping and properties, for
`(snail shell text)`), `rapier` (vehicle and contact physics, for
`(snail shell game chassis)`) and `assembler` (the toolchain's in-process
assembler and linker). `snail-scheme`'s managed values stay in WasmGC; Rust
retains external resources behind scalar handles and never stores guest GC
roots.

Core runtime services are written in Rust, using crates.io's libraries,
and reached from `snail-scheme` through `extern`s: a string crosses as
staged scalars, and text comes back as a reply read a scalar at a time.
Results such as a reply or real-number text are scratch owned by the
runtime instance, with no handle and no part in cleanup, because the
private `snail-scheme` wrappers read them before returning and no user code
runs in between.

Each build links the program with the runtime into one module
(`(snail shell project build)`, "Programs"), choosing the runtime's
features by the libraries the program reaches; stage 0 builds the plain and
assembler runtimes for the command line (`host/chez/snail/stage0/build.sld`).
Node's WASI and the browser host's (`host/browser/load.mjs`) supply the
platform operations.

```sh
cargo test --manifest-path crates/snail-scheme-support/Cargo.toml --all-features
cargo fmt --manifest-path crates/snail-scheme-support/Cargo.toml --all -- --check
```

Host compilation is used for unit tests.
