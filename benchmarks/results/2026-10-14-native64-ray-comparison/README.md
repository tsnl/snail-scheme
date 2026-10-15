# Current native64 and V8 on Ray

| Executor | Median workload seconds | Range | Median process seconds |
| --- | ---: | ---: | ---: |
| V8, linked WasmGC | 0.127955 | 0.127079–0.128581 | 0.152292 |
| Native LLVM, in-house Immix | 0.193422 | 0.193176–0.194000 | 0.195176 |

The restored native target takes **1.512× V8’s workload time** on Ray, or
51.2% longer. Including process startup and terminal cleanup, the ratio is
1.282×. Four retained process observations per target each execute all 50
original renders. This single-workload result does not establish a suite-wide
winner or identify the collector as the cause.

## One program, two production link paths

The [complete strict Ray source](../2026-10-14-strict-ray/README.md) remains
unchanged: 50 full 100 × 100 renders, a reconstructed 33-sphere scene each time,
original arithmetic/order, complete decimal PGM output and the final result
predicate. The canonical input is `50`, `1`, `"outputs/ray.output"`, `ok`.
Its typed input decoder supplies resolution 1 and expected-kind 1; the source
SHA-256 is `cba5eae0a68ccf32eea895799f3d4eaa57e3d2384a63df57685f5fac5ff92e32`.
The original preparation retains the source adaptation and Chez controls.

The native restoration is frozen at
`f347b43b8170af11bf8e23a1c9ccd4d01f7f7b61`. The production command
`scripts/build-native --wasm` consumes the previously optimized unlinked
program and **runs Binaryen again**, as required for every build. Its resulting
optimized program has SHA-256
`d620f33931a18252c4906ae45f55fba76a7a32ee292f7e7cceb3c4b5c884d634`.
Both executors then consume those same bytes:

- Native mechanically lowers them to LLVM and links the in-house precise Immix
  collector, the current Rust native archive, and the explicit scalar C provider.
- Wasm links the current Rust Wasm provider and runs Binaryen on the complete
  module. V8 executes that newly linked artifact.

The final V8 module is
`b82e589f84aff8e0375cada32013ac931ebe1f34262506398ccad9c66ff8eb38`;
the native executable is
`baa70c23e9f133ebc85510b709f1aeb8a03120f26a5601262c2b96094d8a890c`.
They are different linked images with different cross-provider optimization
opportunities. The earlier Ray comparison’s V8 artifact is retained separately;
its timing is not reused here. Both current providers are built from the same
Rust source files. Native collection uses its unmodified default 256-MiB virtual
arena and 8-MiB minimum allocation budget, without prefaulting or forced collection.

`benchmark.h` declares every C import with its actual I32/I64/F64/Bool/Char
carrier. `benchmark.c` supplies the canonical inputs and ASCII pathname as a
separate non-LTO object; LLVM cannot substitute constant results for its opaque
calls. `entry.c` invokes the exported C adapters directly. This benchmark host
adds no Scheme-aware behavior to LLVM and no optimization to the compiler.

## Timing and correctness

One initial pair is excluded from summaries but fully retained and validated.
Four subsequent pairs alternate V8/native and native/V8, giving each executor
two first and two second positions. All ten outcomes pass. Each process runs
on logical CPU 5 on the recorded Intel Core Ultra 7 270K Plus machine, with a
fresh output directory and the original relative pathname. Agent-controlled
builds, compression, diagnostics and tests were paused; unrelated system activity
and ordinary filesystem-cache effects remain possible.

Node 24.19.0 uses its default V8 tiering. Native uses Clang/LLD 22.1.8 and the
in-house collector; both paths use Binaryen 132. Node profiling/coverage/debug
variables and native collector/test overrides are removed. No tracing or counters
are active in the measured processes. The compiler and runtime version commands,
exact build arguments, source files and binary identities are retained.

Both hosts initialize the runtime/module and call Scheme main before the clock.
The clock encloses `bench(50)` and its success check. Scene construction, all
renders, formatting and ordinary file deletion/open/write/close operations are
inside the call. Terminal runtime cleanup and JSON output follow the clock.
Process elapsed time separately spans subprocess launch through exit. The driver
saves raw status/output before validation, retains all attempts and performs no
retries or outlier removal.

Every image matches the complete independent reference byte for byte: 29,517
bytes, SHA-256
`38babccc4583f44c18d17488314bffe9723a0fd2bdeff7227ec0d7ed1ea1463d`.
This final image check alone does not prove all repetitions survive. Separate
tracing of the exact native executable records **50 opens, 49 deletions and 50
closes** for the output. Current V8 host diagnostics record the same lifecycle
and all 100 expected iteration barriers. These diagnostic executions are excluded
from timing. The initial sandbox-denied strace attempt is preserved, followed by
the successful authorized child-process trace. Fine-grained counters from the
older V8 artifact are not attributed to the current artifact.

All **129** frozen source, artifact, provider, host, tool and driver identities
match before and after the campaign. `clean.json` preserves every observation;
`summary.json` retains samples, ranges, medians and ratios. The independent
explanation and parent critique appear in `measurement-review.md`. Four samples
support this descriptive comparison, not significance estimates or causal claims
about root bookkeeping, allocation, collection or foreign calls.

## Replay

`artifacts.tar.xz` preserves the native/V8 inputs and outputs, current source
files, exact Rust providers, build/trace records, excluded and retained images,
and invocation code. External tools are recorded by path/hash. The original
strict preparation and its compiler sources are retained as input provenance.
The manifest checks every regular archive member and the archive itself.

```sh
python3 benchmarks/strict-suite/replay.py /tmp/native64-ray-replay \
  --report benchmarks/results/2026-10-14-native64-ray-comparison
```

Resolve `files/` paths in `replay-plan.json` beneath the restored directory,
retain the pinned external tools, and use a separate directory with empty
`outputs/` for each process. The plan keeps all 50 renders and the complete image
contract. `replay-check.json` records actual relocated correctness executions;
those timings are excluded from the clean campaign. New performance observations
require a new quiet window and remapped frozen paths.
