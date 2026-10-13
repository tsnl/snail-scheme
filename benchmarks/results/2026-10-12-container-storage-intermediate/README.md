# Intermediate container and binding storage measurement

The frozen `3f2db1cc31f2e816572720a60c660364459d76e3` checkpoint uses actual
I64 vector elements and an F64 shared-cell payload in the positive controls.
Their kernel medians improve 2.66× and 4.13× against the pre-storage compiler,
and 3.56× and 4.12× against this same compiler with storage optimization disabled.
This is a four-kernel experiment. Pair/record field specialization, richer
container copy keys and the new Array/Storage interface are outside its scope.
It does not establish performance on the five real workloads or the full suite.

The baseline is `f07d1eb12f7c7234463a606a09190325a3c906b5`, whose production code
equals `d4f0d4203a8adc9cd1f1f338d991da31794ae725`. All three variants use identical
portable Scheme sources, inputs, Node binary, Rust runtime and host scripts.
The candidate's supported `(storage-optimizations-enabled #f)` parameter disables
concrete binding and container payload lowering. The fixed public-vector wrapper,
generic access protocol and closure-environment structure remain in both modes.
Thus on/off measures enabled concrete lowering within this compiler; the old
baseline comparison also includes those protocol changes.

## Clean results

Each cell has one discarded preliminary execution and three retained observations,
in rotating variant order. Ten discarded baseline calibration executions selected
common counts. All 58 executions passed return-code, complete Scheme result checks
and independently calculated Python checksums. Node processes were fresh, used
default tiering and CPU 5 affinity, with no profiler, GC flags or probes. Parent
and Astra explicitly held build/test jobs until the timing window was released.

Kernel seconds exclude input construction and the complete final checksum; process
seconds also include startup, module compilation, construction and checking.
The former is the primary metric here. They are separate measurements of each run.

| Kernel | Old baseline s | Candidate off s | Candidate on s | Baseline/on | Off/on |
| --- | ---: | ---: | ---: | ---: | ---: |
| I64 vector update | 0.561708 | 0.751504 | 0.211214 | 2.659× | 3.558× |
| Shared F64 cell | 0.437853 | 0.436016 | 0.105894 | 4.135× | 4.117× |
| F64 vector update | 0.304547 | 0.371711 | 0.296384 | 1.028× | 1.254× |
| Managed pair vector | 0.531783 | 0.640097 | 0.512105 | 1.038× | 1.250× |

With payload optimization disabled, the new compiler is slower than the old
baseline by 33.79% for I64 updates, 22.05% for F64 updates and 20.37% for the managed
pair vector; the cell median differs by −0.42%. The new wrapper/protocol costs are
included in that comparison. Enabled lowering more than recovers the cost for
the I64 and cell controls. The smaller baseline gains for the other two kernels
should be read with their three-observation scope.

Whole-process baseline/off/on medians are respectively 0.603699/0.792459/0.244938 s
for I64, 0.467163/0.464904/0.134500 s for the cell,
0.354257/0.420574/0.345957 s for F64, and
0.588977/0.698094/0.565744 s for managed pairs. All retained values and ranges are
in [clean-summary.json](clean-summary.json); raw observations, exact commands,
timestamps, inputs, stdout, stderr and checksum records are in the archive.

Arrays contain 65,536 elements. Common rounds are 928 I64 sweeps, 352 F64 sweeps,
672 pair-field sweeps, and 31,000,000 shared-cell updates. Integer values start at
2^40, beyond i31. The pair workload checks reference identity and shallow-copy
mutation after timing. The updating cell closure returns unspecified, with one
final observation through the second closure.

## Reached storage evidence

Seven modules were prepared with storage off/on. All 36 uninstrumented linked
correctness executions passed, including both runtime-selected opaque append
branches. A separate counter observer passed 26 executions. These used small
inputs under concurrent preparation/test activity; their elapsed values are
excluded. Counters cover initialization and checking, increment before operands
evaluate and count reached requests, including possible aborted operands. They
are not completed operations, physical V8 allocations or causal cost fractions.
Constant global initializers are excluded.

| Control, size 8 / rounds 3 | Enabled final Wasm | Reached evidence |
| --- | --- | --- |
| I64 vector | `(array (mut i64))` | One data array; 32 gets and 32 sets, including initialization/checking |
| Shared F64 cell | `(struct (field (mut f64)))` | One shared cell; updater gets/sets 3 times, observer gets once |
| F64 vector | `(array (mut eqref))` | One generic data array; no reached F64 array operations |
| Pair vector | `(array (mut (ref $pair)))` | Source and shallow-copy arrays, reached pair-reference gets/sets/copy |

The optimized cell's readiness field is removed where initialization is proven;
the compiler's physical helpers also preserve explicit readiness for early reads.
The [WAT projections](wat/shared-cell.wat) retain actual hot functions and data
definitions from the final optimized module. Full WAT is archived. F64 fields
inside ordinary `$float` boxes and I64 fields inside `$integer` boxes are excluded
as proof of specialized container storage.

Whole-invocation scalar constructor requests in these diagnostic inputs change
from off to on as follows: I64 update 53→15 integer requests; shared cell 13→9 float
requests; F64 update 89→89 float requests; managed pair vector 55→57 integer
requests. Signed deltas and reached type definitions are in
[shape-summary.json](shape-summary.json). These counts support the mechanism;
they do not apportion the measured elapsed time.

The F64 update is a negative control specifically for array specialization.
Other bindings and captures still change with the flag, explaining why a
same-compiler timing difference can exist without a concrete F64 data array.
The frozen source loses precision at `inexact` and mixed numeric arithmetic;
later transfer-rule corrections are excluded from this checkpoint.

The larger combined vector fixtures construct a typed zero-length `latest`
anchor but reach no typed element accesses in their hot modes. That constructor
does not establish hot-source specialization. Direct, opaque and apply append
correctness is retained; no append speed claim is made here. Pair fields remain
generic, so precise pair-reference array elements do not establish unboxed car/cdr.
The coverage fixture additionally exercises NaN, signed zero, exact I64, Unicode
characters, aliases, overlap, mixed copy, fresh result holes and factory-result
constraints. Its portable behavior passes; the full representation manifest is
a plan with pending categories, not a completed coverage claim.

## Reproduction

[manifest.json](manifest.json) maps every archived file to a content hash and
records the archive SHA, source checkpoints, exact tool binaries, modules and
host hashes. [artifact-summary.json](artifact-summary.json) keeps module sizes
and tool paths readable. Both builds use Binaryen 132 with the repository's
`-O3 --closed-world --always-inline-max-function-size=40 --converge` Scheme and
linked optimization stages. Rust runtime, platform and entry-module capture
hashes match the baseline. Preparation durations are not compilation benchmarks.

Restore and verify all blobs and the 12 clean comparability cases without timing:

```sh
python3 benchmarks/results/2026-10-12-container-storage-intermediate/repro/run-frozen.py \
  --output /tmp/snail-container-intermediate-restored
```

After coordinating a quiet host, add `--run-clean` to execute the same frozen
counts and rotations from restored original modules. No rebuild is needed.
Fixture sources, compiler snapshots, build drivers and commands are retained for
independent rebuilding. The archive also retains the separately labeled parent
physical-helper references for read-before-init and a failed RHS preserving the
old cell value; those are correctness evidence with no timing claim.
