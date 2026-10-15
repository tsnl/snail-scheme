# More complete-program comparisons and remaining costs

The strict compiler beats Rust/Wasm on symbolic differentiation and beats both
Chez controls on complex Mandelbrot. Rust wins complex Mandelbrot, and both
Chez controls win differentiation. These are two additional original full
workloads, not a new run of the entire suite.

All entries are workload seconds; lower is better. Each cell is the median of
four retained fresh-process runs, following one discarded four-system round.

| Original workload | Strict Snail | Original Chez | Adapted source on Chez | Rust/Wasm |
| --- | ---: | ---: | ---: | ---: |
| deriv, 10,000,000 differentiations | 1.864275 | 0.417337 | 0.720121 | 2.765973 |
| mbrotZ, 1,000 × 75 × 75 pixels | 0.575473 | 1.450098 | 3.629053 | 0.367697 |

Snail takes 32.6% less time than Rust on deriv, but 2.59 times the adapted
Chez time and 4.47 times the original Chez time. On mbrotZ it takes 60.3% less
time than original Chez, while Rust takes 36.1% less time than Snail.

Both strict artifacts use the compiler measured as `7ff18c0`, whose code was
published in the unmerged stack as `0cf2240`. The new source adapters do not
change that compiler. Historical measured strict coverage reaches 26 of 57
workloads, with 25 paired Chez comparisons; earlier entries use their own
recorded compiler versions.

## What the source comparisons mean

The [deriv preparation report](../2026-10-13-strict-deriv/README.md) records the
closed datum representation, complete-expression checks, sharing probes and
the deliberately preserved upstream quotient rule. Each source pair remains
an explicit pair in strict Scheme. Rust uses reference-counted expression
nodes with vectors of arguments and immediate reclamation. Its input and full
returned expression are made opaque each iteration. The final full equality
predicate is timed in all four systems. The advantage here does not establish
equal allocation work or a general advantage over Rust.

The [mbrotZ preparation report](../2026-10-13-strict-mbrot-z/README.md) retains
the original complex arithmetic, descending pixel loops, all matrix stores,
escape/cap checks, and final result 5. Strict Scheme uses immutable records
with two F64 fields. Rust passes a pair of F64 values and stores its rows in
linear-memory vectors. Its whole matrix is made opaque before the final
scalar predicate. Legal downstream optimization can eliminate temporaries
and reuse arithmetic in either program. The adapted Chez control uses the
same Scheme arithmetic helpers and explicit record representation; original
Chez keeps its original complex-number implementation.

These are comparisons of complete source programs implementing the same
workloads. Different layouts, lifetime management and opacity boundaries remain
material. Instrumented constructor completions and surviving native allocation
paths in the preparation reports are not physical allocation totals.

## Removing two graphs callbacks did not establish a useful speedup

A separate source ablation replaces the two Boolean-matrix row generators
with concrete workers receiving their initialized captures as parameters.
It preserves the original row construction order, row identities, matrix
stores, other callbacks and continuation chain. Complete small graph outputs,
row alias/mutation contracts and the full original 3 × 7 workload pass before
measurement. The fresh behavioral explanation and informed review are recorded
in [callback-review.json](callback-review.json).

| Same original graphs workload | Median | Retained range |
| --- | ---: | ---: |
| Existing compiler/source | 1.822358 | 1.803533–1.850449 |
| Two manually specialized callbacks | 1.817190 | 1.809045–1.823210 |

Six alternating retained pairs follow one discarded pair. The 0.28% median
reduction and overlapping ranges do not establish a material benefit. The
variant removes the twelve optimized indirect instruction sites associated
with those row callbacks, but leaves the continuation creation/resumption
path. Earlier heavy instrumentation attributed roughly 87% of construction
completions to that unchanged path; that percentage is neither physical
allocation share nor an upper bound on speedup.

The ablation combines dispatch removal, explicit capture transport, code
copying and subsequent inlining. It does not isolate indirect dispatch alone.
No production compiler optimization follows from this result. The archive
keeps the frozen experiment package, including its historical review-pending
README; the parent review and timing records here supersede that status.

## Collector policy on unchanged mperm

The four configurations run exactly the same optimized Wasm, original
20:10:2:1 input, host and final predicate. The preceding default-policy profile
classified about 90% of sample-weighted time as GC, with most reported pause
time in young-generation collections. This motivates the policy experiment;
the profile itself does not measure exact total collector CPU.

The policies are the default, `--no-parallel-scavenge`,
`--max-semi-space-size=128`, and `--minor-ms`. All eight bounded raw/optimized
correctness checks pass before measurement.

| Engine policy | Clean median | Retained range | Time / default |
| --- | ---: | ---: | ---: |
| Default | 16.323617 | 16.073478–16.578469 | 1.000× |
| Serial scavenging | 16.518627 | 16.046227–16.555671 | 1.012× |
| Maximum semi-space size 128 | 16.184547 | 15.889654–16.443095 | 0.991× |
| Minor mark-sweep | 15.736259 | 15.487127–15.789001 | 0.964× |

The first two changes have overlapping sample ranges with default. Minor
mark-sweep takes 3.6% less time in this batch, leaving most of the previous
several-fold gap. No default engine flag changes follow from this experiment;
other workloads have not been measured with these policies.

Separate [collector diagnostics](collector-diagnostics.json) verify that the
flags changed actual behavior. Default and serial scavenging each record 258
young collections with `new_space_capacity` 64 MiB. The larger setting records
128 with capacity 128 MiB, but the reported young-collection pauses still sum
to about 13.6 seconds. Fewer collections alone do not remove that observed
work. Minor mark-sweep instead reports 118 `mms` events and a 144 MiB capacity.

Default's young and major pauses sum to 14.740 seconds; minor mark-sweep's sum
to 7.766 seconds. Yet the clean total-time improvement is only 3.6%. Printed
pause totals omit substantial costs in the alternate configuration; additional
profiling would be needed to attribute its time outside those intervals.
These traces run after the coordinated window, with build work allowed, and
are not added to the clean samples. Their raw fields, synchronous markers and
whole-process resource statistics are archived. A parser initially assumed
the final stdout line was JSON; a trailing minor mark-sweep event exposed that
assumption. The corrected parser selected the unique result record from the
saved outputs without rerunning the programs.

## Measurement and reproduction

Runs are sequential on logical CPU 5 of the same Intel Core Ultra 7 270K Plus
used by the earlier reports. Other agents held all build/test jobs during the
window. Node 24.19.0 uses default tiering and no inherited `NODE_OPTIONS`;
collector overrides apply only to their named mperm configurations. The
affinity also constrains V8 worker threads. These observations do not establish
how collector policies compare when workers can use multiple CPUs.

For the four-system and four-policy comparisons, each system occupies every
ordinal position once across four retained cyclic rotations. This balances
position, not every predecessor effect or all drift. Each execution starts
a new process, so discarding the first round does not remove JIT tiering from
later runs. Setup and input preparation are outside workload clocks; original
repetition counts and the final predicate remain inside. Process wall times
are stored separately. All 74 executions pass, and recorded tool/program hashes
match before and after each comparison. Raw [deriv](clean-deriv.json),
[mbrotZ](clean-mbrotZ.json), [callback](clean-graphs-callbacks.json) and
[collector-policy](clean-mperm-policies.json) records preserve commands, output,
process durations, order and every retained sample; [summary.json](summary.json)
gives medians, ranges and ratios.

[Rust contracts](rust-handoff.json) and [build provenance](rust-build-provenance.json)
identify the frozen artifacts and their exact source bundles. Rust targets
`wasm32-wasip1`; the frozen release manifests use optimization level 3, LTO,
one codegen unit and aborting panics. Historical build-environment gaps remain
explicit in the provenance.

Restore the regular-file archive and verify every archived hash:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/runtime-comparison-replay \
  --report benchmarks/results/2026-10-14-strict-runtime-comparisons
```

After arranging a quiet window, reproduce an original comparison:

```sh
python3 benchmarks/results/2026-10-14-strict-runtime-comparisons/reproduce.py \
  /tmp/runtime-comparison-replay mbrotZ /tmp/repeated-mbrotZ.json
```

Other choices are `deriv`, `graphs-callbacks` and `mperm-policies`. The driver
relocates archived programs and inputs, checks exact external tools, preserves
the original schedule, and saves failures before checking their contracts.
