# Benchmarks

The active corpus is [`lofi`](lofi/README.md): all 57 canonical R7RS workloads,
with bare Lofi sources, external Chez controls, Rust implementations, exact
inputs and explicit source/target-validation/measurement status. Lofi is the
only compiler input language. Chibi hosts the compiler; Chez is an independent
comparison system.

The current harness is Scheme and all comparison implementations and native
entries are Rust built with Cargo. The shared runtime is built through
`src/native/runtime/Cargo.toml`; native builds add the collector crate at
`src/native/Cargo.toml`. [Historical sources](history.md) preserve
the earlier C/Python experiment drivers at their exact Git revision.

```sh
chibi-scheme -I bootstrap -I benchmarks benchmarks/lofi/runner.scm inventory
chibi-scheme -I bootstrap -I benchmarks benchmarks/lofi/runner.scm prepare --output /tmp/lofi-check --benchmarks ack
chibi-scheme -I bootstrap -I benchmarks benchmarks/lofi/runner.scm validate --output /tmp/lofi-check
```

Validation runs each workload's six routes in one fresh Chibi process. Scheduler
commands retain raw output, exit status and signals under
`commands/validation-scheduler/`; frozen-driver captures remain under
`frozen-driver/`. If a child terminates, completed route checkpoints remain
visible, unfinished routes become `not-completed`, and the scheduler continues
every remaining selected workload. Validation requires a fresh attempt; a failed
campaign stays intact and a new campaign uses a new output directory.

Preparation captures `SNAIL_NATIVE_CPU`. Leave it unset for the portable native
default or select an explicit compiler CPU name such as `x86-64-v3`. Freezes
reject `native`, whose meaning depends on the build host, and empty values.
This override affects Lofi-native guest code and its Rust runtime/providers;
the independent Rust-native controls keep their own build configuration.

Tail compares the entire output against an independently reversed-line oracle.
Its concatenation uses bounded call arity, avoiding an observed Chibi crash in
the canonical validator. UTF-8 decoding, blank lines, LF termination and
rejection of CR remain explicit; the host's internal failure mechanism is unresolved.

Preparation copies checked-in target sources; it does not elaborate Scheme or
expand macros. The compiler always runs Binaryen. Native builds consume the
retained raw Wasm and verify that their mandatory optimization produces exactly
the V8 program bytes. Earlier freezes supplied already optimized Wasm to the
native helper; the [optimization audit](lofi/evidence/20261015-native-optimization-audit.json)
records those differing effective modules. The
[complete 57-workload report](lofi/evidence/20261015-full57.md) records 326 measured
routes and all 1,956 scheduled processes passing their full predicates at frozen
compiler `8e547bfb`. Both default Ack Wasm failures, 12 unavailable adapted Chez
controls and two primary Mperm Chez timer-name rejections remain visible.
Corrected Mperm's six-way campaign is reported separately. Lofi trails Chez and
Rust on all six geometric-mean comparisons; matching-case counts, observed
ranges and representation differences accompany every comparison.

The [arithmetic, array-access and inlining ablation](results/2026-10-15-arithmetic-array-ablation/README.md)
repeats six unchanged workloads with Chez and Rust controls. It separates
wrapping/IEEE arithmetic, direct native array addressing and Binaryen's guest
inlining policy, retaining every sample and the remaining representation costs.
Those selected workloads do not establish a new whole-suite ranking.

The [UTF-8 string comparison](results/2026-10-16-utf8-strings/README.md) repeats
unchanged `bv2string` against a fresh compiler baseline: 6.1× faster on V8 and
10.1× natively, with original/adapted Chez and Rust controls. It retains all
samples and documents shared-host conditions and the remaining Rust gap.

The [production shared-LTO comparison](results/2026-10-16-production-lto/README.md)
measures six unchanged workloads after self-call environment reuse. All 234
scheduled attempts pass. Shared LTO reduces native time by 35% on Mandelbrot,
40% on Array1, 31% on bytevector-to-string and 9% on GCbench; Fibonacci changes
little. Native still trails V8 on five of those six cases. This selected result
does not replace the full57 baseline.

The [native root-proof comparison](results/2026-10-16-native-proof-ablation/README.md)
retains all 102 attempts across five selected workloads. Proving that recursive
Fibonacci workers cannot collect removes unnecessary root frames and enables
further LLVM optimization: integer and floating Fibonacci become 2.49× and
1.69× as fast as V8. Array1 remains faster; GCbench remains about 2.09× slower.
A separate final-type check experiment has mixed results and remains unlanded.

The [native CPU and allocation experiments](results/2026-10-16-native-cpu-gc/README.md)
retain 138 exploratory attempts and 42 separate successor attempts. The product
x86-64-v3 option reduces Mandelbrot time by 33.6%; the supported allocation
call-site candidate reduces GCbench time by 8.85% against its matched control
but takes 1.95% more time than the earlier inline prototype. The larger GC
budget remains experimental, with pause and memory limits recorded separately.

The [rejected sweep bitmap experiment](results/2026-10-16-native-sweep-probe/README.md)
retains all 18 attempts and its pre-run acceptance rule. Publishing each bitmap
word once gives a 0.97% higher GCbench median with overlapping ranges, so no gain
is established and the prototype remains unlanded.

The later [packet-input comparison](lofi/evidence/20261015-input-packets.md)
measures current input buffering on Cat/WC separately; those medians do not
replace this full-suite freeze. The earlier
[six-case timing report](lofi/evidence/20261015-clean-six.md)
and the following validation checkpoints remain historical evidence.

The [canonical validation checkpoint](lofi/evidence/20261015-existing41.md)
records 53 Lofi Wasm successes and 52 native successes, with GCBench's native
build timeout preserved. At that checkpoint four source ports remained pending. These correctness
runs do not add performance coverage.

The subsequent [native parity check](lofi/evidence/20261015-native-parity.md)
passes GCBench and establishes identical optimized guest programs for nine
cases, bringing canonical native correctness coverage to all 53 programs in that
checkpoint. Earlier failures and measured artifacts remain unchanged.

Subsequent current-source checks pass complete SLaTeX, Dynamic and Scheme
workloads. The [Dynamic/Scheme checkpoint](lofi/evidence/20261015-dynamic-scheme.md)
includes original/adapted Chez, both Rust targets, interpreter probes and source
resource lifecycles. That checkpoint registered 56 sources while Compiler was
pending. It added no clean timing coverage; the completed full57 report above
supersedes its current coverage status without changing the original records.

[`wasm-reference`](wasm-reference/README.md) contains the 57 separate Rust ports
and complete correctness fixtures. Its original Chez controls now come from
the static Lofi corpus rather than a Scheme-source generator.

[`results`](results) retains historical evidence unchanged, including original
raw records, frozen snapshots, failures and measurements made before the Lofi
migration. Those results describe their recorded revisions and do not establish
Lofi behavior or performance. The removed Scheme benchmark drivers remain
available in Git at revision `d5c2d06`; the complete Peval preparation checkpoint
is `0cda43f`. Historical snapshot replay requires its recorded source revision.
