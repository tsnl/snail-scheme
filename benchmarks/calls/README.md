# Throwaway call optimization experiment

This directory documents an isolated experiment from production base `5ad489e`;
it is not a proposal to land the experimental pass. The source pass and harnesses
are preserved in `full-call-experiment.patch` under the saved evidence directory.
Production already emits direct workers
for immutable lambda bindings and runs Binaryen at inlining threshold 40 with
convergence. The prototype adds conservative information about aliases, callback
parameters, returned closures, and assigned bindings. Inlining thresholds 80 and
160 are separate Binaryen ablations.

## What the experiment changes

`src/snail-scheme/call-flow.sld` computes a finite set of possible lambda bodies
for each expression and binding. Scalar and opaque values have distinct markers.
The equations join all assignments and call arguments, including recursive call
edges. An opaque call or heap operation makes concrete closure arguments escape;
escaped procedures receive unknown arguments and their returned closures escape
transitively. Library results and the optional exported CLI handler seed the same
escape rule. A 256-round limit abandons the entire result if it cannot converge.

Only a singleton lambda set can add a direct call. The emitter still evaluates
all operands, then the actual operator, and extracts that closure's environment.
It retains initialization checks, argument normalization, declared entry/result
contracts, mutation, identity, and the existing proper tail-call machinery. An
arity mismatch or rest lambda uses the existing generic adapter. No representation
or numeric optimization changes, and no Scheme bodies are copied or rewritten.

An independent second ablation selects the existing uniform adapter for immutable
core primitive definitions. This covers primitives outside the production direct
primitive whitelist. Selection requires the exact resolved binding identity and
the existing whole-module exclusion of initialized or assigned definitions. The
actual operator is still read; its environment, argument vector, argument guards,
and suspended result-check context reach the original adapter unchanged. This
does not infer the procedure argument to `apply` or remove primitive checks.

Within the prototype both changes are disabled by default. `emit.scm` and `native.scm` select
`baseline`, `direct` (closure flow only), `primitives` (adapter selection only), or
`combined`. The threshold experiment applies only to baseline and closure flow.
The simplify skill's independent behavioral review checked the escape invariant,
including closures hidden in containers, callbacks returning callbacks, and
exported entry points. The implementation follows that model; exhaustive IR
dispatch and the fixed-point operation remain cohesive rather than split solely
to meet a line count. A separate explanation reviewed immutable adapter selection,
especially assignments through imported aliases and the `apply` tail context.

## Work and timing boundaries

The callback program creates a closure with different captured scale/bias values
on each traversal, aliases it, passes it to a higher-order fold, and checks an
independent closed-form answer after every traversal. The timed Scheme driver
performs 4,096 traversals of a preallocated 10,000-element vector. It is a focused
monomorphic-callback workload, not a prediction for arbitrary higher-order code.
It includes one complete in-process warmup before timing.

The unchanged `benchmarks/cpu.scm` and `benchmarks/memory.scm` programs are measured
at 256 and 64 repetitions respectively. Their existing untimed correctness checks
remain. The compiler uses `benchmarks/compile-self.scm` and an unchanged source
snapshot at `803d169`, which adds the independent append stack-usage and numeric
printing fixes needed for compiler self-compilation. The experimental pass is not
part of that input compiler; both executable variants compile the same frozen
production source and must match the Chibi reference WAT byte for byte.

Compilation and process startup are outside internal workload timers. V8 uses its
default tiering. Each executable starts in a fresh process. One full process run
per variant is discarded before samples. The first experiment uses ten rotating
main/native rounds and six alternating compiler rounds. The primitive experiment
uses eight rotating main/native rounds and four compiler rounds. All timed
processes are pinned to logical CPU 3 on an Intel Core Ultra 7 270K Plus. The parent
agent reserved quiet windows after its builds and benchmarks completed; unrelated
operating-system activity remains possible. Node is 24.19.0, Binaryen is 132, and
the compiler host is Chibi 0.12.0.

## Closure flow and larger inlining results

Median complete-workload seconds, with the existing threshold 40 unless stated:

| Executed program | Baseline | Closure flow | Baseline / flow |
| --- | ---: | ---: | ---: |
| Wasm callback driver | 0.48771 | 0.45735 | 1.066x |
| Wasm CPU program | 0.33247 | 0.33235 | 1.000x |
| Wasm memory program | 0.20785 | 0.20918 | 0.994x |
| Native callback driver | 1.99945 | 1.52507 | 1.311x |
| Wasm compiler compiling itself | 13.89105 | 13.68548 | 1.015x |

The focused callback result is repeatable within this run: all ten paired rounds
improve. The compiler's six paired ratios range from 0.982 to 1.045 and cross one;
its small median difference is inconclusive. These results do not establish a
general speedup range or support the proposed 5–10x gain.

Raising the global inlining threshold made every measured Wasm program slower:

| Executed program | Baseline 40 | Baseline 80 | Baseline 160 | Flow 80 | Flow 160 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Callback driver | 0.48771 | 0.82482 | 0.83276 | 1.33346 | 1.34233 |
| CPU program | 0.33247 | 1.23753 | 1.19359 | 1.14805 | 1.12310 |
| Memory program | 0.20785 | 0.36949 | 0.45856 | 0.36761 | 0.45846 |

This ablation changes Binaryen's global threshold; it does not measure a selective
Scheme IR inliner. The existing optimization pipeline already inlines at 40 and
converges. Avoid extrapolating these regressions to every possible inliner.

## Independent primitive adapter results

This second quiet window repeats the baseline and flow controls and adds the
two primitive adapter variants. All variants use threshold 40. Median seconds:

| Executed program | Baseline | Flow | Primitives | Combined |
| --- | ---: | ---: | ---: | ---: |
| Wasm callback driver | 0.48752 | 0.45639 | 0.47473 | 0.44236 |
| Wasm CPU program | 0.33285 | 0.33244 | 0.33255 | 0.33256 |
| Wasm memory program | 0.20770 | 0.20892 | 0.20717 | 0.20761 |
| Native callback driver | 1.99502 | 1.51975 | 1.99537 | 1.51420 |
| Wasm compiler compiling itself | 13.99375 | 13.52342 | 13.72123 | 13.75252 |

Primitive adapters alone improve the callback driver's median speed by 2.7%
(all eight paired ratios are 1.018–1.039), while CPU, memory, and native callbacks
are essentially unchanged. The compiler's four paired ratios are 1.003–1.045;
its 2.0% median gain is modest evidence from a small sample. Combining flow and
primitive adapters improves the callback driver by 10.2% in Wasm and 31.8% native.
The compiler results are too close and too few to establish an interaction
between the two options. No samples or outliers are discarded after the declared
warmups.

The small adapter substitution is a proportionate candidate for a production
change with integration checks and measurement on the final production stack.
It has a simple local proof, shrinks the compiler's Wasm, and provides a modest
measured benefit. Keep the general closure-flow pass and higher global inlining
thresholds experimental; their cost and limited coverage do not justify a broad
production refactor.

## Static call sites and costs

Counts are syntactic calls in emitted Scheme worker/library bodies before
Binaryen, not execution frequencies. They exclude runtime helper definitions.
The final column is linked optimized Wasm bytes at threshold 40.

| Program / mode | Direct Scheme workers | Direct primitive adapters | Generic apply | Wasm bytes |
| --- | ---: | ---: | ---: | ---: |
| Callbacks / baseline | 106 | 0 | 80 | 286,743 |
| Callbacks / flow | 119 | 0 | 67 | 288,023 |
| Callbacks / primitives | 106 | 43 | 37 | 287,786 |
| Callbacks / combined | 119 | 43 | 24 | 288,994 |
| CPU / baseline | 137 | 0 | 92 | 295,398 |
| CPU / flow | 151 | 0 | 78 | 295,979 |
| CPU / primitives | 137 | 51 | 41 | 297,721 |
| CPU / combined | 151 | 51 | 27 | 298,295 |
| Memory / baseline | 159 | 0 | 114 | 311,732 |
| Memory / flow | 175 | 0 | 98 | 316,669 |
| Memory / primitives | 159 | 70 | 44 | 314,390 |
| Memory / combined | 175 | 70 | 28 | 319,334 |
| Compiler / baseline | 4,683 | 0 | 1,878 | 1,923,993 |
| Compiler / flow | 4,775 | 0 | 1,786 | 2,298,541 |
| Compiler / primitives | 4,683 | 989 | 889 | 1,904,972 |
| Compiler / combined | 4,775 | 989 | 797 | 2,278,783 |

The primitive adapter change removes 52.7% of the compiler's remaining generic
application sites. The flow pass removes 4.9%. The flow compiler binary grows
19.5%; primitive adapters alone shrink it 1.0%. Source call counts do not identify
which sites dominate runtime, and Binaryen/V8 can optimize generic dispatch too.

Build durations are separate, single preparation observations made while other
work sometimes ran; they are not controlled build-speed comparisons. Closure
analysis itself takes 18–27ms for the small programs and 3.273s for the compiler
(54 rounds, 37,382 nodes). Small-program traced emission changes from
0.595/0.640/0.689s to 0.623/0.671/0.715s. Compiler emission changes from 31.201s to
25.296s despite adding the pass: its hash lookup also bypasses some existing
linear known-lambda lookups. That incidental compiler implementation effect must
not be confused with faster execution of the compiled compiler.

Larger inlining produces substantial code growth and build cost. For example,
the CPU binary grows from 295,398 bytes to 1,169,562 at threshold 80; its Binaryen
step takes 54.999s instead of 0.597s in the recorded preparations. The combined
flow/threshold-160 CPU binary reaches 1,384,481 bytes. Native callback emission,
LLVM translation, and Clang preparation are traced separately in the saved
reports; native compiler-self performance and larger native inlining settings
were not measured.

## Reproduction

Use the tools and BDWGC environment described in `doc/backend.md` and
`doc/native.md`. The complete source patch also applies to the review stack's PE
layer, so unpublished experiment commits are not required:

```sh
call_evidence=/path/to/2026-10-10-call-prototype
git worktree add -b experiment/reproduce-calls /tmp/snail-reproduce-calls 464f19f
cd /tmp/snail-reproduce-calls
git apply "$call_evidence/full-call-experiment.patch"
```

The commands below repeat the experiment on the review stack's compiler graph.
The original emission hosts are separately preserved in `frozen-host-inputs.tar.gz`
when the historical source hashes are needed. Each archive directory contains
the original compiler, runtime source, workload sources, and emission harness.
From the new worktree's root:

```sh
mkdir -p build/call-prototype
cargo rustc --crate-type=cdylib --offline --release --target wasm32-wasip1 \
  --target-dir build/call-prototype/runtime-build
cp build/call-prototype/runtime-build/wasm32-wasip1/release/snail_runtime.wasm \
  build/call-prototype/runtime.wasm
python3 benchmarks/calls/measure.py \
  --runtime build/call-prototype/runtime.wasm \
  --output build/call-prototype/reproduction-flow --build-only
python3 benchmarks/calls/measure.py --primitive-adapters \
  --runtime build/call-prototype/runtime.wasm \
  --output build/call-prototype/reproduction-primitives --build-only
for mode in baseline direct primitives combined; do
  chibi-scheme -h512M -I src benchmarks/calls/native.scm "$PWD" \
    "$PWD/benchmarks/calls/callbacks.scm" \
    "$PWD/build/call-prototype/callbacks.native-$mode" "$mode"
done
mkdir build/call-prototype/compiler-source
tar -xzf "$call_evidence/compiler-input-803d169.tar.gz" \
  -C build/call-prototype/compiler-source
cargo rustc --manifest-path build/call-prototype/compiler-source/Cargo.toml \
  --crate-type=cdylib --offline --release --target wasm32-wasip1 \
  --target-dir build/call-prototype/compiler-runtime-build
cp build/call-prototype/compiler-runtime-build/wasm32-wasip1/release/snail_runtime.wasm \
  build/call-prototype/compiler-runtime.wasm
python3 benchmarks/calls/compiler-probe.py
python3 benchmarks/calls/compiler-probe.py --primitive-adapters
```

`measure.py` freezes source files before emission, assembles and merges the full
Rust-linked Wasm modules, and varies call selection and the inlining threshold.
Its report contains commands, build durations, trace events, source/artifact
hashes, sizes, and static call counts. `sample.py` verifies those hashes before
sampling existing artifacts. The native path uses the unchanged production
Wasm-datum-to-LLVM translator and Clang settings. The compiler probe consumes an
archived `803d169` source tree and a runtime built from that same revision.
The separate preparation preserves the source baseline and avoids measuring
compilation concurrently with execution.

```sh
python3 benchmarks/calls/sample.py \
  --report build/call-prototype/reproduction-flow/report.json \
  --cpu 3 --rounds 10 --compiler-rounds 6 \
  --competition-note 'Describe other work running on the host.'
python3 benchmarks/calls/sample.py \
  --report build/call-prototype/reproduction-primitives/report.json \
  --compiler-report build/call-prototype/compiler-primitive-probe/report.json \
  --cpu 3 --rounds 8 --compiler-rounds 4 \
  --competition-note 'Describe other work running on the host.'
python3 benchmarks/calls/verify.py --mode combined --all-typing \
  --output build/call-prototype/verification-combined-all
python3 benchmarks/calls/verify-native.py
```

## Correctness evidence

`make test`, `make check`, and `git diff --check` passed. The experiment executed
68 linked Wasm checks: the existing backend successes/errors, polymorphism and
typed-tail counterexamples, and a new semantics fixture under baseline/direct
and the larger inlining thresholds. The fixture exercises operand/operator order,
changing closure environments, identity, mutation, opaque callbacks, callbacks
returning callbacks, rest arguments, multiple values, initialization errors,
checked domains/results, and 200,000 tail transfers.

The second experiment executes 101 linked Wasm checks with both options enabled,
including all runtime `CASES` from `scripts/test-typing`, and all 28 native backend
success/error executions. The native hash-table fixture uses collection interval
97. These are the optimized typing mode; the parent separately ran the full
production guarded/optimized matrix. The custom native semantics fixture passes
with `SNAIL_NATIVE_GC_INTERVAL=17`, including all four expected failure modes.

`primitive-semantics.scm` additionally checks effects, mutation through a renamed
import, and 200,000 tail calls through `apply`: all four Wasm modes and baseline/
combined native executions pass. All native callback variants produce the same
checksum. All three baseline workload WAT files are byte-identical to emission
by the original production compiler; the second experiment's baseline and flow
WAT files also exactly match their first-experiment controls. Every timed compiler
output is checked against the same Chibi reference digest.

## Preserved evidence and limits

Raw reports are in `benchmarks/results/2026-10-10-call-prototype/`. They retain
individual samples and order, checksums, source and artifact hashes, exact build
commands, code sizes, and compiler traces. Paths inside those reports point to
the original isolated worktree's ignored `build/call-prototype/` artifacts. The
first pass is committed as `6dece2b`; immutable primitive selection is `4b49f63`.
The frozen compiler workload stays at `803d169`, independent of later production
metadata-indexing changes. No production stack branch was modified.

`full-call-experiment.patch` preserves the experimental compiler changes and all
source harnesses; its application was checked against `464f19f` without changing
that branch. `compiler-input-803d169.tar.gz` contains every compiler input covered
by the saved compiler source manifest plus the Cargo/native build inputs.
`frozen-host-inputs.tar.gz` preserves both original emission hosts and their
source manifests. The archive SHA256 values are recorded in `provenance.json`.

`benchmarks/calls/primitive-adapter.patch` is the separate candidate production
change. It applies cleanly at integration commit `7ac47fd` and includes only the
adapter dispatch substitution, without flags or the flow pass. It was extracted
from the tested prototype but not applied to production. Its proof relies on
preinitialized core bindings, canonical definition identity, complete mutation
exclusion, immutable closure code, and unchanged operand/operator/guard and
tail/result-context handling. The parent owns final integration validation.

The closure analysis is intentionally context insensitive: closures hidden in
objects, opaque callbacks, and polymorphic uses lose precision. It does not give
each closure a unique Wasm type or monomorphize shared higher-order functions.
Those approaches remain unmeasured. Static calls can expose inlining opportunity,
but fewer indirect sites alone do not predict runtime benefit. The focused native
callback gain justifies further targeted experiments; these results do not
justify a broad closure representation refactor or a higher global threshold.
