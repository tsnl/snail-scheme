# Complete Destruc preparation

The complete original workload is ready for parent-coordinated timing. No clean
performance measurement is reported here. All compiler work remains in the
unmerged draft stack.

- Source and frozen driver: `92a491a4aaec7bc1a880d86204b81ed2cab1ffcb`.
- Compiler/build basis: `2def9941eb85f211e116e6955799fdc9ef561da8`; all 52 source
  files are unchanged. No compiler or backend change was needed.
- Upstream: `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`.
- Preparation: `/tmp/snail-strict-destruc-preparation-20261014-r3`.
- Canonical optimized module: 6,737 bytes, SHA-256
  `59981f469f785d37662e3a60149f8a79b5e4e1c2bbaf94aaf30d347977717832`.

The input remains 4,000 complete calls to `destructive(600,50)`, with both runtime
inputs hidden on every invocation. Each invocation allocates the ten outer nodes,
performs all 600 refill/redistribution iterations and returns the original outer
root. The final predicate compares all ten expected rows, all 60 items and every
list end. Expected data decodes before timing; the final equality decision stays
inside the workload. Nonpositive repeat counts preserve the original initial
false result. Positive counts execute the workload even for a false expectation.

The adapter uses a parametric mutable proper-list variant with fresh head/tail
Ref cells, instantiated for outer rows and inner items. A closed empty/integer
item type distinguishes a row ending from an empty-list item. General accessors,
length, construction and append carry rigid `All` contracts. Two integer stores
wrap the original iteration value; counted substitutions replace the list
operations and distinguish their empty values. Ref cells, item variants and
empty objects add representation costs compared with original Scheme pairs.
This is a concrete typed port, not a general mutable-pair or datum facility.

The original final `set-cdr!` has two effectful operands. Scheme leaves operand
order unspecified. Both compiled Chez diagnostic controls evaluate the left-row
split before the right-row target search, so the adapted source uses a narrow
`let*` to select that order. Both operand bodies remain exact. The two row spines
are disjoint, making their final values and complete node state independent of
this choice; the final tail store follows both. The [review](review.md) records
the argument, including the cleared singleton and abandoned right suffix.
Trace agreement describes instrumented controls, not uninstrumented native
instruction scheduling. Original Chez is untouched; reversing the recorded
kernel/helpers and expected/predicate/error-output changes recovers its complete
source exactly. The first differing-order probe is retained as rejected evidence.

The [correctness summary](correctness-summary.json) records 112 executions:

| Checks | Executions |
| --- | ---: |
| Original counts 1, 2 and 4,000 in raw/optimized Wasm and both Chez controls | 12 |
| Complete values, ordered effects and all-node graphs in four forms | 44 |
| Full predicate and initial-false boundary probes in four forms | 56 |

Separate graph probes assign IDs using actual Ref/pair identity and retain every
allocated logical node until a final snapshot. An independent Python model
matches every allocation and head/tail write, the complete returned values, and
every registered node's final contents. This exposes detached suffix sharing and
unchanged abandoned nodes that ordinary structural equality would miss. The
fixtures include empty rows, empty-list items, zero-width refills, odd/even splits,
a later refill and consecutive complete calls with fresh nodes. The canonical
600/50 result is observed separately without graph tracing. Negative expectations
change late items, item tags, row lengths and outer length; false and empty outer
lists remain distinct. Diagnostic registries do not enter the canonical artifact.

The [retention audit](retention-audit.json) examines the exact canonical optimized
Wasm, whose only exports are `bench` and `main`. Its concrete types retain both
mutable inner fields and outer head cells. The ten-node outer construction is
unrolled by the optimizer; the descending iteration loop, refill allocation,
append traversal, length scans, prefix item stores and suffix tail stores remain.
The repeat loop consumes both opaque return values, and its complete predicate
runs after repetition.

A separate observer counts all 18 function entries and optimized constructor and
store sites without reoptimization. Removing its recorded insertion ranges
recovers the original optimized text exactly. Initialization is excluded by
snapshotting counters after `main`. The independent graph model predicts these
per-invocation counts, all observed exactly at repeats 1, 2 and 4,000:

| Operation | Per invocation | At count 4,000 |
| --- | ---: | ---: |
| Outer logical nodes | 10 | 40,000 |
| Inner logical nodes | 43,095 | 172,380,000 |
| Integer-item head stores | 84,370 | 337,480,000 |
| Inner-tail plus outer-head stores | 10,207 | 40,828,000 |

The corresponding explicit Ref and integer-item constructor sites also match
the model. At every positive repeat count, the final outer and inner equality
functions have 11 and 70 entries respectively, demonstrating one complete final
comparison. A positive false-expectation probe still invokes the kernel; a
zero-repeat probe performs no kernel, constructor, store or opaque-input work.
These are executed Wasm sites, not V8 physical allocation counts, machine-code
instruction counts or performance samples.

`make test` and `make check` pass. The 29 preceding strict specifications and
generated source programs are byte-identical. Raw and optimized modules execute
in Node; original and adapted Chez controls are compiled at the same level. The
archive freezes 156 case-file hashes, all 52 compiler files, hosts, sources,
controls, source patches, build/validation records, independent oracles and
isolated diagnostics. The manifest covers all 249 archive members.

Restore and verify the archive without running a workload:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-destruc-replay \
  --report benchmarks/results/2026-10-14-strict-destruc
```

Parent integration on the combined draft stack separately rebuilt this source
with the String block backend and executed its count-one validation in Node.
The [integration record](integration/check.json) preserves that successful run
and artifact. Its optimized WAT matches the frozen program exactly after
renaming generated type IDs shifted by the two added String dependency types.
The integration check does not replace the frozen performance artifact or add
a timing sample.
