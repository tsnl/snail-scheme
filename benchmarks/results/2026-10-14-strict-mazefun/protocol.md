# Mazefun evidence and future timing protocol

The ready preparation is `/tmp/snail-strict-mazefun-preparation-20261014-r3`.
It records Node 24.19.0, Chez 10.4.1, Chibi 0.12 and Binaryen 132 paths and exact
binary hashes. Its 52 compiler/build files match compiler commit
`53008a43e75cc1d1c3d6844ab923807389b84149`. `BINARYEN_CORES=1` was used for
preparation and the separate observer. No canonical artifact was altered while
finishing this evidence package.

The later parent integration check is separate. Its archived capture identifies
the newer compiler commit, complete compiler hashes, two changed compiler source
files and integrated host. Rebuilding the exact frozen maze source yielded the
same raw and optimized binaries, followed by two successful canonical executions.
The original preparation's compiler/driver labels and canonical bytes stay intact.

1. Read the pinned upstream input through the recorded Chez reader. Prepare
   complete original/adapted programs and the strict typed source. The strict
   module initializes procedures, runtime input values and complete expected
   data before the benchmark call. The original Chez harness and the adapted
   boundary likewise decode expected data before timing.
2. Compile raw Wasm and the optimized canonical module, plus both Chez forms.
   Validate the original 11 × 11 workload at repetition counts 1, 2 and 10,000.
   The two dimension hiding calls return their runtime values on every kernel
   invocation. The final complete predicate remains inside the workload.
3. Run the separate complete-output and cavity-trace probes, then the full
   predicate fixtures and Chez sharing assertions. Retain their complete raw
   records, including intentionally rejected predicates. Preserve the failed
   preparation attempts as failed evidence.
4. Inspect the exact optimized canonical binary and its disassembly. Add
   counters to a separate text copy only. Check that removing every insertion
   recovers the original text, assemble without another optimization pass, and
   subtract setup counters before invoking the workload. Compare counts 1, 2
   and 10,000, plus invalid expectation and initial false. These are diagnostic
   executions; their durations cannot be used as timing samples.
5. Verify all recorded case/compiler hashes, full comparison records and the
   complete source reversal. Freeze this evidence archive and verify it with
   the existing `replay.py` manifest protocol.

After restoring the archive to a fresh directory, the observer can be rebuilt
using the archived compiler tool path:

```sh
BINARYEN_CORES=1 python3 /tmp/mazefun-replay/evidence/observe-optimized.py \
  /tmp/mazefun-replay /tmp/mazefun-observer
```

Use the recorded Node executable to run
`evidence/retained/observe.mjs` with the new `observed.wasm`, restored
`mazefun/spec.json`, a count and `canonical` or expected-kind code `3` (invalid).
The original observer host/results remain archived. All counters are reset
logically by subtracting their post-`main` values, so expected-data construction
and staged procedure setup do not enter the kernel counts.

Clean performance measurement is separate future work. The parent coordinates
a quiet CPU window and any matched Rust control before timing. Use the frozen,
uninstrumented optimized artifact and all prepared controls at the original
count/dimensions, with one discarded round and rotating retained system order.
Use the benchmark's existing timing boundary and complete predicate. Record
affinity, tool/source hashes, commands and raw samples. Do not infer speed ratios
from this preparation, the earlier failed attempts, the observer or correctness
run durations. This report freezes zero clean samples.
