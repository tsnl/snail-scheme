# Initialized captures and calls through structured operators

The two compiler changes together reduce workload time by 14.0% on quicksort,
52.5% on graphs, 6.7% on mperm and 55.1% on simplex. Quicksort and simplex beat
both Chez controls. Rust/Wasm wins all four workloads in this batch; these
measurements do not establish general parity with Rust.

All times below are seconds, medians of seven retained fresh-process runs.
The four compiler configurations use identical benchmark sources, inputs,
hosts and original repetition counts. Lower is better.

| Original workload | Baseline | Initialized captures | Structured calls | Both | Original Chez | Adapted source on Chez | Rust/Wasm |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| quicksort, 2,500 × 10,000 values | 1.386546 | 1.233080 | 1.387339 | 1.192354 | 1.772481 | 1.749762 | 0.953066 |
| graphs, 3 × 7 vertices | 3.841950 | 2.827844 | 2.476089 | 1.824846 | 0.766352 | 0.785504 | 0.588629 |
| mperm, M:N:K:L = 20:10:2:1 | 17.554164 | 17.505192 | 16.336902 | 16.379563 | 4.586732 | 4.589012 | 4.519188 |
| simplex, 1,000,000 tableaus | 0.952649 | 0.864698 | 0.652116 | 0.427649 | 0.718772 | 0.866274 | 0.269081 |

| Original workload | Both / adapted Chez | Both / Rust |
| --- | ---: | ---: |
| quicksort | 0.681× | 1.251× |
| graphs | 2.323× | 3.100× |
| mperm | 3.569× | 3.624× |
| simplex | 0.494× | 1.589× |

The baseline compiler is `efbb151`; initialized captures are `192d810`,
structured calls alone are `1d745e6`, and their combination is `7ff18c0`.
These are experimental source checkpoints; stack publication can give the
same code different commit IDs. [Compiler identities](compiler-identities.json)
and [artifact identities and sizes](artifact-structure.json) identify the bytes.
[Publication verification](publication.json) checks the draft stack against the
measured combined compiler, including its strict contracts.

Initialized nonrecursive `let` values and parameters can be captured directly.
A closure created in a let body cannot precede successful initialization of
that let's bindings. Recursive definitions and aliases retain their own
readiness events. Copying a Ref or vector reference preserves shared identity;
it does not copy its contents or make an uninitialized alias readable.

Immediate invocation also propagates through a let's body or a block's final
expression. The emitter first evaluates and holds arguments, then evaluates
operator initializers and prefixes, performs the original readiness check and
invokes the known code. Intermediate value uses still require values, escaping
closures survive, and proper tail calls remain tail calls. Conditional and
conversion operators remain conservative. A returned anonymous lambda may
still construct an environment and closure even when its known code is invoked
directly. There is no new IR layer or frontend change.

Independent behavioral explanations and informed critique preceded these
bounded changes. All 264 capture contracts pass; the standalone structured
change passes 267 contracts plus its final escaping-fixture recheck. The final
combined source passes all 271 contracts. Executable cases run raw and optimized
Wasm, and rejected programs check their diagnostics. All 20 real-provider
external-boundary cases, `make test` and `make check` pass per variant. Each
configuration also passes all four canonical workloads under raw and optimized
Node execution. [Review](review.json) records scope, semantic invariants,
deliberate function-size exceptions and corrected test-fixture development.

Separate heavy diagnostics count completed construction instructions after
setup. They are not clean timings or native allocation counts:

| Workload | Baseline | Initialized captures | Structured calls | Both |
| --- | ---: | ---: | ---: | ---: |
| graphs | 1,471,284,465 | 984,108,024 | 785,162,469 | 491,303,784 |
| mperm | 437,134,807 | 437,134,766 | 269,858,040 | 269,858,040 |

The observed reductions overlap. In mperm, 269,858,000 of the remaining
constructor completions are the source program's required inner/outer list
nodes; the remaining 40 construct its explicit Ref cells. Removing nearly all
compiler-added construction does not remove that list workload. The ordinary
runtime improves about 7%, far less than the 38% reduction in instrumented
constructor completions. The structured and combined mperm sample ranges
overlap, so this batch does not establish an additional capture-change benefit
there. Smaller Wasm files also do not predict runtime: structured calls alone
shrink quicksort while leaving its observed runtime essentially unchanged.

The observer inserts typed identity calls and scalar counters after constructors,
adds no persistent reference roots, and preserves the original instruction
forms when erased. Actual Node probes cover operand effects, constructor/cast
traps, a nullable call and readiness. Separate recurrence checks validate count
definitions. These helpers can still change JIT optimization, scalar replacement
and collection behavior. The archive retains the observer, raw counters,
baseline profiles, disassembly, recurrence checks and all four configurations.

After clean timing finished, a new mperm profile used the ordinary combined
module. [CPU samples](mperm-cpu-summary.json) classify 14,464 of 15,539 samples
as garbage collection: 93.1%, or 90.2% when weighted by sample deltas. A separate
[GC trace](mperm-gc-summary.json) records 258 scavenges and five major collections
between benchmark markers. Printed pause fields sum to 14,757.4 ms in a
16,157.3 ms diagnostic window, about 91.3%; decimal rounding alone gives a
14,744.25–14,770.55 ms sum interval. These are profiler classifications and
reported pause durations, not exact total collector CPU or clean elapsed samples.

Earlier uninstrumented V8 disassembly in the archived baseline evidence found
32-byte inner and outer list nodes, while a rooted Chez pair probe found
16-byte pairs. This Node build has pointer compression disabled. The current
Wasm preserves those two-field list layouts, but the new profile does not itself
remeasure native layout. Memory footprint and collector policy are concrete
next experiments; the present evidence does not isolate their individual costs.

Each workload has one discarded seven-system round and seven retained cyclic
rotations, so every system occupies every ordinal position once. This balances
position, not predecessor effects or all temporal drift. All 224 executions
pass their predicates, and every recorded artifact/tool identity matches before
and after its window. Runs are sequential on logical CPU 5 of an Intel Core
Ultra 7 270K Plus, with other agents holding build/test work. Node 24.19.0 uses
default V8 tiering and no profiling, heap, stack or `NODE_OPTIONS` overrides in
the clean runs. Discarding fresh processes' first round does not remove tiering
from later fresh processes. Initialization and input preparation are outside
workload clocks; original repetitions and the final predicate remain inside.
Mperm's initial queue fill and quicksort's RNG/vector preparation stay untimed.
Process wall time is recorded separately.

Rust references retain the algorithm, original full inputs, repetition counts
and final predicate but use idiomatic linear-memory representations. Graphs
uses vectors and linked lists with shared Rc edges; mperm uses Rc inner tails
and Box outer rows with immediate reclamation; quicksort uses a packed I64
vector; simplex uses F64 vectors and native-width indices. Rust's opacity
barriers also differ from Scheme's host calls. In particular, simplex makes its
fresh full tableau opaque before solving. The strict graphs optimizer can
legally remove unused result payloads, as disclosed in its earlier report.
These are source-program comparisons, not equal-allocation experiments or an
isolated ranking of compiler quality.

[Rust artifacts and semantic contracts](rust-handoff.json) and
[build provenance](rust-build-provenance.json) preserve exact artifact, source,
input and host hashes. Recorded Rust is 1.95.0, targeting `wasm32-wasip1`;
frozen Cargo manifests set release optimization level 3, LTO, one codegen unit
and aborting panics. Three historical validation records lack verbose rustc
arguments and a complete inherited build environment; the provenance keeps
that distinction explicit instead of assuming absent overrides.

Raw [quicksort](clean-quicksort.json), [graphs](clean-graphs.json),
[mperm](clean-mperm.json) and [simplex](clean-simplex.json) observations include
commands, input, stdout, stderr, process duration and retained status.
[Summary](summary.json) includes every sample and range, and
[window metadata](clean-window.json) records the protocol and holds. Simplex's
separate [preparation report](../2026-10-13-strict-simplex/README.md) documents
complete-output checks and a deliberately preserved upstream equality-case
discrepancy. This report adds simplex to historical measured strict coverage:
24 of 57 workloads, with 23 paired Chez comparisons. It is not a new full-suite
measurement on this compiler.

Restore and verify the regular-file archive without executing benchmarks:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/call-capture-replay \
  --report benchmarks/results/2026-10-13-strict-call-captures
```

After arranging a quiet CPU window, reproduce one full seven-system comparison:

```sh
python3 benchmarks/results/2026-10-13-strict-call-captures/reproduce.py \
  /tmp/call-capture-replay quicksort /tmp/repeated-quicksort.json
```

The reproduction driver relocates archived inputs/programs through the recorded
path map, verifies their hashes and the external tools, retains failed
observations, and repeats the original schedule and result contracts.
[Replay verification](replay-check.json) records independent archive restoration
and bounded executions from the restored artifacts.
