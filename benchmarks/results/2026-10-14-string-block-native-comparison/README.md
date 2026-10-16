# The same String Wasm on V8 and archived LLVM

Bounded String backing arrays reverse the executor winner for this workload:
archived LLVM/Immix is **2.08× faster with flat storage**, while V8 is **2.27×
faster with bounded blocks**. Each native input is byte-identical to the Wasm
executed by V8 for that layout.

| String layout | V8 seconds, median (range) | LLVM + Immix seconds, median (range) | Faster executor |
| --- | ---: | ---: | --- |
| Flat i32 array | 4.802693 (4.756741–4.806597) | 2.304770 (2.290360–2.323317) | LLVM 2.08× |
| Bounded i32 blocks | 0.984614 (0.984538–0.993274) | 2.236353 (2.232431–2.242179) | V8 2.27× |

Changing the layout improves V8 by 4.88× and this archived native path by 1.03×
in this independent window. The earlier [current-Wasm comparison](../2026-10-14-current-wasm-llvm/README.md)
used flat String storage. The [separate block-storage comparison](../2026-10-14-string-block-comparison/README.md)
records the Unicode/copying contracts and V8 resource diagnostics. These are
selected String measurements, not a full-suite executor result or a production
native-backend proposal.

The original source, 100 invocations, ten trials per invocation, threshold
500,000 and final length 524,278 remain. Only strict-wasm.sld differs between the
frozen flat and block compilers. No character narrowing, views, copy removal or
benchmark-specific compiler rule is introduced. Small-string owner-allocation
cost is outside this full growth workload. Later
[size controls](../2026-10-14-string-size-controls/README.md) measure that tradeoff
separately, including regressions on smaller growth/copy inputs.

One discarded four-cell round precedes four retained fresh-process cyclic
rotations: 20 checked executions, with each cell in each retained position once.
All 689 frozen source/artifact/tool identities are unchanged. Processes are
pinned to CPU 5 in a coordinated window with agent-controlled builds, tests,
profiling and compression held; unrelated system activity remains possible.
Default V8 tiering is retained. NODE_OPTIONS and collector overrides are cleared
before applying each recorded environment. Clean runs have no validation,
collector tracing, audit or profiling flags; their opacity counters report null.

The native emitter, host and collector remain at
`b419cc607e6cc13e854671fb9796f894a9d1faa6`. Both layouts use the same 300 MiB
prefaulted, nonmoving Immix arena, exact explicit root frames and archived
eight-byte field/array-element layout. V8 uses its default heap policy and
native i32 scalar arrays. Thus identical Wasm does not establish identical
physical storage or resident-memory policies.

Module/main setup, runtime input parsing and native arena prefaulting finish
before the workload timer. It encloses bench(count), its original final
predicate and the host acceptance assertion. Formatting and validation-counter
checks follow the timer. Compilation is excluded. Separate whole-process
medians from the same retained observations preserve both winners:

| Layout | V8 process seconds | LLVM process seconds | LLVM setup seconds |
| --- | ---: | ---: | ---: |
| Flat | 4.832313 | 2.402349 | 0.088927 |
| Blocks | 1.015894 | 2.333998 | 0.089247 |

Native setup includes prefaulting and module/main initialization. Process time
also includes launch, input loading, formatting and teardown. These medians are
computed from recorded process/setup values, not by subtracting unrelated runs.

[clean.json](clean.json), [plan.json](plan.json), [quiet-window.json](quiet-window.json)
and the unchanged [measurement driver](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-string-block-native-comparison/measure.py) preserve the observations and
protocol. [provenance.json](provenance.json) records source/artifact/tool identity,
the identical-Wasm checks, derived medians and unchanged native sources.
Full-count native block validation and a separate forced-GC count-one check are
archived alongside both layouts' exact Wasm, disassembly, LLVM, host objects,
native executables, inputs, build logs and manifests.

The bounded [archive](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-string-block-native-comparison/artifacts.tar.xz), [manifest](manifest.json) and
[path map](path-map.json) retain every frozen identity except external Nix/run
binaries, whose paths and hashes remain recorded. Inherited Rust reference
source bundles are included for identity completeness; no Rust cell is measured
in this matrix. Only the relevant native String build directories and supporting
source/validation records are added, without copying unrelated experiment trees.
Original file modes and absolute source mappings are preserved.

Restore and hash-check the archived files, then run four relocated count-one
correctness probes with the original non-count inputs and predicate:

```sh
python3 benchmarks/results/2026-10-14-string-block-native-comparison/replay.py \
  benchmarks/results/2026-10-14-string-block-native-comparison \
  /tmp/string-block-native-replay
```

[replay-check.json](replay-check.json) records those probes and verifies all
original archive members again afterward. They establish restored execution and
result acceptance, not new performance samples. A new clean timing comparison
requires remapped paths and a separately frozen observation set.
