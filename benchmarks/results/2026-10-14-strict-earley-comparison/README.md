# Complete Earley five-system comparison

Production V8 takes **1.484× original Chez time** on the complete canonical
Earley workload. It takes **0.754× adapted Chez time**. Native takes **1.458×
V8 time on the exact same final Wasm**, with an explicit **1 GiB native heap
reservation**. All 30 fresh processes passed; no sample was retried or replaced.

The original input is unchanged: count **1**, length **15**, expected
**2674440**. The complete parser constructs and materializes its tree list, then
takes its length. Parser construction, forward/backward state passes and all
three query APIs remain in the source. The
[preparation report](../2026-10-14-strict-earley-preparation/README.md) records
complete source reversal, five-target correctness, ordered small trees, mutable
storage/identity, captured lexer behavior and legal optimizer payload removal.
No compiler or runtime source changed for this port or campaign.

| System | Workload median (s) | Retained range (s) | Process median (s) |
| --- | ---: | ---: | ---: |
| V8, production once-optimized Wasm | 2.644450 | 2.616986–2.649600 | 2.697860 |
| V8, final common Wasm | 2.663772 | 2.622339–2.672358 | 2.719199 |
| Native, final common Wasm | 3.882573 | 3.874936–3.892978 | 3.905057 |
| Original Chez | 1.781515 | 1.778598–1.787982 | 1.836837 |
| Exact adapted-kernel Chez | 3.505472 | 3.493376–3.506326 | 3.570275 |

Each row contains five retained observations. Adapted Chez takes **1.968×**
original Chez time. That difference includes the typed representations and the
explicit append helper's temporary reversed prefixes; it does not isolate one
adapter operation. Native takes **2.179×** original Chez time and **1.108×**
adapted Chez time. The two V8 medians differ by 0.73%, with overlapping ranges;
these five observations do not establish a stable small performance difference.

## Exact artifacts and process protocol

Implementation commit: `14a84bd1f64ef4faac23b9b3aa54062d9c55c010`.
Preparation commit: `fed3f033dda359d25fcefe04f9a281ef51d63f67`.
Compiler basis: `011833645d88aae50c3c47a4eb6fa008136034c0`.

| Identity | SHA-256 |
| --- | --- |
| Frozen plan | `063472786ad5ea7d0d20c6b50ee025a7d9719f3b2dc13f241cab71ef9ad06168` |
| Frozen runner | `83943c281cebe9493afe4bab48a059ef4f6e79a837f51528e56e0cc7c3ce30b6` |
| Production Wasm, 24240 bytes | `923ee2e96a8d4ee9c252af935d138b1faf07625e14428568ed17b1d06ea01956` |
| Final common Wasm, 28961 bytes | `2f2d788d5851dd964550b26054d5cf034dc598015a163b79378aa7a214029ea5` |
| Mechanical LLVM module | `a88fbaefa2b4f3d6838909fbb078a65dc89d06dfaec21349fb0a9680f5801a6e` |
| Timer-only native executable | `b3ea7dccca35a6ae729295469f6ce42fae1040d321a3cdf888e5613a9b960bea` |

Both production targets require Binaryen 132. Native re-enters the shared
`-O3 --closed-world --always-inline-max-function-size=40 --converge` pipeline
before mechanical Wasm-to-LLVM lowering. The repeated pass further inlines and
unrolls recursive helpers and grows the module by 19.5%. The
[retention audit](../2026-10-14-strict-earley-preparation/retention-audit.json)
shows unchanged reachable names/tree type shapes and the changed static
allocation sites. The separate production-V8 row measures the actual build path;
the two common-artifact rows use the exact `2f2d…` bytes. No optimization policy
or additional variant was introduced during measurement.

The native clock entry was relinked against the exact frozen LLVM module,
provider object, native C runtime, collector and Rust static archive. Only the
entry adds `CLOCK_MONOTONIC` around one `wasm.bench(count)` call. Initialization,
`wasm.main`, printing and `native_finish` are outside that clock. V8 instantiates
and runs `main` before its workload clock, which includes the guest call and
scalar status assertion. Both Chez controls use the unchanged benchmark loop
and predicate with the existing monotonic nanosecond-jiffy prelude. Input
reading, compilation/startup and result output are excluded. V8 tiering work
that occurs during the invocation remains part of its fresh-process workload.
The separate process clock includes spawn, capture and owned-group cleanup.

The parent explicitly released the quiet window after other agents confirmed
their owned processes were terminal. No build, test, compression, profiler or
other coordinated benchmark overlapped the campaign. One complete five-system
round was discarded in advance. Five retained rounds rotated the order, placing
every system in each position exactly once. Every process was pinned to CPU 5
with a 180-second deadline and a 10-second group cleanup deadline. The observed
Intel Core Ultra 7 270K Plus used `intel_pstate` with the `powersave` governor
and 800 MHz–5.5 GHz limits; this was not fixed-frequency execution.

The runner verified all 161 frozen identities before/after the campaign and
before each sample. Exact output framing, the complete workload predicate,
zero exit status, empty stderr and stopped process groups passed in all records.
It kills the owned group, reaps its direct child and verifies no live group
members remain. Adopted zombie descendants may remain for their reaper; the
earlier preparation phrase “groups killed and reaped” should be read with this
more precise ownership distinction. No failure or unplanned exclusion occurred.

## Scope and resource limits

The port uses a declared finite atom/user-info vocabulary and I64 arithmetic,
not general Scheme symbols or arbitrary precision integers. Its complete
source tree representation preserves order, rule identity and sharing. The
stack-bounded append helper adds a temporary reversed prefix spine while sharing
the original suffix. The strict opacity barrier and Chez `hide` dispatch also
differ. The exact adapted Chez control makes these source-adapter costs visible.

Both optimized Wasm artifacts retain reachable recursive tree-spine generation
and the final length traversal. They legally remove unused rule-name, token and
child payloads/tags and unused acceptance/count query fields. Full separate
probes exercise those payloads and callable boundaries. Equal output alone is
not an allocation proof, and these results are not an isolated collector comparison.

The native default 256 MiB arena exhausted on the canonical preparation workload.
The same preparation executable passed with a **1073741824-byte reservation**,
which is explicit in every native timing record. A separate earlier resource
observation recorded **984944 KiB maximum RSS**, **974880768 arena bytes used**
and **239603216 live bytes at collection observations**. Those quantities are
different and were not measured during the clean campaign. The observed live
peak does not bound maximum live memory between collections. All original
failures and diagnostics remain in the preparation archive.

## Reproduction and evidence

The exact command was:

```sh
python3 benchmarks/results/2026-10-14-strict-earley-preparation/measure-five.py \
  --run --output build/earley-clean-01
```

`measurements/` retains every raw sample and the complete campaign JSON.
`summary.json` records unrounded medians/ranges and ratios. `quiet-window.json`
and the before/after host snapshots are separate records; the frozen plan was
not retrospectively changed. `verification.json` checks the schedule, framing,
balance, identities and aggregate arithmetic without rerunning a benchmark.

The comparison archive freezes these new records and the exact runner/plan.
Its manifest pins the preparation archive
`41c29fadd9835d397be0e9730c7217a7c137020fe0ffdd737868be6377f4f0eb`,
which contains every source, binary, build command, control and failed attempt.
Tool paths, hashes and raw version responses are in the preparation's separate
pre-campaign snapshot. Parent integration owns the historical coverage update;
this report does not imply a full-suite rerun on the frozen compiler.
