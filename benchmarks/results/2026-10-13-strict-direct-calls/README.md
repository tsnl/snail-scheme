# Direct local calls: implementation and clean measurements

Passing captured lexical state directly to local procedures reduces quicksort
workload time by 36.7%. Graphs is unchanged, and mperm's median is 1.3% higher
in this batch. Fewer static construction sites do not establish a speedup.

| Original workload | Before, seconds | After, seconds | Original Chez | Same adapted source on Chez | After / adapted Chez |
| --- | ---: | ---: | ---: | ---: | ---: |
| quicksort, 2,500 × 10,000 values | 2.203270 | 1.393597 | 1.777212 | 1.756330 | 0.793× |
| graphs, 3 × 7 vertices | 3.840009 | 3.828682 | 0.765270 | 0.784589 | 4.880× |
| mperm, M:N:K:L = 20:10:2:1 | 17.321359 | 17.543191 | 4.576840 | 4.559850 | 3.847× |

These are medians from the same quiet window for each row. The compiler before
the change is `a4030ce190058db3e9d64f6942401b5fa38dbd58`; after is
`35d5baa52c2a0e25d0c86c02adefd661a6457a3b`. The subsequent `83dfe42` commit only
documents the implementation. All benchmark sources, inputs, original counts,
hosts and Chez binaries remain unchanged across the compiler comparison.
The quicksort baseline is byte-identical to the earlier frozen module.
The [enumeration preparation](../2026-10-13-strict-enumeration-ports/README.md)
records the bounded source adaptations and complete structural checks.

The compiler selects a local lambda binding when every concrete use is a call
operator. Its native function receives captured lexical state as extra
parameters, and its initializer publishes readiness at the original source
event. Transporting a payload and readiness flag does not read the source
binding: nullable references stay nullable until that original read. Operand
effects still precede the operator readiness check. Explicit Ref objects stay
shared, and bindings captured by surviving closures retain shared initialization
cells so later initialization remains observable. Proper tail calls remain
Wasm tail calls. Aliases, escaping values, globals and the current named-let
expansion conservatively retain closures.

The implementation changes `strict-specialize.sld` and `strict-wasm.sld` and
adds nine contracts. A fresh independent behavioral explanation and informed
critique preceded implementation; parent source review checked capture closure,
readiness, recursive activations, deferred reads and proper tail calls. The
cohesive twelve-line call dispatch remains an intentional exception to the
ten-line helper target. [Review and validation](review.json) records the evidence.

All 260 current strict contracts pass: a full 259-case run plus the separately
added final fixture. Executable cases run raw and optimized Wasm; rejection
cases check their expected diagnostics. All 20 real-provider external-boundary
contracts, `make test` and `make check` pass. The raw mutual-recursion fixture
contains actual `return_call` instructions and completes 100,000 calls.
Quicksort has 34 positive/boundary outcomes plus 12 parent-run expected
rejections of incorrect complete values or RNG sequences. Graphs has 20
canonical/supplemental outcomes, mperm 56, and both isolated sharing-observer
executions pass. Diagnostic observers remain separate from the canonical
enumeration modules.

In optimized quicksort, the partition's ten struct construction instructions
disappear. The change also exposes direct calls and captured scalar values to
optimization, so the measured gain is not an isolated estimate of allocation
or GC cost. Graphs retains the same audited operations and seven data layouts;
its CPS and named-let closures remain. Mperm removes some procedure scaffolding
while preserving inner/outer list payloads, explicit mutable Refs, shared tails,
the global plan's queue root, initial fill, fill-before-flush order and final
equality/sum traversal. Static Wasm does not establish equal dynamic allocation
or machine-code lifetime across V8 and Chez. Graphs still legally loses unused
result-list payloads while retaining fresh result-vector construction/filling.

Each workload has one discarded four-system round followed by four retained
rounds, rotating system order so each occupies every position. All observations
start fresh processes on logical CPU 5. Node 24.19.0 uses default V8 tiering,
without `NODE_OPTIONS`, profiling or heap/stack overrides. Other agents explicitly
paused build/test work. Workload clocks exclude initialization and include the
original repetitions and final predicate. Mperm's initial queue fill and
quicksort's base RNG/vector setup remain before the clock. Whole-process times
are recorded separately. All 60 executions pass their predicates and all
recorded artifact/tool hashes match before and after the window.

[Quicksort samples](clean-quicksort.json), [graphs samples](clean-graphs.json),
[mperm samples](clean-mperm.json), [summary and ranges](summary.json), and the
[quiet-window record](clean-window.json) preserve the measurements. Mperm's
old/new sample ranges overlap; the reported 1.3% change is this batch's observed
median, not a claim about a stable regression. The separate handwritten
[quicksort ablation](../2026-10-13-strict-quicksort-profile/README.md) remains a
different experiment with more aggressive private lowering.

The [archive](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-13-strict-direct-calls/artifacts.tar.xz) and [manifest](manifest.json) contain 663 exact
files: before/after modules, compiler source, original/adapted controls, input
and host files, checks, static inspection, and the measurement driver. The
[replay check](replay-check.json) independently verifies all members and runs
six bounded raw/optimized checks from the restored artifacts. Restore with:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/direct-call-replay \
  --report benchmarks/results/2026-10-13-strict-direct-calls
```

After coordinating a quiet CPU window, reproduce quicksort with:

```sh
python3 /tmp/direct-call-replay/measurements/measure-direct-calls.py quicksort \
  /tmp/direct-call-replay/before/quicksort \
  /tmp/direct-call-replay/after/quicksort/strict.wasm \
  /tmp/direct-call-quicksort-results.json
```

For graphs or mperm, use that workload name, `before/enumeration`, and
`after/enumeration/<name>/strict.wasm`. The driver checks canonical inputs and
uses the archived host and controls and records tool identities. This checkpoint adds
two measured strict workloads, bringing historical strict coverage to 23 of
57; it is not a fresh rerun of the other workloads or a complete-suite result.
