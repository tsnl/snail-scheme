# Native backend archive

Snail Scheme now emits WasmGC and runs command programs through Node.js/WASI.
The LLVM emitter, native collectors, native runtime, and their build instructions
remain on [`archive/llvm-backend-20261012`](https://github.com/tsnl/snail-scheme/tree/archive/llvm-backend-20261012).
The measured comparison uses the separately preserved
[`experiment/r7rs-native-v8-20261012`](https://github.com/tsnl/snail-scheme/tree/experiment/r7rs-native-v8-20261012)
harness. See the [measurement report](../benchmarks/results/2026-10-12-native-v8/README.md)
and [current backend instructions](backend.md).
