# Floating arithmetic controls for mbrot and pnpoly

Explicit Chez flonum operations narrow mbrot's difference and reverse pnpoly's
comparison. These fresh pairs use the **earlier interim numeric compiler
320987e**, with the exact strict binaries from the next-five batch.

| Workload | Strict median (range), s | Flonum Chez median (range), s | Strict / Chez |
| --- | ---: | ---: | ---: |
| mbrot | 0.312854 (0.312492–0.313251) | 0.450408 (0.450364–0.451645) | 0.694600 |
| pnpoly | 0.709309 (0.682634–0.724378) | 0.613348 (0.611353–0.614730) | 1.156454 |

Strict takes 30.5% less time for mbrot and 15.6% more for pnpoly. The earlier
same-kernel generic-Chez medians were 2.266252 s and 1.527904 s in the
[next-five batch](../2026-10-13-strict-numeric-next-five/README.md). Those are
historical observations from a separate window; the table above is the paired
comparison. Arithmetic specialization changes the comparison materially, while
host wrappers, representations and static type knowledge still differ.

[All 16 observations](results.json) passed: four discarded and twelve retained,
with no failed, timed-out or replacement samples. Each process used CPU 5 and
default V8 tiering during an explicitly coordinated quiet window. One complete
discarded round preceded three retained rounds. Order alternates, and each
system occupies the first retained position three times across the two cases.
Original inputs and repetitions remain: mbrot uses 1,000 iterations of its
75-by-75 matrix, expecting 5; pnpoly uses 1,000,000 iterations with the original
two 20-element vectors and 12 point tests, expecting 6.

The controls start from the exact prepared same-source Chez programs, retaining
the original harness, hide procedure, predicates and optimization level 2. Only
floating operator names change: 13 sites in mbrot's `count`, and 11 in pnpoly's
`pt-in-poly2`. The escape counter's `(+ c 1)`, polygon length subtraction and
both index decrements keep integer operations. Exact reversal restores the
starting source, and surrounding bytes are identical. The domain audit is a
premise for these pinned functions; textual counts do not infer numeric types.
The archive includes both complete sources, patches and proof records.

The [preparation](prepared.json) freezes source, input, binary, driver and tool
hashes, checked before every sample. All new controls pass counts 1 and 2.
[Compatibility checks](compatibility-review.json) reproduce the historical
fibfp/sumfp control sources byte for byte and pass fresh count 1/2 execution.
Partial preparation is rejected. Earlier preparation snapshots and diagnostics
remain archived. [Replay validation](replay-check.json) verifies all 271 files,
rechecks source proofs and medians, and passes 16 bounded executions: raw and
optimized Wasm, both new Chez controls and both historical controls.

The compiler snapshot is `39d68ff0702d20857a5f42d8ff3170335e67cc8a`, containing
numeric commit `320987e43e705bd81c7058985656c084c99474a3` cherry-picked as
`a23fbdc90a9aacffa44fcdfdef01dc549df69c22`. All 50 compiler files are preserved.
The final overload/shared-IR work is outside this snapshot. Control driver
commit is `866cc3c2c68b22f44599391c41f5b313777ef0f0`. Node 24.19.0 /
V8 13.6.233.17-node.51, Chez 10.4.1, Binaryen 132 and all executable hashes are
recorded. The unchanged strict binaries retain the workload operations audited
in the next-five report; no new machine-code or dynamic execution audit is
claimed here. Cumulative coverage remains 18 passing measured ports/slices,
Ackermann's prior default-stack failure and 38 unported workloads out of 57.

Restore the archive from the repository root:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-next-float-replay \
  --report benchmarks/results/2026-10-13-strict-numeric-float-controls
```

To repeat timing, use the recorded tools and driver files matching the hashes
in restored `flonum-controls/prepared.json`, as checked in with this report:

```sh
python3 benchmarks/strict-suite/flonum.py measure \
  --output /tmp/strict-next-float-replay/strict-next-float-controls --cpu 5
```

This overwrites only restored `flonum-controls/results.json`; the archive keeps
the original observations and copied baseline evidence unchanged.
