# String storage controls on V8 and native Immix

| Variant | Median seconds | Range |
| --- | ---: | ---: |
| Strict WasmGC, original i32 storage | 4.806832 | 4.761675–4.832280 |
| Same i32 Wasm, reassembled | 4.805126 | 4.772489–4.829739 |
| WasmGC packed i8, ASCII-only experiment | 1.240474 | 1.233363–1.250536 |
| Original idiomatic Rust/Wasm String | 0.057449 | 0.057107–0.057748 |
| Rust/Wasm byte elements, four fresh buffers | 0.043317 | 0.042758–0.043689 |
| Rust/Wasm u32 elements, four fresh buffers | 0.308486 | 0.306157–0.311800 |
| Rust/Wasm byte elements, four zeroed buffers | 0.086343 | 0.083403–0.088610 |
| Rust/Wasm u32 elements, four zeroed buffers | 0.466349 | 0.462451–0.472630 |
| Archived LLVM/Immix, eight-byte elements | 2.305033 | 2.297347–2.321656 |

Nine retained fresh-process runs per variant follow one discarded round:
90 checked executions. Cyclic rotation places each variant once in every ordinal
position. All workloads retain the original 100 invocations, ten trials each,
threshold 500,000 and final length 524,278. All result checks pass; all 170 frozen
source/artifact/tool identities remain unchanged. Processes run on CPU 5, with
default Node 24.19/V8 tiering and no NODE_OPTIONS. All agent-controlled CPU work
was held; unrelated machine activity remains possible.

The original and reassembled GC i32 cases agree closely. Changing only GC element
width gives a 3.88× speedup for this fixed ASCII input. Even the Rust u32 control
with four freshly allocated, zeroed buffers is 10.31× faster than the original
GC i32 case. Width and zeroing therefore do not explain the entire gap. That
cross-implementation comparison still includes different allocation/reclamation,
copy implementations and representation overhead; it does not isolate GC alone.

## Exact storage experiments

The GC width experiment changes one `(array (mut i32))` declaration to packed
i8 and its two reads to unsigned packed reads in the already optimized WAT.
All control flow, allocation sites, logical lengths, copies and predicates are
unchanged. Reversing those three substitutions recovers the exact original WAT.
The reassembled i32 module has byte-identical non-custom sections to the original;
its name section is omitted. Binaryen 132 assembly explicitly disables compact
imports, which this Node version rejects. The first rejected compact-import
attempt remains archived separately. This i8 experiment is valid for the fixed
ASCII alphabet only and is not a general Unicode implementation.

Sixteen separate complete-payload probes check both widths at eight thresholds,
including 500,000, after timing. Separate observer exports read the final String;
they are absent from the primary binaries. The original predicate remains the
only result check inside the primary workload timer.

All four Rust controls use the same fresh-buffer algorithm: construct the first
concatenation, copy both overlapping halves into distinct buffers, then allocate
and copy a fresh final concatenation. Byte/u32 and copy-only/zeroed are separate
compile-time variants in one frozen Wasm artifact. The old buffer is freed after
the first concatenation; first/back/front remain alive through final construction.
This matches logical source replacement and copying while making reclamation
explicit. Scheme lets GC reclaim unreachable buffers. Each Rust trial also
allocates a fresh seed and drops its final result after reading its length;
Scheme resets from a constant seed and retains its last global String. The
original idiomatic Rust version additionally uses formatting, keeps the prior
buffer borrowed longer, and may reuse/reallocate its back buffer for the final
append. It remains a reference, not a one-variable control.

The optimized Rust artifact retains all four allocation sites and complete copies.
Separate reached-path diagnostics count 61,000 selected trial allocations:
60,000 growth allocations plus 1,000 seeds. Zeroed variants execute that many
selected calloc memory.fill operations, covering 3,145,173,000 logical byte writes
or 12,580,692,000 u32-storage bytes. Copy-only variants execute none of those fills.
Those are diagnostic Wasm operations and lengths, not physical memory traffic.
Full-count scalar checks, complete small/canonical untimed payload comparisons,
negative-result checks, and 48 complete-payload checks of the reassembled and
instrumented controls are retained by the control preparation. They do not imply
complete inspection of every timed trial's payload.

The control source was subsequently committed as `15b685c9f67a6d194d10013425efe1d8919e848f`
and its preparation evidence as `1f6ecd2f51c99ccc8dc4e558db8ffb6882768deb`.
The original frozen handoff still records its then-pending commit state; its
source and artifact hashes were fixed before these observations and are unchanged.

The native reference consumes the exact original GC i32 Wasm but lowers it to
eight-byte fields/array slots and the archived Immix collector. Its 300 MiB arena
is prefaulted before timing. It retains explicit roots and ordinary collection.
See the [matched LLVM/V8 report](../2026-10-14-current-wasm-llvm/README.md) for
the broader native experiment and its limitations.

## Allocation evidence and next experiment

The earlier [String diagnostics](../2026-10-14-strict-string-comparison/README.md)
placed approximately 3.86 seconds in system CPU and 0.83 seconds in user CPU
within the workload, with 2.896 million minor page faults. The width preparation's
separate resource runs reduce that to roughly 654,000 faults and 0.89 seconds of
system CPU with packed elements. These are diagnostic observations, not the
clean timings in the table; their exact records and hosts are retained.

The recorded Node version's V8 source gives regular pages a reuse-pool path,
while large pages go through chunk allocation and a virtual-memory reservation.
The header limits the pool to regular page size. This is consistent with the
observed page churn; it does not quantify that mechanism's contribution by itself.
Sources: [allocator implementation](https://raw.githubusercontent.com/nodejs/node/v24.19.0/deps/v8/src/heap/memory-allocator.cc),
[allocator contract](https://raw.githubusercontent.com/nodejs/node/v24.19.0/deps/v8/src/heap/memory-allocator.h).

The next candidate is smaller GC backing blocks for large Unicode strings,
preserving copying, mutation and full-width characters. That implementation and
its performance are still unproven; this report does not change production storage.

## Timing and replay

All timers include the full workload and final scalar predicate; compilation,
instantiation/input parsing and result formatting are outside them. GC/native
hosts additionally include their final acceptance assertion. Rust uses its
recorded Instant/report boundary. No payload audit, resource sampling or diagnostic
counter is enabled in these primary runs. Process elapsed times are also retained
in `clean.json` and must not be mixed with the workload column.

`clean.json` contains every sample, exact command/environment/stdin and frozen
identity. `artifacts.tar.xz` and `manifest.json` preserve the programs, source,
specifications, width transformation, diagnostics and measurement scripts with
an absolute-to-archived path map. External Nix tools are identified by hash/path;
they are not copied. Relocating a replay requires mapping the recorded paths and
freezing new identities. Use the original commands without audit/profiling flags
for a new clean observation set; preserve the original counts and predicates.
