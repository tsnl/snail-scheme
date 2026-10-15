# Array1 with the same kernel source on Chez

With the strict kernel's source edits applied to Chez, **strict Wasm takes
5.214 seconds and adapted Chez takes 6.486 seconds**, about **19.6% less
elapsed time for strict**. Original Chez takes 6.658 seconds in this same
three-system window. The source alignment changes Chez's median by about 2.6%.

| System | Retained median | Retained range |
| --- | ---: | ---: |
| Strict Wasm | 5.214099 s | 5.209884–5.226514 s |
| Original Chez | 6.657885 s | 6.630653–6.679832 s |
| Same-kernel Chez | 6.485677 s | 6.460475–6.535633 s |

Strict/adapted time is **0.803941×**; strict/original time is **0.783146×**.
[All twelve observations](results.json) pass the original result checks, with
no failures, timeouts, replacement samples, or shortened counts. The workload
remains `go(500, 1000000)`, one outer harness invocation, result `1000000`.

The adapted complete Chez program differs from the frozen original at exactly
three locations: two `(make-vector n)` calls become `(make-vector n 0)`, and
`go`'s initial `(result '())` becomes `(result 0)`. Reversing those edits restores
the complete original source byte-for-byte. The extracted adapted kernel text
matches the frozen strict kernel exactly. Imports, macro definitions, numeric
type information, and host wrappers remain different. Chez keeps its original
hide, harness, result predicate, and optimization level 2.

The original strict and Chez artifacts are reused without rebuilding. All three
systems are remeasured together on CPU 5 in fresh processes with default V8
tiering; parent builds/tests are paused. Tools are Node 24.19.0 / V8 13.6.233.17,
Binaryen 132, and Chez 10.4.1 on the same Intel Core Ultra 7 270K Plus. One full
discarded round runs strict/original/adapted. Retained rounds rotate as
original/adapted/strict, adapted/strict/original, and strict/original/adapted,
so each system occupies each retained position once. A small adapted behavior
check precedes timing; the discarded trio validates original-size results before
retained rounds. Every invocation checks frozen sources, artifacts, host, tools,
driver, and original counts. Timing boundaries stay as documented in the
[original report](../2026-10-13-strict-vector-array1/README.md).

The [preparation record](prepared.json) proves source equality and identifies
the adapted object; the archive preserves every exact source, artifact, command,
output, and hash. The exact strict artifact retains the previously audited
allocation/fill/copy work. The original Chez assembly identity limitation also
remains as documented in the original report. No additional profiling is used
to attribute this difference to one mechanism. This control adds no workload:
cumulative coverage stays 13 measured ports/slices, Ackermann's prior
default-stack failure, and 43 unported workloads. The baseline report/archive
remain unchanged.

Restore and verify the archive, then optionally repeat the complete control
with the recorded tools, from the repository root:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-array1-control-replay \
  --report benchmarks/results/2026-10-13-strict-vector-array1-same-source
python3 benchmarks/strict-suite/array1-control.py measure \
  --output /tmp/strict-array1-control-replay/strict-array1-control --cpu 5
```

[Replay verification](replay-check.json) records hash-checked restoration and
a small result check on the restored adapted Chez payload. Repeating measurement
overwrites only the restored control `results.json`.
