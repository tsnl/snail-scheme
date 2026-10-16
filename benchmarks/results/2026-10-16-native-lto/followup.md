# Native LTO and collector follow-up

This adds a second, independent campaign to the [original report](README.md).
The original files and measurements are unchanged. All **162 scheduled runs
passed**: 27 arms, each with one warmup and five measured fresh processes.

The runtime-only dead-block sweep change reduces `gcbench` time by **9.4%**.
Shared LTO retains its substantial scalar and string wins, but the production
benchmark harness still shows an **array regression of 27%**. Delaying all
guest optimization until the final link does not resolve that regression.
The LTO default change remains experimental; the independently useful runtime
changes are being prepared separately.

## Production-harness comparison

Median guest seconds; lower is better:

| Workload | Baseline native | Production LTO | V8 | LTO / baseline | LTO / V8 |
| --- | ---: | ---: | ---: | ---: | ---: |
| fib | 3.195149 | 1.288854 | 2.093888 | 0.403 | 0.616 |
| fibfp | 0.581088 | 0.232365 | 0.382417 | 0.400 | 0.608 |
| mbrot | 0.722047 | 0.478028 | 0.288790 | 0.662 | 1.655 |
| array1 | 3.292421 | 4.181957 | 5.418404 | 1.270 | 0.772 |
| bv2string | 0.603741 | 0.416050 | 0.373044 | 0.689 | 1.115 |
| gcbench | 3.985310 | 3.881602 | 1.427338 | 0.974 | 2.719 |

The baseline and V8 executables are from the same canonical freeze as the
original campaign. The LTO binaries use the proposed production build path
and direct Rust `std::hint::black_box` in benchmark providers, instead of the
earlier experiment's opaque machine-code trampolines. The ordinary baseline
remains a product comparison, rather than a byte-identical provider ablation.
All six LTO guests have exactly the same Binaryen-optimized Wasm as the freeze.
The counts, inputs, output predicates and result-consumption rules are unchanged.

Inspection of the actual linked IR and machine code verifies that recursive
Fibonacci work, Mandelbrot recurrence, array initialization and copying, PRNG
and byte stores, and recursive tree construction survive. Each of these
observations refers to its retained binary hash. Hook counts and correct final
answers alone would not establish retained work. Direct `black_box` was checked
on this toolchain; it is not a portable proof against arbitrary future optimizers.

`array1` ranges remain clearly separated: baseline 3.235076–3.332244 seconds,
production LTO 4.123683–4.285732 seconds. There is no evidence here that the
earlier regression was merely a noisy run or the trampoline implementation.

## Matched ablations

These arms have their own controls; compare within a row. They use the earlier
opaque-provider boundary and are not byte-identical to the production-harness
builds above.

| Workload and change | Control | Candidate | Candidate / control |
| --- | ---: | ---: | ---: |
| gcbench: skip sweeping individual objects in wholly dead blocks | 3.917379 | 3.548946 | 0.906 |
| array1: retain out-of-line root enter/leave helpers | 4.155848 | 3.731112 | 0.898 |
| array1: skip redundant zero fill, with LTO | 4.155848 | 4.116744 | 0.991 |
| array1: optimize guest only at final LTO | 4.263401 | 4.458946 | 1.046 |
| fib: optimize guest only at final LTO | 1.316057 | 1.296060 | 0.985 |

The dead-block collector change has disjoint ranges: 3.907406–3.932023 versus
3.533914–3.557653 seconds. Marking already records all lines occupied by live
allocations, including large-object continuation blocks. A block with no live
lines can therefore clear its object-start bitmap without touching every dead
header. Exact-start membership is checked before dereferencing candidate
headers; allocation still zeroes storage before reuse. Mixed live/dead blocks
retain the previous object-by-object sweep, and finalizers are queued first.

Separate instrumented runs report identical non-time GC counts: 226,122,908
allocations, 4,463,717,120 payload bytes, 34 collections, 320,561,531 field visits
and 14,395 root visits, with a 512 MiB heap and 7,994,907 live objects after the
last collection. Instructions fall about 4.7% and cache misses about 17.6%.
Those counters explain the mechanism; their instrumented durations are not
substituted for the clean timings above.

Keeping root helpers out of line partially recovers array performance, but is
still slower than ordinary native code. The loops retain a carried closure
environment and three dependent heap loads; the stack-root reload differs
between these builds. Counters do not support increased cache or branch misses
as the explanation. The precise remaining CPU dependency effect is unresolved.
Final-type checks and conservative struct/array alias metadata did not resolve
the regression in diagnostics. The latter leaves both hot loops' machine code
unchanged after excluding addresses and comments.

Zero-fill elimination helps much less with LTO in this campaign: about 0.9%,
with ranges 4.142660–4.213470 versus 4.110427–4.124797 seconds. The earlier
non-LTO comparison measured 8.0%. These are different build paths; the effect
must not be transferred from one to the other.

The optimization-order pair changes prelink `default<O3>` to raw lowered LLVM
with the same target data layout, followed by the same shared LTO. An initial
raw-bitcode link without a data layout failed and is retained. Successful
treatment builds add only the control's layout; body equivalence was checked
before optimization. Array time gets 4.6% worse, with disjoint ranges; this is
not a fix. Fibonacci improves about 1.5%, also with disjoint ranges, while both
linked workers retain the full recursive calculation.

## Reproduction and limits

The baseline revision is `313cec8752b1fcd3b7a2577f3fc65b96ea1b9dd3`.
Production LTO build code is `90edf1b1e93af6ace69eb907dd65d91021758d5c`;
the provider and harness revision is `835cd98b3e24d75a132d75a5e801ed9edd7c6183`.
[product-lto.patch](product-lto.patch) retains that combined proposal against
the baseline. Apply it with `git apply --unidiff-zero` in an isolated checkout;
it is experimental evidence, not a landed default. The original report retains
the zero-fill prototype; the follow-up archive retains the collector patch,
source snapshots, array controls, and optimization-order build commands.

The driver pins CPU 2, rotates cases and arms, verifies frozen sources and
executables before and after the campaign, and retains every scheduled attempt
without replacement. Timers include guest execution and the complete predicate;
preparation, compilation, process startup and cleanup are excluded. V8 tiering
during guest execution is included. GC diagnostics and stress overrides were
unset for clean timing.

All task-owned heavy workers were held. The backend test coordinator was
suspended after its last worker completed; that worker remained as an unreaped
zombie during timing and was reaped after the coordinator resumed. It did not
consume CPU. Before/after host snapshots retain process states and executable
names; unrelated command arguments are omitted, with hashes of the local raw
snapshots retained. Ambient desktop processes remain, so this is not an
exhaustive assertion of machine-wide quiet.

The production GCbench LTO build also completed directly through the native
supervisor, without the old Node spawn anomaly, in 133.725 seconds. This was a
diagnostic build with concurrent correctness work and saved linker temporaries,
not a controlled compile-time comparison. Large generated guest bodies and
their expansion during shared optimization remain a build-cost concern.

These six workloads do not establish parity across the 57-case corpus. Chez
and Rust were not rerun in this follow-up; their contemporaneous controls
remain in the original report.

[followup.json](followup.json) retains every sample, range, median and ratio.
[followup-evidence.tar.gz](followup-evidence.tar.gz) contains the fixed plans,
driver, all supervised attempt records and outputs, provider/build provenance,
selected complete guest IR and machine code, diagnostic reports and failed
attempts. Its internal `evidence-files.sha256` verifies retained files. As in the
original archive, executables, Cargo targets and full toolchains are excluded;
their hashes and commands identify the original artifacts. The archive helper
specifies the selection. [FOLLOWUP-SHA256SUMS](FOLLOWUP-SHA256SUMS) covers this
additive report and evidence.
