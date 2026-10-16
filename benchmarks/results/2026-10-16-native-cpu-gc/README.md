# Native CPU selection and allocation experiments

The implemented x86-64-v3 CPU option reduces Mandelbrot's median native time by
**33.6%** against its default build. The supported allocation call-site
candidate reduces GCbench time by **8.85%** against its matched control, while
taking **1.95% more time** than the earlier compiler-dependent inline prototype.
Native still takes 7.1% more time than V8 on Mandelbrot and 89.1% more on GCbench.

Two separate campaigns retain every attempt: **138 exploratory attempts**
across 23 routes, followed by **42 successor attempts** across seven routes.
All passed, with one warmup and five fresh-process samples per route and no
retries or replacements. The successor campaign uses the default GC budget;
the larger budget remains an experiment confined to the first campaign.
Native builds include the
[landed root proof](../2026-10-16-native-proof-ablation/README.md) at
`506b5f9649b9a28260af70e472ad63a48b01994b`. Workloads, inputs, repetition counts,
complete predicates, providers, timing entries and optimized Wasm remain the
frozen `f320ef2f` inputs from the
[production shared-LTO report](../2026-10-16-production-lto/README.md).
These selected campaigns add no full57 ranking or new Chez/Rust comparison runs.

## Product CPU option and supported allocation call-site successor

These are fresh measurements from the second campaign. The CPU pair uses the
actual product build option, while the allocation candidate replaces the
disputed exported-function annotation with a documented LLVM call-site
`alwaysinline` attribute and a private Rust allocation hint. Its exported
allocation ABI and collector logic remain unchanged.

| Workload and route | Median seconds | Observed range |
| --- | ---: | ---: |
| mbrot, product default | 0.461124 | 0.460228–0.462764 |
| mbrot, product x86-64-v3 | 0.306057 | 0.305844–0.306424 |
| mbrot, V8 | 0.285843 | 0.285232–0.286047 |
| gcbench, matched control | 2.561357 | 2.554510–2.568284 |
| gcbench, earlier inline prototype | 2.290124 | 2.279853–2.298161 |
| gcbench, supported call-site candidate | 2.334756 | 2.326457–2.355566 |
| gcbench, V8 | 1.234940 | 1.231356–1.239554 |

The call-site candidate uses **8.85% less time** than the control but **1.95%
more time** than the earlier prototype. The difference is retained rather than
carrying forward the prototype's larger gain. Both comparisons use these fresh
default-budget runs of the exact retained control and prototype ELFs. No larger
budget or CPU-selection/allocation combination was measured for the successor.

The CPU option landed in [PR #289](https://github.com/tsnl/snail-scheme/pull/289)
at `e66484f733860f4d806ea1f1f7930cd84051056e`. The measured pair uses
`source.patch`; the final `source-v2.patch` changes failed-build evidence, its
regression test and documentation. The retained `source-v1-to-v2.diff` shows no
change to successful code generation or command flags. The allocation numbers
belong to the retained candidate ELF, not to a later production build.

The allocation build is warning-free. Its retained code comparison shows an
outlined allocation call on the dynamic-size array path and stack-layout
differences from the earlier prototype, while fixed struct allocations remain
inline. This identifies a code-shape difference, without isolating its causal
contribution to the 1.95% timing difference. Fixed-size zero fills remain;
there is no dead-zero-store elimination claim.

## Exploratory CPU selection

Each generic/x86-64-v3 pair is newly built from the same source. Generic retains
the portable production target; x86-64-v3 is an explicit build choice. All
cells below are median guest seconds. The last column compares x86-64-v3 with
its generic control.

| Workload | Generic native | x86-64-v3 native | V8 | Native change |
| --- | ---: | ---: | ---: | ---: |
| fib | 0.877756 | 0.881257 | 2.163823 | 0.4% more time |
| fibfp | 0.228125 | 0.231481 | 0.391707 | 1.5% more time |
| mbrot | 0.462401 | 0.306907 | 0.285692 | 33.6% less time |
| array1 | 1.260208 | 1.245557 | 3.272145 | 1.2% less time |
| bv2string | 0.380501 | 0.381218 | 0.370098 | 0.2% more time |
| gcbench | 2.611492 | 2.509722 | 1.239817 | 3.9% less time |

| Workload | Generic range | x86-64-v3 range | V8 range |
| --- | ---: | ---: | ---: |
| fib | 0.867840–0.884988 | 0.877528–0.889151 | 2.160789–2.171258 |
| fibfp | 0.201720–0.231797 | 0.231358–0.231545 | 0.390982–0.392275 |
| mbrot | 0.460617–0.462732 | 0.305610–0.311847 | 0.285519–0.286229 |
| array1 | 1.257959–1.266036 | 1.243044–1.247027 | 3.256492–3.333332 |
| bv2string | 0.379129–0.383897 | 0.378983–0.383013 | 0.369437–0.371358 |
| gcbench | 2.594885–2.625146 | 2.505658–2.535194 | 1.234370–1.246526 |

Ranges are observed minima and maxima, not confidence intervals. Fibonacci and
bytevector-to-string ranges overlap; their small median differences do not
establish reliable gains or regressions. The unusually low generic fibfp
sample remains included. These results do not support a universal CPU speedup.

An additional Mandelbrot build targets `arrowlake-s`: **0.294387 s**, range
0.293798–0.294936. It uses 36.3% less time than generic and 4.1% less than
x86-64-v3. It remains 3.0% slower than V8; x86-64-v3 remains 7.4% slower.
No other workload has an arrowlake-s measurement in this campaign.

The prototype selects the CPU through external wrappers: LLVM optimization
receives `-mcpu`, and the shared Rust fat-LTO link receives `-C target-cpu`.
Each mode has its own Cargo cache. The saved-object wrapper is configured
consistently, but this experiment executes the bitcode/shared-LTO route.
These exploratory measurements predate the product CPU option measured above;
they do not use an implicit host-specific default.

Generated guest LLVM is byte-identical across CPU modes for each workload.
Final assembly retains the repetition drivers and kernel loops. Mandelbrot's
generic build packs squares into SSE lanes; v3 and arrowlake-s use scalar AVX,
with arrowlake-s also unrolling the recurrence twice. Saved final-LTO LLVM
retains separate floating multiply/add/subtract operations, with no fast-math
flags or guest FMA instructions. The speedup includes these code-generation
decisions; it does not isolate an instruction-set feature.

## Exploratory runtime inlining and GC budget

This separate GCbench pair uses two `inline(always)` attributes, on
`native_alloc` and `Collector::allocate`, without changing collector logic.
Both arms use the portable target. Each is also measured with the recorded
environment setting `SNAIL_GC_MIN_BYTES=268435456` (256 MiB).

| Runtime | Default budget | 256 MiB minimum budget | Budget change |
| --- | ---: | ---: | ---: |
| Matched control | 2.552619 | 1.868914 | 26.8% less time |
| Inline prototype | 2.290494 | 1.602615 | 30.0% less time |

| Runtime | Default range | 256 MiB range |
| --- | ---: | ---: |
| Matched control | 2.548646–2.553031 | 1.862520–1.881606 |
| Inline prototype | 2.280706–2.298155 | 1.591958–1.614642 |

Inlining reduces median time by 10.3% under the default budget and 14.2% with
the larger minimum budget. Combining the two experiments uses 37.2% less time
than this pair's default control, while remaining 29.3% slower than V8's
1.239817 s. No CPU-selection/runtime-inlining combination was measured.

The CPU-generic GCbench control and the inline-pair control differ by about 2%
despite identical guest LLVM and workload inputs. They are independent builds
with different ELF identities. Each treatment is compared with its own control;
these controls are not interchangeable.

The recorded Rust compiler warns that an inline attribute on an externally
exported function is ignored. In this build its LLVM nevertheless carries
`alwaysinline`, and final machine code inlines the allocation boundary. That
compiler-dependent prototype is the artifact measured in this first campaign.
The supported call-site implementation has its own separate comparison above.

Earlier, separate instrumented runs on the original `f320ef2f` production ELF
retain the following GCbench resource diagnostics. They are **not measurements
of the new root-proof or inline-pair binaries**, and their seconds do not enter
any performance table above.

| Minimum allocation budget | Collections | Maximum RSS, KiB | Mean recorded mark+sweep, ms |
| --- | ---: | ---: | ---: |
| Default | 79 | 268380 | 19.20 |
| 128 MiB | 54 | 268580 | 20.00 |
| 256 MiB | 38 | 268380 | 19.80 |

Each diagnostic preserves 226,122,905 allocation requests and 4,328,130,064
requested bytes. RSS covers the supervisor and its reaped descendant subtree;
it is not a managed-heap liveness measure. The mean is aggregate mark+sweep
time divided by collection count, not a complete pause measurement. Maximum
pauses and their distribution remain unknown. The changed collection schedule
also changes transient liveness. The budget remains experimental, with no
recommendation to change the default policy.

The archive also retains the earlier sampled profiles, raw PCs, executable
maps and symbolization. The initial invalid file-offset decoder result remains
marked invalid beside the corrected load-address analysis. These diagnostics
motivated the experiments and are separate from uninstrumented timing.

## Correctness and measurement protocol

All 13 CPU binaries pass the unchanged canonical final predicate. The v3
strict-semantics run also passes forced collection, 56 conversion-boundary
inputs and 29 expected traps. Its main native runner exercises pure and
allocating recursive groups and dynamic-call collection effects from the
landed root-proof fixtures. The
original two-attribute runtime prototype passes 61 Rust tests and 255 linked
native command checks at `82cab01`; the fresh pair at `506b5f96` then passes
the canonical GCbench predicate before all scheduled timing attempts.

The actual product CPU change passes the recorded Scheme checks, build suite,
v3 native suite, and default/v3 standalone execution with forced collection,
traps and linked V8 parity. CPU attributes and imported-object behavior have
separate checks. The call-site candidate passes 61 Rust tests and the retained
small native fixture under forced collection, including dynamic arrays, zeroed
reuse and live roots. Its canonical GCbench predicate passes before timing.
Preparation failures and their subsequent fresh successful attempts remain
visible. These validation runs add no performance samples.

Every native build consumes the frozen raw guest and reruns mandatory
Binaryen; its optimized bytes exactly match the Wasm executed by V8. Providers
retain opaque input boundaries and observation counters are disabled. The
fixed schedule rotates workloads and arms, pinning each fresh process to CPU 2
on the recorded Core Ultra 7 270K Plus host. One warmup precedes five samples
per route. The guest timer includes repeated work and the complete final
predicate; setup, startup, result formatting and final cleanup are excluded.
V8 tiering during the workload remains inside that interval.

All task-owned build, correctness, profiling, archive and Git jobs were idle
during both measurement windows. Independent review of the 80 exploratory and
34 successor process-name snapshots found no competing named compiler or
profiler; ordinary desktop activity remained. Snapshots were taken every five
seconds, and CPU percentages are process-lifetime averages. There is no
external-session quiet attestation or exhaustive claim that the machine was
idle. Both drivers and observers were reaped after their campaigns.

## Retained evidence and reproduction

[comparison.json](comparison.json) retains every sample, range, ratio, actual
command, executable dependency hash and audit result. The audit verifies all
138 and 42 scheduled IDs in order, successful terminal status and descendant cleanup,
actual command identities, input/output hashes, predicates, guest timers and
independently recomputed statistics. The driver also checks frozen inputs and
artifacts before and after execution.

The driver inherits a frozen production row and replaces its command and
`arm_dependencies`. Inherited validation and `native_parity` fields describe
the source row. The separate CPU/runtime manifests and actual command hashes
identify the executed ELFs, including both budget routes for each runtime ELF.

[evidence.tar.gz](evidence.tar.gz) retains the exploratory campaign and common
frozen inputs; [successor-evidence.tar.gz](successor-evidence.tar.gz) retains the
separate product/call-site campaign. Together they contain exact binaries,
source snapshots and patches, Wasm and LLVM, final assembly, preparation commands
and failures, correctness checks, memory/profile diagnostics, observer output
and Scheme configuration/driver/audit scripts. Preparation manifests retain their original
premeasurement status wording. `archive-paths.json` maps archive members back
to their original paths. Safe execution records retain their original bytes;
any preparation-environment filtering is listed with original hashes in
`environment-filtering.json`. Caches, installed toolchains and repeated run
directories are omitted; their relevant identities remain in the manifests.
Every retained timing record is byte-identical to its local original. Internal
file manifests and [SHA256SUMS](SHA256SUMS) bind the retained files.

To reproduce, use the frozen production setup and the retained root-proof
source, raw guests, providers, entries and configurations. Recreate the explicit
CPU wrappers or the two-attribute runtime patch using fresh output paths and
separate caches. `configure-cpu-gc.scm` constructs the named arms;
`measurement/driver.scm` runs the fixed schedule. Set `SNAIL_NATIVE_SUPERVISOR`
to the recorded supervisor before invoking Chibi with
`-I wasm-native/scheme -I benchmarks`. Set the minimum budget only for its named
arms, coordinate a quiet window, and retain every attempt including failures.
For the successor campaign, apply its separate retained source patches and use
the product CPU option with fresh outputs and caches;
`configure-product-probes.scm` constructs the seven named arms. The successor
archive retains its own unmodified measurement driver and complete schedule.
