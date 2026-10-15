# Rejected short/long Unicode String prototype

This prototype is **rejected for integration**. Removing the short String owner
preserves the full growth/copy win, but does not recover short growth overhead
and substantially worsens scalar access. The source commit is
`3370a372c96635dc2888dcc38804799c4c2dcbea`; the evidence commit is separate.
The production draft should retain its previous representation while other work
proceeds. The implementation commit and archive preserve this experiment only.

| Growth threshold | Flat seconds | Blocks seconds | Hybrid seconds | Hybrid / flat |
| ---: | ---: | ---: | ---: | ---: |
| 16 | 0.154525 | 0.188605 | 0.191795 | 1.241× |
| 64 | 0.322689 | 0.357017 | 0.376457 | 1.167× |
| 1,024 | 0.206134 | 0.228399 | 0.218078 | 1.058× |
| 4,096 | 0.195054 | 0.201690 | 0.199640 | 1.024× |
| 8,192 | 0.215584 | 0.220845 | 0.219890 | 1.020× |
| 32,768 | 1.778673 | 0.442663 | 0.444628 | 0.250× |
| 500,000, canonical | 4.886460 | 0.982036 | 0.981928 | 0.201× |

The full row retains the original 100 invocations, ten trials, threshold 500,000
and result 524,278. Smaller rows vary only runtime input and repeat count in that
same frozen program. Their repeat counts differ, so absolute times across rows
are not comparable. These controls add no canonical suite coverage.

| Scalar length | Ref hybrid / flat | Ref hybrid / blocks | Set hybrid / flat | Set hybrid / blocks |
| ---: | ---: | ---: | ---: | ---: |
| 22 | 2.226× | 1.373× | 1.340× | 1.325× |
| 2,038 | 2.208× | 1.851× | 1.743× | 1.634× |
| 8,192 | 2.232× | 1.859× | 1.760× | 1.657× |
| 8,193 | 2.781× | 2.318× | 2.101× | 1.980× |
| 65,526 | 3.232× | 1.783× | 2.396× | 1.646× |

Scalar rows request approximately 20 million source reads or writes each.
Reads consume every loaded Unicode scalar in a complete checksum. Writes select
one runtime Unicode scalar per round, store it at every index, and keep stores
observable through exported probes and an imported per-round callback. Every
final character is checked after the workload timer. Separate validation also
checks every intermediate store round. Static optimized-Wasm inspection retains
the self-tail-recursive workers, native i32 array.get/array.set, index increments,
checksum dependencies and imported callback; it is not a physical access trace.

The measured layout uses one i32 array `[permission, scalars]` for values up to
8,192 scalars, and the prior immutable owner with bounded i32 payload blocks for
longer values. Its short permission cell adds four bytes; the block directory
itself remains proportional to length. A private nonnullable WasmGC eq reference
carries only those two cases. Source String typing, explicit Top witnesses,
Unicode width, identity, literal permissions and frontend type rules are
unchanged. Both flat arrays copy with one native array.copy after complete
validation; mixed and long copies use bounded directional spans. The compiler
snapshots differ only in strict-wasm.sld.

The remaining storage tests, casts, validation and traversal are visible in the
optimized artifacts. The timings measure their combined cost with the allocation
change; they do not isolate any one cause. No further representation refinement
or unmeasured reference-array alternative is accepted from this experiment.

All 357 clean executions pass. Every row retains six fresh-process cyclic
rotations after one discarded rotation, placing all three variants in each
ordinal position twice. All 983 frozen source/artifact/tool identities per row
match before and after. The parent ran the batch on CPU 5 with Node 24.19 default
tiering, NODE_OPTIONS and collector overrides cleared, and agent-controlled
builds/tests/profiles/compression held. `quiet-window.json`, `summary.json` and
the archive's `evidence/clean/` retain the complete protocol, every sample and range. Unrelated
system activity remains possible.

Seventeen focused contracts passed, including raw/optimized actual Node
execution for runnable fixtures. The canonical raw/optimized counts 1/2/100,
complete payload/store, Unicode, alias and harness probes passed. All six scalar
artifacts passed 222 correctness/rejection processes, covering lengths
0/1/22/8,192/8,193/65,526 and counts 0/1/5, with deliberate wrong results rejected.
`make test` and `make check` passed. The broad strict run completed 91/288 cases
without failures, was held for timing, and was then canceled because performance
rejects this layout. Its completed records remain intact; the broad suite is
explicitly incomplete, and session 57453 terminated with exit 143.

The [behavioral brief](behavioral-brief.md) and [focused review](simplify-review.md)
record the fresh independent explanation and informed debate, including why a
short wrapper is unnecessary and why span room must use logical cursors before
adding a permission header. The alternative i31/reference-array layout was
considered, with unresolved reference-width, scanning/copy/barrier and metadata
costs; it was not implemented or timed.

`artifacts.tar.xz` preserves exact compiler/program sources, raw/optimized Wasm,
inputs, contracts and interrupted-suite records, all timing plans and clean
observations, preparation and measurement drivers, tool identities, static
inspection, source patch and review. `manifest.json` records every archived byte
and original source path. Verify it without running any workload:

```sh
python3 benchmarks/results/2026-10-14-string-hybrid-layout/archive.py --verify
```

`prepare.py` records preparation against the earlier preserved flat/block freeze.
A new clean timing batch needs relocated plans, fresh identities and a newly
coordinated window. Historical String/block/size/native reports remain unchanged.
