# WasmGC execution and build tools

Chibi hosts `(lofi compiler bootstrap)`. It emits WasmGC, which Binaryen assembles
and optimizes. Node/V8 runs command-line programs; browser hosts instantiate the
same Wasm target with browser providers. Wasm engines own managed memory and
machine code generation. The LLVM backend and custom native collector are removed.

## Tools

Enter `nix-shell`, then install the Rust target with `rustup target add wasm32-wasip1`.
The shell supplies Chibi, Binaryen, Node, Cargo through rustup, and a C linker for
ordinary Rust host tools. There is no LLVM guest-lowering dependency.

```sh
./lofi run examples/fibonacci.sld
./lofi compile -o build/fibonacci.wasm examples/fibonacci.sld
node scripts/run-lofi.mjs build/fibonacci.wasm
```

`scripts/build-lofi` retains raw Wasm, WAT, optimized Wasm and compiler traces.
`scripts/link-lofi-runtime` compiles `src/runtime/` for `wasm32-wasip1`, merges
scalar services, wires diagnostics/cleanup, and optimizes the linked module.
The reusable Chibi orchestration modules live under `src/lofi/host/`.
See [commands](options.md) and [the compiler reference](compiler.md).

## Resource ownership

The engine traces managed references. Rust scalar services own streams, text
and symbol tokens behind handles; they never hold guest GC roots. Hosts close
owned resources after normal completion or traps. Browser services provide
platform operations through explicit adapters.

Build/test capture can use `tools/host/process-supervisor.rs`. This Linux host
tool owns process groups, adopts orphaned descendants, enforces deadlines,
kills and reaps descendants, and retains terminal evidence. It loads no guest
code and has no scalar invocation protocol.

## Verification

```sh
make test
make check
cargo test --manifest-path src/runtime/Cargo.toml --offline
cargo test --manifest-path tools/host/Cargo.toml --offline
cargo fmt --manifest-path src/runtime/Cargo.toml --all -- --check
cargo fmt --manifest-path tools/host/Cargo.toml --all -- --check
scripts/test-backend
scripts/test-build
```

Backend correctness requires actual raw and optimized Wasm execution. Integration
fixtures retain expected rejections, values, effects, traps and cleanup checks.
CI partitions the complete current backend and integration inventories.

The [57-workload corpus](../benchmarks/README.md) retains all sources and frozen
measurements. New campaigns compare Lofi/Wasm with original/adapted Chez and
Rust/Wasm and Rust/native controls. Historical six-route campaigns retain their
original results, including the retired Lofi/native route; they are not new
measurements of the current compiler.
