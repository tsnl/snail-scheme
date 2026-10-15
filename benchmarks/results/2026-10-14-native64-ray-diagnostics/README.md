# Native64 Ray diagnostics

Both executors retain the empty `no-root` and `no-point` allocations in the
captured optimized machine code. The native paths additionally maintain the
Immix start bitmap, allocation header, byte/object counters, and explicit
reference frames. This investigation supports allocation and frame bookkeeping
as concrete contributors to native work; it does not assign the complete
native/V8 time difference to one operation or establish a production tuning fix.

The [clean comparison](../2026-10-14-native64-ray-comparison/README.md) remains
the primary timing result: native 0.193422498 s versus V8 0.127955350 s, or
1.512×, for 50 full renders. Here the native executable is unchanged, SHA-256
`baa70c23e9f133ebc85510b709f1aeb8a03120f26a5601262c2b96094d8a890c`.
Both targets originated from the mandatory Binaryen-optimized Wasm
`d620f33931a18252c4906ae45f55fba76a7a32ee292f7e7cceb3c4b5c884d634`;
the linked V8 module is
`b82e589f84aff8e0375cada32013ac931ebe1f34262506398ccad9c66ff8eb38`.
Native mechanically lowers that program to LLVM and retains the in-house
collector and frozen shared Rust archive. Production sources are unchanged.

## Exact executable samples

Eight fresh CPU-5 processes were sampled with perf 7.2.3, `cycles:u` at 4,999 Hz.
All 7,966 native CPU-core samples are retained; every report records zero lost
samples. Percentages weight each sample by its perf period and exclude taskset.
These are whole-process self samples, including setup and cleanup. Agent builds
were not paused for profiling, so profiled elapsed times are not clean timings.

| Machine-code region | Sampled cycles |
| --- | ---: |
| `f.20`, including inlined first-hit, allocation, roots, math and type tests | 63.10% |
| `native_gc_collect` | 17.40% |
| `allocate_header` | 12.42% |
| `native_gc_alloc`, excluding inlined copies | 1.06% |
| `f.17`, unit-vector | 2.17% |
| Rust port write / exported character write | 0.93% / 0.98% |

Within the exact `f.20` disassembly, the two empty-allocation blocks account for
6.21% (`0x4f726`–`0x4f827`, exclusive end) and 6.70%
(`0x4fd90`–`0x4fe91`) of process samples. These blocks include root-count
publication, collection checks, and allocation bookkeeping. The selected
first-hit frame entry/exit blocks account for 3.39% and 1.69%. These address
regions describe sample locations; they are neither complete allocator/root
cost totals nor isolated causal estimates. Inlining and sampling skid matter.
Raw callchains are preserved, but tail calls and incomplete LLVM unwind metadata
make self samples more reliable than the printed caller chains.

The existing opt-in GC timers on the exact executable report 73 collections,
34,992,392 allocations, 319,662,952 payload bytes, 0.000208 s marking, and
0.033441 s sweeping. These totals have process scope. The live heap after the
last collection is 3,592 bytes, with a peak of 3,648 bytes; the arena high-water
extent is 8,421,376 bytes. Sweeping, rather than tracing the small live graph,
accounts for almost all measured collector work.

## Separate additive counter build

Copied C runtime sources and the frozen LLVM receive only counters. Every
patch, constructor site, compiler invocation, failure and final binary is
archived. The optimized Wasm, frozen original LLVM and Rust archive remain
unchanged. Snapshot output is outside the `bench(50)` clock. Both diagnostic
runs produce identical operation counts:

| Phase | Allocations | Payload bytes | Collections |
| --- | ---: | ---: | ---: |
| Runtime/module/main setup | 42 | 552 | 0 |
| `bench(50)` | 34,992,350 | 319,662,400 | 73 |
| Terminal cleanup | 0 | 0 | 0 |

The workload constructs 16,094,700 `no-root` objects and 16,094,700 `no-point`
objects: 91.99% of its allocations. Their native tags are 38 and 30. The
process allocation total matches the exact executable's existing counter.
There are 20,727,432 logical root-enter routine invocations, comprising
18,486,800 nonempty frame links and 2,240,632 zero-capacity invocations. Of the
nonempty links, 17,000,000 have capacity 14 in the first-hit loop. Zero-capacity
production paths do not link frames and may disappear under LTO; additive
counters preserve logical invocations. Counts describe this diagnostic native
build, not V8 physical allocations or baseline costs.

Captured Node 24.19.0 TurboFan `function70` code, linked function index 25,
contains a 16-byte `no-root` allocation at offsets `+0x2f9`–`+0x332` and a
16-byte `no-point` allocation at `+0x967`–`+0x9ff`. The latter is outside the
main code path, so checking only the contiguous fast path would miss it. Native
allocates the same 16-byte aligned footprint for each empty variant, then
updates the start bitmap, header, `since_collection`, `allocated_bytes`, and
`allocated_objects`. Its reference values use the i64 ABI and its root-chain
pointer is volatile. Those source/assembly facts suggest constraints on LLVM
elimination; this report does not measure the independent cost of each fact.
V8 code-print flags are diagnostics, and no V8 allocation count is inferred.

## Frozen heap-cadence comparison

The exact executable uses the unchanged 256-MiB reservation. Only the existing
minimum allocation-budget control varies. One excluded cycle and four retained
rotated cycles per variant were frozen before execution. Agent-controlled builds,
tests, profiling and compression were held; other system activity is uncontrolled.
These processes have no profiler or opt-in GC timers.

| Minimum budget | Median workload seconds | Retained range | Relative to default |
| --- | ---: | ---: | ---: |
| Default, 8 MiB | 0.193746 | 0.192985–0.195732 | 1.000× |
| 1 MiB | 0.191795 | 0.191177–0.194258 | 0.990× |
| 64 MiB | 0.216581 | 0.216101–0.216871 | 1.118× |

The roughly 1% small-budget difference is within this small sample's scale,
with overlapping ranges. The 64-MiB slowdown is evidence against simply
collecting less often as a sufficient explanation or solution. Changing the
budget also changes reclamation and memory/cache behavior, so it does not
isolate collection cost.

All 50-render invocations pass predicate `1` and the full 29,517-byte image
check, SHA-256 `38babccc4583f44c18d17488314bffe9723a0fd2bdeff7227ec0d7ed1ea1463d`.
This includes the first-look statistics/profile runs, eight retained profiles,
two counter runs, two V8 code-print runs and all fifteen heap-policy trials.
The original exact-artifact lifecycle checks establish 50 output opens/closes
and 49 deletions; they are not replaced by a final-image-only argument.

## Evidence and replay

`summary.json` contains scoped counters and the reproducible sample aggregation.
`artifacts.tar.xz` retains raw profiles, images, code dumps, original frozen
inputs/providers, successful and failed diagnostic builds, source patches and
offline-analysis errors. `manifest.json` verifies every regular member and the
archive. The first counter compilation failed because its added declaration
preceded LLVM's target triple; it is preserved as `counter-build-failure-0`.
An invalid perf reporting option and an offline sample-parser error are retained.
There are no failed workload executions, replaced samples or discarded trials.

```sh
python3 benchmarks/strict-suite/replay.py /tmp/native64-ray-diagnostics-replay \
  --report benchmarks/results/2026-10-14-native64-ray-diagnostics
```

`replay-plan.json` identifies restored inputs and exact native/V8 commands.
`replay-check.json` records actual relocated native and V8 correctness runs.
Use fresh directories with empty `outputs/` and the recorded external tools.
Offline analysis needs no quiet window; new performance comparisons require one.
The driver accepts `--comparison` and `--build` for relocated frozen inputs and
fresh evidence directories. Its modes `profiles`, `v8-code`, `counters`,
`freeze-heap`, `heap-controls`, `summarize`, and `archive` retain every outcome
before validation; the heap mode requires an explicit quiet-window record.
