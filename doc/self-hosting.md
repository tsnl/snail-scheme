# Native self-hosting investigation

> Historical investigation: the LLVM backend and custom native runtime have been
> removed. Commands and native-bootstrap plans below describe earlier revisions.
> The current self-hosting target is WasmGC on an engine such as V8; that milestone
> remains unimplemented. See [the current build contract](backend.md).


A native compiler could reduce Siegework's build time by running its Scheme
passes as compiled code. Compiling a command that calls the current public
`(lofi compiler)` service would still run those passes in Chibi. There is no
self-hosted compiler or measured self-hosting speedup yet.

This is a design and measurement milestone. It adds a reproducible measurement
command, compatibility probes and a bootstrap plan. It does not change the
compiler, its language contract, or the default `lofi` command.

## What works today

The product [`(scheme base)`](../src/scheme/base.sld) expands typed Scheme forms
into Lofi. Scheme programs already use the Wasm and native backends: building
`examples/scheme-fibonacci.sld` with `scripts/build-native` and executing the
result prints `832040` with exit status zero.

The compiler implementation uses Chibi's considerably larger Scheme environment.
[`bootstrap/`](../bootstrap/README.md) deliberately keeps that environment separate
from the product Scheme libraries. The public
[`(lofi compiler)`](../src/lofi/compiler.sld) is a scalar service interface;
[`CompilerHost`](../src/lofi/compiler/service.mjs) starts Chibi to implement it.
A native provider for that service is not currently supplied. Making that
provider start Chibi would provide a useful adapter, but would not move checking,
specialization or emission into native code.

## Build observations

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

The current recorder follows the `src/lofi/compiler/` layout and imports native
trace utilities through `bootstrap/`. That include root also exposes `src/native/`;
no separate legacy package search path is needed. The retained observations above
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

## Why checking and emission are expensive

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
12.518 seconds and emission 11.876. This is an instrumented experiment, separate
from the original baseline; a production optimization and clean measurements
belong in the follow-up fix PR. It identifies avoidable host work without needing
to self-host first. The existing unifier must remain responsible for rigid
variables, repeated-variable consistency, occurs checks and diagnostics.

## Reproduce the readiness probes

These commands use today's tools; the `snail` interface below is proposed.
Run from the repository root. Each negative probe stops at its first failure,
so this is evidence of blockers, not an exhaustive language conformance audit.

```sh
mkdir -p build/self-hosting-probes
scripts/build-native examples/scheme-fibonacci.sld build/self-hosting-probes/fibonacci
build/self-hosting-probes/fibonacci
scripts/build-lofi src/lofi/compiler/bootstrap.sld build/self-hosting-probes/compiler.wasm
```

The native control prints `832040`. Compiling the compiler currently fails in the
reader at `compiler/bootstrap.sld:30:23`, at the `library:` identifier prefix.
A smaller independent import probe reaches the explicit unsupported-modifier
error:

```sh
cat > build/self-hosting-probes/prefix.sld <<'SCHEME'
(import
 (prefix (scheme base) s:))
42
SCHEME
scripts/build-lofi build/self-hosting-probes/prefix.sld build/self-hosting-probes/prefix.wasm
```

A native service probe reaches the missing provider declaration for
`("lofi.compiler" "result-ok")`:

```sh
cat > build/self-hosting-probes/service.sld <<'SCHEME'
(import
 (scheme base)
 (only (lofi compiler) empty-library-map))
(define libraries (empty-library-map))
42
SCHEME
scripts/build-native build/self-hosting-probes/service.sld build/self-hosting-probes/service
```

Source inspection identifies larger compatibility decisions behind these first
errors:

| Compiler use | Current product boundary | Port decision |
| --- | --- | --- |
| `define-record-type`, field setters and object identity in `types.sld` and `ir.sld` | Typed data declarations and explicit mutable storage | Give solver holes, bindings and IR nodes concrete types and preserve identity. |
| Quoted/quasiquoted heterogeneous data throughout types, macros and WAT emission | Typed homogeneous lists; no general Scheme datum syntax | Use explicit datum values where data is genuinely heterogeneous; use typed records/unions for compiler structures. |
| Object-or-`#f` lookups and general truthiness | Conditions require `Bool` | Represent absence explicitly and preserve lookup/equality semantics. |
| Parameters, `guard`, variadic/multiple-value helpers and mutable pairs | Initial Scheme surface, not the complete Chibi environment | Audit actual uses; port to explicit compiler context/results or implement a deliberately scoped library capability. |
| Identity hash tables and comparators in inference/library resolution | Chibi/SRFI imports do not become product libraries automatically | Supply typed tables with stable binding identity and measured costs. |
| Exact integers and rationals in `numeric-literals.sld` | Fixed-width default arithmetic plus explicit numeric libraries | Preserve exact source decoding and IEEE rounding with deliberate numeric representations. |
| Files, ports, temporary directories and subprocesses | Chibi orchestration plus Rust scalar services | Give the native command explicit resource-owning host operations. |
| Wasm construction, WAT reading/writing and LLVM emission | Native lowering is also implemented in hosted Scheme | Port the full native build closure, including the backend libraries, not just its command wrapper. |

Extending the Scheme frontend is one possible approach. Compiling the compiler
unchanged would require a substantially wider Scheme implementation, beyond
fixing an import spelling or adding `define-record-type`. The proposed first port
keeps the typed language and gives compiler data concrete representations, using
Scheme surface forms where they fit. It should not silently introduce universal
dynamic values or change existing Scheme numeric behavior to get a bootstrap.
The exact port scope needs a separate implementation review.

## Proposed `snail` command and bootstrap

The eventual command is a native executable containing the compiler passes.
These commands are proposed, not implemented:

```sh
snail run program.sld -- argument
snail build program.sld -o program
```

`run` resolves the source graph, checks and specializes it, emits Wasm, lowers it
through the native backend, links the selected providers and executes the native
program immediately. `build` performs the same compilation without executing the
result and is also used to rebuild the compiler. Keep map-based Wasm compilation
available for shader and browser build composition. Hosting the compiler natively
can produce the same Wasm artifacts measured here; `snail run` additionally pays
for native lowering and linking and needs its own timing. Preserve explicit
library roots, provider choices, located diagnostics and the existing initialization/exit-status
rules. The first implementation can execute a linked child executable; an
in-process native loader is a separate optimization. Report compile/link and
program execution time separately.

External Binaryen, LLVM and Rust tools remain allowed. The self-hosted command
must not invoke Chibi or delegate compiler passes back through the current
compiler service. A compiled launcher or a native provider that invokes Chibi is
not bootstrap completion.

1. **Measure the existing host.** Retain the current baseline and profile, identify
   expensive passes and add representative compiler-scale correctness inputs.
2. **Port one dependency closure.** Start with located syntax and compiler data,
   then resolution/expansion, inference, concrete preparation and Wasm emission.
   Keep pass boundaries and frontend behavior stable. Compare their results with
   Chibi before making native execution the default. Port host I/O and native
   build orchestration with explicit handles and cleanup.
3. **Build stage 1 with Chibi.** Stage 0 is the existing Chibi-hosted compiler;
   it compiles the ported compiler through Wasm and the native backend into
   `snail.stage1`. Execute it on real programs, including Siegework.
4. **Rebuild the compiler natively.** Stage 1 builds stage 2 from the same sources;
   stage 2 builds stage 3. Verify both generations execute the compiler passes
   themselves with Chibi unavailable. Compare deterministic Wasm/IR outputs;
   account explicitly for native build metadata before requiring binary equality.
5. **Gate the switch with evidence.** Run the relevant correctness suites and
   actual native execution, including macro identity, located failures, numeric
   edge cases, proper tail calls, collector roots and foreign resource ownership.
   Preserve the complete 57-workload comparison and its existing limitations.
   Measure clean end-to-end builds with matched inputs and a recorded cache policy.

Compiler modules allocate many short-lived objects and depend heavily on identity.
A successful bootstrap alone would not establish good native GC behavior or a
speedup. Profile the native compiler before changing collector or representation
policy. Keep any such implementation work in follow-up PRs.

## What would count as a speedup?

Measure the Chibi and stage-2 compiler against the same Siegework revision,
optimization flags and provider/tool versions, with several sequential samples.
Include every stage needed by the requested command. Report the distribution of
compiler-pass time, external tool/link time and total time, alongside correctness
and artifact evidence. A faster kernel microbenchmark or faster launcher startup
is insufficient evidence about the demo build.

If fraction `f` of total time can be sped up by factor `s`, the predicted overall
speedup is `1 / ((1 - f) + f / s)`. This is an estimate under a fixed workload,
not a result: it excludes changes in allocation, GC, algorithm costs and external
tools. The diagnostic phase breakdown can identify the opportunity; only a
working stage-2 compiler can measure the actual speedup.
