# WebAssembly backend

The compiler remains hosted by Chibi. Source expands into resolved IR, grouped
by library; `wasm.sld` emits WasmGC text directly. Binaryen assembles, links, and
optimizes it with the Rust runtime compiled to Wasm.

## Build and run

Run ordinary Scheme build scripts with Chibi:

```sh
chibi-scheme -I src build.scm
chibi-scheme -I src examples/rust-interop/build.scm
```

`(snail-scheme compiler)` exports `source-file->wat-file(root, input, output)`.
`(snail-scheme build)` supplies complete build operations:

- `build-runtime(root)` builds/reuses the Rust Wasm runtime and returns its path.
- `link-wasm(wat, runtime, output)` assembles, links, optimizes and publishes Wasm.
- `build-wasm(root, input, output)` combines source emission and linking.
- `run-wasm(root, module, arguments)` runs Node/WASI and returns its exit code.
- `run-command(stage, argv)` runs a subprocess with tracing and raises on failure.

`source-file->wat-file` and `build-wasm` accept two optional arguments, in order:
foreign declarations (an alist of Scheme names to Wasm import modules), then
project library directories. For example:

```scheme
(build-wasm "." "app/main.scm" "build/app.wasm" '() '("app/lib" "shared/lib"))
```

Paths are relative to the calling script's working directory. For nonstandard
libraries, the first existing `name/parts.sld` in those directories wins, followed
by the compiler's `src/`. Its parse/declaration errors are reported without trying
another copy. Transitive imports use the same search order. Missing-library
errors include the import name and all searched paths. `(scheme ...)` imports
always use the checkout's bootstrap runtime libraries and cannot be shadowed by
project directories. Foreign declarations do not package separate Rust crates.

The single root Cargo crate contains all Rust services under `src/`.
`build-runtime` invokes Cargo with a stable manifest and target directory;
Scheme-only changes do not rebuild Rust. To prebuild the identical runtime:

```sh
cargo build --offline --release --target wasm32-wasip1 --target-dir build/wasm-runtime
```

The artifact is `build/wasm-runtime/wasm32-wasip1/release/snail_runtime.wasm`.
Release LTO settings live in the root manifest. Scripts can build it once and
link several Scheme modules against it. Runtime initialization occurs once in
the linked Wasm entry before Scheme executes. Rust pointers address one linear
memory; Scheme values live in WasmGC and cross the AWI as root handles.

`rust-toolchain.toml` requests Rust stable, rustfmt and the WASI target; the Nix
shell includes rustup. First use may download missing components. Pin an exact
Rust version separately when reproducing historical toolchain measurements.
`CARGO`, `WASM_AS`, `WASM_MERGE`, `WASM_OPT`, and `NODE` select executable paths. Chibi hosts
the build module's process/filesystem operations today. The Node runner provides
WASIp1 and finalizer imports; a browser WASI adapter remains future work.
WasmGC, reference types, tail calls, mutable globals, sign extension, and bulk
memory are enabled explicitly rather than enabling every experimental feature.

## Build ownership

Scripts own artifact paths and decide whether failures abort or are caught.
Linking stages use unique temporary directories on the destination filesystem;
failed builds preserve existing output and report the directory retaining their
intermediates. Successful builds remove the directory. Cleanup failure after
publication prints a warning instead of claiming the completed build failed.
Tool arguments are passed literally, without shell quoting or interpolation.
Concurrent builds with distinct output paths have independent intermediates;
concurrent successful publishers to one path replace it atomically, last wins.
Do not mutate runtime sources or build configurations while another script is
linking the returned Cargo artifact. There is no separate runtime cache manager.

## Source to WebAssembly

| Module | Responsibility |
| --- | --- |
| `ir.sld` | Seven resolved expression forms and shared binding identities |
| `library.sld` | Library containers, imports, exports, dependency order |
| `expand.sld` | Located syntax to IR, including `syntax-rules` expansion |
| `wasm.sld` | Binding/capture analysis and direct folded WAT emission |
| `src/runtime/wasmgc.wat` | Value representations, checked primitives, calls |
| `src/runtime/awi.wat` | Root handles and scalar accessors for foreign Wasm code |
| `src/awi.rs` | Rust ownership and checked conversions over AWI |
| `src/lib.rs` | Rust ports, formatting, text search, clocks, process services |
| `build.sld` | Chibi-hosted Cargo, linking, execution and artifact publication |

IR expressions are names, literals, applications, lambdas, blocks, conditionals,
and assignments. A library owns its body and dependencies. Expansion retains
binding identity; shadowing a primitive cannot silently select its fast helper.
There is no second internal IR or compiler-managed operand stack.

The emitter analyzes assignment, captures, and initialization. Immutable,
already-initialized captures travel as values; assigned or early-captured
bindings use shared cells. Recursive cells exist before their initializers run.
Reading an uninitialized binding fails, including when a known callee can be
called directly. Library initialization follows dependency order.

A fixed-arity lambda has a worker taking its environment and individual
arguments, plus a uniform closure adapter taking an argument array. Proven
immutable fixed callees call workers directly, so Fibonacci does not allocate
argument vectors. Unknown calls and `apply` use adapters. Tail positions emit
`return_call` or `return_call_ref`; different argument counts need no trampoline.
`apply` and `call-with-values` invoke Scheme in Wasm, preserving tail calls.

A single return value is an ordinary reference. Zero or multiple values use a
private packet, checked at single-value contexts and propagated at returns.
Nonfinal block expressions discard any value count.

## Representations and ownership

Scheme values are `eqref`. Signed31 integers use `i31ref`; larger exact integers
use an `i64` box and inexact numbers an `f64` box. Pairs, vectors, text, closures,
cells, records, and multiple-value packets use WasmGC structs and arrays.
Equivalent Wasm types are structural: names alone do not distinguish them.
Atoms and text wrappers therefore carry explicit category tags.

The Wasm engine sees references in globals, locals, arrays, tables, and active
frames. It owns collection and relocation. Rust does not scan its own stack for
Scheme roots: owned AWI handles retain references in a Wasm table. Temporary
arguments and results use that same mechanism. The Rust `Root` wrapper releases
its table slot on `Drop`, retains a separate slot on `Clone`, and transfers
ownership on return. See [AWI](rust-interop.md).

WasmGC removes the single 32-bit linear-memory address-space limit from Scheme's
object heap. It does not promise an unlimited heap or arrays; engines still
impose implementation limits. Rust currently targets ordinary wasm32 linear
memory and retains its own address-space limit.

Portable WasmGC does not expose forced collection, collector statistics, or
finalizers. Explicit close releases external resources promptly.
The JS host additionally registers extension objects with `FinalizationRegistry`
and calls the Rust resource-release export when cleanup occurs. This is a
host service, not a WasmGC opcode; it is neither timely nor guaranteed at shutdown.

## Continuations and native execution

`call/cc` and `call-with-current-continuation` are unsupported in this backend.
The accepted direction is single-shot, delimited continuations through Wasm
stack switching, with an independent native Wasm-to-LLVM execution backend.
A consumed continuation cannot be resumed again. Ordinary Rust-to-Scheme
callbacks are supported; allowing suspension or escape across Rust frames
requires a separate ownership and cleanup contract.

Suspending preserves a stack; abandoning a Rust frame must account for its
pending destructors. A future cancellation operation can unwind a suspended
stack when the toolchain supports it. Host finalization could schedule that
cancellation, but does not itself implement unwinding. Current Rust release
builds use `panic = "abort"`; no Rust forced-unwind support is promised.

The Scheme [`native` library](../src/snail-scheme/native.sld) translates the complete
linked Wasm module to an x86-64 Linux executable. Scripts call
`wasm-file->native-file(root, input-wasm, output-executable)` and choose whether
to run it. The converter reads the validated binary directly, independently of
Scheme IR, and emits structured LLVM operands through `llvmlite` for both the
Scheme and Rust portions. A C host supplies
Wasm memory/table mechanics, WASIp1, and BDWGC. Clang/LLD compile and link these
automatically. [Native execution](native.md) explains coverage, proper tail calls,
GC roots, resource finalization, and the remaining unsupported Wasm features.

## Validation and measurements

Run `make test`, `make check`, `cargo test --offline`,
`cargo fmt --all -- --check`, `scripts/test-backend --target both`,
`scripts/test-native`, and `scripts/test-build`.
The integration suites execute real linked Wasm, including closures, mutation,
recursive initialization, rest arguments, values, numeric boundaries, proper
tail calls, errors, and Rust callbacks with retained roots. Unit tests remain in
implementation modules; integration fixtures remain in `tests/`.

The frontend-only [examples/compile.scm](../examples/compile.scm) script has been
compiled to Wasm, then executed to emit Fibonacci WAT, which was linked and run
successfully. It imports `(snail-scheme compiler)` without the Chibi-specific
build module. This checks compiler-source capability; the default host remains
Chibi and running build scripts under Snail is a later milestone.

The [production WasmGC report](../benchmarks/results/2026-10-10-wasmgc-production.json)
measures the full linked CPU benchmark under Node/V8: 0.08627s versus Chez
0.03053s and Chibi 0.48150s. That is 2.83× Chez's time and 5.58× faster than
Chibi. Binaryen inlining threshold 40 plus convergence reduced execution time
from 0.33860s, with representation checks preserved. Eight rotating rounds use
the same source and checksum; compilation and process startup are excluded.
V8 tiering during the timed workload remains included.

The [complete native comparison](../benchmarks/results/2026-10-10-binary-runtime.json)
translates the exact Rust-linked module used by V8. Native takes 0.03850s, Chez
0.03039s, V8 0.08477s, Guile 0.09555s, and Chibi 0.46300s. See
[BENCHMARKS.md](../BENCHMARKS.md) for scope, reproduction, the remaining native
compile-time cost, and the older bounded experiment's distinct measurements.
