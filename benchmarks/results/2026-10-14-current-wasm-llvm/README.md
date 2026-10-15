# Current Wasm on archived LLVM and Immix

LLVM with Immix wins three of the four successfully restored workloads: String,
permutations and quicksort. V8 wins complex Mandelbrot. Both executors consume
the **same optimized Wasm bytes** for each pair. These are selected workloads,
not a result for the full suite or a reason to restore the native production path.

The String row uses the earlier flat layout. A [later same-Wasm flat/block comparison](../2026-10-14-string-block-native-comparison/README.md)
shows bounded String blocks reverse its executor winner from LLVM to V8.

| Workload | V8 seconds, median (range) | LLVM + Immix seconds, median (range) | Faster executor |
| --- | ---: | ---: | --- |
| string | 5.030250 (5.002498–5.044233) | 2.299514 (2.294725–2.346621) | LLVM 2.19× |
| mbrotZ | 0.576075 (0.575839–0.576423) | 1.033035 (1.029923–1.037989) | V8 1.79× |
| quicksort | 1.192104 (1.187652–1.193170) | 1.061121 (1.060104–1.064487) | LLVM 1.12× |
| mperm | 16.367943 (16.071041–16.543939) | 6.430860 (6.427510–6.435529) | LLVM 2.55× |

The clean run retains four fresh-process observations per cell after one discarded
round: 40 executions total, 32 retained. Every original result check passes.
Cases rotate through all four ordinal positions; V8/native order alternates,
giving each implementation two first positions and two second positions per
case. Processes are pinned to CPU 5, default Node 24.19 / V8 13.6 tiering is
retained, and all agent-controlled builds, tests and profiling were held.
Unrelated system activity is not excluded. Raw observations, commands, all
samples, timestamps and 64 unchanged source/artifact/tool identities are in
[clean.json](clean.json) and [quiet-window.json](quiet-window.json).

## Workloads, timing and limitations

Original inputs and counts remain: String 100 repetitions with threshold 500,000
and ten trials each; mbrotZ 1,000; quicksort 2,500; mperm 20 with n=10, k=2, ell=1.
The artifacts come from their recorded strict compiler checkpoints, with no
frontend rerun for this comparison. The native path lowers each frozen Wasm
through the recovered emitter; all prior strict source adaptations therefore
apply equally to the two executors.

Module initialization, exported `main`, benchmark setup and native arena
prefaulting finish before the workload timer. It encloses `bench(count)` and the
final host result assertion. Result
formatting and diagnostic counter checks follow it. Clean opacity functions
retain their calls but disable validation counters; they report null counts.
GC event tracing and per-allocation statistics are disabled.

The native configuration uses a 300 MiB arena for String, mbrotZ and quicksort.
**mperm exhausts that capacity during setup.** The reported mperm result is an
explicit **1 GiB capacity variant** with all other collector settings unchanged.
Its diagnostic peak live payload was 614,393,720 bytes. V8 uses its default heap
policy: this comparison does not impose equal resident memory or heap capacity.

The attempted deriv artifact remains excluded because the archived emitter
cannot lower its nonfinal struct subtype. Both this build failure and mperm's
default-capacity failure are retained in the preparation evidence. There is no
four-workload geometric mean that hides those limitations.

Including startup and teardown preserves all four winners, though quicksort's
advantage becomes small. These are separately observed process elapsed medians,
not differences inferred by subtracting unrelated measurements:

| Workload | V8 process seconds | LLVM process seconds | LLVM setup seconds |
| --- | ---: | ---: | ---: |
| string | 5.058729 | 2.410996 | 0.095184 |
| mbrotZ | 0.601727 | 1.144109 | 0.094994 |
| quicksort | 1.216667 | 1.172298 | 0.095500 |
| mperm | 17.384377 | 7.041025 | 0.571139 |

Native setup includes heap prefaulting and module/main initialization. Process
time additionally includes launch, input loading, output and teardown. No
compilation is included in either timing column.

## Exact restored implementation

The isolated experiment is commit `b419cc607e6cc13e854671fb9796f894a9d1faa6` on
`experiment/current-wasm-llvm-20261014`. It starts from archive `5c277ab` and
recovers Immix from `7f698687b9e7c6af4272a6a19c35ca9e1a9f9d11`. The collector is
nonmoving, with 32 KiB blocks, 128-byte lines, an 8 MiB initial allocation budget
and subsequent budgets of `max(8 MiB, 2 * live payload)`. Arenas are prefaulted.
The archived layout uses eight-byte native fields and array elements, including
the String workload's i32 Unicode elements.

This baseline keeps **exact explicit root frames**, proper tail calls, bounds
checks, ordinary collections and zeroing. It does not use the later LLVM
stack-map/bitmap-sweep experiment, preserved at
`experiment/shared-binaryen-20261011` / `e3e66bc6a45263928cfd1e7a31659d00e6a47ca7`.
The host imports are compiled in a separate `-fno-lto` C object. Guest and
collector use Clang/LLD 21.1.8 with `-O3 -flto`; runtime-loaded inputs and the
opaque host calls prevent exposing workload inputs to whole-program compilation.

Each retained native run performs 2,001 workload collections for String, 662 for
mbrotZ, 23 for quicksort and 20 for the mperm capacity variant. Thus the native
wins are obtained with active collection. The paired times do not isolate GC
from instruction selection, layout, root maintenance or allocation policy.
For String, the [previously measured V8 page-fault/kernel costs](../2026-10-14-strict-string-comparison/README.md) make allocation
policy a plausible explanation worth testing further; this comparison alone
does not establish that causal attribution.

## Validation and reproduction

[Preparation](preparation.md) and its original logs preserve forced-collection
probes, native roots/callbacks/finalizers, proper tail transfers, traps, Scheme
checks, strict C and sanitizer checks. Those diagnostic timings are separate
from the clean results above. The final native host's full original inputs are
checked again by every clean execution.

`artifacts.tar.xz` contains 106 exact artifacts and source files, including the
frozen Wasm, specifications, disassemblies, emitted LLVM, native executables,
native host, emitter and collector, build commands, and unsuccessful attempts.
[manifest.json](manifest.json) checks every member. The parent restored and
hash-verified all members and executed eight additional count-one correctness
probes, one per executor/workload, with original non-count inputs and validation
barriers enabled: [replay-check.json](replay-check.json). These are not timings.

```sh
mkdir /tmp/current-wasm-llvm-replay
tar -xJf benchmarks/results/2026-10-14-current-wasm-llvm/artifacts.tar.xz \
  -C /tmp/current-wasm-llvm-replay
```

The restored `artifacts/<case>/inputs.txt` and `spec.json` keep the original
counts. Run `artifacts/<case>/native inputs.txt` with the capacity recorded in
[handoff.json](handoff.json), or run the recorded Node binary with
`sources/experiments/current-wasm-llvm/node-host.mjs`, the corresponding
`input.wasm`, and `spec.json`. Native binaries require the recorded x86-64 Linux
Nix dependencies; the archived source/build commands support rebuilding them.
Unset `NODE_OPTIONS`, `SNAIL_NATIVE_GC_INTERVAL`, and collector diagnostic/policy
environment overrides before applying the recorded arena capacity.

[measure.py](measure.py) implements the fresh-process schedule and validation;
[plan.json](plan.json) preserves exact original paths and hashes. Relocating the
archive requires adjusting those paths and freezing a new plan. Results from a
different machine or toolchain belong to a new observation set. The experiment
remains separate from the current compiler stack; this layer publishes evidence.
