# Self-hosting investigation

The compiler remains hosted by Chibi. The execution target is WasmGC; the LLVM
backend and custom collector have been retired. A compiled compiler could reduce
Scheme pass costs, but there is no self-hosted compiler or measured self-hosting
speedup yet. The observations below are historical diagnostics, followed by the
current bootstrap boundaries and proposed acceptance criteria.

## Current boundary

The product [`(scheme base)`](../src/scheme/base.sld) expands an initial typed
Scheme subset into Lofi. It shares hygienic macro expansion, resolution, checking
and the WasmGC backend. It does not implement the full Scheme environment used
by the compiler itself. [`bootstrap/`](../bootstrap/README.md) keeps Chibi's
implementation libraries separate from product imports.

The public [`(lofi compiler)`](../src/lofi/compiler.sld) is a scalar service
interface; [`CompilerHost`](../src/lofi/compiler/service.mjs) starts Chibi to
implement it. Compiling a caller of that service does not compile the compiler
passes. A launcher that still invokes Chibi is not self-hosting.

## Historical build observations

On 2026-10-17, Linux x86-64, Intel Core Ultra 7 270K Plus, Chibi 0.12.0,
Binaryen 132 and Node 24.19.0, with `BINARYEN_CORES=1`:

| Observation | Seconds |
| --- | ---: |
| Original app build, first wall-time sample | 152.968 |
| Original app build, second wall-time sample | 149.226 |
| First instrumented diagnostic | 120.935 |
| Second instrumented diagnostic, final recorder | 104.903 |
| Resolution in the first diagnostic | 2.030 |
| Checking | 32.303 |
| Concrete preparation/specialization | 9.954 |
| Wasm IR emission | 65.300 |
| Artifact construction, including external tools | 1.432 |
| Binaryen assembly + optimization, contained in artifact construction | 1.283 |

The first sample used compiler revision `62f4e0d6`; the second sample and first
profile used `a1c8ec37`, which only adds the measurement command. The final
recorder at `5710a39a` removes a duplicate WAT span and adds these notes. All four
runs compiled the same compiler and application sources, and all shader and
simulation Wasm hashes matched. The table reports first-diagnostic phase totals
for both entry compilations. WAT writing took 0.033 seconds, separate from the
much larger Wasm IR emission cost. The second diagnostic attributed 52.647 seconds
to emission, 28.759 to checking, 10.501 to specialization and 1.280 to Binaryen.
The instrumented runs' lower totals are **not speedup results**: instrumentation,
allocation/GC and machine variability can change these costs. Use its spans to
locate expensive work, not to infer clean phase times or a native speedup.

The retained [measurement summary](measurements/self-hosting-2026-10-17.json)
records commands, identities, hashes, phase totals and readiness diagnostics.
`$REPO` in that file stands for the local checkout path. Raw logs, traces and
artifacts remain in the named ignored `build/` directories; the commands below
regenerate them. This is a small observational sample, not a statistical result.

These are build observations on one machine and compiler/application revision, not a controlled
comparison against the reported 7–8 minute build. In particular, this checkout
contains the prototype Siegework plus derived serialization; it does not contain
the larger colony application from PR #302. The measurements include shader and
simulation compilation and browser packaging, but neither native compilation of
the simulation nor a self-hosted compiler. They do not establish a native
speedup. The existing 57-workload runtime comparison is unchanged.

## Reproduce the measurements

Use the repository's normal development environment. Choose fresh directories
whose parent already exists:

```sh
mkdir -p build
node scripts/measure-siegework.mjs baseline build/siegework-baseline-1
node scripts/measure-siegework.mjs baseline build/siegework-baseline-2
node scripts/measure-siegework.mjs profile build/siegework-profile-1
node scripts/measure-siegework.mjs hotspots build/siegework-hotspots-1
scripts/view-traces build/siegework-hotspots-1/app/build.trace.json
```

Run these sequentially without other compilation or profiling jobs. Keep sources
fixed for each invocation. The tool defaults `BINARYEN_CORES` to `1`, accepts an
explicit override, and records the effective value. Baseline runs the original
app driver and sources, including the driver's existing reader trace. Cache state,
CPU scheduling and other machine load remain uncontrolled; collect more samples
before making small performance claims. Use the same source revision, tools,
threading and cache policy when comparing another host.

Each run retains command arguments, source revision/status/diff, tool versions,
selected environment overrides, machine/load information, a merged `build.log`,
monotonic wall time and process status. Successful runs also retain artifact sizes
and SHA-256 hashes. Pre/post source identity checks reject observed source changes.
This is recorded provenance, not a hermetic build: keep product sources tracked
and record any additional untracked inputs separately. A failed command leaves
its evidence directory and returns nonzero; it never overwrites an existing run.

Profile uses private copies of the compiler libraries beneath the output directory. It
requires exactly one match for each instrumentation site and puts that loader
view first. It verifies that the expected phases actually ran. No production
source is patched. The copied compiler decorates resolution, checking, concrete
preparation, Wasm emission and artifact construction. The copied artifact module
also decorates artifact reading and retains the normally deleted WAT-writing and
Binaryen traces as `artifact-*.trace.json`. `instrumentation.json` hashes the
original and copied sources. Inspect `result.json` for phase totals and load the
raw trace files in the existing trace viewer.

The current recorder follows the `src/lofi/compiler/` layout and imports
`(lofi host chromium-trace)` through `bootstrap/`. The retained observations above
belong to their recorded revisions before this layout change.

The [profiling helper](../src/lofi/compiler/profile.sld) now also instruments
individual binding checks and generalization groups, emitted functions and module
initialization. Function and binding spans carry source file/line/column labels;
activation preparation, binding planning and obligation settlement have nested
operation spans. Its fixed recipes must match every selected definition exactly
once before compilation starts. The driver verifies that source-unit spans exist.

`hotspots` adds aggregate timing for frequently called helpers: overload trials,
concrete typing, layout lookup, local allocation and related operations.
`operations.json` records attempted calls, inclusive time and self time by phase.
Self time excludes other measured helpers only. Raised trials still count;
`dynamic-wind` restores timer nesting without intercepting their exceptions.
Reports are saved after completed phases; failed builds retain the last completed
report and any completed trace spans. Coarse `profile` mode leaves those hot
helper procedures unwrapped. It still records source-unit spans and their totals.

These wrappers retain an exit obligation and are deliberately confined to
compiler diagnostics. They change allocation and stack shape and do not preserve
tail-call space behavior at instrumented boundaries. Helper clock reads add
further overhead; use counts and substantial totals, not millisecond differences
between individual calls. The existing Chibi trace clock has millisecond wall-time
resolution; backward steps clamp to zero. Do not instrument every recursive
source visitor or emit one trace event for every type comparison.

Spans are inclusive. `lofi.artifact` includes WAT writing, assembly, optimization
and artifact reading recorded in its separate trace; do not add that parent span
to its children. The outer trace also records reader work. Unattributed wall time
includes host startup, other orchestration and browser packaging. Instrumented
runs are diagnostics, not clean timing samples. Compare the two Wasm hashes
between modes to check whether the decorations changed generated artifacts;
matching bytes do not prove every runtime behavior correct.

## Historical overload diagnosis

The [follow-up profile record](measurements/overload-profile-2026-10-17.json)
contains operation totals, the experimental patch, and artifact hashes.
A follow-up granular diagnostic found that speculative overload compatibility
trials dominate both phases. Checking attempted 136,363 trials; specialization
and emission each attempted 185,706. Aggregate inclusive time in compatibility
was 16.441 seconds during checking, 8.795 during specialization and 81.599 during
emission in that diagnostic. These are instrumented measurements, not clean
phase costs. Most other measured emission work was much smaller: activation
scanning took 1.905 seconds, layout work 1.715 and local allocation 0.460.

`compatible?` copies trial types and uses `guard` around `unify!` to reject
incompatible candidates. A mismatch raises an exception. The cost of those
exceptions depends on the surrounding compiler stack. A small probe performing
2,000 scalar mismatch trials took 0.009 seconds at depth zero, 0.064 at depth 500
and 0.241 at depth 5,000. The same obviously incompatible comparison returned
without raising in 0.000–0.001 seconds at all three depths.

The final recorder was validated on a complete build at `1d86722a`: 535 emitted
function spans and 711 initializer-check spans were recorded, with identical
shader and simulation Wasm. It again counted the same compatibility trials.

A private overlay experiment added a conservative type-shape filter before the
existing trial. Variables still pass through to the original unifier; only
already contradictory shapes are rejected early. Its complete build took 38.557
seconds, with identical shader and simulation Wasm. Simulation checking took
12.518 seconds and emission 11.876. This was an instrumented experiment, separate
from the original baseline. The later [production filter](overload-performance.md)
and [3D compilation changes](compilation-performance.md) have their own ordinary
build measurements. They demonstrate avoidable host work before self-hosting.
The unifier remains responsible for rigid variables, repeated-variable consistency,
occurs checks and diagnostics.

## Remaining dependencies

The old native readiness probes and native bootstrap proposal are preserved in
[the pre-removal investigation](https://github.com/tsnl/snail-scheme/blob/e528eb28f07650b8f61046572feb233fec9a9fe5/doc/self-hosting.md).
Their first-failure diagnostics belong to those revisions; they are not a current
compatibility inventory. In particular, `scripts/build-native` is no longer a
command in this checkout.

Compiling the hosted Scheme sources requires broader support for records,
heterogeneous data, general truthiness, exceptions, multiple values, parameters,
identity tables, exact numeric decoding and host I/O. Each dependency needs an
explicit representation and actual execution evidence. `Any` is the dynamic
option: projections must be checked until the compiler proves them safe. It does
not by itself supply Scheme data operations, mutable-pair semantics or libraries.
The scope of a typed port versus broader Scheme support remains a separate
implementation decision; neither route is complete today.

## Proposed bootstrap

`bootstrap` is proposed, not implemented. It should use Chibi as stage 0 to
compile the compiler passes to WasmGC and leave an executable launcher in the
current directory. That launcher needs an engine and explicit host services;
bundling the engine is a separate packaging decision. The compiler it runs must
execute the passes itself instead of forwarding them to Chibi.

1. Port or implement the compiler's actual dependency closure, keeping located
   syntax, resolved IR, type evidence and pass boundaries visible. Compare each
   pass with Chibi on the same inputs before switching hosts.
2. Build stage 1 with Chibi, then execute it on real programs, including Siegework.
   Keep external tool execution and scalar-resource ownership explicit.
3. Have stage 1 compile stage 2 and stage 2 compile stage 3 from the same sources.
   Run with Chibi unavailable and compare deterministic Wasm/IR outputs. Record
   launcher and engine metadata separately from generated program bytes.
4. Run correctness checks for macro identity, located failures, numeric boundaries,
   initialization, proper tail calls and foreign resources. Preserve the complete
   57-workload comparison, failures and historical limitations.
5. Measure clean end-to-end builds with matched inputs, tool versions and cache
   policy. Profile allocation and engine behavior before changing representations.

## What would count as a speedup?

Measure the Chibi and stage-2 compiler against the same Siegework revision,
optimization flags, engine and provider/tool versions, with several sequential
samples.
Include every stage needed by the requested command. Report the distribution of
compiler-pass time, external tool/link time and total time, alongside correctness
and artifact evidence. A faster kernel microbenchmark or faster launcher startup
is insufficient evidence about the demo build.

If fraction `f` of total time can be sped up by factor `s`, the predicted overall
speedup is `1 / ((1 - f) + f / s)`. This is an estimate under a fixed workload,
not a result: it excludes changes in allocation, GC, algorithm costs and external
tools. The diagnostic phase breakdown can identify the opportunity; only a
working stage-2 compiler can measure the actual speedup.
