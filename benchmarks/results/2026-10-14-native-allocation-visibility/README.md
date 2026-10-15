# Native allocation: expose initialization to LLVM

Inlining both native allocation layers reduces the complete Matrix median from
**1.686211 s to 1.416101 s**, using **16.02% less time**. Inlining only the inner
collector allocator uses 0.92% less time. The bytevector control changes from
**0.901291 s to 0.901567 s**, 0.03% more time with overlapping ranges. This is a
Matrix improvement, not a demonstrated speedup across workloads.

The production change adds `always_inline` to `native_gc_alloc` in
`src/precise-gc.c` and its outer `native_alloc` wrapper in `src/native.c`.
Link-time optimization was already enabled. Both bodies, including checks,
collection, retries, zeroing, rooting and accounting, remain unchanged. The
previously separated hole-search helper remains out of line.

## Controlled comparison

| Complete workload | Current baseline | Inner allocator inlined | Both layers inlined | V8, identical Wasm |
| --- | ---: | ---: | ---: | ---: |
| Matrix, 2,500 searches | 1.686211 s | 1.670678 s | **1.416101 s** | 0.702953 s |
| `bv2string`, count 100 | 0.901291 s | 0.903549 s | **0.901567 s** | 0.649597 s |

Each entry is the median of eight retained fresh processes. Retained ranges:

| Complete workload | Baseline | Inner allocator | Both layers | V8 |
| --- | --- | --- | --- | --- |
| Matrix | 1.678286–1.690414 | 1.667533–1.676682 | 1.413160–1.421753 | 0.701183–0.706253 |
| `bv2string` | 0.899061–0.905551 | 0.900602–0.905640 | 0.898624–0.907975 | 0.646923–0.653771 |

Native still takes **2.015× V8 time on Matrix** and **1.388× on `bv2string`**.
Overlap does not prove equivalent bytevector performance. These are not new
Chez or Rust measurements and do not increase suite coverage.

Each workload has one predetermined discarded process per system, followed by
four rotations and their reversals. Every system appears twice in each retained
position. All **72 processes passed**, with 64 retained observations and no
replacement, extra warmup or retrospective outlier exclusion. The coordinated
window lasted 83.695 seconds; other agents held builds, guests, profiling and
compression. Guests were pinned to CPU 5. Before/after CPU-policy records do not
establish a fixed frequency. Default GC policy and default V8 tiering were used.

## What the generated code shows

The current baseline still calls a shared 310-byte `native_gc_alloc`. Forcing
that function inline alone enlarges the outer `native_alloc`, which LLVM then
leaves as a shared call. Forcing both layers inline removes both allocation call
boundaries at the examined Scheme construction sites. Collection and slow
reservation remain real calls when required.

The archived Matrix `f.33` disassembly includes a complete 24-byte object
initialization at addresses `0x60668`–`0x606da` in the selected binary: reserve
32 aligned bytes, publish start membership, store the GC header, update counters,
then write the type and two payload fields directly. It contains no preliminary
payload clearing at this site. The source allocator's zeroed-storage contract
is preserved; LLVM removes stores it can prove are immediately overwritten.
This is stronger evidence than counting `memset` symbols alone. Other paths,
including arrays, retain initialization work. The comparison does not isolate
the individual contributions of call removal, dead stores, register allocation
and code layout.

Inlining increases generated machine code:

| ELF `.text` bytes | Baseline | Inner allocator | Both layers |
| --- | ---: | ---: | ---: |
| Matrix | 392,545 | 367,521 | 505,105 |
| `bv2string` | 260,977 | 257,185 | 270,001 |

Matrix's `.text` grows **28.67%** and the bytevector's **3.46%**. The
representative Matrix function grows from 4,084 to 10,091 bytes, including
duplicated slow branches. No instruction-cache effect is isolated by these
measurements. The growth is a reason to measure more workloads before treating
the change as universally beneficial.

## Frozen artifacts and observable work

The base is `5b61de743c4d533eb82da837e53687b4fa6d3c1c`, which already includes
the preceding bump-path split. Both complete source programs and canonical
inputs are unchanged. Matrix uses the preceding frozen production module;
bytevector conversion also includes the existing constant-visibility and
readiness improvements. Both production paths require Binaryen.

| Workload | Common final Wasm SHA-256 |
| --- | --- |
| Matrix | `dfb9d40d9544334b3328aa041cbff50d30f40b28a65fc6bb690ea0e62f7e31cd` |
| `bv2string` | `03b6ed0da64be15486b095364da2dd9535a10f082277f0d92316b5e4f4cf22da` |

For each workload, all three native variants link the same frozen LLVM module,
provider object, entry program and Rust archive. The original and expanded
Clang commands are retained. Only the chosen C source annotations and output
paths vary. The toolchain's register-clearing hardening and other flags stay
enabled; their isolated cost is not measured here. Timers retain the full worker
and original result predicate; compilation, instantiation and setup precede the
clock. JIT work during the worker remains included. Matrix validates all five
ordered 6-by-5 answers, and bytevector conversion retains its original failure
count predicate and all 1,001 roundtrips per invocation.

Separate statistics runs produce identical nonclock collector fields for all
three native variants. Matrix retains 224,085,259 allocations, 5,807,145,296
requested bytes and 950 collections. Bytevector conversion retains 801,730
allocations, 512,661,128 requested bytes and 62 collections. Those totals include
setup, and their diagnostic clocks are excluded from the clean comparison.

## Validation and reproduction

All six full native workload controls pass before timing. The selected two-layer
change passes the complete native suite: 252 recorded commands, including linked
Wasm controls, actual native execution, forced collection, root and tail stress,
array bounds/storage, C signatures, Rust callbacks and resource cleanup, traps
and relocated artifacts. `make check` also passes. No standalone ASan/UBSan claim
is added by this report.

After stacking this change above the new reader library, the freshly linked
native reader also passes all 84 valid/error cases and five additional cases
with collection forced at every allocation. `reader-integration.json` records
the build, command outcomes and complete-output hashes. The reader's input and
oracle evidence is in the preceding reader-library report; these checks add no
workload timing.

The archive retains all C variants, shared input artifacts, programs, build
commands, disassembly, process captures, plans, schedules and diagnostic counters.
It also retains the initial missing-provider-header build failure. A separate
runaway disassembly regex was terminated before the quiet window and replaced
with bounded literal-delimiter extraction. Its diagnostic record preserves the
PID and reason, but not a timestamp or termination capture. The before-window
ordering comes from the coordinator's execution record; the archive alone does
not independently establish that ordering.

```sh
python3 benchmarks/results/2026-10-14-native-allocation-visibility/archive.py
python3 benchmarks/results/2026-10-14-native-allocation-visibility/archive.py --replay /tmp/allocation-visibility-replay
```

Verification checks every unique regular archive member before extraction.
Replay runs all eight full-result native/V8 controls in the fresh destination;
all eight relocated controls passed, and the captures are in `replay/`.
The archive contains 336 verified members. An independent read-only review
reproduced the schedules, identities, medians, code-size figures and local
constructor analysis. Replay is a correctness check, not a timing campaign.
The pinned external tools and
shared libraries recorded by the artifacts remain prerequisites. The change is
prepared for the draft stack; nothing is merged.
