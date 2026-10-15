# Matrix: native executor attribution on frozen Wasm

The native executor's allocation path is the leading measured opportunity.
The preserved native samples place approximately **51–57% of observed user
cycles** in `native_gc_alloc`, `allocate_header`, and memset paths. Its current
bump operation still enters an out-of-line function whose common path pays the
prologue for a much larger hole/large-object implementation. This happens for
224 million workload allocations, although **99.8776%** of allocation requests
use an already available bump range. The exact same Wasm's V8 TurboFan code
contains inline top/limit checks and bump-pointer updates.

Collection is material: separate native collector phase clocks account for
about 12.2% of that diagnostic workload clock, and a second sampling method
observes 12.23% of cycles in the collection body. Root publication, calls, type
checks, and linked-list access also remain visible in hot native functions.
These measurements identify mechanisms and priorities. They do **not** assign
the whole executor gap to allocation, predict a speedup, or establish the
effect of any production change.

No production source, GC policy, benchmark source, selected Wasm, or baseline
native binary was changed. Binaryen remains part of both production target
pipelines. The heavily instrumented native builds are separate diagnostics and
their times are excluded from performance conclusions.

## Frozen comparison

The completed seven-system campaign is retained in
`evidence/inputs/tmp/snail-strict-matrix-20261014/build/matrix-seven-system-campaign-20261014/campaign.json`.
It has 56/56 valid launches, seven retained samples per system, no replacements,
and CPU 5 affinity. Its same-module executor comparison is:

| Executor | Clean workload median | Retained range |
| --- | ---: | ---: |
| V8, native-final Wasm | 0.700726481 s | 0.699038986–0.702965355 s |
| Native LLVM/Immix | 1.901276011 s | 1.890884443–1.906404105 s |

The ratio is approximately 2.71× and the difference is 1.200549530 s.
The production V8 artifact's separate median is 0.705711381 s. This diagnostic
uses the native-final module for executor attribution; these are two different
Wasm artifacts:

| Artifact | SHA-256 |
| --- | --- |
| Native-final optimized Wasm, 39,444 bytes | `dfb9d40d9544334b3328aa041cbff50d30f40b28a65fc6bb690ea0e62f7e31cd` |
| Selected native executable | `f5209b3e8833647312ae29f118188517a0451e252f82702cf6be3352bfb139ee` |
| Production V8 Wasm / native build input | `f047b9cfbebd9127dfde44fb28efd80a9f3da1bd736352218e05e5f325013f46` |
| Frozen timing plan | `27ad980f6dfbae3702fd5dd20f7eda357eb3fc849a34161e80f4001ddaccddec` |

Original ownership remains `/tmp/snail-strict-matrix-20261014`, preparation
commits `7cf879e` and `dcec89f`, compiler basis `3dcce40`. Canonical inputs are
2,500 invocations, five columns and invariant size five. Each full result is
checked by the ordered five-matrix predicate. The source preparation separately
proved complete payload, order, alias behavior, raw/optimized/native outputs,
and original/adapted Chez behavior. A return value of one is that full
predicate, not an allocation checksum. Both production opacity providers are
non-counting; `barriers=0` native and null host counters in V8 are expected.

## Sampling scopes and retained limits

The first V8 run uses only a derived JavaScript host. Removing its recorded
additions reproduces the original host bytes exactly. `main`, instantiation,
input preparation, and inspector connection precede the profiler request.
Profiler startup submission and acknowledgement bracket the actual asynchronous
start; the original workload timer starts after acknowledgement. The stop
submission follows the original result assertion and timer stop.
`v8-profile/profile-window.json` retains all six `process.hrtime.bigint` markers.

The inspector profile contains 664 samples, 721,546 weighted microseconds and
a 722,321-microsecond profiler span. Its separate host workload clock is
715.088547 ms. Startup/stop intervals remain included rather than being clipped
using an assumed mapping to inspector timestamps. The initial inspector leaf
interval is 7,025 µs. Weighting samples by their preceding intervals is
statistical attribution, not continuous CPU accounting. It profiles the main
thread's scoped workload; background engine work is not fully attributed.

The largest V8 leaf intervals are `function84` 17.43%, `function89` 14.28%,
`function88` 12.93%, `function75` 10.61%, and `function64` 9.95%. The GC leaf
is 9.21%. These percentages include the profiler boundary intervals and should
not be compared as an exact time partition against native phase clocks.

Both native sampling runs execute the immutable native argv/input/cwd from the
plan, with CPU 5 affinity. They observe the **whole process**, including setup
and cleanup, without a native workload-timer bracket. The first uses
`cycles:u`, frequency 999, and 16,384-byte DWARF stack capture. Its 1,908 samples
span 1,903.768 ms and represent approximately 10,180,247,533 cycles. There are
zero reported lost samples. Reconstructed callchains include invalid small
addresses such as `0xf`; ancestry is unusable and is excluded from every claim.
All raw callchains remain archived.

The bounded cross-check uses `cpu_core/cycles/u`, fixed prime period 1,000,003,
and **no callchain capture**. It retains 10,177 samples and approximately
10,177,030,531 cycles, with zero reported loss. Exact event attributes, sampling
windows, stderr and complete flat reports are retained for both runs. The
different methods intentionally test the first capture's GC discrepancy.

| Native leaf | First: 999 Hz + DWARF | Cross-check: fixed period |
| --- | ---: | ---: |
| `native_gc_alloc` | 37.03% / 706 samples | 34.37% / 3,498 samples |
| `allocate_header` | 14.55% / 277 | 12.84% / 1,307 |
| `memset@plt` | 3.21% / 61 | 2.15% / 219 |
| libc memset | 1.84% / 35 | 1.46% / 149 |
| `native_gc_collect` | 3.61% / 69 | 12.23% / 1,245 |
| `f.33` = `function88` | 17.39% / 332 | 15.76% / 1,604 |
| `f.31` = `function84` | 5.69% / 108 | 5.00% / 509 |

The allocator/header/memset aggregate changes from 56.63% to 50.82%; the GC
estimate changes substantially. The initial GC split is therefore unsuitable
as the sole quantitative estimate. The cross-check agrees approximately with
independent collector clocks, while retaining a different scope and measured
quantity. Sampling aliasing or capture overhead is a plausible explanation for
the discrepancy, not a proven diagnosis of it. The initial capture was retained,
not rejected or replaced. Tiny unresolved/kernel-labelled leaves remain in the
denominator despite user-only event attributes. Zero reported losses does not
prove uninterrupted coverage. All percentages are period weights rounded by
perf, not counts assigned exact elapsed times.

The final binary has one `native_gc_collect` symbol containing the inlined
mark-roots, trace, finalizer, and sweep phases. Those helpers have no separate
retained code symbols; they are not missing from the flat denominator. The
source and complete binary disassembly establish this, rather than assuming
that a function named “collect” necessarily includes every GC cost.

## Runtime and generated-code observations

The opt-in `SNAIL_GC_STATS=1` run keeps the original binary and default policy.
Its statistics include setup and cleanup:

| Statistic | Value |
| --- | ---: |
| Requested objects / bytes | 224,085,259 / 5,807,145,296 |
| Collections | 950 |
| Mark clock / sweep clock | 0.006813 s / 0.223836 s |
| Arena bytes used / configured | 8,454,144 / 268,435,456 |
| Last live / peak live payload bytes | 16,224 / 21,488 |
| Root visits / field visits | 189,263 / 786,909 |

The diagnostic workload clock is 1.887578204 s. The phase sum is 0.230649 s,
about 12.2% of that clock, with a disclosed whole-process numerator. Those clocks
measure GC phases, **not total allocation overhead**. Requested bytes are neither
RSS nor physically aligned arena consumption. There are no large allocations.

The selected binary was compiled with `-O3 -flto`. LTO retains calls from
constructor sites to `native_gc_alloc`; that body calls `allocate_header` and
`memset@plt`. The `allocate_header` symbol is 1,785 bytes. Its bump case loads
`cursor` and `limit`, checks capacity, and advances `cursor`, but still passes
through the prologue/epilogue used by its uncommon search/large-object paths.
`native_gc_alloc` also performs per-object start-bitmap updates, GC header
initialization, payload zeroing, budget checks and allocation totals. The
annotated IP concentration near the bitmap update is informative but sampling
skid prevents assigning the following instruction's sample weight to one
specific operation.

After the archive was closed, read-only inspection of the immutable Clang
wrapper found its `zerocallusedregs` hardening entry maps to
`-fzero-call-used-regs=used-gpr`, and its default setup includes that entry.
The currently inherited hardening environment includes it. The selected
allocator's epilogue visibly clears caller-used registers before return.
`toolchain-flags.json` retains hashed source excerpts as a supplemental report
file. The historical build record does not include that environment or an
expanded wrapper invocation, and this report measures no isolated flag cost.

Bounded V8 code-print runs on the unchanged module retain both Liftoff and
TurboFan output for functions 64, 88 and 89. For example, function89's TurboFan
32-byte allocation advances the allocation-top pointer inline and then stores
the map, properties and two fields. No per-object C allocator call appears in
that demonstrated fast path. Native `f.33` has a 4,084-byte body and a root frame
with 16 slots; V8 function88's TurboFan instructions occupy 1,760 bytes. Size
alone is not a performance explanation. The native machine code visibly links
roots, publishes fields, handles indirect calls, and reloads list references.

`function-map.json` parses the selected binary's name section. LLVM `f.N`
uses the **binary index including four imports**, not definition ordinal N.
For example, indices 21/26/29/31/33/34 identify
functions 64/75/79/84/88/89. A preliminary definition-only mapping was corrected
before reporting. No V8 code-print flag uses a guessed fixed index.

Relevant frozen sources are `src/precise-gc.c` (allocation and collection),
`src/native.c` (roots, arrays and checked operations), and
`src/snail-scheme/llvm.sld` (root publication and lowering). Their original bytes,
`reader.scm`, the final WAT/LLVM IR, and complete native/V8 disassembly are in
the archive. Readiness/global-closure checks remain in this immutable baseline;
the separate constant/readiness work can overlap these samples.

## Separate logical counters and initialization invariant

Two successful counter builds retain scalar-only additions to the frozen
LLVM/C sources, with exact byte-erasure ledgers. They do not regenerate the
guest or change collection policy. The original Rust ABI library and provider
object are reused. Setup counters are saved and reset immediately before the
original timer start; worker counters are saved after the timer stops and
before diagnostic I/O. The reported count is verified from immutable input
configuration, not an invented return field.

| Workload counter | Full 2,500-invocation total |
| --- | ---: |
| Allocations / requested bytes / aligned bytes | 224,085,000 / 5,807,140,000 / 7,970,680,000 |
| Bump successes / hole searches | 223,810,699 / 274,301 |
| Start-bitmap updates / allocator-header writes | 224,085,000 / 224,085,000 |
| Payload zero requests / bytes | 224,085,000 / 5,807,140,000 |
| Arrays / elements | 11,140,000 / 55,882,500 |
| Array slot requests / copies | 146,855,000 / 0 |
| Active root enters | 166,075,042 |
| Root slot stores / root count stores | 2,921,335,645 / 361,340,007 |
| Direct / indirect guest calls | 236,105,043 / 84,947,500 |
| Reference tests / null guards | 172,965,040 / 2,147,143,507 |

The largest allocation types are the I64-list cons (58,417,500 objects) and
list-of-rows cons (51,042,500). Type tags 430 and 422 identify those layouts;
array tag 319 identifies the mutable I64 array. Thus packed byte-array storage
is not this Matrix workload's central issue.

These are **logical requests at lowering/runtime boundaries**. Added counter
calls can inhibit LLVM elimination and alter register allocation. Counts of
root stores, guards, casts or calls are not claims that all those instructions
survive LTO, nor a basis for dividing the elapsed gap among them. The successful
counter builds agree on all original counts and the independent uninstrumented
collector's whole-process totals equal setup plus worker exactly.

The second counter build separately measures final constructor writes:
434,785,000 struct field stores covering 3,391,610,000 bytes, 212,945,000 struct
type tags covering 1,703,560,000 bytes, and 78,162,500 array tag/length/element
stores covering 625,300,000 bytes. Their 5,720,470,000 bytes overwrite about
98.51% of the allocator-zeroed payload. The remaining 86,670,000 bytes are
unused parts of four-byte fields' eight-byte slots. Independent arithmetic from
the frozen Wasm type layouts reproduces the field counts, requested sizes and
write widths; it does not merely sum the same counter code.

In the frozen lowering, constructor reference operands are published **before**
allocation. `allocate-struct` then writes its type and every field using casts,
null/trap guards, GEPs and stores. Along its successful initialization path there
is no intervening allocation or callback. `native_array_new` likewise allocates
once, then writes type, length and all element slots before returning. Default
array elements are consequently zeroed by the allocator and written again by
the array constructor; later Scheme vector writes are a separate operation.
The runtime has synchronous GC safepoints. This establishes the demonstrated
constructors' initialization order, **not permission to remove zeroing from the
public allocator contract**, every client, or a later production optimization.

## Retained failures, audit and replay

The first `perf script` extraction requested a CPU field absent from one hybrid
event's attributes. Its exit status and complete stderr are retained. A second
extraction omits that field and keeps the original capture intact. The first
counter preparation failed its exact-erasure check because a leading newline
remained after diagnostic declarations were removed. No compiler/executor was
started; its failure record is retained. Both subsequent builds are preserved,
including their exact counter-source versions.

Every launched diagnostic/extraction command has a finite owned process group,
regular stdout/stderr files, exit status, environment, hash audits and cleanup
record. Leaders are reaped and no executing owned descendants remain. Zombies
are recorded as stopped. Matching hashes before/after detect persisted changes;
they do not prove that an external process could never transiently mutate a
file. The frozen ownership arrangement provides that separate guarantee.

`checks.json` records an audit under `python3 -O`: all full results, captures,
group cleanup, type-layout arithmetic, scope totals, source erasures, and both
flat sample totals pass. `manifest.json` covers every regular archive member
and external tool identity. `archive-verification.json` records byte verification
before and after relocated **V8, original native and counter native full2500**
correctness executions. Replay durations have no clean timing interpretation.
Historical attempt manifests retain the driver's SHA at execution; the final
runner extends the initial recorder, while all actual derived hosts, LLVM/C
sources, executables, commands and raw outputs required for these replays remain
preserved.

To inspect/replay the retained evidence, from this directory, use fresh output
directories:

```sh
mkdir /tmp/matrix-native-diagnostics-replay-report
cp artifacts.tar.xz manifest.json /tmp/matrix-native-diagnostics-replay-report/
python3 freeze.py replay --report /tmp/matrix-native-diagnostics-replay-report \
  --root /tmp/matrix-native-diagnostics-replay
```

Use a fresh replay root and report destination for another replay, because the
recorder refuses to overwrite attempt directories. To repeat original diagnostic
launches while the frozen owner tree exists, run `diagnose.py freeze` in a fresh
diagnostic worktree, then the explicit `v8-profile`, `native-stats`,
`native-perf`, `native-perf-leaf`, `build-counters`, `native-counters`, and
`inspect-native` operations. The native build argv and final link argv are
preserved verbatim in the archived native build records.

The first production experiment justified by this evidence is a general
allocation fast/slow-path separation, preserving existing zeroing, GC policy,
ABI and initialization behavior. That separate experiment needs independent
review, actual linked execution, and a new coordinated timing campaign. This
report contains no candidate implementation or measured speedup.
