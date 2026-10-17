# Building and linking

The tested target is **64-bit x86-64 Linux**. Other 64-bit targets need explicit
ABI, collector and tail-call validation. 32-bit native targets are rejected.

```sh
scripts/build-native examples/fibonacci.sld build/fibonacci
build/fibonacci

scripts/build-native \
  --rust-provider fixture tests/native-mixed.rs \
  tests/native-mixed.sld build/mixed

scripts/build-native --wasm --entry-rust tests/native-runner.rs \
  build/native-tests/semantics.wasm build/semantics
```

With its default command host, `scripts/build-native` accepts a final result of
`Unit`, `I32` or `I64`. Unit produces status zero;
integers in 0..255 become the process status and other integers produce status
one. `-I DIRECTORY` selects Lofi libraries. See [command options](../../options.md).

The helper also accepts `--llvm` and `--object` inputs, `--export NAME`, and
`--entry-rust FILE`. Object input requires an explicit Rust entry point. A custom
host calls `native_host_init(argc, argv)`, `native_module_init()`, `wasm.main`,
then additional typed exports, and finishes with `native_finish(status)`.
Its Rust `extern "C"` declarations must match those exports exactly. Ordinary foreign interfaces
carry scalars; a native host that retains managed references across guest calls
must explicitly publish roots.

The driver checks tools before compilation and publishes a successful build
atomically. Failed builds retain intermediates without replacing an existing
executable. Configuration, commands, hashes and compiler traces remain beside
the output in its uniquely named build directory. Binaryen is mandatory even
for `--wasm` inputs. Raw Wasm is retained only for diagnostic comparisons.

[`build.scm`](../../../build.scm) shows the ordinary library calls for a selected public
entry. It accepts `REPOSITORY SOURCE EXPORT RUST-ENTRY OUTPUT` and works with
absolute paths from any working directory; its first comment runs the
[`answer.sld`](../../../examples/native/answer.sld) and
[`entry.rs`](../../../examples/native/entry.rs) example, which prints `42`.

`(native)` reads a Wasm file through `wasm-binary->llvm`, with explicit
physical `make-native-import` declarations and build paths. `llvm-bitcode` retains
optimized guest bitcode for the executable link; `llvm-object` emits real ELF
machine code for saved artifacts. `link-native-object` receives the runtime root,
bitcode or machine object, Rust entry, providers and build directory.
These operations do not import compiler syntax,
bindings or inferred IR. The runtime root is the `src/native/` directory,
containing the native runtime crate and its scalar-services dependency.


## Chibi library paths

Use the repository's `bootstrap/` loader view for host Scheme. It exposes
`(native)`, `(native ...)` and `(lofi compiler bootstrap)`, while leaving
Chibi's own `(scheme base)` in control. Do not add `src/` as the host search
root: that would expose the product `(scheme base)` to Chibi.

```sh
repo=/absolute/path/to/checkout
chibi-scheme -I "$repo/bootstrap" "$repo/build.scm" \
  "$repo" "$repo/examples/native/answer.sld" answer \
  "$repo/examples/native/entry.rs" /tmp/answer
/tmp/answer
```

All script arguments above are absolute, so this works outside the repository.
The native library uses only other `(native ...)` libraries and installed
Chibi/SRFI libraries. The product compiler is imported separately by the recipe.

## Optimization and artifacts

The Wasm pipeline links provider Wasm and runs Binaryen on the linked module.
Native builds retain guest bitcode for linker-plugin fat LTO with the Rust
entry, runtime and providers. Saved ELF objects link too, but their guest bodies
are already machine code. Comparisons must retain the common guest Wasm identity
and disclose these provider and linkage differences.

`SNAIL_NATIVE_CPU` may select an LLVM/Rust CPU name, such as `x86-64-v3`.
Unset means the compilers' portable default; an empty value is rejected.
The setting applies to newly generated guest and Rust code, never retroactively
to an imported ELF object. `native` ties the output to the build host. CPU
selection preserves Wasm floating-point and trap semantics.
