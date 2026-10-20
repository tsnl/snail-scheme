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


## Build profiles

Public `lofi compile` / `lofi run` commands and the Siegework build recipe default
to debug Wasm optimization. `--release` selects O3, inlining and convergence.
Debug retains O1 cleanup so unreachable initializers and foreign imports can be
removed. The selected profile applies to generated dependencies and the final
runtime link. Low-level `scripts/build-lofi`, `scripts/link-lofi-runtime` and
library APIs retain release defaults; both scripts accept `--debug` and
`--release`. Diagnostic prune-only linking retains its separate behavior.

The 57-workload runner and Siegework measurement driver explicitly request
release builds. Their optimization level is independent of development defaults.

A historical [Fibonacci CLI build-and-run pair](measurements/debug-profile-reuse-2026-10-18.json)
took 5.68 seconds in debug and 155.94 seconds in release, both printing `832040`.
The runtime was prebuilt; caches and host load were uncontrolled. This is not a
full Siegework measurement or a runtime speed comparison.
