# String storage costs across sizes

The bounded String representation has a measurable short-string cost. In this
unchanged growth/copy program it takes 10–22% longer at the three smallest sizes,
2–3% longer at the next two sizes, and runs 3.98× as fast at the largest size.
The earlier [canonical comparison](../2026-10-14-string-block-comparison/README.md)
retains its roughly fivefold improvement. These smaller parameter controls
qualify that result; they do not add six workloads to suite coverage.

| Threshold | Repetitions | Final characters | Flat seconds | Blocks seconds | Blocks / flat |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 16 | 200,000 | 22 | 0.154731 | 0.189507 | 1.225× |
| 64 | 100,000 | 118 | 0.322206 | 0.360228 | 1.118× |
| 1,024 | 10,000 | 2,038 | 0.207757 | 0.229576 | 1.105× |
| 4,096 | 2,500 | 8,182 | 0.195639 | 0.201726 | 1.031× |
| 8,192 | 1,250 | 16,374 | 0.215531 | 0.220530 | 1.023× |
| 32,768 | 500 | 65,526 | 1.780915 | 0.447398 | 0.251× |

Values are medians of four retained fresh-process runs per cell. One discarded
flat/block pair precedes four alternating pairs, giving each representation two
first positions and two second positions. All 60 executions pass; all 525 frozen
identities per size match before and after. `summary.json` and each size's
`clean.json` preserve every sample and range. Different repeat counts make
absolute times incomparable across table rows; ratios compare the two layouts
at the same input and count.

## Same programs, different runtime inputs

Both programs are the exact frozen modules from the canonical comparison:
flat SHA256 `c45ff252b8a9137e5e3fc1624b2301d6087e66ac01decd5e8d89db73070de669`
and blocks SHA256 `c3389ca3e8f07901f37969cb7e40cf66b47f2fcc8be6d1ce488f87fc2f4de6e0`.
No source, Wasm, optimizer setting or host code changed. Only the runtime size,
repeat count and corresponding expected result differ from the original suite
input. There are still ten trials per invocation, starting from the six-character
literal, with all append, fresh substring and state replacement operations.

One growth step makes the length `2 * old_length + 10`. An independent scalar
calculation supplies each expected length. Original compiled Chez accepts all
six count-one inputs; both timing artifacts pass their count-one validation
barriers and reject an expected length one larger. These 30 preparation
executions are correctness checks, outside the timing table. The unchanged
full-program preparation additionally retains its complete payload, alias,
Unicode, boundary and readonly checks.

The block representation adds an immutable owner even when storage fits one
array, plus block selection and bounded-copy logic. The measured regression is
consistent with that extra work, but this control does not isolate owner
allocation from individual access/copy costs. The larger improvement likewise
changes allocation shape and traversal together. This program exercises growth
and copying; it does not establish the cost of every String operation or every
short-string application. The general representation remains a draft while a
simpler short-storage alternative is assessed.

## Timing and reproduction

Node 24.19 uses default V8 tiering. Each process is pinned to CPU 5; NODE_OPTIONS
and collector overrides are removed. Agent-controlled builds, tests, profiling
and compression were held for this batch; unrelated system activity remains
possible. Compilation, process startup, instantiation and main initialization
are outside the workload timer. It includes all repetitions and the final
acceptance assertion. Process times remain separate in the raw observations.

`measure.py` reuses the canonical comparison driver, changing only its rotation
to permit multiple balanced cycles of two variants. `prepare.py` records the
parameter choices, specifications, correct/wrong-result probes and exact input
identities. `run.py` executes the frozen plans sequentially. The plans retain
original absolute paths; a new clean comparison requires relocation, a fresh
freeze and a newly coordinated window.

The archive preserves the frozen identity files, source and program artifacts,
all six plans/specifications/observations, correctness probes and drivers with
original path mappings. External tools are recorded by path/hash. Restore and
hash-verify it, then execute twelve separate count-one Wasm correctness probes:

```sh
python3 benchmarks/results/2026-10-14-string-size-controls/replay.py \
  benchmarks/results/2026-10-14-string-size-controls \
  /tmp/string-size-controls-replay
```

Those replays leave archived files unchanged and are not performance samples.
