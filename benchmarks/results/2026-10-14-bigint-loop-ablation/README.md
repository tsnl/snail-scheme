# Bigint loop ablation: no useful workload gain

Replacing one hot Integer-library self-tail call with a local loop **does not
improve these complete workloads usefully**. Against matching assembly controls,
Pi takes **1.0125× time** for the raw backedge and **1.0270×** after equal extra
optimization. Chudnovsky takes **1.0108×** and **0.99558×**, respectively; its
small optimized difference has overlapping observed ranges. All **110 planned
processes pass** the complete original results. This negative experiment does
not justify shipping a generic compiler loop transformation.

## Matched controls and complete measurements

Each row has ten retained fresh processes per workload, following one
predetermined discard. All observations remain, including every discarded
result; ranges are observed minima/maxima, not confidence intervals.

| Frozen Wasm variant | Pi median (s) | Pi range (s) | Chudnovsky median (s) | Chudnovsky range (s) |
| --- | ---: | --- | ---: | --- |
| Original production artifact | 2.233812 | 2.230040–2.253191 | 0.715319 | 0.711949–0.722383 |
| Unchanged WAT, assembled again | 2.262956 | 2.237449–2.274897 | 0.716730 | 0.713778–0.725082 |
| Assembly control, extra Binaryen optimization | 2.215099 | 2.198285–2.235605 | 0.720549 | 0.710723–0.727147 |
| One self-tail call replaced by backedge | 2.291257 | 2.287705–2.294784 | 0.724467 | 0.722570–0.729935 |
| Backedge, same extra Binaryen optimization | 2.274967 | 2.269172–2.279315 | 0.717366 | 0.715502–0.720401 |

Pi's raw and optimized backedge variants take **1.25% and 2.70% more time**
than their matching roundtrip controls. Chudnovsky's raw variant takes **1.08%
more time**; the optimized variant takes **0.44% less time**. Relative to the
original frozen production binaries, the optimized backedges take 1.0184× and
1.0029× time. Full-precision medians, ranges and all five control ratios are in
[`independent-review.json`](independent-review.json).

The initial four-way preparation compared original, reoptimized original,
backedge and reoptimized backedge. Its source, plans and validation records
remain under `lineage/` in the archive. It was diagnostic preparation and was
never the clean timing population. The final five-way preparation adds an
unchanged WAT assembly roundtrip, then optimizes that assembled control and
the backedge equally. This separates the changed loop from reassembly and
an extra optimizer pass. Both extra passes use the unchanged production flags:
`-O3 --closed-world --always-inline-max-function-size=40 --converge`.

## Hot loop and the deliberately narrow change

The unchanged [Integer library](../../../src/snail/integer.sld#L225) has SHA-256
`6954e2b5414e3baf093f6bb11f9a2ebe42d60bff0c1fd2900a979f15395da8cc`.
The original production `function85` is the `subtract-product!` inner loop
in normalized long division. It traverses divisor limbs, multiplies by the
trial quotient digit, subtracts the low product limb, writes the private
dividend buffer, and carries the high product plus any borrow forward.
The source's limb, carry, readiness and bounds contracts remain.

Separate Node CPU profiles place **71.24% of Pi** and **46.07% of
Chudnovsky** sample weight in this function. They aggregate exclusive samples
by function and use each recorded time delta as its weight. They cover the
**whole process**, including initialization and output, and were collected
with other concurrent work. Their instrumented durations are excluded from
the timing comparisons; the weights locate a hot function without attributing
time to individual instructions or collector behavior.

The archived `transform.py` targets only this exact frozen function. Seven
arguments remain unchanged. It evaluates the next index and carry into two
scalar temporaries before assigning either loop parameter, preserving parallel
argument updates, then branches within the function. One self-tail call changes;
arithmetic, initialization/readiness guards, array checks and stores remain.
It does not alter Scheme source, precision, repetitions or the bigint algorithm.

The [original excerpts and source identities](original-code/sources.json),
verified byte-for-byte against the existing control archives' full code dumps,
show TurboFan performing frame teardown and
a jump for the original self-tail call on each limb. Signed division by the
constant `2^30` was already lowered to shifts/corrections. The later captures
from the exact measured probes confirm the raw `function85` has an actual
intrafunction backedge: **892 instruction bytes**, versus the original
**584**. The extra optimizer pass inlines that loop into `function88`, whose
TurboFan body has **1,960 instruction bytes**. Raw-loop code retains spills,
readiness/index/bounds checks and a loop-header stack-limit poll. These static
observations establish emitted behavior; they do not assign the regressions
to one mechanism. Both Liftoff and TurboFan captures remain in the archive.
The new captures ran after the clean campaign, in a separate diagnostic
session, with code-printing flags and unchanged default tiering.

## Full work, provenance and coordinated execution

Pi keeps all **100 repetitions**, all three original algorithms, ten precision
rows from 50 through 500 digits and both rounding-difference columns.
Chudnovsky keeps all **1,000 repetitions**, complete binary splitting and ten
exact outputs. Module initialization, input/expected parsing and conversion
precede the workload clock. The complete repetition loop and final numerical
predicate are timed; decimal serialization follows it. The unchanged host
also checks three scalar opacity calls per repetition. Process clocks include
launch, initialization, output and cleanup, and are retained separately.

All five variants pass full-count validation, counts 0/1/2 and two altered
expectations per workload: 60 preparation guest records. Zero count returns an
empty result with a false predicate; both negative expectations also produce
a false predicate, which the validation host requires. Ten additional timer
diagnostics validate the exact timed frames and remain excluded from medians.

The production artifacts come from the
[existing integer controls](../2026-10-14-strict-integer-controls/README.md):
compiler/runtime `6f9ed95`, library `820e9f9`, adapter `1672d05`, and validation
followup `35f4c55`, with their exact source/tool identities retained. The probe
plan's `compiler_basis=b9bfe87` identifies its diagnostic checkout; these
measurements reuse the frozen production binaries rather than rebuilding the
compiler at that revision. All modifications are recorded Wasm artifacts.

The coordinated timing window ran from **2026-10-14 21:03:36.346 UTC to
21:06:27.829 UTC**, **171.483 seconds**. The coordinator polled its actual
owned session **61576** to terminal exit zero, independently checked all 110
records and 35 frozen identities, then released the holds. Other agents held
builds, guest execution, profiling, compression and publication during the
window; static work continued. This records coordination, not OS idleness.

Guests ran serially on CPU 5 with default V8 tiering, stack and GC policy,
and a 60-second timeout. Pi precedes Chudnovsky. Ten rotating rounds give each
variant two appearances at each of five positions per workload. There are
100 retained observations and ten predetermined discards, with no replacements
or exclusions. Every sample has complete output, positive finite clocks,
empty stderr, no timeout, no live owned descendants, a reaped leader and closed
capture handles. Immediate fixed CPU policy and affinity agree; instantaneous
frequency differs, so fixed frequency is not established.

## Offline evidence audit

The archive contains every clean record and host snapshot, the controlled
WAT/Wasm variants and checks, initial preparation lineage, timer diagnostics,
raw CPU profiles, complete/selected code captures, and both independent audits.
It includes the new runner plus its three actual imported helpers: the prior
integer measurement driver, `matrix_port.py` and `data_ports.py`. Build caches
are excluded. The [manifest](manifest.json) lists exact safe regular-member
hashes and references the existing Pi, Chudnovsky and preparation control
archives; those larger archives are not duplicated.

[`review.py`](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-bigint-loop-ablation/review.py) recomputes the planned population, complete frames,
commands, context, ownership cleanup, balanced medians and ratios from raw
records. It separately validates correctness records, profile weights and
captured code tiers/sizes, and checks frozen artifact hashes and probe scope.
Verify all archive members without launching guests:

```sh
python3 -I -B benchmarks/results/2026-10-14-bigint-loop-ablation/package.py
```

After unpacking the verified archive, run
`python3 -I -B comparison/review.py campaign preparation diagnostics profiles code`.
This replay requires no original absolute paths. Optional
`--check-live-identities` additionally checks the original frozen paths.
No compiler implementation is included, and measured suite coverage is unchanged.

Archive verification checks safe member names, inventory and byte identities;
the separate directory replay checks the campaign's semantics. Directory replay
expects a trusted extraction of the verified archive. The selected new code
captures are checked for module/function/index/tier/size identities; the original
excerpts additionally receive a byte comparison against their full captures.
Explicit archive creation keeps one private snapshot through semantic audit,
hashing and compression. The committed archive preserves the original collection
and packaging evidence; this follow-up creation-tool simplification does not
rebuild it or change any observations.
