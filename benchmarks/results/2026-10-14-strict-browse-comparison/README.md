# Complete Browse comparison

All **56 planned processes pass** the original 2,000 complete worker
invocations and final 100-integer predicate. Production Snail/V8 takes
**7.673× original Chez time**, **0.635× adapted Chez time**, and
**2.055× this Rust/Wasm control's time**. Native takes **1.724× V8 time on
the identical native-final Scheme Wasm**.

## Workload medians

Each median uses seven retained fresh processes. One predetermined process
per system is discarded; every discarded result is also validated.

| System | Median (s) | Retained range (s) |
| --- | ---: | ---: |
| Snail / production Wasm / V8 | 4.037493 | 4.003570–4.059463 |
| Snail / native-final Scheme Wasm / V8 | 4.297396 | 4.279336–4.337461 |
| Snail / native64 | 7.409398 | 7.344130–7.650692 |
| Original source / Chez | 0.526165 | 0.522230–0.527615 |
| Adapted Scheme and library bodies / Chez | 6.360476 | 6.346831–6.385901 |
| Rust / optimized Wasm / V8 | 1.964427 | 1.897607–2.668717 |
| Rust / native | 1.396764 | 1.364914–1.859060 |

Ranges are observed minima/maxima, not confidence intervals. Every planned
observation remains, including the wider Rust/Wasm and Rust/native ranges.
Full-precision workload/process statistics and ratios are in
[`independent-review.json`](independent-review.json).

Adapted Chez itself takes **12.088× original Chez time**. Its exact edited
workload and library bodies replace heterogeneous source pairs with a closed
Datum variant, explicit Ref cells, and reusable helpers; its local compatibility
boundary represents those variants and Refs with Chez vectors. These source,
helper and representation changes jointly affect the comparison. The original
Chez gap cannot be attributed entirely to V8 or to one representation change.

The unchanged Rust control uses Vec database/property tables, Rc lists,
string symbol comparisons, copied star-prefix spines and a Boolean collapse of
Empty/True matcher returns. Its setup shares parsed pattern trees through
vectors instead of constructing Scheme's cyclic list ring. Its per-match
`black_box`, ownership, allocation and reclamation differ. These are separate
algorithm and layout controls; the ratios do not isolate GC or code generation.

## Complete work and clock boundaries

The [preparation](../2026-10-14-strict-browse-preparation/README.md) retains
the complete source pinned to upstream
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1` and unchanged input. The Scheme
compiler/library basis is **`15d2c64`**, with separately hashed native/control
sources, build records and tool provenance. The existing control archive retains
the actual frozen source snapshot and native build record at
`build/browse-attempt2/controls/native/native.native-5edrrh6_/build.json`;
later integration revisions are not substituted into the measured artifacts.

Scheme preserves the property association lists, interned symbol identities,
copied cyclic pattern ring, destructive shuffle, three nested investigation
loops, shared suffixes and all three matcher-result classes. Empty is truthy,
and short-circuiting preserves the selected result class and skipped branches.
The original final unused gensym operation remains. No reduced worker or
precomputed result replaces the source program.

The final database predicate is independent of the discarded matcher results.
Preparation therefore separately records byte-identical ordered recursive
arguments, result classes and worker results on five Scheme paths at counts
**1 and 2**. Full-count internal traces were not recorded. The
[clean retained-work inspection](../2026-10-14-strict-browse-preparation/retained-work.md)
follows raw, optimized and native-final Wasm through the investigation loops
to the matcher, and inspects the actual native executable's recursive matcher
and allocation calls. Clean full-count correctness, bounded traces and static
retention evidence support distinct claims; final database equality alone does
not establish matcher execution.

Input parsing, file close, module initialization and database construction
precede each workload clock. All seven clocks include the 2,000 complete
worker invocations and final predicate; serialization, output and terminal
cleanup follow. The Scheme timing hosts use a constant opaque barrier with
observational counting disabled; Rust keeps its existing black boxes.
Process time separately covers launch, initialization, capture and bounded
cleanup. Subtracting workload time does not measure pure startup. Native and
its V8 control share the exact final Scheme Wasm, while scalar-provider
compilation target and linkage differ.

## Coordinated execution and evidence

The window ran from **2026-10-14 20:34:53.507 UTC to 20:38:29.701 UTC**,
216.194 seconds. Other active agents held builds, guest execution, profiling,
compression and publication; static review/editing continued. The coordinator
polled its actual owned session **49220** to terminal exit zero, independently
checked every record and all 330 frozen identities, then released the holds.
[`coordination.json`](coordination.json) preserves that ownership account;
it does not claim an otherwise idle operating system.

Guests ran serially on CPU 5 with a 120-second timeout and normal V8 tiering,
stack and GC policy. Seven retained rotating rounds place each system in every
order position once. There are seven predetermined discards and 49 retained
observations, with no replacements or retrospective exclusions. Every raw
record has successful exit, complete expected output, positive finite clocks,
empty stderr, no timeout and empty live-process-group checks. The frozen runner
uses `communicate`, waits for the leader and performs bounded group cleanup;
the records do **not** explicitly mark per-sample pipe closure or leader reap.
Before/after fixed CPU policy and affinity agree; instantaneous frequency
differs, so this is not a fixed-frequency claim.

The frozen runner verifies identities before each sample and again after the
last sample. Its actual supervision imports are the two archived modules
`matrix_port.py` and `data_ports.py`. The broader compiler/build Python snapshot
remains in the existing preparation archive. The independently written
[`review.py`](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-strict-browse-comparison/review.py) checks their hashes and archive import origins,
every raw record, complete frame, schedule, exact command, recorded environment,
cleanup, balanced medians and the coordinator's saved independent audit.
Working directories are explicit in every sample; stdin selection is recorded
in the frozen plan and runner, without a separate per-sample stdin-path field.

`artifacts.tar.xz` contains every raw record and host snapshot, the frozen timing
plan/runner/two-module supervision closure, and both independent audits.
[`manifest.json`](manifest.json) lists exact safe regular-member hashes and
references the existing executable/source/control archive: 720 regular members,
11,119,660 compressed bytes, SHA-256
`acdb23f3daaff14507a007549319da75c429f0b04baddc02f86044f1bdb53ce7`.
Executable controls are not duplicated. Verify the measurement archive without
launching guests:

```sh
python3 -I -B benchmarks/results/2026-10-14-strict-browse-comparison/package.py
```

After unpacking the verified archive, run
`python3 -I -B comparison/review.py campaign preparation` to recompute the
result without original absolute paths. The optional `--check-live-identities`
requires all frozen artifacts at their original paths. This audit does not run
benchmarks; execution replay requires the pinned tools and a separate
coordinated window.

This adds Browse to historical strict coverage: **43 of 57 measured workloads**,
**42 with paired Chez controls**, across separate compiler checkpoints.
It is not a complete-suite rerun on one revision.
