# SFIR commands

`snail-sfir` is hosted by Chibi. Help works before dependency checks.

```sh
./snail-sfir run [-I DIRECTORY] [--target wasm|native] SOURCE.sfir [ARGUMENT ...]
./snail-sfir compile [-I DIRECTORY] [--target wasm|native] -o OUTPUT SOURCE.sfir
```

Wasm is the default target. `-I` may repeat; search those directories in order,
then the repository's `lib/` directory. Library names map to `.sfir` paths:
`(example math)` loads `example/math.sfir`. Inputs have explicit SFIR syntax;
there is no Scheme or macro-expansion mode.

Arguments after the source in `run` are literal program arguments, including
strings beginning with a dash. The host receives them in its argument vector.
The command's final expression has type `Unit`, `I32`, `I64` or `Never`. `Unit`
returns status zero; integer results in 0–255 become the exit status, and other
integer results become status one. Initialization runs once. Normal completion
and traps drain owned runtime resources.

Compilation writes into a private directory and publishes the completed output
atomically. A failed build retains its intermediates and preserves the previous
output. Running compiles privately, invokes the selected host, and removes the
successful build's temporary files.

## Module and backend tools

`scripts/build-sfir [-I DIRECTORY] [--export NAME] SOURCE OUTPUT.wasm` produces a
module with raw Wasm, WAT and a trace beside the mandatory Binaryen output. Its
optional `--command` flag checks the command result contract; ordinary modules
may expose other concrete signatures for custom hosts.

`scripts/link-sfir-runtime INPUT.wasm OUTPUT.wasm` links scalar Rust externs and
optimizes the complete Wasm reactor. `scripts/run-sfir.mjs` executes that reactor.

`scripts/build-native` takes SFIR by default. `--wasm` consumes an existing Wasm
module and still runs Binaryen before mechanical LLVM lowering. `--rust-provider
MODULE SOURCE.rs` supplies concrete scalar Rust exports compiled by Cargo;
`--entry-rust FILE` supplies a Rust executable crate root as the invocation host.
There is no `--strict` split
or dynamic Scheme foreign-call convention.
