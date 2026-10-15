# Native execution

The native backend mechanically lowers Binaryen-optimized Wasm to LLVM, then
links the same Rust scalar extern implementations used by Wasm. SFIR inference,
specialization and representation choices happen before Wasm emission.

```text
located SFIR -> checked and specialized program -> Wasm -> Binaryen
  -> canonical Wasm types and operations -> LLVM -> Clang/LLD + C/Rust providers
```

The Wasm pipeline links its provider Wasm and optimizes the linked module too.
Native linking and Wasm linking offer different cross-provider optimization
opportunities. Comparisons retain the common program Wasm identity and disclose
these final provider/linkage differences.

## Build and invoke

The tested target is **64-bit x86-64 Linux**. Other 64-bit targets need explicit
ABI, collector and tail-call validation. 32-bit native targets are rejected.

```sh
./snail-sfir run --target native examples/fibonacci.sfir
./snail-sfir compile --target native -o build/fibonacci examples/fibonacci.sfir

scripts/build-native \
  --c-provider fixture tests/native-mixed.h tests/native-mixed.c \
  tests/native-mixed.sfir build/mixed

scripts/build-native --wasm --entry-c tests/native-runner.c \
  build/native-tests/semantics.wasm build/semantics
```

A command's final result is `Unit`, `I32` or `I64`. Unit produces status zero;
integers in 0..255 become the process status and other integers produce status
one. `-I DIRECTORY` selects SFIR libraries. See [command options](options.md).

The lower-level helper accepts `--export NAME` and `--entry-c FILE`. A custom
host calls `native_host_init(argc, argv)`, `native_module_init()`, `wasm.main`,
then additional typed exports, and finishes with `native_finish(status)`.
Its C declarations must match those exports exactly. Ordinary foreign interfaces
carry scalars; a native host that retains managed references across guest calls
must explicitly publish roots.

The driver checks tools before compilation and publishes a successful build
atomically. Failed builds retain intermediates without replacing an existing
executable. Configuration, commands, hashes and compiler traces remain beside
the output in its uniquely named build directory. Binaryen is mandatory even
for `--wasm` inputs. Raw Wasm is retained only for diagnostic comparisons.

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

| SFIR/Wasm value | C/Rust carrier |
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
I64 fields that happen to resemble addresses are never roots. Struct fields use
eight-byte slots. Arrays store elements at their declared Wasm width: i8 uses
one byte, i16 two, i32/f32 four, and i64/f64/references eight. The lowering passes
this constant stride to checked allocation, indexing and overlapping copies.
Static arrays use the same payload layout. Reference-array layout and permanent
static reference roots remain unchanged; numeric payloads are never scanned.

Both allocation layers are explicitly inlined during LLVM link-time optimization.
This exposes the collector's zeroing beside each Wasm constructor's field stores,
so LLVM can remove zeros that are immediately overwritten. The public allocator
still returns zeroed storage; default initialization, collection thresholds,
root publication and allocation counters keep their existing contracts. Hole
searches remain out of line. Inlining only the inner allocator leaves the outer
call boundary in place. The
[allocation visibility experiment](../benchmarks/results/2026-10-14-native-allocation-visibility/README.md)
measures the benefit and increased code size on two complete workloads.

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
including headers and unused space, excluding C metadata and roots. Setting
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
There is no moving compaction, multithreaded guest execution, or
reusable native-instance lifecycle yet.

## Failure and resource lifetime

Expected Wasm failures check divisors, overflow, conversion ranges, nulls, bounds
and casts before LLVM operations can produce undefined behavior. Unsupported
optimized instructions or module shapes fail with a Wasm-specific diagnostic.
Linear memory, SIMD, atomics, exceptions and multivalue results remain outside
the native lowering subset. Function and global exports have C adapters;
exporting a table to a C host is rejected. Active element segments validate the
whole range, including empty segments beyond the table end.

SFIR I/O wrappers own scalar Rust resource handles. Alias-visible close detaches
the handle before flushing, and callbacks do not keep a Rust resource borrow
across a guest call. Normal return, traps, I/O failures and arena exhaustion
finish through terminal cleanup. Cleanup does not reenter generated code or
unwind through Rust. Resumable exceptions and reusable native instances are not
implemented.

## Validation

`scripts/test-native` executes common Wasm/native scalar semantics, conversions,
traps, subtype identity, cyclic graphs, exact tracing and tail calls. SFIR cases
also exercise mixed C signatures, concrete variants/strings/bytevectors and
Unicode/I64 I/O, including `/dev/full`, stale aliases and allocation failure.
Commands and terminal outcomes remain under `build/native-tests`.

The shared checks are `make test`, `make check`, `cargo test --offline`,
`cargo fmt --all -- --check`, `scripts/test-backend` and `scripts/test-build`.
The public command and linked Wasm must actually execute; compilation alone is
not target validation. See [build requirements](backend.md).
