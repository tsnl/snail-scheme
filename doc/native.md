# Native execution

The standalone [Wasm-to-native package](../wasm-native/README.md) mechanically
lowers Binaryen-optimized Wasm to LLVM, then links the same Rust scalar extern
implementations used by Wasm. The compiler emits Wasm only. Ordinary Scheme
build scripts import the compiler and native package separately; Lofi inference,
specialization and representation choices happen before Wasm emission.

```text
located Lofi -> checked and specialized program -> Wasm -> Binaryen
  -> canonical Wasm types and operations -> LLVM bitcode -> Cargo/rust-lld shared LTO
```

The Wasm pipeline links its provider Wasm and optimizes the linked module too.
Native linking optimizes the guest bitcode together with the Rust entry, runtime
and providers. Comparisons retain the common program Wasm identity and disclose
the final provider/linkage differences between the two routes.

## Build and invoke

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
one. `-I DIRECTORY` selects Lofi libraries. See [command options](options.md).

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
[`answer.sld`](../examples/native/answer.sld) and
[`entry.rs`](../examples/native/entry.rs) example, which prints `42`.

`(wasm-native)` reads a Wasm file through `wasm-binary->llvm`, with explicit
physical `make-native-import` declarations and build paths. `llvm-bitcode` retains
optimized guest bitcode for the executable link; `llvm-object` emits real ELF
machine code for saved artifacts. `link-native-object` receives the runtime root,
bitcode or machine object, Rust entry, providers and build directory.
These operations do not import compiler syntax,
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

| Lofi/Wasm value | Rust carrier at the C ABI |
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

The in-house collector is synchronous, single-threaded Immix with opportunistic
evacuation, 32-KiB blocks and 128-byte lines. It traces only declared reference fields and
explicit roots. Null, tagged i31 values and aligned object addresses are disjoint.
I64 fields that happen to resemble addresses are never roots. Struct fields use
eight-byte slots. Arrays store elements at their declared Wasm width: i8 uses
one byte, i16 two, i32/f32 four, and i64/f64/references eight. The lowering passes
this constant stride to checked allocation, indexing and overlapping copies.
Static arrays use the same payload layout. Reference-array layout and permanent
static reference roots remain unchanged; numeric payloads are never scanned.

The collector and native host live in the shared Rust runtime crate, selected
with native target conditions and statically linked into the executable. Ordinary
native builds retain guest bitcode so linker-plugin fat LTO can optimize guest
calls together with Rust runtime and provider bodies. Saved ELF artifacts remain
machine objects and do not expose guest bodies to later optimization. The
allocator's zeroed-storage, collection, root-publication and allocation-counter
contracts apply to both paths. The earlier
[allocation visibility experiment](../benchmarks/results/2026-10-14-native-allocation-visibility/README.md)
measured a separate C/LTO prototype; its results do not describe this Rust build.
Array construction uses the cleared payload directly when the incoming
initializer's full bit pattern is zero. Nonzero patterns, including floating-point
negative zero and NaN payloads, take the ordinary width-specific fill path.

Roots include live reference locals/operands, globals, tables, mutable static
literal reference slots and Rust-owned ABI table entries. A collection excludes
stale temporary slots. Nonfinal types carry their concrete type identity and
parent chain; recursive group canonicalization preserves Wasm equivalence and
inherited field layout. A sibling cast traps. The frontend's existing rejection
of cyclic datum-label literals remains; mutable literal graphs can form cycles
at runtime and are traced correctly.

Reference locals live directly in writable root slots. Reference temporaries
have private storage: a collecting call publishes its live operands and held
arguments, then reloads relocated values into that storage before subsequent
uses. LLVM promotes the private storage and supplies branch/loop phi nodes.
Derived addresses never survive collection; they are recomputed from repaired
bases. The Rust array constructor also roots its own initializer when the array
contains references. A caller's root does not repair a helper's by-value copy.

The root ABI requires generated modules to define `native_gc_relocatable_roots`.
Objects emitted before this contract must be regenerated from Wasm before
linking with this runtime; otherwise linking fails on that missing symbol.
Existing statically linked executables retain their own runtime and behavior.
Foreign code must publish writable roots and reload them after collecting calls,
or pin rooted objects with `native_gc_pin`/`native_gc_unpin`. Pinning alone does
not keep an object alive. These unsafe pin operations set/clear one bit; callers
must coordinate overlapping leases and unpin only after all raw-pointer uses end.

Each record's immutable field descriptor is resolved once before tracing its
edges. Marking makes no callbacks and neither mutates nor mutably borrows the
owned offset storage, so a growing worklist cannot invalidate it. Each offset
is checked against the object's payload extent before its field is read;
pointer-shaped scalar words remain unscanned.

Small allocations (at most one line including their header) mark their starting
line; reclamation also reserves the following line because an object can straddle
the boundary. Medium and large objects mark their full extent. This conservative
line reservation does not scan pointer-shaped numeric fields. After weak cleanup,
a block with no retained lines
can clear its exact-start map without inspecting dead object headers. Candidate
roots must pass exact-start membership before a header is read, so stale header
bits cannot revive an object. Allocation clears the payload before reusing that
storage. Blocks containing live lines retain the ordinary per-object sweep.

The allocation policy follows [Immix, sections 3.1–3.3](https://www.mmtk.io/assets/pubs/immix-pldi-2008.pdf):

- Recycle holes in address order before consuming empty blocks.
- Preserve useful small holes by sending medium objects to a separate bump
  cursor in empty blocks. Allocations of at least 8 KiB, including their header,
  bypass both cursors and reserve whole blocks.
- Reserve 2.5% of mapped blocks, rounded down, for evacuation. This reserve is
  inside the heap cap; heaps smaller than forty blocks have no reserved block.
- Select fragmented source blocks using hole-count histograms, previously marked
  lines and currently available target space. During tracing,
  copy movable survivors once, leave forwarding headers, and repair every edge.
  If target space runs out, retain the remaining objects in place.

The histogram follows the [original MMTk block sweep](https://github.com/JikesRVM/JikesRVM/blob/f10ba059ebdb801cc66e2cb6552a6f4a3a0f193d/MMTk/src/org/mmtk/policy/immix/Block.java#L139):
count transitions from marked to unmarked lines before reserving the conservative
following line. Estimate copy volume from marked lines,
separately from retained allocation capacity. Otherwise alternating live/dead
lines would look unfragmented after guard lines consume every available hole.
Prior marks predict copy cost; current allocation state bounds target capacity.
New allocations reduce available target space without being presumed live in the
previous mark histogram. Each copy checks actual capacity, so underestimated
survival causes in-place marking rather than overwriting occupied storage.

At the cutoff, follow the [2008 implementation](https://github.com/JikesRVM/JikesRVM/blob/f10ba059ebdb801cc66e2cb6552a6f4a3a0f193d/MMTk/src/org/mmtk/policy/immix/Defrag.java#L171):
include the first histogram bucket that reaches or exceeds estimated target
capacity, then rely on allocation failure to stop copying. Section 3.2.1's prose
instead excludes the crossing bucket. That interpretation can repeatedly skip a
large group of equally fragmented blocks and eventually exhaust the heap; a
regression test exercises partial evacuation of exactly this case.

Allocation occupancy and current collection marks are separate maps. Evacuation
uses only previously free storage and never allocates into selected source blocks.
An unmarked line during tracing is not necessarily free: its objects may simply
be unvisited. Weak resource records follow forwarding pointers without retaining
their wrappers; unreachable wrappers still receive exactly one cleanup.

This implements the paper's full-heap collector, without a generational nursery
or write barriers. Deliberate platform differences are a single mutator/collector,
Rust-owned out-of-heap metadata, exact-start membership and payload-size headers,
and whole-block large-object allocation. Object-header sweeping preserves exact
membership checks. These differ from MMTk's compact embedded metadata and LOS;
we do not claim identical metadata overhead or performance.

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
capacity policy, not a measured optimum. Each region owns its block, line and
exact-start maps. Survivors may move between regions during evacuation; each
individual allocation stays entirely inside one region.
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

Default collection is driven by allocation-space exhaustion, using the mapped
heap's headroom instead of an 8-MiB allocation floor. Explicit collections and
test safepoints remain available. For comparison with older measurements only,
setting `SNAIL_GC_MIN_BYTES` restores the former allocation-budget policy: the
larger of that value and twice the last live payload. This setting is absent by
default. Reservation and allocation exhaustion use the normal cleanup path.
`SNAIL_GC_STATS=1` reports collector counters on stderr.
`heap_bytes` is current total capacity, `initial_heap_bytes` records the initial
mapping, `heap_limit=0` means no explicit cap, and `regions`/`growths` count
successful mappings/additions. `arena_used` sums each region's used-block
high-water mark; these are virtual managed extents, not resident memory.
`last_occupied` reports the retained line/block capacity at the last collection;
`last_live` counts only its live payload bytes.
`evacuating_collections`, `moved_objects`, `moved_bytes` and `recovered_blocks`
show whether movement actually happened; `overflow_allocations` and
`reserve_blocks` expose the allocation policy. `SNAIL_GC_EVACUATION` accepts
`auto` (default), `always` (stress every collection), or `never` (ablation).
`SNAIL_NATIVE_GC_INTERVAL=1` forces collection before every allocation for testing.
There is no multithreaded guest execution. The
[Scheme native adapter](lofi-native-loading.md) provides independent instances
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

Lofi I/O wrappers own scalar Rust resource handles. Alias-visible close detaches
the handle before flushing, and callbacks do not keep a Rust resource borrow
across a guest call. Normal return, traps, I/O failures and arena exhaustion
finish through terminal cleanup. Cleanup does not reenter generated code or
unwind through Rust. Resumable exceptions are not implemented. A failed worker invocation closes
that instance; another instance may run the same linked artifact.

## Validation

`scripts/test-native` executes common Wasm/native scalar semantics, conversions,
traps, subtype identity, cyclic graphs, exact tracing and tail calls. Lofi cases
also exercise mixed Rust scalar signatures at the C ABI, concrete variants/strings/bytevectors and
Unicode/I64 I/O, including `/dev/full`, stale aliases and allocation failure.
Commands and terminal outcomes remain under `build/native-tests`.

The shared checks are `make test`, `make check`,
`cargo test --manifest-path wasm-native/Cargo.toml --offline`,
`cargo fmt --manifest-path wasm-native/Cargo.toml --all -- --check`,
`scripts/test-backend` and `scripts/test-build`.
The public command and linked Wasm must actually execute; compilation alone is
not target validation. See [build requirements](backend.md).
