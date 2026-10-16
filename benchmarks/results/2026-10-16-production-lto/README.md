# Shared LTO in the production native build

The native executable already statically linked the Rust runtime. Keeping the
guest as LLVM bitcode until the final link now lets LLVM optimize it together
with that runtime and its providers. [PR284](https://github.com/tsnl/snail-scheme/pull/284)
landed this default as `0e7b57ce`; explicitly saved machine objects still link
as machine objects.

This fresh production comparison finds substantial improvements on Mandelbrot,
arrays, bytevector-to-string conversion and GCbench, with small improvements on
the two Fibonacci workloads. It measures six selected workloads, not the full
57-case suite. Native still takes more time than V8 on five of these six cases.

## Completed measurements

All **234 scheduled attempts passed**: one warmup and five fresh-process samples
for each of 39 available routes. Three unavailable adapted-Chez controls remain
explicit. No attempts were retried or replaced. Cells are median guest seconds;
the ranges below are observed minima and maxima, not confidence intervals.

| Workload | Native control | Shared LTO | V8 | Native time reduction | LTO / V8 |
| --- | ---: | ---: | ---: | ---: | ---: |
| fib | 4.045542 | 4.010619 | 2.165387 | 0.9% | 1.852 |
| fibfp | 0.738634 | 0.728539 | 0.392395 | 1.4% | 1.857 |
| mbrot | 0.705469 | 0.462071 | 0.286089 | 34.5% | 1.615 |
| array1 | 2.141595 | 1.287355 | 3.314976 | 39.9% | 0.388 |
| bv2string | 0.576479 | 0.397563 | 0.370503 | 31.0% | 1.073 |
| gcbench | 2.864248 | 2.615170 | 1.233715 | 8.7% | 2.120 |

| Workload | Native control range | Shared LTO range | V8 range |
| --- | ---: | ---: | ---: |
| fib | 4.041395–4.147878 | 4.008164–4.011748 | 2.161688–2.165952 |
| fibfp | 0.737802–0.745212 | 0.727732–0.731794 | 0.391837–0.415326 |
| mbrot | 0.704687–0.707882 | 0.461246–0.464591 | 0.285413–0.286331 |
| array1 | 2.139015–2.142486 | 1.283409–1.288123 | 3.301949–3.368444 |
| bv2string | 0.575995–0.589967 | 0.395757–0.404074 | 0.369328–0.370823 |
| gcbench | 2.838968–2.874131 | 2.597653–2.622277 | 1.232440–1.241073 |

Array1 is 2.58 times as fast natively as on V8 in this comparison. Bytevector to
string remains 7.3% slower; GCbench takes 2.12 times as long. This does not
identify the fraction spent collecting. Fibonacci's final assembly still
maintains root frames around its recursive worker; this campaign does not
isolate the time attributable to that bookkeeping.

The same rotated schedule includes independent Chez and Rust implementations:

| Workload | Chez original | Chez adapted | Rust / Wasm | Rust / native |
| --- | ---: | ---: | ---: | ---: |
| fib | 1.361274 | unavailable | 0.659360 | 0.731250 |
| fibfp | 0.849850 | unavailable | 0.228452 | 0.231198 |
| mbrot | 2.224233 | 2.222129 | 0.361990 | 0.220001 |
| array1 | 6.841289 | unavailable | 0.316284 | 2.373785 |
| bv2string | 0.465120 | 0.466850 | 0.043917 | 0.026303 |
| gcbench | 0.387996 | 0.836934 | 0.700250 | 0.562545 |

Their source and representation differences remain explicit in the corpus;
these comparisons do not isolate individual language features.
[comparison.json](comparison.json) retains all samples, ranges, unavailable
rows, identities and ratios. Historical experiments remain unchanged, including
the earlier LTO array regression. Those older source/provider configurations
are not interchangeable with this production result, particularly Fibonacci.

## Controlled inputs and retained work

The control is `bb2e90f713ad96b381b1843438c56724620c046e`; the measured candidate
is `f320ef2f1b160ed85b3823696d4a916ab352f0d4`. Both contain the landed self-call
environment improvement. The final rebase to reviewed `4350026f` adds only
the independent Tail validator fix; all 18 generated provider, configuration
and timing-entry files are byte-identical to the measured candidate.

The actual compiler, native lowering and Rust runtime sources match between
arms. Canonical workload sources, inputs, counts and complete predicates also
match. For all six workloads the raw Wasm, mandatory Binaryen output and emitted
LLVM text are byte-identical. Every native route lowers the exact optimized
Wasm used by V8. Counts are respectively 5, 10, 1000, 1, 100 and 1; Array1's one
outer invocation contains all 500 million-element allocation/copy iterations.

The production difference comprises shared LTO and necessary Rust `black_box`
returns in benchmark providers. These preserve the opaque imported input/hide
boundaries after their implementation becomes visible to LLVM. This is a
production integration comparison, not an ablation of a single linker flag.
It uses neither the earlier experiment's machine-code trampolines nor diagnostic
save-temporary flags.

Hook-count correctness and final code review establish different facts. All
normal-validation routes pass, then separate observation-disabled timing
artifacts pass their complete predicates: 33 available routes per arm at each
stage. Final disassembly of the exact measured ELF binaries retains all
configured repetitions and the recursive Fibonacci calls, Mandelbrot recurrence,
array initialization/copy loops, pseudorandom byte filling/conversion/equality
loops and both GCbench tree construction styles. The archive includes that
review, full disassembly and 36 descriptor-to-function relocation checks.

The custom paired driver derives its rows from the candidate plan. For
`native-control` it overrides the command and `arm_dependencies` with the
control ELF; inherited candidate validation/parity fields are not identities
of the executed control ELF. The independent control freeze supplies its own
successful validation, parity and build records. Both audits check the actual
command against that control identity. `artifact_identities.arms.control` in
the JSON records the executed control hashes explicitly.

## Protocol and evidence

Runs use CPU 2 on the recorded Core Ultra 7 270K Plus host. Case order rotates
by round, and arm order rotates within each case. The guest monotonic timer
includes the repeated workload and complete final predicate; setup, process
startup, result formatting and cleanup are outside it. V8 tiering during the
workload is included. Rust 1.95, LLVM 22, Binaryen 132, Node 24.19 and Chez 10.4.1
identities and the complete execution environment are retained.

All task-owned compilation, correctness and profiling jobs were idle. A separate
observer took 144 five-second process-name snapshots. No competing compiler or
profiler jobs appeared; ordinary desktop activity remained. This is not an
external-session quiet attestation or an exhaustive machine-wide idle claim.
The observer records process-lifetime CPU averages, not interval CPU accounting.

The independent audits verify every scheduled ID and order, every command,
successful terminal status and descendant cleanup, output/predicate evidence,
all five samples per eligible row, and recomputed statistics. The final driver
also re-verifies frozen inputs and artifacts before reporting completion.

[evidence.tar.gz](evidence.tar.gz) includes the preparation and measurement plans,
source snapshots, commands, stdout/stderr, process records, native binaries and
Wasm, generated LLVM, complete disassembly, work review and host observations.
Its `evidence-files.sha256` covers 6,259 retained files. Caches, toolchain binaries,
repeated working-directory copies and older evidence archives are omitted;
their original identities remain in the manifests. Six unrelated historical
source records have environment entries filtered by an explicit allowlist,
with original hashes recorded; measured process records remain byte-identical.
[SHA256SUMS](SHA256SUMS) covers the published report, JSON and archive.

For reproduction, the archive's `preparation/prepare-control.sh` and
`prepare-candidate.sh` show the exact commands and explicit Chibi include paths.
Check out the two recorded revisions in isolated directories and choose fresh
output paths. After preparation and validation, `configure.scm` selects both
native arms and external controls, and `measurement/driver.scm` executes the
fixed schedule. Set `SNAIL_NATIVE_SUPERVISOR` to the candidate freeze's retained
supervisor before invoking the driver. Coordinate the measurement window;
never reuse or replace failed campaign output directories.
