# Neutral behavioral brief for independent simplify review

Review only the newly extended strict benchmark driver, its scalar host adapter,
and the source adaptations and correctness oracles for paraffins and gcbench.
Compiler feature work is frozen at af02dac; this task must not change it. Earlier
benchmark specifications and generated strict sources must remain unchanged.
No performance measurements or publishing are authorized by this checkpoint.

The driver consumes pinned upstream Scheme programs and their complete input
files, compiles strict raw and optimized Wasm, and runs original and adapted Chez
controls. Preserve unread input datums. The adapted Chez control must execute the
same adapted kernel text as strict Scheme; original Chez retains the upstream
program and wrapper. Record exact source changes, executable/tool hashes,
commands, outputs and compiler identity separately from the driver revision.
Failed or unsupported cases must be visible rather than counted as passing.

Paraffins enumerates chemical structures by integer partitions and recursive
radical combinations. Its canonical input requests 10 invocations at n = 23;
the final scalar result is 5,731,580. Immutable closed variants can replace its
symbol/tagged-vector representation. Preserve generation order, symmetry bounds,
list accumulation, and numeric partition storage. Small supplemental checks must
compare every product and recursive child in order against the original program,
including the length and termination of both output lists. Structural output
checks should detect changed values, truncated lists and extra suffixes. Carbon
counts and constructor arities provide independent consistency checks.

Gcbench requests one invocation at stretch depth 20. It builds trees both by
mutating freshly allocated child slots and by constructing parents after their
children. It also creates a long-lived tree and a half-filled F64 array while
repeatedly allocating temporary trees. Keep every construction count, the array
size and fill range, and diagnostic placement. The original outer correctness
predicate is always true; retain it and disclose its weakness. Strict mutation
uses explicit Ref cells, adding two child cells per record and one shared empty
sentinel per invocation. The adapted Chez control must share that representation
change. Scalar printing at the same source sites is permitted with host and I/O
costs disclosed.

Supplemental gcbench validation should check complete trees, child/padding
invariants, independent child updates, every array element and the exact ordering
and multiplicity of construction events. Expected lengths must not determine the
amount of work performed. Include malformed structures and changed, shortened
and lengthened expected arrays. These probes must not add deep traversals to the
canonical timed program or preserve otherwise unobserved fields in that module.

Behavioral correctness and benchmark meaning are separate questions. Inspect
canonical optimized artifacts independently of validation artifacts. Paraffins'
count predicate permits legal elimination of payload storage; later timing can
measure that source program if the eliminated and retained work are disclosed.
Gcbench's intended long-lived tree currently dies before temporary allocations,
which invalidates its particular collector comparison. Keep that case excluded
from measurement. Do not add a retention boundary as part of this checkpoint;
only describe a separately reviewable proposal and how graph rooting would be
verified. Static instruction sites do not establish dynamic allocation counts
or V8 machine-code behavior.

Please explain the behavior at a high level, then give pseudocode, invariants,
edge cases and unresolved assumptions. Challenge unnecessary state or stages
without inspecting the implementation, repository files or diffs.
