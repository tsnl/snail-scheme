# Linear-memory runtime and collector experiments

The compiler lowers its managed values into wasm32 linear memory. The runtime
uses a nonmoving conservative collector. This chapter describes that contract
and the separate experiments started on 2026-11-11. The microbenchmarks below
measure root publication; they are not whole-program performance estimates.

The initial direction is a nonmoving collector, with managed objects and
explicit root frames in one linear memory. Keep arithmetic in Wasm locals;
publish live pointers before calls that can collect. A shadow root stack does
not require every scalar to live in memory. Interior pointers and contiguous
arrays of records then follow from byte offsets and strides. They do not
require memory64.

## The compiler and runtime

`wasm.sld` still selects logical structs, arrays, closures and evidence records
from `Prepared`. `wat.sld` supplies its folded instruction vocabulary and text
writer. `memory.sld` then replaces managed instructions with checked offsets,
loads, stores, allocator calls and a shared function table. Fixed helper
templates go through this pass too. Each finished physical function is rendered
before lowering the next, so the compiler need not retain its entire expanded
instruction tree alongside the output text.

The frontend, ownership checks, allocation decisions and supported source types
are unchanged. Structs, captured environments, saved continuations and arrays
that previously allocated still allocate on the heap. Scalars remain Wasm
locals. Wasm keeps the ordinary control stack; the explicit stack holds roots.
Escape analysis, user-visible interior pointers, additional array element
layouts and an LLVM backend are future work in
[#749](https://github.com/tsnl/snail-scheme/issues/749).

Every managed object starts with two 32-bit words: a runtime layout identity
and an array length. Payload fields have their natural alignment, at most eight
bytes. Null is zero. Code references are managed descriptors containing a
function-table index and the module that owns its globals. Source array bounds,
null checks and dynamic casts remain checked. The 4-GiB limit covers all linear
memory, including Rust services, metadata, roots and the heap.

`crates/snail-core-support/src/gc.rs` owns the heap and its metadata. Small
objects occupy power-of-two slots, 16 bytes through 32 KiB, in 32-KiB blocks;
larger objects have separate extents. Conservative marking checks membership
and requested byte extent before reading a candidate. Padding and one-past
addresses do not retain an object. Metadata is outside the scanned payload.
Allocation collects according to the live-byte budget and retries after
collection when memory is exhausted. No object moves. Fixed slots allow reuse
between surviving objects without the line fragmentation encountered in the
initial nonmoving Immix port; the historical moving collector and the bounded
mark/line experiment below remain distinct implementations.

Each function reserves an initialized root frame without collecting, then
publishes its pointer parameters. Pointer locals remain rooted until return.
Pending operands have separate slots, cleared after their consuming operation
finishes. Returns and tail calls pop the caller only after evaluating their
arguments; no collection occurs before the callee publishes those arguments.
A host invocation saves and restores frame depth, including when a trap skips
generated epilogues. A frame also roots its module while old code is executing.

Module globals occupy registered cells. Active modules retain their owner
object; old closures retain their code, globals and imported modules through
that owner after reload. Dead code descriptors release their table entries
before indices are reused. Logical recursion groups and import/export
signatures are interned using complete keys, so erasing references to `i32`
does not erase layout checks at a source-library link boundary.

On Node and in the browser, `hostExports` is the host-facing view of an
instance's exports. Managed results become opaque handles with registered roots;
a weak identity cache preserves object identity, and finalization releases
roots without deciding language resource cleanup. Nullable handovers still use
`null`. Host calls check runtime ownership and logical types. Foreign callbacks
use the corresponding descriptor to carry managed arguments and results through
the same view, including synchronous re-entry. Raw imports between compiled
modules pass addresses directly. The native loader uses explicit code handles;
the compiler engine recreates a forwarded code descriptor in its receiving
runtime instead of passing an address from a different heap.

`SNAIL_GC_STRESS=1` collects at every allocation after program initialization.
The root regression covers incoming parameters, earlier operands, rotating loop
values, closure captures and array initialization. Host-boundary tests also
collect between calls and catch a nested trap before continuing.

## First migration measurements

The initial implementation gives every function a root frame, including leaf
functions and scalar tail loops. It reads pointer locals from those frames.
These are the baseline for optimization, not a prediction of unavoidable
shadow-stack overhead. The workloads below are ordinary Snail-Core source with
identical allocation decisions, compiled by the frozen WasmGC compiler at
`6ecf6291` and the linear-memory backend. They cover computation, lists, arrays,
capturing closures and one-shot resumable effects; they are small synthetic
programs, not application-wide speed estimates.

Milliseconds per complete Wasm batch, then linear/WasmGC ratio:

| Workload | V8 WasmGC | V8 linear | Ratio | Wasmtime WasmGC | Wasmtime linear | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Scalar arithmetic | 0.567 | 7.436 | 13.11× | 0.984 | 7.898 | 8.02× |
| Tiny rooted calls | 0.112 | 5.518 | 49.14× | 0.556 | 9.787 | 17.62× |
| Lists | 0.266 | 2.879 | 10.82× | 3.727 | 4.614 | 1.24× |
| Arrays | 0.454 | 6.971 | 15.34× | 2.587 | 12.030 | 4.65× |
| Capturing closures | 0.059 | 0.668 | 11.33× | 1.380 | 1.129 | 0.82× |
| Resumable effects | 0.053 | 0.722 | 13.60× | 2.254 | 1.360 | 0.60× |

Each process warms each entry 32 times, then records nine samples of 32 calls.
The table takes the median of 27 samples across three fresh processes, with
variant order alternated. Every checksum agrees. The machine is the Intel Core
Ultra 7 270K Plus below, pinned to P-core 0. Node 26.8.1 / V8 14.6 uses
`--no-liftoff --no-wasm-lazy-compilation`; Wasmtime 48.0.7 uses Cranelift Speed
and DRC for WasmGC. Compilation and initialization are outside execution times.
GC timing is disabled for these samples; allocation and collection remain in
execution. Separate nine-call diagnostic batches record allocation counts,
requested bytes, collection time and longest observed pause.

The linked module grows from 194,631 to 312,349 bytes. Median eager compilation
on the pinned core is 134 to 226 ms in V8 and 84 to 129 ms in Wasmtime. Peak
process RSS is 124,708 to 97,956 KiB in Node and 23,788 to 28,428 KiB in Wasmtime;
RSS includes the engine and generated code. The JSON also records linear-memory
size, which excludes the WasmGC heap and must not be used to compare total heaps.
Other development work was running on other cores during this initial sample.

Reproduce using `tests/linear-gc/programs/runtime.sld`, compiled with each
checkout's own compiler and Rust runtime, then:

```sh
tests/linear-gc/programs/measure /path/to/wasmgc.wasm /path/to/linear.wasm /tmp/results
node tests/linear-gc/programs/report.mjs /tmp/results
```

Raw samples and artifact hashes are in
`tests/linear-gc/results/2026-11-11-mvp/`. The earlier publication-only experiment
below used hand-written code and a much cheaper frame protocol. Its percentages
do not bound the naive production implementation. The next stage measures
which runtime costs can be removed while keeping collection correct.

## The existing Immix implementation

The mature implementation is recoverable at
[`fc8bf59ad2bc6f18d8c99547c56689f14d70aa95`](https://github.com/tsnl/snail-scheme/tree/fc8bf59ad2bc6f18d8c99547c56689f14d70aa95/src/native),
the last revision before [PR #341](https://github.com/tsnl/snail-scheme/pull/341)
removed the LLVM backend. Its 2,075-line `src/native/native_gc.rs` includes
tests. [PR #301](https://github.com/tsnl/snail-scheme/pull/301) introduced the
later evacuation and tracing work. Recover the source without switching branches:

```sh
git show fc8bf59a:src/native/native_gc.rs
git show fc8bf59a:doc/book/native/collector.md
git show fc8bf59a:doc/book/native/roots.md
```

It has 32-KiB blocks, 128-byte lines, bump allocation through recyclable holes,
a separate medium-object cursor, whole-block large objects, growth, evacuation,
weak cleanup and relocatable roots. Its LLVM backend already distinguishes
collecting calls, publishes reference arguments and operands, handles tail
transfers and reloads relocated references. Those contracts are valuable.

It is **precise**, not a conservative interior-pointer collector. `candidate`
accepts exact payload starts; `trace_object` follows declared reference fields.
`map_region` uses `mmap`; metadata uses Rust allocations outside the managed
arena. Restoring it unchanged would not provide the requested Wasm heap.

A production port can reuse the allocation policies, bounded-arithmetic checks,
weak cleanup design and tests. Replace mappings with linear-memory regions,
keep collector metadata in separately owned unscanned storage, add an
interior-address lookup, and initially disable evacuation. An ambiguous word
cannot safely be rewritten: it might be an integer. Later, exact heap layouts
could coexist with ambiguous roots and pin only ambiguously referenced objects;
that is the approach explored by
[Fast Conservative Garbage Collection](https://www.cs.utexas.edu/~mckinley/papers/conservative-gc-oopsla-2014.pdf).
Its Java measurements are not a performance prediction for Snail.

## What the prototype implements

`crates/linear-gc-prototype/runtime/src/lib.rs` is a small `no_std` Rust module,
compiled unchanged in its algorithm to Wasm32 and Wasm64. It is informed by the
archived Immix geometry and hole allocation; it is not a restored or benchmarked
version of the mature collector.

- A fixed 4-MiB arena, 32-KiB blocks, 128-byte lines, 16-byte allocation alignment.
- A bump cursor through free line runs. Collections retain every line touched
  by live objects; dead allocations lose membership even on retained lines.
- An owner map from each allocation granule to its payload start. The requested
  byte extent excludes padding and one-past addresses before tracing.
- Conservative scanning of active root words and aligned pointer-width payload
  words, with a bounded mark worklist. All metadata also lives in linear memory,
  outside the scanned managed arena. There are no host callbacks during GC.
- No movement, finalization, nursery, write barrier, concurrent mutation, growth
  or allocations larger than one block. Exhaustion traps deterministically.

An interior *value* may address any byte. A stored pointer must occupy a complete
aligned pointer-width slot. Packed or encoded/tagged pointers would need a
different tracing contract. An end pointer alone does not retain its object.
Pointer-shaped integers may retain garbage; a regression demonstrates this.
These are representation constraints, not facts conservatism can discover.

The deliberately direct owner/size/mark/work arrays cost about 3.3 MiB for the
4-MiB arena, plus roots and the Rust stack. Sweeping visits every possible start
slot. This makes the experiment easy to inspect but unsuitable as evidence of
production memory efficiency or Immix pause times.

## Roots: the important compiler contract

Wasm locals and the operand stack are invisible to a collector implemented in
Wasm. Moving the heap to memory does not make those values scannable. At every
collecting call, every object needed afterward must be reachable through an
active root or a retained object. A conservative scanner cannot compensate for
an absent root.

```text
evaluate arguments, rooting earlier results across later collecting evaluations
publish live pointers, including parameters and interior addresses
publish the initialized frame's extent
call an operation that may collect
restore the previous root extent
```

Slots beyond the active extent are not scanned. A popped frame need not be
zeroed; slots must be initialized before being republished. Reserve bounded
root space without collecting. A nonmoving collector does not need relocation
reloads. Tail calls unlink the caller only after evaluation and checks, then
the callee roots incoming pointers before any collection. No asynchronous
collector may observe the handoff.

Allocation is a physical backend property: a source-pure function can allocate.
Do not equate an empty source effect row with “cannot collect.” Unknown and
foreign calls must conservatively count as collecting unless their ABI proves
otherwise. Root emission must cover parameters, pending operands, closures,
evidence records, branch results and loop-carried values after lowering.

[TinyGo #5742](https://github.com/tinygo-org/tinygo/issues/5742) reported live
objects reclaimed on Wasm under both precise and conservative collectors. It
identified missing parameter spills in two compiler paths, but explicitly did
not establish those omissions as the reproducer's cause. The merged fix,
[PR #5751](https://github.com/tinygo-org/tinygo/pull/5751), addressed LLVM merging
root-tracking calls through a loop phi: the next iteration overwrote the only
slot while an earlier incoming pointer remained live. Its repair runs after
LLVM optimization. Test both parameter handoff and independently live loop
values; do not assume one slot for a merged value roots every live input.

The fixtures force real collection with a pointer held only by a callee's
parameter, with a caller temporary, across nested calls and tail transfers,
and through a loop. Deliberately broken parameter and loop variants must
demonstrate lost allocation membership; the parameter variant additionally
forces reuse and overwrite. Other checks cover an interior root into an inline
record array, interior heap edges, cycles, popped roots, extent boundaries,
false retention, invalid root bounds and allocation sizes, exhaustion, and
automatic collection. Wasm64 also rejects a false candidate whose low 32 bits
match a real allocation.

## Measuring shadow roots

`tests/linear-gc/run bench` builds the collector and generates inspectable WAT
workloads. The same artifacts run on Wasmtime and V8. They link directly through
Wasm imports and shared memory; the host times a whole loop, never individual
calls inside it.

Three arms perform identical pointer loads, calls, arithmetic and checksums:

| Arm | Data placement at the collecting call |
| --- | --- |
| `locals` | Wasm locals; no per-call root frame |
| `shadow` | Pointer-width root stores and frame publication; computation stays in locals |
| `stack` | The same roots, plus pointer reloads and a memory-backed scalar accumulator |

The accumulator in `stack` is loaded/stored in its arithmetic loop. Loop control
and machine temporaries still use Wasm locals; this is a data-frame experiment,
not a fully transformed control stack. No `volatile` operations force the
engines to preserve redundant accesses. An engine may optimize this frame.

All arms call the same runtime-module safepoint, whose collection switch lives
in runtime memory. Timed call kernels disable collection to isolate publication
from GC. A harness frame retains the allocated input objects identically in all
arms; it also lets correctness runs enable collection on every call. That frame
is established once, outside the inner loop. It would not be a substitute for
correct callee roots in a real program. Each argument alternates between the
base and an interior address on successive calls, preventing a benchmark of
only invariant pointer publication.

Each case calibrates the baseline to at least 20 ms, warms each arm five times,
then takes 15 paired rounds while rotating arm order. The results preserve every
sample and check equal checksums. Percentages are medians of paired ratios,
not ratios of unrelated best runs. Allocation churn and collection pauses are
reported separately. There is no WasmGC comparison or end-to-end compiler test.

### Local measurements

Intel Core Ultra 7 270K Plus, Linux 7.3.0 x86-64, pinned to performance core 0.
Rust 1.95.0 release builds; Wasmtime 48.0.7 with Cranelift `Speed`; Node 26.8.1
with V8 14.6.202.34 and `--no-liftoff` to compile directly to its optimizing
tier. Engines ran sequentially. Frequency was not fixed. These are warm-cache
microbenchmarks on one machine.

The table gives overhead against `locals`. Each range spans the medians from
**two separate process runs**, not a confidence interval. “Work” is the number
of multiply/add rounds per call. All pointer arguments change each call.

| Engine / address bits | Shadow: 1 pointer, work 1 | Shadow: 4 pointers, work 1 | Shadow: 16 pointers, work 1 | Shadow: 16 pointers, work 64 | Data frame: 16 pointers, work 64 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Wasmtime / 32 | 9.9% | 14.1% | 14.5–16.2% | 1.9–2.4% | 98.0–99.4% |
| Wasmtime / 64 | 16.7–27.5% | 13.6% | 12.7–13.1% | 1.2–2.0% | 3.9–4.9% |
| V8 / 32 | 10.3–31.7% | 4.0–14.6% | 26.4–29.8% | 0.7% | 120.0–120.1% |
| V8 / 64 | 14.7–26.6% | 25.8–44.3% | 23.4–23.8% | 0.2–0.3% | 118.8–119.4% |

Publishing 16 pointers adds **1.3–1.9 ns per call** across these measurements.
The tiny baseline calls take roughly 5–12 ns. One- and four-pointer results
are less stable between processes; their added absolute costs are below 1 ns.
Do not treat a single percentage from these tiny cases as a fixed tax.
The memory-backed accumulator costs about 2–2.2 times the baseline in three
engine/width combinations; Wasmtime's memory64 case behaves quite differently.
Memory64 is neither a uniform slowdown nor a uniform improvement here.

Separately, one million 32-byte allocations with one retained object trigger
seven collections in every engine/width combination. The first run takes
about 7.1–7.7 ns per allocation, including those collections. Collection of
one live object takes about 70–100 microseconds; a chain of 10,000 live
32-byte objects takes about 136–169 microseconds. The fixed metadata scan
dominates the sparse-heap case. These are this prototype's figures, not the
archived Immix collector's or a production throughput promise.

The four `2026-11-11-*.json` files under `tests/linear-gc/results/` retain raw
samples, checksums having been checked during the run. V8's records include
the SHA-256 hashes of the four Wasm artifacts shared by both runners. Both
widths pass 13 common heap/root regressions; memory64 adds the high-bit
candidate check. All nine generated call kernels also pass with collection
enabled at every call. The same correctness suite passes after Binaryen 132
`-O3 --enable-memory64 --enable-tail-call` optimization, on both engines.

These measurements support keeping arithmetic in Wasm locals and publishing
roots only where collection is possible. They do not show that custom GC is
faster than WasmGC overall. Liveness, call frequency, cache pressure, root-frame
depth, retained garbage and layout changes still need application measurements.

## Wasm64

Memory64 changes memory addresses to `i64`; it does not expose the Wasm control
stack or remove the root obligation. The
[WebAssembly feature matrix](https://github.com/WebAssembly/website/blob/main/features.json)
records default support in Chrome 133, Firefox 134 and Node 24. Safari is listed
at Technology Preview 251 rather than stable support. Check the deployment
engines before selecting it as the only target.

Both the actual Rust collector and its root regressions execute here as
memory64 on Node 26.8.1 and Wasmtime 48.0.7. The harness explicitly enables
Wasmtime's memory64 option. A separate smoke module grows a memory and
loads/stores at **4 GiB + 16**; it does not claim that the collector's fixed
4-MiB arena spans that boundary or that the engine supports all 64-bit addresses.
Engine and host address-space limits still apply.

[Rust's target documentation](https://doc.rust-lang.org/rustc/platform-support/wasm64-unknown-unknown.html)
classifies `wasm64-unknown-unknown` as Tier 3, without distributed standard
library artifacts. The prototype uses pinned Rust 1.95.0, `rust-src`,
`RUSTC_BOOTSTRAP=1` and `-Z build-std=core`; its panic trap also requires the
experimental `simd_wasm64` intrinsic feature. This is a research build, not a
supported stable Wasm64 distribution pipeline. Some engine-support prose in
the Rust page is older than the feature matrix and the successful executions.

Wider pointers increase object and root footprints; pointer-heavy layouts need
a separate comparison. Keep address width a target-layout parameter. Function
table indices can remain `i32` when data addresses become `i64`. At JavaScript
boundaries use BigInt for `i64`, and range-check before converting an offset to
a Number or typed-array index. Reacquire memory views after growth.

The existing Rust support crate builds for `wasm32-wasip1`, and native/browser
adapters contain 32-bit ABI assumptions. A memory64 collector does not prove
that the current WASI bindings, linker, allocator, loader or host packet formats
are memory64-ready. A 32-bit I/O scratch-memory bridge or updated host ABI would
be a separate design; neither is implemented here.

## Scope of later optimization

The migration preserves allocation sites so comparisons with WasmGC can use the
same source and object shapes. Escape analysis and stack allocation remain
separate optimizations. Precise heap descriptors can reduce scanning and false
retention; liveness can reduce root publication and stale roots. A nonmoving
heap permits pointer values to remain cached in Wasm locals across collection,
although mutable field loads still need ordinary alias reasoning.

The microbenchmarks above isolate publication and deliberately forced scalar
spills. Compiler and application measurements must also include the allocator,
collector, code size and host boundaries. An ablation that omits roots or
collection is only an experimental ceiling for bounded workloads; it cannot
establish a safe implementation's performance. The migration and optimization
reports are tracked in [#749](https://github.com/tsnl/snail-scheme/issues/749).

Ordinary Wasm call frames remain engine-owned. Moving the entire control stack
into memory would require another transformation or an interpreter/trampoline;
it is not required to trace the managed heap. Memory64 remains an experiment:
the production compiler, Rust services, linker and host ABI currently use
32-bit addresses.
