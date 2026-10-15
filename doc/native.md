# Native execution

The native backend lowers the existing compiler's optimized program Wasm to
LLVM, then links a native executable with the same Rust runtime implementations.
LLVM has no Scheme frontend, type inference, or Scheme optimization pass.
The installed command remains the Chibi-hosted Wasm compiler; native builds use
`scripts/build-native`.

```text
existing Scheme frontend -> program Wasm -> mandatory Binaryen optimization
  -> Binaryen text -> canonical Wasm types and instruction order
  -> mechanical LLVM lowering -> Clang/LLD + native Rust archive + C providers
```

The Wasm output pipeline merges its Rust/provider Wasm and optimizes again.
Consequently the two final linked outputs have different opportunities for
cross-provider inlining. A pure program can use exactly the same optimized
program Wasm for both executors; a native executable and a fully linked Wasm
module are not identical program images.

## Build and invoke

The supported target is **64-bit x86-64 Linux**. This restoration is exercised
with Clang/LLD 22.1.8, Binaryen 132, Chibi 0.12 and Rust's native toolchain.
`nix-shell` supplies Clang, LLD, Binaryen and the bootstrap tools. Other 64-bit
targets need ABI, tail-call and operating-system validation before enabling them.
32-bit native targets are rejected.

```sh
scripts/build-native examples/fibonacci.scm build/fibonacci
build/fibonacci

scripts/build-native --strict tests/strict/data-tree.scm build/tree
build/tree                         # returns the strict main result, 14

scripts/build-native --strict \
  --c-provider fixture tests/native-mixed.h tests/native-mixed.c \
  tests/native-mixed.scm build/mixed

scripts/build-native --wasm --entry-c tests/native-runner.c \
  build/native-tests/semantics.wasm build/semantics
```

Ordinary Scheme initializes its module, runs `snail_main`, drains pending
resource notices and returns zero. Strict or supplied-Wasm builds require a
zero-argument `main` returning Unit, I32 or I64. Unit returns zero; an integer in
0..255 becomes the process status, and an out-of-range integer returns one.
`--export NAME` retains additional strict exports. `--foreign NAME MODULE`
supplies an ordinary Scheme extension binding; `-I DIRECTORY` selects project
libraries. Arguments after the executable name are available through the shared
Rust `command-line` implementation.

`--entry-c FILE` selects an explicit C invocation host, useful for libraries and
tests. The host calls `native_host_init(argc, argv)`, `native_module_init()`, then
the required `wasm.EXPORT` C adapter, and finally `native_finish(status)`. Strict
module-level forms live in `wasm.main`; call it before other strict exports.
A host retaining a managed reference across another guest call must publish an
explicit native root; ordinary external bindings use scalars or owned ABI handles.

`CHIBI`, `CLANG`, `LLD`, and `CARGO` select build tools. `WASM_AS`, `WASM_OPT`,
`WASM_DIS`, and `WASM_MERGE` select Binaryen executables. Preflight reports missing
tools before compiling. Every production build runs Binaryen, including
`--wasm` inputs. Direct `wasm->llvm` calls and
`link-strict-runtime --diagnostic-prune-only` are test/diagnostic intermediates.
They do not provide a production optimization bypass.

Each build retains a unique adjacent `OUTPUT.native-*` directory with Wasm,
LLVM, the generated entry, a compilation trace, and `build.json`. The JSON keeps
tool paths/versions, exact command arguments, diagnostics and SHA-256 identities
for sources and outputs. Successful publication atomically replaces the output;
failure preserves its previous contents. A program with generated companions is
published through a relative symlink into its complete retained generation.
Native artifact lookup uses the physical executable's `artifacts` directory,
unless `SNAIL_ARTIFACT_ROOT` explicitly supplies a directory. Generator execution
still uses the existing linked-Wasm build machinery.

## Direct C contracts

`define-extern` supplies the exact Wasm module, name and signature. The native
driver maps `snail.library` to actual exported Rust C symbols and resolves the
selected platform aliases to those providers. It reads their signatures from the
same Rust sources Cargo builds. This deliberately closed reader accepts literal
export names and explicit scalar types; unsupported syntax or aliases fail.
Lowering compares the complete provider signature with the Wasm declaration
before emitting a call. Linker symbol resolution alone cannot check a C signature.

`--c-provider MODULE HEADER SOURCE_OR_ARCHIVE` adds one explicit C provider.
Clang reads the header's external, nonvariadic prototypes. A C source is compiled
with that header forcibly included, so contradictory definitions fail. For a
prebuilt archive, its supplied header is the authoritative C contract; the
builder cannot reconstruct C types from machine-code symbols. Headers should
contain only the provider's supported scalar prototypes and required typedefs.

| Scheme/Wasm value | C/Rust carrier |
| --- | --- |
| I32, Bool, Char / i32 | `int32_t` or `uint32_t`; Rust `i32` or `u32` |
| I64 / i64 | `int64_t` or `uint64_t`; Rust `i64` or `u64` |
| F32 / f32 | `float` / `f32` |
| F64 / f64 | `double` / `f64` |
| Unit / no result | `void` / no result |

On this LP64 target, the corresponding `int`, `long`, and `long long` spellings
are accepted. Narrow C `char`, C `_Bool`, variadics, unprototyped declarations,
alternate calling conventions, aggregate arguments and pointer signatures are
rejected. Bool and Unicode Char deliberately use full
32-bit carriers. A scalar i64 is never silently converted to a pointer.

Native pointers, Wasm memory32 offsets, managed references and ABI root handles
are separate representations. The one native diagnostic boundary explicitly
takes a native byte pointer and `size_t`; it does not reuse the memory32 import.
A future Vulkan/foreign-pointer adapter must declare pointer ownership, lifetime,
nullability and any scalar handle encoding explicitly. This restoration installs
direct scalar C linkage; it does not install a Vulkan API or infer pointer types.

## Collection and tail calls

The in-house collector is synchronous, single-threaded, nonmoving Immix with
32-KiB blocks and 128-byte lines. It traces only declared reference fields and
explicit roots. Null, tagged i31 values and aligned object addresses are disjoint.
I64 fields that happen to resemble addresses are never roots. Native fields and
array elements initially use eight-byte slots; Wasm i32 and packed i8/i16 accesses
still truncate and extend at their declared widths. This baseline costs more
storage for narrow scalar fields than compact Wasm layouts; compact native
storage is future work.

Roots include live reference locals/operands, globals, tables, mutable static
literal reference slots and Rust-owned ABI table entries. A collection excludes
stale temporary slots. Nonfinal types carry their concrete type identity and
parent chain; recursive group canonicalization preserves Wasm equivalence and
inherited field layout. A sibling cast traps. The frontend's existing rejection
of cyclic datum-label literals remains; mutable literal graphs can form cycles
at runtime and are traced correctly.

Guest functions use LLVM `tailcc`; C imports and exported adapters keep the C
convention. A tail transfer resolves its target and performs all checks before
unlinking the caller's root frame. Outgoing values remain in native ABI locations;
the callee links reference arguments before any allocation or callback. No
asynchronous collector observes the transfer. Tests force collection immediately
before unlink and after callee entry and execute changing-arity tail calls with a
256-KiB stack and bounded root depth.

The arena reserves 256 MiB of virtual address space by default. Startup does not
prefault the entire arena. `SNAIL_GC_HEAP_BYTES` sets the checked fixed reservation,
rounded down to 32-KiB blocks; at least one block is required.
`SNAIL_GC_MIN_BYTES` sets the minimum allocation budget between collections
(default 8 MiB). Reservation and allocation exhaustion terminate through the
normal cleanup path. `SNAIL_GC_STATS=1` reports collector counters on stderr.
`SNAIL_NATIVE_GC_INTERVAL=1` forces collection before every allocation for testing.
There is no growing arena, moving compaction, multithreaded guest execution, or
reusable native-instance lifecycle yet.

## Failure and resource lifetime

Expected Wasm failures check divisors, overflow, conversion ranges, nulls, bounds
and casts before LLVM operations can produce undefined behavior. Unsupported
optimized instructions and module shapes fail with a Wasm-specific diagnostic;
the backend does not substitute another operation. Linear memory, SIMD, atomics,
exceptions and multivalue results are outside the supported lowering subset.
Function and global exports have C adapters; exporting a table to a C host is
unsupported and rejected. Active element segments validate their complete range,
including empty segments at offsets beyond the table length.

Rust keeps the same owned `Root` ABI used by Wasm and calls the generated C ABI
adapters. Resource borrows end before allocations and callbacks. GC finalizers
only queue scalar resource IDs and never retain the watched wrapper. The outer
invocation drains them when Rust resource borrows have ended. Kind 1 goes to
the shared port cleanup; kind 2 goes to the shared numeric-array cleanup.

Normal return, explicit exit, guest traps, I/O failures and arena exhaustion call
`native_finish`. It disables callbacks, drains owned files and numeric arrays once, then
terminates. Cleanup never reenters Scheme. Expected errors neither longjmp through
Rust nor use panic-abort as their control mechanism. Native failures are terminal;
there is no resumable exception protocol across Rust frames. Tests observe file
destruction and buffered output before process exit, including `/dev/full`
failure and a trap raised by a Scheme callback invoked from Rust.

## Validation

`scripts/test-native` executes shared Wasm/native scalar semantics, conversion
boundaries, traps, subtype identity, cyclic graphs, precise tracing, tail calls,
the real mixed C fixture, current strict variants/strings/rounding, and shared
Rust roots, callbacks and Unicode/I64 file services. It retains commands and
results in `build/native-tests/results.json` and source hashes beside them.
`make test`, `make check`, `cargo test --offline`, `cargo fmt --all -- --check`,
`scripts/test-backend`, `scripts/test-build`, and `scripts/test-strict-io` cover
the existing compiler and actual linked-Wasm behavior as well.
