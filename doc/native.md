# Native execution

The standalone [Wasm-to-native package](../wasm-native/README.md) mechanically
lowers Binaryen-optimized Wasm to LLVM, then links the same Rust scalar extern
implementations used by Wasm. The compiler emits Wasm only. Ordinary Scheme
build scripts import the compiler and native package separately; SFIR inference,
specialization and representation choices happen before Wasm emission.

```text
located SFIR -> checked and specialized program -> Wasm -> Binaryen
  -> canonical Wasm types and operations -> LLVM opt/llc -> Cargo/rust-lld + Rust runtime/providers
```

The Wasm pipeline links its provider Wasm and optimizes the linked module too.
Native linking and Wasm linking offer different cross-provider optimization
opportunities. Comparisons retain the common program Wasm identity and disclose
these final provider/linkage differences.

## Build and invoke

The tested target is **64-bit x86-64 Linux**. Other 64-bit targets need explicit
ABI, collector and tail-call validation. 32-bit native targets are rejected.

```sh
scripts/build-native examples/fibonacci.sfir build/fibonacci
build/fibonacci

scripts/build-native \
  --rust-provider fixture tests/native-mixed.rs \
  tests/native-mixed.sfir build/mixed

scripts/build-native --wasm --entry-rust tests/native-runner.rs \
  build/native-tests/semantics.wasm build/semantics
```

With its default command host, `scripts/build-native` accepts a final result of
`Unit`, `I32` or `I64`. Unit produces status zero;
integers in 0..255 become the process status and other integers produce status
one. `-I DIRECTORY` selects SFIR libraries. See [command options](options.md).

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

[`build.scm`](../build.scm) shows the ordinary library calls for a selected public
entry. It accepts `REPOSITORY SOURCE EXPORT RUST-ENTRY OUTPUT` and works with
absolute paths from any working directory; its first comment runs the
[`answer.sfir`](../examples/native/answer.sfir) and
[`entry.rs`](../examples/native/entry.rs) example, which prints `42`.

`(wasm-native)` reads a Wasm file through `wasm-binary->llvm`, with explicit
physical `make-native-import` declarations and build paths. `llvm-object` produces the
object, and `link-native-object` receives the runtime root, object, Rust entry,
providers and build directory. These operations do not import compiler syntax,
bindings or inferred IR. The runtime root is the `wasm-native/` directory,
containing the single Cargo crate used for both Wasm and native execution.

## Direct C contracts

`define-extern` supplies the exact Wasm module, name and signature. The native
driver maps `snail.library` to actual exported Rust C symbols and resolves the
selected platform aliases to those providers. It reads their signatures from the
same Rust sources Cargo builds. This deliberately closed reader accepts literal
export names and explicit scalar types; unsupported syntax or aliases fail.
Lowering compares the complete provider signature with the Wasm declaration
before emitting a call. Linker symbol resolution alone cannot check a C signature.

`--rust-provider MODULE SOURCE.rs` adds a Rust provider crate. The ABI reader
accepts literal `#[unsafe(export_name = "symbol")]` attributes on public
`extern "C"` functions with explicit scalar parameters and results. Comments
and string contents do not declare exports. Type aliases, macro-generated
exports, pointers, variadics and aggregates are outside this closed interface.
Cargo compiles the same source as an ordinary dependency, with one shared Rust
runtime and standard library. There are no C headers or C compilation steps.

| SFIR/Wasm value | Rust carrier at the C ABI |
| --- | --- |
| I32, Bool, Char / i32 | `i32` or `u32` |
| I64 / i64 | `i64` or `u64` |
| F32 / f32 | `f32` |
| F64 / f64 | `f64` |
| Unit / no result | No result |

Bool and Unicode Char use full 32-bit carriers. A scalar i64 is never silently
converted to a pointer. The source declaration is a trusted foreign contract;
ABI checks do not establish the safety of arbitrary native code.

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
I64 fields that happen to resemble addresses are never roots. Struct fields use
eight-byte slots. Arrays store elements at their declared Wasm width: i8 uses
one byte, i16 two, i32/f32 four, and i64/f64/references eight. The lowering passes
this constant stride to checked allocation, indexing and overlapping copies.
Static arrays use the same payload layout. Reference-array layout and permanent
static reference roots remain unchanged; numeric payloads are never scanned.

The collector and native host live in the shared Rust runtime crate, selected
with native target conditions. LLVM emits the guest object before Cargo links
it with that crate. Consequently Rust LTO can inline within the runtime, but it
cannot eliminate allocator zeroing using later guest field stores. The earlier
[allocation visibility experiment](../benchmarks/results/2026-10-14-native-allocation-visibility/README.md)
measured a C/LTO build; its result does not describe this Rust link boundary.
The allocator continues to return zeroed storage, with the same collection,
root-publication and allocation-counter contracts. Array construction uses this
cleared payload directly when the incoming initializer's full bit pattern is
zero. Nonzero patterns, including floating-point negative zero and NaN payloads,
take the ordinary width-specific fill path.

Roots include live reference locals/operands, globals, tables, mutable static
literal reference slots and Rust-owned ABI table entries. A collection excludes
stale temporary slots. Nonfinal types carry their concrete type identity and
parent chain; recursive group canonicalization preserves Wasm equivalence and
inherited field layout. A sibling cast traps. The frontend's existing rejection
of cyclic datum-label literals remains; mutable literal graphs can form cycles
at runtime and are traced correctly.

Tracing marks every line occupied by a live allocation, including large-object
continuation and tail blocks. After weak cleanup, a block with no marked lines
can clear its exact-start map without inspecting dead object headers. Candidate
roots must pass exact-start membership before a header is read, so stale header
bits cannot revive an object. Allocation clears the payload before reusing that
storage. Blocks containing live lines retain the ordinary per-object sweep.

Guest functions use LLVM `tailcc`; C imports and exported adapters keep the C
convention. A tail transfer resolves its target and performs all checks before
unlinking the caller's root frame. Outgoing values remain in native ABI locations;
the callee links reference arguments before any allocation or callback. No
asynchronous collector observes the transfer. Tests force collection immediately
before unlink and after callee entry and execute changing-arity tail calls with a
256-KiB stack and bounded root depth.

The heap initially reserves 256 MiB of virtual address space. An allocation
that cannot fit collects, then normally reuses reclaimed space. If more than
75% of capacity remains occupied, it first tries to add a region, normally
doubling total capacity, to avoid repeated tracing for tiny reclaimed holes.
Occupancy counts retained 128-byte lines and entire large-object block
reservations, including headers and unusable tails. At or below 75%, at least
one quarter of total allocation space is reusable, though fragmentation can
still prevent a particular contiguous fit. Such a miss also requests growth.
A larger object can request a larger region. This headroom rule is a simple
capacity policy, not a measured optimum; it does not grow after every budget
collection. Each region owns its block, line and exact-start maps; live objects
keep their addresses, and a contiguous object stays entirely inside one region.
Growth publishes a region only after its mapping and metadata both succeed.
If the preferred addition fails, the collector tries the minimum complete
block-rounded extent. Failed growth still permits allocation in any fitting
reclaimed hole, including when the explicit cap prevents growth. Mappings are
retained for reuse, and startup does not prefault their pages.

`SNAIL_GC_HEAP_BYTES` remains an explicit hard cap on total managed mapped bytes,
including headers and unused space, excluding Rust metadata and roots. Setting
only this variable preserves the earlier fixed initial reservation.
`SNAIL_GC_INITIAL_BYTES` optionally selects a smaller initial reservation for
tuning or growth tests. With no explicit cap, it replaces the 256 MiB initial
size and growth continues subject to checked size limits and OS availability.
Both settings round down to 32-KiB blocks, require at least one block, and reject
sizes above `SIZE_MAX / 4` or an initial size above the cap. Requests instead
round up to include their header and alignment. The last addition can consume
a smaller cap remainder; the cap is never rounded upward. Free space across
separate regions cannot satisfy one contiguous object, even when adjacent in
the virtual address space.

`SNAIL_GC_MIN_BYTES` sets the minimum allocation budget between collections
(default 8 MiB). After collection the budget is the larger of that minimum and
twice the live payload bytes; a capacity miss can collect sooner. Reservation
and allocation exhaustion terminate through the normal cleanup path.
`SNAIL_GC_STATS=1` reports collector counters on stderr.
`heap_bytes` is current total capacity, `initial_heap_bytes` records the initial
mapping, `heap_limit=0` means no explicit cap, and `regions`/`growths` count
successful mappings/additions. `arena_used` sums each region's used-block
high-water mark; these are virtual managed extents, not resident memory.
`last_occupied` reports the retained line/block capacity at the last collection;
`last_live` counts only its live payload bytes.
`SNAIL_NATIVE_GC_INTERVAL=1` forces collection before every allocation for testing.
There is no moving compaction or multithreaded guest execution. The
[Scheme native adapter](sfir-native-loading.md) provides independent instances
through isolated Rust workers.

## Failure and resource lifetime

Expected Wasm failures check divisors, signed division overflow, conversion
ranges, nulls, bounds and casts before LLVM operations can produce undefined
behavior. Unsupported optimized instructions or module shapes fail with a
Wasm-specific diagnostic.
Linear memory, SIMD, atomics, exceptions and multivalue results remain outside
the native lowering subset. Function and global exports have C adapters;
exporting a table to a C host is rejected. Active element segments validate the
whole range, including empty segments beyond the table end.

SFIR I/O wrappers own scalar Rust resource handles. Alias-visible close detaches
the handle before flushing, and callbacks do not keep a Rust resource borrow
across a guest call. Normal return, traps, I/O failures and arena exhaustion
finish through terminal cleanup. Cleanup does not reenter generated code or
unwind through Rust. Resumable exceptions are not implemented. A failed worker invocation closes
that instance; another instance may run the same linked artifact.

## Validation

`scripts/test-native` executes common Wasm/native scalar semantics, conversions,
traps, subtype identity, cyclic graphs, exact tracing and tail calls. SFIR cases
also exercise mixed Rust scalar signatures at the C ABI, concrete variants/strings/bytevectors and
Unicode/I64 I/O, including `/dev/full`, stale aliases and allocation failure.
Commands and terminal outcomes remain under `build/native-tests`.

The shared checks are `make test`, `make check`,
`cargo test --manifest-path wasm-native/Cargo.toml --offline`,
`cargo fmt --manifest-path wasm-native/Cargo.toml --all -- --check`,
`scripts/test-backend` and `scripts/test-build`.
The public command and linked Wasm must actually execute; compilation alone is
not target validation. See [build requirements](backend.md).
