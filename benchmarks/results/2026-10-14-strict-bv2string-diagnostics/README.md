# Full bv2string attribution

The largest sampled work is scalar decoding and RNG, with encoding next.
The optimized RNG's canonical branch executes two hardware signed divisions;
immutable captured constants and the byte bound are not visible there as
constants. Separate GC observations show short collection brackets. These
findings explain concrete extra work without assigning the entire **20.569×**
Rust/Wasm gap to one mechanism. No production change or timing ablation is
included.

The [clean comparison](../2026-10-14-strict-bv2string-comparison/README.md)
remains the performance authority: V8 median 0.939190951 s versus Rust/Wasm
0.0456596115 s. Its original/adapted Chez controls remain separate. All diagnostic
durations below are from instrumented/observed executions outside clean timing,
while unrelated work could run. None is a replacement performance sample.

## Exact workload and artifacts

Every accepted diagnostic uses count **100**, 1,000 stress roundtrips, maximum
1,000 and expected failures zero. It retains repeated RNG resets, the initial
sanity case, all three conversions, comparison, failure handling and the final
predicate. The 745 copied files and all 384 clean-plan identities were checked
before/after each owned command. The copied preparation includes complete sources,
raw/optimized artifacts, both Chez controls, tool/build provenance and the full
**single-invocation** internal trace. That trace has 3,476,209 u32 fields and
SHA-256 `206b9db498985fcea1b6bdb458de81388a4c2e4f1a92418285b65562519fe35e`.
There is no full-100 internal trace; unchanged full-count results, existing reset
and opacity checks, source erasure and separate site totals supply outer evidence.

V8 uses the exact 8,208-byte production-optimized module
`c9ba1e18d65ead5db6cc005d9486e7275c14f9e8c91875edaa68e2ae59d7b1d6`.
Both native builds were supplied that module but mandatory re-entry Binaryen
produced a distinct 9,721-byte final module,
`2463c3f837b5133d6a622fe0d690da47cffb464bbda63d2f90f000b27649e41e`.
The selected native executable is
`bc586c42b31ef7e9e36d156fc803afb45c69f411362d0cf2bea20333596d1f5c`.
Native statistics therefore concern its actual built binary, with that distinct
final lowering. The comparison README now states this explicitly; archived
plans/manifests and historical results are untouched.

## Unchanged-guest sampling

One scoped V8 profile contains **894 samples**, 947,282 μs of weighted intervals.
The requested interval is 1,000 μs. Exclusive leaf intervals are merged by
complete frame location/name; whole boundary intervals remain in the denominator.

| Mapped functions | Weighted μs | Share |
| --- | ---: | ---: |
| RNG closure, function89 | 326,184 | 34.43% |
| Decode count/fill loops, functions59/67 | 388,198 | 40.98% |
| Encode count/fill loops, functions74/77 | 132,054 | 13.94% |
| Elementwise comparison, function40 | 29,389 | 3.10% |
| Input byte-fill loop, function93 | 28,369 | 2.99% |
| Stress driver, function99 | 13,864 | 1.46% |
| Decode constructor, function57 | 11,769 | 1.24% |
| Profiler GC leaf | 8,409 | 0.89% |

Sampling starts after `main` and stops immediately after the original host clock
read, preserving its result assertion inside the clock. Start submission/ack,
worker start/end, stop submission/completion and the full profile are retained.
The profiler span is 948,022 μs; its first 6,941 μs interval lands in inspector
`post`. The asynchronous start introduces about 7.15 ms between `main` return
and the worker, potentially changing initialization garbage/heap state. Sampling
and delayed intervals are not continuous CPU execution. A function's exclusive
samples combine its checks, loads, arithmetic, inlining and other work; they do
not isolate bounds checks, closure dispatch, division or allocation.

An optional unchanged Rust/Wasm profile contains 261 samples at requested 100 μs,
over 54,481 weighted μs. Its first 6,926 μs interval is inspector setup. Its scope
is synchronous `WASI.start`, including input, predicate, reporting and exit beyond
the internal Rust clock. Frames include `main`, `roundtrip`, `from_utf8`,
`dlmalloc`, `memcmp` and `dlfree`; short scope and unequal brackets preclude a
matched allocation-cost or function-share comparison with Snail.

## RNG path and actual instructions

The selected call chain is `bench` → `export0` → function101, which implements
the outer loop/reset/sanity and calls function99 for stress roundtrips. Functions99
and93 invoke the first-class RNG closure through `$call42`; function93 visibly
passes `i64.const 128`. The closure stored in `$type42` carries function89 and
`$environment89`, so function89 keeps a general I64 bound parameter. The
constant byte bound is lost across this closure call boundary. Sanity length
generation also calls function89 directly with 10.

The original/adapted `letrec` defines `a=701`, `c=743483`, `m=524287` and the
mutable seed. Constants a/c/m are held in immutable `$type64` I64 fields and
captured through environment fields 2/3/4. Seed capture field 1 holds an immutable
`$type65` wrapper referring to `$type66`'s **mutable** I64 field. Treating all
captures as mutable would conflate initialization representation with seed
mutation. Any future simplification must preserve letrec initialization errors
and type/closure semantics.

The binary name section maps function89 to **index 21**. A filtered full-count run
prints both Liftoff and TurboFan code under default tiering. The TurboFan
`n<16384` branch is at offsets 0x777–0x806. At 0x7cb `idivq rdi` computes remainder
by captured `m+1`; at 0x7fc `idivq r8` computes remainder by the general bound.
These hardware instructions execute on the canonical branch. Division by eight
at 0x7d5–0x7e0 is reduced to signed shifts/bias; it is **not** a third optimized
hardware divide. The branch also retains loads through capture/Ref wrappers.
Nine field-load instructions remain there after engine CSE/removal, compared
with twelve source `struct.get` requests per call in the separate counter guest.

Rust's frozen optimized byte-fill WAT uses inlined, unrolled I32 multiplies/adds,
shifts and mask127, with no division/remainder in that byte loop. Dynamic size
generation remains. This supports a constant-visibility/arithmetic-lowering
mechanism alongside capture/cell access. It does not quantify their separate
contributions to function89's sampled share. The diagnostic guest's operation
requests are not hardware counters from the sampled or printed-code execution.

## Executed sites and source-predicted passes

An independent small RNG oracle predicts **495,028 bytes per invocation**,
49,502,800 across the full workload. A separate, heavily instrumented derivative
passes the unchanged full predicate and matches all 33 independent expected
totals; all 71 counter names are retained. Its additions erase exactly to the
optimized WAT. Array length operands are evaluated once in fresh I32 locals;
no diagnostic reference storage is introduced. No re-optimization is performed.
V8 still compiles a changed module, so physical lifetimes/JIT behavior can differ.

| Executed request sites | Full-count total |
| --- | ---: |
| RNG function entries | 49,602,900 |
| RNG captured field gets / cell gets | 248,014,500 / 347,220,300 |
| RNG signed remainder / quotient requests | 99,205,800 / 49,602,900 |
| Decode packed-byte reads, functions59+67 | 396,022,400 |
| Decode readiness gets, functions59+67 | 792,044,800 |
| Comparison plus encoding scalar reads | 198,011,200 |
| Decode scalar writes | 99,005,600 |
| Scalar-array / packed-array requests | 200,200 / 200,200 |
| Scalar-array / packed-array requested elements | 99,005,600 / 99,005,600 |
| Secondary String-array requests | 0 |

Each decode count/fill loop executes `$ready177`, `$ready182`, `$ready184` and
`$ready188` once per scalar. The first pair precedes leading-width work, the
second precedes scalar/leading-prefix work. Across two decodes and two passes
these make 16 readiness-get requests and eight packed-byte read requests per
original byte. Global readiness gets are **zero** on function89's canonical
branch; caller/decoder checks must not be assigned to its exclusive samples.
Other counters record selected ordered I64 predicates, zero predicates and
index/byte narrowings; they are not an exhaustive type/bounds-check ledger.

The library source explains two scalar passes per conversion: decode validates
and counts before allocating/filling; encode sizes before allocating/filling.
The two decodes plus encode therefore make six scalar passes, followed by the
elementwise comparison and preceded by RNG filling. ASCII is still checked
through the general UTF-8/scalar path. Helper calls and staged initialization
checks coexist with element accesses; neither source nor site totals establish
their individual machine costs.

Operation requests are counted before their operands; array requests/elements
are counted after the length operand but before allocation. No separate
constructor completion counter is claimed. Full successful execution establishes
completion for these requests, without equating them with physical allocations.
Canonical loop bounds put any one counter below 10^9 plus bounded roundtrip
overhead, far below signed I64 overflow; the largest observed counter is
495,028,000. Payload requests imply 495,028,000 V8 element bytes (I32 Strings,
I8 bytevectors), excluding object headers/alignment and initialization costs.

## Collection, allocation and control limitations

A separate unchanged V8 guest reports 370 GC events, with 368 overlapping the
937.52531 ms worker envelope. All overlapping events are minor GC; their whole
durations sum **10.24161 ms**, about 1.09% of that observed envelope. Delivery
occurs afterward in one batch; two event-loop turns plus `takeRecords()` collect
pending entries before disconnecting. This bounded drain is not completeness
proof, and event sums are not isolated CPU costs. The raw occurrence/delivery
timestamps and kind/flags follow [Node's performance APIs](https://nodejs.org/docs/latest-v24.x/api/perf_hooks.html#garbage-collection-gc-details).

The unchanged selected native binary, default 256 MiB arena/adaptive minimum 8 MiB
budget and `SNAIL_GC_STATS=1`, records **801,730 allocations**, **1,601,725,128
requested payload bytes**, **192 collections**, mark0.000433 s and sweep0.005134 s.
Counters include initialization/teardown and collector clock reads. Requested
payload includes native object header words, excludes collector headers/alignment,
and is not RSS. Native arrays occupy 8-byte element slots: corresponding scalar
and packed-array element requests imply 1,584,089,600 payload bytes. Source also
zeroes object payload at allocation, then initializes array slots. These are
storage/initialization observations, not measured cost shares. Collector pauses
alone are not supported as the principal explanation; allocation fast paths,
zeroing, barriers and JIT/GC interactions remain unisolated.

Rust stores owned UTF-8 Strings/Vec bytes and uses deterministic Drop; Snail
Strings store I32 scalars in V8 GC blocks, with precise Immix and wider slots in
native. Rust still retains three copy/allocation sites, two UTF-8 validations,
comparison and frees for stress roundtrips. Empty buffers may avoid payload
allocation. Rust folds the seven-byte initial sanity vector; Scheme retains its
RNG path. Original/adapted Chez source agreement and clean medians do not isolate
width, allocation, ownership, GC, initialization checks or arithmetic lowering.

## General next experiments and evidence closure

The first prospective experiment is constant propagation through proven immutable
captures plus call-target visibility, keeping the genuinely mutable seed and
initialization/type semantics. The next is eliminating demonstrably redundant
UTF-8 helper/initialization/range work on general paths while preserving all
Unicode and error contracts. Separate storage/initialization probes can investigate
native wider slots and duplicate zeroing. These are priorities supported by
observed work, not implemented changes or promised speedups. No benchmark-specific
compiler rule or new clean campaign is part of this report.

The archive preserves inputs, complete guest/tool attempts, all profile trees,
GC events, native statistics, counter source/erasure ledger, generated machine
output and selected source excerpts. An early print-all attempt, a valid counter
attempt missing readiness coverage, setup errors, the native copy's missing-mode
launch failure and both rejected reference-wrapper assembly attempts are retained.
The latter used generic reference-result blocks that weakened Binaryen's inferred
exact type; final counters use scalar operands only. No failed run contributes
to a clean statistic. The first three diagnostic attempts predate launcher-hash
logging; exact injected hosts/guests/commands are retained, with a later driver
snapshot and an explicit version-history note rather than an invented launch hash.

All guest commands use fresh processes/cwds, CPU 5, cleared Node/debug/preload/GC
override variables, bounded owned groups and raw persistence before validation.
Every completed group has no live members. Earley timing imposed a hold after
the first three diagnostics; all handles were terminal until its release.

The archive contains **873 regular files** and lists 13 external tool identities;
it is 19,006,340 bytes, SHA-256
`1f28c47d4ad4e64cf00ab32b16614ae1ae7583f561b80fba08b45e5bb18c7e80`.
The final counter module is
`190a726260bfaa1d088d83219a496ae5bc5c772a9e9dd8e6906dba74b3877103`.

Restore and check every archived byte without execution:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/bv2string-diagnostics-restored \
  --report benchmarks/results/2026-10-14-strict-bv2string-diagnostics
```

`archive-verification.json` records all-file verification and two actual relocated
full100 correctness replays, original guest and counter derivative. `replay/`
preserves their raw records outside the primary archive to avoid circularity.
The explicit validation checks also reject malformed profiles under `python3 -O`.
The [review record](measurement-review.md) describes the bounded simplify pass.
