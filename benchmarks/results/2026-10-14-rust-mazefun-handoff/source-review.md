# Rust Mazefun source, predicate and lifetime audit

The corrected reference retains the unshortened original input: 10,000 calls to
`make-maze(11,11)` and the complete supplied 121-cell grid. Every positive
repetition reconstructs the cave, candidate holes, shuffled list, cavity changes
and final mark lists. No maze, RNG sequence, label table or result is cached.
The original three `black_box` boundaries remain: both dimensions and the
complete returned result for each invocation. No barriers were added inside the
kernel to counter ordinary compiler optimization.

The canonical kernel is unchanged after three explicit reversals: remove its
ownership/order comments, restore the `make_maze` function name, and restore its
unsigned parity assertion. The recovered region is byte-identical to historical
SHA256 `100fe4f4302bc0500effeeaf79735ad1e92cca593a63e24f0665e6c73c6c25de`.
The new signed wrapper makes the parity decision and returns the original symbol
`error` for even dimensions. Negative odd extents normalize to zero only after
that decision, preserving original increasing construction: negative rows give
an empty outer list; positive rows with negative columns give empty rows.
Storage/indexing must remain manageable and fit Wasm32.

Initial open cells retain coordinate labels at even/even positions. Candidate
holes retain increasing row/column order at mixed parity. Shuffle starts at zero,
advances `(state * 3581 + 12751) % 131072`, selects modulo the remaining length,
removes only that position while sharing its suffix, and prepends the selected
position to the recursively shuffled remainder. Its bounded arithmetic fits
Wasm32; LLVM retains the power-of-two remainder as mask `131071`.

Each hole enumerates open neighbors in up/down/left/right order. Duplicate
coordinate labels reject piercing. Otherwise each component flood reads its old
label from the current updated cave, before recoloring to the hole coordinate.
A flood writes its cell before recursion, takes neighbors from the incoming cave,
and carries updated caves through the ordered calls. The old-label guard retains
no-op visits to cells already changed or in other components. The hole is written
after its component floods. There is no mutable-grid, union-find or alternative
maze algorithm.

Rust cave and shuffle nodes are persistent `Rc` chains. Writes copy the changed
row/outer prefixes and share untouched suffixes and rows. Native pointer-identity
tests retain that sharing guarantee. Coordinate labels are copied inline tuples,
with an inline `Option<Position>` for walls, rather than separately allocated
Scheme coordinate pairs/false or strict `Coordinate(I64,I64)`/`Wall` variants.
Neighbor and mapped-ID scratch use contiguous `Vec`s instead of source lists;
the original concatenation/append spines and matrix-size pair are absent. Hole
collection and final conversion also use scratch vectors before building full
persistent lists. These are disclosed representation/allocation differences.

The Rust reverse iterator invokes pure initial matrix callbacks in reverse order
while constructing increasing result lists. The original `for` is written as
increasing recursion; identical callback evaluation, cons allocation scheduling,
physical allocation or host liveness is not claimed. Hole list order, shuffle,
neighbor order and flood decisions are preserved. Full non-square/skinny output
probes support those value/order decisions without claiming an execution trace
of every original allocation.

All owners keep shared tails alive. Intermediate cave/list/vector owners drop
inside each invocation, so reference decrements, recursive destruction and
allocator work are timed. The prior result remains owned while its replacement
is constructed and is released on assignment afterward. Observer top-level
release counts are `N-1` inside repetitions. The final result moves into the
reporter and is released after stopped-clock capture and both output prints.
Scheme collection controls reclamation differently, and an exact lifetime/GC
cost comparison is outside this claim.

The corrected driver reads signed decimal i64 count/dimensions and retains the
reader's complete expected datum before the clock. It establishes initial false
after starting the clock. Nonpositive counts perform no maze calls, retain false
and preserve exact signed CSV labels. Positive calls can return error or a full
grid. The timed predicate dispatches those three states and directly compares
proper outer/row list shape, both lengths, each Atom kind, one-byte spelling and
mark value against the untouched expected datum. It allocates no second expected
grid and uses no invalid-expected sentinel. Successful comparison precedes clock
capture; serialization/CSV and final result cleanup follow it.

The historical decoder conflated strings/vectors with symbols/lists and kept
only the first character of marks. Actual historical Wasm accepts `(("_"))`,
`((_tail))` and `#((_))` for a one-cell maze although original Chez rejects them.
Its zero-count false and even-dimension error cases fail. All these observations
are retained separately. Corrected failures panic without stopped-clock capture
or normal result/CSV printing; original Chez reports `INCORRECT`. Exceptional
diagnostics and abort cleanup are not claimed equal.

The shared reader's canonical `#f` token represents false. Alternative boolean
spellings, escaped boolean-like/numeric symbols, generic Scheme numeric syntax,
proper lists written with dotted-tail notation, malformed trailing input and
huge/exceptional recursion/resource behavior are outside this reader/domain
equivalence. Ordinary parsed String/Vector/Character/improper-list kinds in the
bounded probes are rejected correctly. No general Scheme reader/equality rewrite
is included.

The exact 125,246-byte release Wasm has SHA256
`4e1f45f9c925dde00788408ab97b262c77c7201967c7b49768970bcd50efd885`.
A separate observer adds 24 counter sites to that exact disassembly. Erasing
only those insertions recovers the canonical text exactly; assembly uses only
the canonical feature set and no reoptimization. Every selected kernel counter
scales exactly for counts 1, 2 and 10,000. Full-count wrong-last-mark rejection
retains all kernel work and reaches all 121 mark comparisons, with one clock
read and no result/CSV prints. Zero-count false performs no kernel work.
Residual write-entry counters include only retained function entries; inlined
write levels are not counted by those counters. They are not total constructor,
V8 physical allocation, generated-machine-instruction or performance counts.

Thirty-six targeted fixtures execute corrected Wasm and untouched original Chez
72 times, with 14 independent complete-output oracle runs. Four committed suite
regression fixtures add 16 executions. The parent independently validates the
same full-count frozen artifact and all 121 cells. All ten native tests, fmt,
release Wasm Clippy and `make check` pass. Diagnostic durations remain execution
provenance only.

A fresh no-history/no-files Sol 6.1 max explanation and one informed critique
accept the direct false/error/grid states and result-specific predicate. They
reject a redundant invalid-expected sentinel, duplicate expected-list allocation,
generic comparison callbacks and a broader parser redesign. The existing
construction, neighbor dispatch, duplicate decision, full serialization, visible
parse/clock/repeat/predicate/report driver and tests remain cohesive exceptions
to the ten-line target; new predicate/wrapper functions stay small. Further
kernel refactoring would change no necessary guarantee or supported behavior.
Other structural/SLaTeX cohort reviews remain separate.
