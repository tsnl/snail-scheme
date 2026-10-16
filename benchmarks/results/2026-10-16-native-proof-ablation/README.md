# Native collection effects and final-type checks

Proving that a function cannot reach managed collection removes unnecessary
root frames. In this experiment, that makes integer Fibonacci 4.61 times as fast
natively, and floating Fibonacci 3.15 times as fast. They become respectively
2.49 and 1.69 times as fast as the matching V8 runs.
[PR287](https://github.com/tsnl/snail-scheme/pull/287) landed the production change
as `506b5f96`. Its generated LLVM matches the four measured candidates exactly.

A separate experiment preserves Wasm's declared final-type information when
choosing runtime reference tests. It improves bytevector-to-string conversion
but slightly regresses GCbench in its matched build pair. That change remains
unlanded. Neither experiment changes the Rust runtime or the optimized Wasm.

## Completed measurements

All **102 scheduled attempts passed**: one warmup and five fresh-process samples
for each of 17 routes. No attempts were retried or replaced. These are five
selected workloads and two separate changes, not a new full57 result. There are
no new Chez or Rust comparison runs in this campaign.

The root-frame experiment uses the production shared-LTO executable as its
control. Cells are median guest seconds.

| Workload | Native control | No unnecessary root frames | V8 | Less native time | Native / V8 |
| --- | ---: | ---: | ---: | ---: | ---: |
| fib | 4.010839 | 0.870957 | 2.166781 | 78.3% | 0.402 |
| fibfp | 0.728416 | 0.231444 | 0.391589 | 68.2% | 0.591 |
| array1 | 1.288965 | 1.260864 | 3.364001 | 2.2% | 0.375 |
| gcbench | 2.608948 | 2.587043 | 1.236145 | 0.8% | 2.093 |

| Workload | Control range | No-root-frame range | V8 range |
| --- | ---: | ---: | ---: |
| fib | 4.000430–4.035059 | 0.865774–0.894916 | 2.158309–2.168736 |
| fibfp | 0.727734–0.728732 | 0.231408–0.231525 | 0.391464–0.393052 |
| array1 | 1.286917–1.291145 | 1.254731–1.262626 | 3.296736–3.426504 |
| gcbench | 2.585508–2.619549 | 2.575827–2.608789 | 1.229681–1.244184 |

Ranges are observed minima and maxima, not confidence intervals. GCbench's
ranges overlap: its small median difference does not establish a reliable gain.
It remains more than twice as slow as V8.

The final-type experiment uses separately built controls. A final target has
no proper subtypes, so its subtype test can use canonical identity equality.
Open targets, nullability and abstract reference categories retain their rules.

| Workload | Matched control | Final-type checks | V8 | Native change |
| --- | ---: | ---: | ---: | ---: |
| bv2string | 0.407022 | 0.381674 | 0.369959 | 6.2% less time |
| gcbench | 2.557947 | 2.592181 | 1.236145 | 1.3% more time |

| Workload | Matched control range | Final-type range |
| --- | ---: | ---: |
| bv2string | 0.404623–0.412830 | 0.381313–0.385234 |
| gcbench | 2.546990–2.562451 | 2.575081–2.605293 |

The two GCbench control builds have different timings despite equivalent LLVM
and workload inputs. Compare each treatment with its own matched control. The
small finality regression is a result for these binaries; it does not establish
that the underlying identity-test operation is intrinsically slower. We retain
the mixed result and hold the change instead of reporting only its win.

## What the root proof changes

The native lowering records direct and tail-call edges. Allocation, imports,
dynamic calls and unfamiliar operations may collect; that effect propagates to
callers. A recursive group with no path to collection needs no published GC
frame. Its reference locals still receive ordinary storage and initialization.
Wrappers and module initialization remain conservative, and stress injection
keeps every function framed because those added safepoints can collect.

The current Fibonacci worker carries a closure reference through recursive
calls. The control publishes it conservatively even though the recursive worker
does no allocation. Removing that requirement also lets LLVM eliminate the
unused environment argument and improve the recursive code. The measured gain
includes these downstream optimizations; it is not an isolated measurement of
the frame push/pop instructions.

The proof uses the native runtime's synchronous, nonmoving collection contract.
Helpers classified as noncollecting must neither collect managed objects nor
invoke guest code. This maintenance obligation is documented beside the
allowlist. No per-callsite liveness analysis or collector redesign is introduced.

## Unchanged work and correctness

Both experiments start from `f320ef2f`, the measured production shared-LTO
candidate in the [preceding report](../2026-10-16-production-lto/README.md).
The root prototype is retained as a patch and exact source; the finality
prototype is local commit `7346622e496509681ed5f2c2e39c344708ccf7ca`.
All canonical source, input, count, full predicates, provider and timing-entry
bytes match that freeze. Every native candidate lowers the exact Binaryen output
run by V8. Timing artifacts disable observation counters and GC statistics.

Final-machine-code review binds live function descriptors to their relocations
and verifies all five integer Fibonacci calculations, all ten floating Fibonacci
calculations, all 500 million-element array initialization/copy iterations, and
both GCbench construction styles and depth loops. The archive retains full
disassembly and that review. Allocation-request diagnostics separately confirm
identical Array1 and GCbench counts and bytes. Instrumented seconds are not used
in the tables. For finality, the only emitted LLVM differences are 12 and 17
exact-test flags respectively; allocation counts and complete predicates match.

Production root-proof validation passes compiler checks, 61 Rust tests and 255
native checked commands, including forced collection, tail stress and expected
traps. Independent package execution exercises bitcode, genuine saved ELF
objects and linked V8. An import-only holder keeps the sole managed reference
across collection: a finalizer proves it survives until return. A separate
mutation control that removes that holder's registration fails this assertion.
All four measured LLVM outputs and optimized Wasm hashes reproduce exactly from
the reviewed production code. Tests do not count as new performance samples.

## Protocol and retained evidence

The fixed schedule rotates cases each round and arms within each case on CPU 2
of the recorded Core Ultra 7 270K Plus host. The guest timer includes the repeated
workload and complete final predicate. Setup, process startup, result formatting
and cleanup remain outside it; V8 tiering during the workload remains inside.
Tool identities and the environment are inherited from the frozen production
campaign. Native code uses the generic portable target in all these runs.

All task-owned build, test, profiling, archive and Git jobs were idle during
measurement. Seventy-six five-second process-name snapshots showed no competing
named compiler or profiler job; ordinary desktop activity remained. This is
neither an external-session quiet attestation nor an exhaustive machine-wide
idle claim. Snapshot CPU percentages are process-lifetime averages.

[comparison.json](comparison.json) retains every sample, range, ratio, artifact
identity and the production reproduction check. The audit verifies all 102
scheduled IDs and their order, exact commands, successful terminal status and
descendant cleanup, source/input/output hashes, scalar predicates, guest timers
and independently recomputed statistics. The driver also verifies frozen inputs
and artifacts before and after execution.

The paired driver copies a production row and overrides its command and
`arm_dependencies`. Inherited validation/parity fields identify the source row,
not the substituted executable. The separate prototype manifests and actual
command hashes identify each executed ELF; the report never substitutes the
inherited `native_parity` identity for them.
Prototype preparation manifests retain their original “not measured” status;
the separate completed measurement and audit records establish the timing results.

[evidence.tar.gz](evidence.tar.gz) retains source patches, exact native/Wasm
artifacts, generated LLVM, preparation failures, correctness and instrumented
records, complete disassembly, all timing process records, observer output and
the Scheme configuration/driver/audit scripts. Repeated workload-directory
copies, caches, installed toolchains and earlier archives are omitted; their
identities remain in the manifests. Interrupted setup traces retain their
original incomplete JSON bytes. Published execution records remain byte-identical
to the originals. The internal file manifest and [SHA256SUMS](SHA256SUMS) bind the
retained evidence and this report.

To reproduce, start with the preceding report's frozen production setup,
apply the retained prototype patch, and rebuild the recorded raw guests with
their unchanged provider/entry/configuration files. Use fresh output paths.
`configure-proof-probes.scm` constructs the explicit arms; `measurement/driver.scm`
runs the fixed schedule. Set `SNAIL_NATIVE_SUPERVISOR` to the retained production
supervisor before invoking Chibi with `-I wasm-native/scheme -I benchmarks`.
Coordinate a quiet window and retain every attempt, including failures.
