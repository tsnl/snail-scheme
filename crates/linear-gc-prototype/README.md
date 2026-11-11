# Linear-memory GC prototype

The [book experiment](../../doc/book/runtimes/linear-memory.md) contains the
findings, archived Immix provenance, root contract and migration analysis.
This directory is isolated from the shipping compiler and runtime.

From the repository root:

```sh
tests/linear-gc/run check
tests/linear-gc/run bench
# Linux: keep paired timings on one chosen performance core.
taskset -c 0 tests/linear-gc/run bench
```

Requires the pinned Rust 1.95.0 toolchain, its `rust-src` and `wasm32-wasip1`
components, and Node with memory64 support. Build dependencies must be cached
for the script's offline builds. On first setup, install `rust-src` and fetch
the runner's dependencies. The experimental core build may also need a first
online run:

```sh
rustup component add rust-src --toolchain 1.95.0
cargo fetch --manifest-path crates/linear-gc-prototype/runner/Cargo.toml --locked
RUSTC_BOOTSTRAP=1 cargo build --manifest-path crates/linear-gc-prototype/runtime/Cargo.toml \
  --release --target wasm64-unknown-unknown -Z build-std=core
```

`runtime/src/lib.rs` owns the bounded nonmoving heap. `runner` emits the WAT
fixture and executes Wasmtime; `tests/linear-gc/run.mjs` runs the same artifacts
on V8. Generated WAT/Wasm and full timing JSON go in `build/linear-gc/`.
Committed samples live in `tests/linear-gc/results/`. The memory64 smoke test
reserves slightly over 4 GiB of virtual address space, touching only one high
page. The collector itself has a 4-MiB fixed arena.

Formatting checks:

```sh
cargo fmt --manifest-path crates/linear-gc-prototype/runtime/Cargo.toml -- --check
cargo fmt --manifest-path crates/linear-gc-prototype/runner/Cargo.toml -- --check
```

To repeat the optimizer regression check after building:

```sh
mkdir -p build/linear-gc/optimized
for name in runtime32 runtime64 workload32 workload64; do
  wasm-opt --enable-memory64 --enable-tail-call -O3 "build/linear-gc/$name.wasm" \
    -o "build/linear-gc/optimized/$name.wasm"
done
cp build/linear-gc/high-address.wasm build/linear-gc/optimized/
crates/linear-gc-prototype/runner/target/release/linear-gc-runner check build/linear-gc/optimized
node tests/linear-gc/run.mjs build/linear-gc/optimized
```
