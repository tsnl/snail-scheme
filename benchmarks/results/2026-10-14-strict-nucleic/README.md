# Complete Nucleic preparation

All 50 original searches pass in untouched Chez, the same adapted kernel on
Chez, diagnostic raw linked Wasm, optimized linked Wasm, and native execution.
The complete 3,485-line source, empty partial assignment `()`, all coordinates
and constants, and expected result `33.797594890762724` are preserved. This
preparation report contains no clean performance samples. Build and validation
durations are retained as diagnostic provenance.

The source authority is upstream revision
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. The frozen compiler basis is
`94787a48e33c416c7f36774e84768d81f15020ce`, including shared scalar trigonometry
(`6dadbea`), identity-table IR copying (`37cac19`) and query-local dependency
reachability (`94787a4`) on `71c6cfb`. Parent publication cherry-picks may have
different commit IDs. The archived bytes and their hashes identify this run.
The adapter was uncommitted during preparation; the record keeps that actual
driver commit instead of replacing it with a later publication commit.

## Source and representation

The adapter retains every definition in the 3,469-line kernel. Counted edits
reverse to the original kernel byte-for-byte. All 6,719 decimal tokens retain
their spelling and order. Forty-six nucleotide constants, six relation matrices,
the identity transform, the ordered search, and the original ratio predicate
remain. The predicate requires `0.999999 < result / expected < 1.000001`; the
initial false result for nonpositive repetition counts is also preserved.

Nucleotides use a concrete base variant and a mutable vector of F64 coordinate
and transform vectors. A ledger maps every original field: slots 0–28 retain
indices, the symbol at slot 29 becomes the base field, and subsequent fields
shift down one. All 57 getter/setter pairs remain. Mutable assignment vectors
become shared Refs containing immutable ID/transform/nucleotide products. This
adds one wrapper allocation at construction and a product allocation on an
assignment setter. The canonical search does not invoke those setters; separate
alias tests exercise them. Points, transforms and search lists retain their
mutable vectors and linked-list operations.

Quoted database vectors become explicit constructors before the worker clock.
Typed arithmetic helpers preserve operand evaluation and sum association.
The peculiar `math-atan2` branches remain Scheme code, including the zero-x
branches and `(0, 0)` returning positive pi/2. Only scalar F64 sine, cosine and
unary atan cross the ordinary Rust library boundary; both production targets
link the same Rust implementations. No host search, data slice, reduced count,
precomputed answer or alternate geometry replaces the algorithm.

The actual Chez reader decodes the original input datums before execution. The
adapter supports the declared empty partial assignment, not arbitrary Scheme
input graphs. The original Chez program remains untouched. The adapted control
runs exactly the strict kernel with corresponding representation helpers.

## Complete observations

Each of the five systems passes counts 1, 2 and 50, all seven full-kernel probes,
and six numeric-predicate fixtures: 15 canonical executions, 35 complete probe
executions and 30 predicate executions. All raw stdout/stderr, commands, exit
statuses and complete observations are retained.

| Probe | Observations per system | Contract |
| --- | ---: | --- |
| Nucleotide database | 8,373 | Every base code, transform and atom value |
| Pseudoknot solutions | 17,301 | Complete solution order, variable IDs, nucleotide identity indices and all transform coordinates |
| Anticodon solutions | 45,825 | The same complete ordered observations |
| Geometry | 771 | Apply, combine, inverse, alignment and relative nucleotides for all four bases |
| Mutation | 5,662 | All nucleotide/point/transform/assignment setters, retained aliases and unchanged-field identities |
| Angles and maximum | 19 | Sixteen zero/quadrant combinations, signed-zero ties and finite maximum ties |
| Final run | 1 | Actual computed result, independently of the coarse acceptance predicate |

Sequence lengths, observation tags, integers and order compare exactly. Database
and mutation probes require exact numeric agreement. Other computed values use
`abs(actual - expected) <= max(1e-11, 1e-11 * max(abs(actual), abs(expected)))`.
Both zero signs must match, and finite expected geometry rejects nonfinite
actual values. Shortened, extended, changed and reordered observations are
explicitly rejected by the comparator.

Adapted Chez and native match the original observations exactly. Raw and
optimized Wasm have the same small transcendental-rounding differences:

| Computed probe | Largest absolute difference | Largest difference divided by `max(1, abs(actual), abs(expected))` |
| --- | ---: | ---: |
| Pseudoknot transforms | 3.2152058793144533e-13 | 2.1613992487996417e-14 |
| Anticodon transforms | 4.085620730620576e-14 | 2.3869795029440866e-14 |
| Geometry | 8.881784197001252e-16 | 3.5854582758757785e-16 |
| Angles, maximum and final run | 0 | 0 |

The JSON summary records each maximum's target, observation index and values.
Matching complete ordered solutions and unchanged traversal/comparison code do
not prove identical internal pruning decisions under every rounding difference.
The probes also establish specific mutation/alias contracts, not an exhaustive
identity isomorphism of every transient search object.

Separate retained-work inspection follows the optimized worker loop into the
search and most-distant-atom reduction on every iteration. The native prepared
Wasm retains that call chain. Actual Wasm validation observes all 50 barriers.
These static and runtime checks do not constitute a dynamic trace of every
pruned search node. The native scalar provider is compiled separately without
LTO; its opaque calls remain in the LLVM-linked program.

## Compiler blockers and bounded preparation

The first attempt failed on a missed multiline call-head adaptation. The corrected
source then spent 19 minutes 48 seconds of CPU time in the frontend before a
recorded stop. It was paused for 74 elapsed seconds during the parent Ray timing
window; that pause is not compiler work. Narrow diagnostics located two graph
traversals that repeatedly revisited shared structure.

IR copying now uses the existing identity table, reserving shells before child
traversal and preserving order, sharing and cycles. Dependency reachability
shares visited bindings within one query, retaining edge-first target checks,
input exclusions, recursive-group order and inference scheduling. Separate
commits and independent explanation/critique reviews cover each fix. Shared and
cyclic graph checks, forward references, inference and initialization contracts
pass. Representative WAT, raw Wasm and optimized Wasm remain byte-identical for
three fixtures across each fix. Bounded synthetic diagnostics are retained;
they are not clean compiler benchmarks.

Subsequent five-minute attempts emitted complete WAT and raw Wasm but expired
inside mandatory Binaryen optimization. A Nucleic-only 1,200-second preparation
bound then completed: the worker compile took 323.732 seconds, including
116.092 seconds in Binaryen; the larger exhaustive probe compile took 557.769
seconds, including 122.234 seconds in Binaryen. Native preparations took 28.611
and 73.080 seconds. These concurrent preparation durations are not performance
measurements. Binaryen remains mandatory for both production targets, including
native `--wasm` inputs. Raw linked Wasm uses explicit diagnostic prune-only mode.

A final independent review found a timeout-supervisor gap: a resistant child
could close its output pipes and outlive its reaped leader. The archive preserves
a concrete failed cleanup demonstration and the successful correction. Timeout
cleanup now kills the owned process group independently of pipe closure. The
original successful preparation helper and metadata are retained; an explicit
amendment records the timeout-only update. All other helper AST definitions and
regenerated Scheme sources are unchanged. All 78 compiler/runtime files and
129 case files verify. No recorded compile is attributed to the later helper.

## Validation and archive

`make test`, `make check`, all 36 Rust unit tests, Rust formatting,
`scripts/test-backend`, `scripts/test-build`, all 292 strict contracts on this
frozen basis, and actual raw/optimized/native scalar-math checks pass. The full
strict suite has exact four-shard coverage and unchanged compiler identities.
An earlier partial strict suite was deliberately interrupted before the second
compiler edit; its 54 passes and interruption remain separate from the final
292-case pass. The scalar math fixture checks 63 cases in each actual target,
including signed zero, nonfinite inputs and ordinary finite values.

The archive includes complete source and input, both Chez controls, all compiled
Wasm/native artifacts and build records, native compiler inputs and Rust static
library, all probes and raw failures, source proofs, retained-work excerpts,
compiler diagnostics, relevant check logs and supervisor boundary tests. The
[focused review](review.md) records independent explanation/critique and coherent
exceptions to the ten-line target. The [protocol](protocol.md) records exact
preparation and timing boundaries.

Restore and verify every archived regular file without executing workloads:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-nucleic-replay \
  --report benchmarks/results/2026-10-14-strict-nucleic
```

Absolute paths in original command records are preserved. Hash replay verifies
contents; it does not promise those temporary execution paths exist after restore.
The supplementary Rust reference was inspected but not executed in this task.
Its Rc/Box geometry, vector-backed domains, startup parsing and nonnegative count
parser differ from this Scheme source, so it is not an algorithm authority or a
validated timing control here.
