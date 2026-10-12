# Final Wasm builtin comparison, 2026-10-12

The frozen combined candidate improves every selected workload: elapsed-time
reductions range from 11.5% (`cat`) to 64.1% (`deriv`), with a **1.564× selected-five
geometric-mean speedup**. Chez remains 5.19–28.94× faster on these inputs. These
are the five historically worst cases, not an estimate for the full 57-case suite.

Baseline is `d2770aba4ee4c6a4c855a39b146d5f939c7fc22f`; candidate is
`d4f0d4203a8adc9cd1f1f338d991da31794ae725`. The comparison covers the combined
UTF8 output, successful-kind predicate, native builtin lowering, Scheme
combinators, known-rest calls and callback-origin changes. The earlier
[one-change ablations](../2026-10-12-builtin-ablations/README.md) ran in separate
windows; their speedups are not multiplied or added to explain this result.

## Clean timings

Original corpus revision `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`, original
inputs/counts, fresh processes pinned to CPU 5, Node 24.19.0 / V8
13.6.233.17-node.51, Chez 10.4.1 at safe optimization level 2. Sources, inputs,
Node binary and JavaScript host hashes match across the frozen Snail artifacts.
All builds finished before the quiet window. One preliminary run per case is
excluded; three retained rounds rotate the systems. Every one of the **60 clean
executions passed**, including all twelve full `cat` output SHA checks.

| Workload | d277 seconds | d4 seconds | Chez seconds | d277/d4 | Elapsed reduction | d4/Chez |
|---|---:|---:|---:|---:|---:|---:|
| cat | 22.918767 | 20.292531 | 0.701266 | 1.129× | 11.5% | 28.94× |
| lattice | 25.172925 | 16.197473 | 1.168692 | 1.554× | 35.7% | 13.86× |
| wc | 12.485604 | 10.475406 | 0.647150 | 1.192× | 16.1% | 16.19× |
| graphs | 12.540423 | 7.789372 | 0.767625 | 1.610× | 37.9% | 10.15× |
| deriv | 6.029514 | 2.167025 | 0.417435 | 2.782× | 64.1% | 5.19× |

[All samples and ranges](clean-summary.json) are retained. Cat's baseline range
is **22.593116–23.812070 s**, candidate **20.284202–20.601361 s**, and Chez
**0.697356–0.709302 s**. Three observations describe this window; they do not
support a population confidence interval. Every baseline observation exceeds
every candidate observation in each selected workload. Workload timers exclude
process startup; raw process-wall times and output/status records are archived.

Final clean results SHA256:
`d9de34e16e672f06c6bf95aadc2c7a3333cbcb76a581a3e5209736ca6cff191e`.

## Observer modes and request counts

The four modes are distinct:

1. Clean runs use original binaries and default V8 tiering, with no counters,
   CPU profiler or GC tracing.
2. Heavy counter-only runs add Wasm globals at constructor, function-entry,
   indirect-call and host-import sites. They ran concurrently with integration
   tests/preparation. Their elapsed times are excluded from performance claims.
3. Paired diagnostic runs use original binaries with **CPU profiling and
   `--trace-gc-nvp` together in the same process**, separately from both modes
   above. They ran in the quiet window, but their times remain observer times.
4. Native disassembly forces eager TurboFan compilation of original binaries.
   It performs no workload and measures no compilation time. It does not prove
   that this exact tier/code executed throughout the default-tier clean runs.

All ten matched counter-only runs passed. Counts include initialization,
checking and output, and exclude constant global initializers. A probe runs
**before operands evaluate**, so counts describe reached operation sites or
requests, not necessarily completed operations. Engine optimization may change
with probes; constructor requests are not materialized-allocation counts, and
`call_ref` requests are not counted native machine jumps.

| Workload | Constructors d277 | Constructors d4 | Signed d4−d277 | Indirect d277 | Indirect d4 |
|---|---:|---:|---:|---:|---:|
| cat | 1,115,017,486 | 1,115,017,385 | -101 | 756 | 754 |
| lattice | 3,575,353,260 | 1,428,346,780 | -2,147,006,480 | 2,812,117,916 | 685,124,914 |
| wc | 1,698,842,361 | 892,013,211 | -806,829,150 | 456 | 354 |
| graphs | 2,794,647,871 | 1,454,167,266 | -1,340,480,605 | 686,774,595 | 392,345,737 |
| deriv | 2,040,000,436 | 800,000,438 | -1,239,999,998 | 590,000,006 | 160,000,004 |

The signed constructor deltas by class show what disappeared:

| Workload | Fixed vectors | Dynamic vectors | Pairs | Closures | Cells | Atoms |
|---|---:|---:|---:|---:|---:|---:|
| cat | -101 | +0 | +0 | +0 | +0 | +0 |
| lattice | -2,131,306,545 | -5,519,420 | -7,073,120 | -1,553,695 | -1,553,700 | +0 |
| wc | -403,414,650 | +0 | +0 | +0 | +0 | -403,414,500 |
| graphs | -1,336,315,427 | -1,404,564 | -1,856,580 | -452,018 | -452,016 | +0 |
| deriv | -639,999,999 | -240,000,000 | -280,000,000 | -39,999,999 | -40,000,000 | +0 |

[The operation/type breakdown](counter-summary.json) preserves every class,
including unchanged value envelopes and floating boxes. Cat's Rust `dlmalloc`
entries fall **223,003,320→519**, and `dlfree` **223,003,298→497**, consistent with
removing one temporary UTF8 String allocation/free per written character. Yet
its Wasm constructors barely change, and the isolated String change improved
elapsed time by only 3.8%. Counts alone are not causal time fractions.

## GC traces and CPU profiles

All ten paired CPU/GC diagnostic executions passed. The table reports summed
V8 `allocated` fields at GC events, in decimal GB, and the candidate's final
reported live heap. It excludes Rust allocations inside Wasm linear memory and
final allocation after the last collection; it includes V8 startup and checking.

| Workload | d277 GB at GC | d4 GB at GC | d4 last live MB | d4 pause rounding interval, ms |
|---|---:|---:|---:|---:|
| cat | 37.473 | 37.474 | 5.69 | 1.25–981.15 |
| lattice | 138.770 | 53.243 | 6.97 | 16.75–411.60 |
| wc | 59.726 | 33.908 | 5.68 | 0.80–995.40 |
| graphs | 118.767 | 64.874 | 5.22 | 286.55–501.80 |
| deriv | 68.088 | 25.285 | 5.64 | 1.15–353.95 |

[Full diagnostic summaries](sampling-summary.json) retain event counts, types,
printed sums and rounding bounds for both revisions. V8 prints `pause` to
0.1 ms per event: cat's d4 printed sum is 2.1 ms across 19,581 events, while
rounding allows 1.25–981.15 ms. Its included `scavenge` phase prints 442.01 ms
at 0.01 ms precision. **Zero-rounded pauses are not free collections**; the
scavenge phase must not be added to its containing pause. These wall-duration
fields also omit some concurrent/background GC CPU work. Field semantics are
verified against the pinned [V8 GC tracer source](https://github.com/nodejs/node/blob/v24.19.0/deps/v8/src/heap/gc-tracer.cc).

The candidate's sampled stacks identify remaining contexts. Fractions below
are unweighted whole-process self-sample frequencies, not exact CPU cost
fractions or attributable gains; initialization/checking and code inlining
change their distribution.

| Workload | Candidate sampled context | Exact identity / source |
|---|---|---|
| cat | Copy loop 33.8%; Rust read-char 12.3%, write-char 9.5% | `function171`, Wasm150, nested under `copy-ports` at program.scm:7; macro expansion location base.sld:40 |
| lattice | Membership 42.0%; lex-first 24.0%; literal callback 9.9% | `memv` function31/Wasm143 at base.sld:264; function165/Wasm164 at program.scm:30; adapter217/Wasm196 at 190:25 |
| wc | Read loop 33.4%; Rust read-char 23.9% | function420/Wasm197, expanded loop under the wc source; base.sld:40 expansion location |
| graphs | Inner loop 20.0%; literal callback 18.0%; membership 17.1% | function217/Wasm185; adapter208/Wasm180 at program.scm:291:30; memv function31/Wasm134 |
| deriv | map-one 38.5%; deriv 20.4%; literal callback 14.4% | function38/Wasm146 at base.sld:279; function184/Wasm168 at program.scm:9; adapter185/Wasm167 at 22:27 |

These are generated Scheme library routines and benchmark callbacks. In the
baseline, hottest membership function28 is `member-by` at base.sld:256; in the
candidate, hottest function31 is **memv calling specialized/inlined member-by
with known eqv?**. Its optimized WAT has direct eqv calls and no constructor
sites. Lattice still executes 2,051,078,150 eqv entry requests. Generic map-one
still packs a callback argument vector and executes call_ref; named `deriv`
callbacks and literal lambda operands therefore have different call paths.

Readable [WAT snapshots](wat) retain these functions and adapters. Raw source
maps archive **both revisions' actual final Wasm indices, import counts,
parameter names and source locations**. Macro-origin locations are distinguished
from their surrounding benchmark procedure. The archive also contains seven
forced-tier native disassemblies and exact selector commands.

The observed data support reduced object/call overhead in lattice, wc, graphs
and deriv. Cat's remaining four fixed-vector requests per copied character and
seven ABI-root entries per character explain why eliminating Rust String churn
leaves substantial work. Files were already buffered: this is not evidence of
one OS syscall per character. The profiles locate further candidates, rather
than proving a particular follow-up's speedup.

## Planning limits and current representation scope

The five copy plans use 81/113/90/130/85 copies respectively; their largest
per-source groups are 4/6/7/4/4. The checked-input observer records **zero budget
denials**: neither total 256 nor per-source 8 explains their remaining generic
paths. [Copy-plan details](copy-budgets.json) were gathered separately from the
compiler processes that produced timed binaries, using original checked
instances/scopes and a process-local planning observer.

Immutable named define/letrec lambda bindings and aliases propagate callback
code identity. Direct lambda operators can specialize. **Literal lambda
callback operands and ordinary let-initialized lambdas remain generic** in this
checkpoint; no preceding pass names them. Heap-loaded/mutable values, unknown
value cardinality and representation/result-boundary constraints are distinct
possible reasons for other generic paths. A generic path alone identifies none
of those reasons.

Implemented `(snail unsafe)` aliases cover I32/I64/F32/F64 and existing managed
Eqref, VectorRef, PairRef, BytevectorRef, StringRef and ClosureRef categories.
GC references remain managed references; containers still store generic
elements. In particular `$vector` is `(array (mut eqref))`, not a specialized
numeric element array. The vector fixture's optimized specialized349/Wasm214
has three `(ref $vector)` parameters and an **eqref result**.

| Workload | d277 linked Wasm bytes | d4 bytes | Signed delta |
|---|---:|---:|---:|
| cat | 495,891 | 505,755 | +9,864 |
| lattice | 520,555 | 560,327 | +39,772 |
| wc | 512,465 | 527,224 | +14,759 |
| graphs | 532,624 | 576,156 | +43,532 |
| deriv | 504,619 | 531,774 | +27,155 |

[Module hashes and sizes](module-sizes.json) are retained. Concurrent build and
compiler-plan durations are not compilation-performance evidence.

## Vector-append boundary and focused timings

**d277 has no public vector-append**. Its row uses an explicit portable,
elementwise Scheme implementation. The same reference source is also compiled
on d4, so the same-compiler reference/public comparison isolates the new
implementation more closely than the cross-compiler comparison. The public
source changes only the target substitution in a common archived template.

All **83 linked correctness executions** passed, followed by an independent
checksum calculation. Coverage includes direct arities 1/2/3, typed wrapper,
runtime choice between distinct closures, dynamic apply, integer/Unicode-char/
pair elements, empty and single vectors, fresh storage, shared pair identity,
mutations in both directions, and the opaque false branch. Root integration
also checks foreign multiple-value envelope slots and vector-map snapshot
behavior, including once-normalized mutable singleton envelopes.

The bounded clean matrix has fourteen input rows × three artifacts: small 8-slot
integer direct arities and typed/opaque/apply/control entries; bulk 1024-slot
integer typed/opaque/apply/control; small pair-element typed/opaque/apply.
One excluded pilot freezes common repetition counts 667,520/10,176/609,856.
One preliminary plus three rotating retained rounds gives **168 fresh clean
executions**, all with independently checked checksums.

| Elements and size | Entry | d277 reference s | d4 reference s | d4 public s | d4 reference/public |
|---|---|---:|---:|---:|---:|
| integers, 8 slots | typed-three | 0.472500 | 0.305801 | 0.218880 | 1.397× |
| integers, 8 slots | opaque-three | 0.469475 | 0.308702 | 0.222311 | 1.389× |
| integers, 8 slots | apply-three | 0.475303 | 0.324067 | 0.225402 | 1.438× |
| integers, 8 slots | checksum-three | 0.222300 | 0.160650 | 0.161424 | 0.995× |
| integers, 1024 slots | typed-three | 0.671481 | 0.448190 | 0.271966 | 1.648× |
| integers, 1024 slots | opaque-three | 0.670520 | 0.446293 | 0.273718 | 1.630× |
| integers, 1024 slots | apply-three | 0.668727 | 0.447186 | 0.274532 | 1.629× |
| integers, 1024 slots | checksum-three | 0.343652 | 0.259586 | 0.260243 | 0.997× |
| pairs, 8 slots | typed-three | 0.440049 | 0.312193 | 0.228757 | 1.365× |
| pairs, 8 slots | opaque-three | 0.438894 | 0.308928 | 0.222724 | 1.387× |
| pairs, 8 slots | apply-three | 0.445785 | 0.319040 | 0.237465 | 1.344× |

[All fourteen rows and ranges](vector-summary.json), including direct arities,
are retained. The timed operation includes per-iteration input mutation, mode
dispatch and a **full-result checksum**. The untimed expected-checksum loop can
warm common helpers. The checksum control is shown and **not subtracted**;
these are complete-workload gains, not isolated array-copy or ABI costs.
Typed versus opaque timings are close and not uniformly ordered: small pair
opaque is slightly faster than typed. No uniform specialized-entry win is
claimed.

Twenty-four request-probe executions verify the paths using three versus
thirteen iterations. Public direct-three/typed-three executes three array.copy
data-copy requests per extra iteration. Opaque adds one generic indirect-call
request; apply adds that and **two argument-array copies**. The generic adapter54
remains and is entered once per opaque/apply iteration. Portable direct/typed/
opaque rows perform no array.copy data-copy requests. Differential total
constructors include the untimed expected-checksum loop; the append-specific
helper/array-copy entries distinguish its invocation path.

The larger vector fixture requests 131 copies and hits the per-source 8 limit
four times in **equal?'s compare-containers validation loop**, original
function98 (`index`, expanded at base.sld:43), not vector-append. Total256 is
not reached. This fixture-only limit differs from the five benchmark plans.

## Validation, Chez evidence and next controls

The [combined validation manifest](validation/manifest.json), SHA256
`758be7694af9b14c695367195e50a0272972972d31d1b68707fd361e7d74db94`, records
passing make test/check, Cargo 26 tests/fmt, and full backend/build/typing checks.
Typing includes 204 linked executions and 39 expected rejection compilations.
Unicode/EOF/streaming, callback effects/shortest lists, mutation/snapshots,
original call error/evaluation order, foreign envelopes, identity/finalization
and fresh rest spines have linked guarded/optimized coverage. Compiler stays
hosted by Chibi.

Earlier safe-O2 Chez statistics and representative disassembly are included
as **historical diagnostics on the same frozen Chez artifacts**, separately
from this fresh timing run. Stats cover load(compiled program), excluding VM
startup; V8 traces cover the whole Node process and different heaps. Exact
allocation ratios across these scopes are not asserted. Representative
character-copy and generic-callback assembly show buffered port fast paths
and register-argument closure calls; they are not the actual benchmark code.
The inspected [Chez port documentation](https://cisco.github.io/ChezScheme/csug10.3.0/io.html)
supports open-coded read-char/write-char on ordinary ports. Broader claims
about Chez optimizations remain inferences rather than inspected facts.

Two useful next one-change controls are propagating literal callback code
origins in deriv/lattice/graphs, and reducing character-loop environment/root
traffic while retaining Unicode, EOF/peek, streaming, buffering and port lifetime
semantics. Preserve closure identity/captured mutation and callback/error order,
then repeat paired counters and quiet clean timings. Current copy budgets and
removed allocation counts do not establish the payoff of either change.

## Raw evidence and reproduction

[manifest.json](manifest.json) maps 1,799 logical files to 1,119 checked,
content-addressed members of [artifacts.tar.xz](artifacts.tar.xz). The archive is
17,866,368 bytes, SHA256
`6e95244f3a289f7c803324a8860f1f7803fc80070b6d5fec95a771df646dbdf0`.
It includes frozen programs/inputs/hosts/compiler sources, all raw timings and
outputs, counters/manifests, combined CPU/GC profiles, source/copy maps, native
code and exact build/observer commands. Cat output payloads are omitted;
verified byte counts and SHA256 values are retained.

Use the same tool binaries from the archived manifest. Python needs the
benchmark environment's matplotlib dependency. Exact commands in this machine
used `/nix/store/3rpxj4nlh9pxbshncijy78acnajnybky-python3-3.14.6-env/bin/python3`.
The helper restores immutable files, verifies every blob, and runs the same
15-case comparator preflight before executing a requested mode:

```sh
python3 repro/run-frozen.py --output /tmp/snail-final-restore --restore-only
python3 repro/run-frozen.py --output /tmp/snail-final-five --experiment five
python3 repro/run-frozen.py --output /tmp/snail-final-vector --experiment vector
python3 repro/run-frozen.py --output /tmp/snail-final-counters --experiment counters
python3 repro/run-frozen.py --output /tmp/snail-final-sampling --experiment sampling
```

Each output path must be new. Reproduction keeps counter/profiler modes separate
from clean measurements. The checked restoration recorded all 1,119 valid blobs,
all 1,799 restored logical files and all 15 comparable cases, without rerunning
benchmarks. [file-sha256.json](file-sha256.json) checks the readable report files;
[repro](repro) contains the unchanged measurement helpers alongside the relocation
helper. Original raw records retain their absolute paths and hashes.
