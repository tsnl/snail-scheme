# Three-way strict V8 experiment

Compare only the frozen baseline (`c9ba1e18…`), scalar-only (`bc2f5942…`) and
scalar-plus-readiness (`632f5368…`) production Wasm modules listed in the
[diagnostic report](README.md). Keep the exact complete source, count 100,
1000/1000/0 input, and original clean host. Do not build or optimize anything
inside this experiment. No native rebuild or new optimization is included.

The immutable snapshots are under `build/constant-visibility/frozen/`. The
plan records exact commands and hashes for the three modules, shared source,
specification, host, Node, taskset and supervision code. Every timed process
uses the clean host without `--validate`, profiling or code-print flags.
Correctness and opacity-count diagnostics are recorded separately.

Run 21 fresh processes serially on CPU 5: one predetermined discarded process
per variant, then all six permutations of the three variants, retaining each
of those 18 samples. Each variant appears twice in each retained position.
Keep the six samples regardless of their values. Report workload median and
full range, with total process duration retained separately. No additional
within-process warmup is added. Compilation, instantiation and `main` precede
the workload clock; JIT work during the workload remains included.

`measure.py` reuses the previously reviewed process-group supervision from
the full bytevector and native-array campaigns. The only runner adaptation
allows all three `strict-v8-*` labels to use the existing strict V8 result
parser. It verifies identities before every process and at completion, rejects
instrumentation environment variables, enforces exact result framing, records
failures, times out bounded groups, kills owned descendants, reaps the leader,
and checks that no executing group member remains. Failure aborts the campaign.
The default invocation checks identities without starting any workload.

Record CPU model, affinity and frequency-policy state before and after the
campaign; do not claim fixed frequency. Start only after the parent releases
the coordinated quiet window and all participating agents hold builds, tests,
compression and profiling. Until that release, this document and JSON plan
are preparation only. No timing has been started.
