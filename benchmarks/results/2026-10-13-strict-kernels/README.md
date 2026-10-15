# Strict Scheme kernels against Chez, October 13

Ten additional strict Scheme workload ports pass their original results and
full repetition counts. Against the original Chez programs, three run faster,
one is close, and six remain slower. These are the same source algorithms and
inputs with narrower numeric types and different, documented harnesses. This
is not the complete suite and does not establish equal type information.

## Final balanced batch

Node 24.19.0 / V8 13.6.233.17, Binaryen 132, Chez 10.4.1 at optimization level 2,
CPU 5 on an Intel Core Ultra 7 270K Plus. All programs start in fresh processes,
with default V8 tiering. One discarded complete run precedes three retained
runs; benchmark order rotates and each Snail/Chez pair alternates execution
order between retained rounds. Compiler and test work was paused during timing.

| Workload | Strict Wasm seconds | Original Chez seconds | Strict / Chez time |
| --- | ---: | ---: | ---: |
| tak | 0.855492 | 0.641301 | 1.334× |
| cpstak | 4.650325 | 1.786547 | 2.603× |
| fib | 2.126661 | 1.371830 | 1.550× |
| fibfp | 0.387841 | 0.861814 | 0.450× |
| sum | 1.301087 | 1.034341 | 1.258× |
| sumfp | 1.113966 | 1.098015 | 1.015× |
| takl | 1.063951 | 2.517069 | 0.423× |
| ntakl | 0.950972 | 2.515974 | 0.378× |
| diviter | 1.097792 | 0.771113 | 1.424× |
| divrec | 1.812745 | 0.935844 | 1.937× |
| ack | **Default-stack failure** | Not timed in this batch | — |

Ratios below 1 mean strict Wasm takes less time. Every one of the 80 warmup and
retained observations passes its result predicate. [Raw observations](results.json)
include workload and process times, command lines, outputs, and artifact hashes.
No benchmark was shortened. Original counts range from one full Takeuchi run
to one million list-allocation runs. The allocation workloads each create
500 million result-list nodes in their source algorithm; representation
optimization is allowed, and this is not a measured allocation count.

An [earlier batch](initial-fixed-order-results.json) used these same compiled
artifacts but accidentally kept system order fixed within each benchmark pair.
Its observations remain archived. The table uses the corrected balanced batch.

## Explicit floating-point operations in Chez

The strict ports use native F64 operations while original Chez source uses
ordinary generic arithmetic. A separate paired control changes only Chez's
kernel arithmetic/comparison operators to `fl+`, `fl-`, and `fl<?`. The original
Chez harness, input, repetition count, and predicate stay in place. Strict
artifacts are unchanged and are remeasured in this control's own balanced
window, rather than reusing earlier strict timings.

| Workload | Strict Wasm seconds | Chez with explicit flonum operations | Strict / Chez time |
| --- | ---: | ---: | ---: |
| fibfp | 0.387403 | 0.397889 | 0.974× |
| sumfp | 1.113788 | 1.152400 | 0.966× |

These paths are within about 3%: the original floating Fibonacci advantage is
largely removed when Chez receives explicit floating-point operations. This
provides comparable arithmetic information without claiming identical compiler
knowledge. [Control samples](flonum-results.json) retain all 16 observations.

## What the code shows

The [code audit](code-audit.json) identifies exact module hashes and separate
V8 machine-code diagnostics. Optimized WAT retains the repeating kernel work;
TurboFan disassembly additionally confirms it for `sum` and `diviter`.
`diviter` still loads list links and allocates new nodes before repeating.
This is stronger evidence than a correct final answer alone, but it is not a
dynamic instruction/allocation count for every workload.

Concrete representations enable useful optimizations. In `takl` and `ntakl`,
Binaryen removes unused element fields entirely: a node contains only the next
reference. The source algorithms and list results remain equivalent, although
physical layouts differ from Chez. Native F64 values stay unboxed.

Remaining work is visible too. The integer summation worker still casts its
closure environment, checks readiness, follows captured closure fields, and
tail-calls itself for each addition. Those operations survive V8 optimization.
Continuation-passing Takeuchi still allocates closures and environments, with
recursive-binding readiness cells in the captured state. These are concrete
optimization targets; this batch does not attribute an exact fraction of time
to any one mechanism. Binaryen also expands Fibonacci considerably: optimized
I64 and F64 modules are 50,344 and 70,336 bytes. No inlining ablation was measured.

Ackermann's raw module passes the first behavior check, but its optimized module
exceeds V8's default stack. Disabling Liftoff also fails. The same optimized
module returns 32765 for the full two repetitions with `--stack-size=4096`.
That is a separate diagnostic, not a passing default-configuration result or a
speed comparison. Its commands and failures are archived.

## Timing and type limits

The strict timer includes one native `bench(count)` call, repeated kernel work,
host opacity calls, and final validation. Initial list construction precedes
it. Final list length is computed in Wasm; the scalar equality assertion is in
JavaScript before stopping the timer. Chez uses its original complete harness.
Startup, input parsing, compilation and instantiation are excluded from workload
time; tiering during execution is included.

Numeric hide sites use typed value-returning imports. List hide sites use a
Boolean barrier and runtime-created list globals. The barrier alone does not
hide a known value. Diagnostic opacity counters are enabled only for behavioral
validation, not for the clean runs. These differences remain part of the result;
the ratios do not isolate the engine, collector or inference pass.

Integer ports use I64, floating ports F64. Their original inputs and all
intermediate values fit those representations. `diviter` and `divrec` add an
explicit `List (List Never)` annotation for the otherwise unconstrained empty
inner lists. Generated source and original source are both preserved. No
compiler/runtime implementation changes were made for these measurements.

## Coverage and reproduction

[Coverage](coverage.json) lists all 57 upstream workloads: ten measured here,
`cat` and `wc` measured separately, Ackermann failing at the default stack, and
44 not yet ported to the strict entry. In particular, `graphs` needs mutable
vectors, `deriv` needs symbolic expression representations, and `lattice` needs
mutable pairs and heterogeneous products. No new full-suite geometric mean is
claimed. The earlier complete-suite results remain historical comparisons.

The 40 raw/optimized behavior checks execute one and two repetitions of each
passing kernel before clean measurement. The final compiler source files are
unchanged from draft-stack commit `93f34a9`; snapshots and hashes are recorded.
The archive includes all prepared sources, raw/optimized Wasm, disassembly,
Chez artifacts, tool identities, both timing batches, flonum controls and
failed preparation/stack diagnostics. See the [driver](../../strict-suite/README.md)
for commands and precise source adaptations. The manifest covers every archived
file. Restoration verifies hashes without running the workload:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-kernels-replay
python3 benchmarks/strict-suite/measure.py measure --output /tmp/strict-kernels-replay/strict-suite --cpu 5
```

The second command executes the complete paired timing batch and requires the
recorded tool binaries. It overwrites restored `results.json`; the checked
report and archive remain unchanged. Flonum controls can be repeated with
`python3 benchmarks/strict-suite/flonum.py measure --output /tmp/strict-kernels-replay/strict-suite --cpu 5`.
