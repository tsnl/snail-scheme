# Complete canonical Rust reference suite

The scope is all 57 workloads at upstream revision
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. A port preserves the original
algorithm, inputs, iteration counts, meaningful object graphs and mutations,
file I/O, RNG sequence, and result predicate. Each workload has its own
executable. Source presence is distinct from full canonical Node/Wasm success;
neither establishes performance. The original five-case report stays separate.

The source groups are numeric recursion and linked lists; FFT and geometry;
text, I/O and RNG; mutable and persistent search structures; exact arithmetic;
then the readers, interpreters, compiler, partial evaluator, theorem provers,
nucleic geometry and SLaTeX processing. All 57 sources are implemented; 56 pass
unchanged default canonical Node/Wasm execution. Default Ackermann retains its
stack failure, with the heap-frame variant recorded separately. Source coverage,
canonical success, outstanding independent reviews and performance remain distinct.

`suite.py` checks independent small inputs against the original Chez source,
rejects deliberately wrong expected answers when the predicate consumes them,
then executes unchanged canonical inputs/counts with `--checks full`. The
original predicates for `cat`, `tail`, `gcbench`, `slatex`, and `quicksort` ignore some or
all expected-input datums. File cases also compare complete output digests;
array, linked-list, tree, complex-number, and FFT tests inspect complete small
structures rather than only final scalar summaries. Quicksort needs an
independent full-vector audit in addition to its original sortedness predicate.

## Implemented representation decisions

- `fib`, `fibfp`, `tak`, and `ack` retain their recurrences. Ackermann's outer
  tail call reuses the Rust frame, but its inner recursion still overflows
  Node's default Wasm stack on canonical `(3,12)`. That failure remains the
  default status. Optional `ack --heap-frames` uses an explicit pending-call
  stack and performs the same recurrence; it has a distinct allocation policy.
- `sum` retains its descending linear loop with an optimization barrier in
  the accumulator. A constant-time closed-form reduction changes this workload.
- `diviter`, `divrec`, and `primes` allocate separately owned linked cells.
  Division inputs are allocated before timing and retained across iterations;
  every division result is fresh and the preceding result is dropped when
  replaced. Empty-list payloads become a uniform integer payload in these
  numeric cells; division does not observe or change payload identity.
- `takl` and `ntakl` compare actual list tails and return a borrowed suffix of
  the supplied lists. They preserve payloads and sharing, although the original
  result predicate checks length. They do not substitute numeric counters.
- `array1` initializes a fresh vector forwards and copies it backwards into a
  second fresh vector on each iteration. Both allocations and contents are
  exposed to the optimizer barrier; full small vectors are tested.
- FFT retains interleaved real/imaginary storage, bit reversal, butterflies,
  twiddle recurrence and the upstream rounded `pi*2` constant. A nonzero full
  transform is checked against an independent direct DFT.
- `mbrotZ` uses rectangular complex addition and multiplication. Both variants
  allocate and fill every matrix cell in the original reverse traversal order.
- String growth creates both overlapping substring buffers before joining
  them. Bytevector/string conversion allocates distinct source and output
  buffers and uses the original random stream. Quicksort retains its original
  generator, crossing swap/restoration and smaller-partition-first recursion.
- Queens uses reference-counted persistent row lists. Append copies its first
  list and shares its deferred second list; placements share suffixes. Puzzle
  and triangle search retain mutable boards, traversal order and restoration.
- `destruc` splits and transfers existing owned cell suffixes without copying.
  The outer fixed collection uses a Rust vector; inner identities and mutations
  remain visible in the linked cells.
- GCbench retains top-down mutation, bottom-up construction, unused node
  payloads, stretch tree and surviving tree/array lifetimes. Rust releases dead
  trees immediately through ownership; Scheme collects them through tracing.
- `sum1` reads numbers from a buffered character port on each iteration;
  `read1` buffers each file's text and parses/releases individual datums.
  The shared input reader handles comments, quotation, strings, vectors,
  bytevectors, character literals and dotted lists used by canonical fixtures.
- The two continuation Takeuchi variants and continuation Fibonacci expose
  saved operand contexts in explicit trampolines. Their specialized captured
  handles do not promise general multi-shot Scheme `call/cc`. Peano Fibonacci
  preserves every successor/predecessor step. Independent review confirmed the
  supplied/active-context invariant and added exact call/capture/invocation and
  Peano-work checks. Canonical reruns after that review are recorded separately.
- Pi runs all three original fixed-point exact algorithms and checks their
  exact differences. Chudnovsky retains binary splitting and integer square
  roots. Its fixed `640320^3` is a compile-time u64 constant, corresponding to
  Scheme's top-level setup before timing; each leaf still computes the variable
  cube and its exact product/quotient. Scalar multiplication can use a different
  bigint operation from Scheme. Rust collects inline result rows in vectors,
  while Scheme builds lists. `num-bigint` owns linear-memory buffers; Scheme
  owns GC values. Replacing a result constructs the next one before dropping
  the previous one.
- Ray tracing retains scene order, nearest-hit search, quadratic roots,
  Lambert shading, ties-to-even rounding and complete ASCII PGM file output.
  Rust points are inline values, rather than separately allocated Scheme vectors.
- Simplex retains both phases, pivot selection/tie breaking, row/column mutation
  and complete basis vectors. Its original numeric input is ignored by the
  hardcoded test tableau. That tableau crosses an optimizer opacity boundary;
  result formatting occurs after the workload timer.
- Equality builds the original shared DAG, unshared tree, flat vector, shallow
  shared lists and deep car chains. Rust's equality primitive uses an explicit
  visited-pair set; reclamation of deep owned chains is iterative. The cyclic
  case and the first parameter are disabled in the original source too.
- Permutation generation retains Zaks's recursive pancake flips, separately
  allocated inner/outer cells, shared unchanged suffixes and queue survivor
  identities. The full original `20:10:2:1` workload passes. Rust reclaims
  detached outer lists iteratively and inner cells through reference counting.
  The result predicate traverses every retained integer and computes its
  expected checksum from `N`; it ignores the pinned expected-input datum.
- Functional maze generation keeps persistent linked matrix rows. Each update
  copies its prefixes and shares unmodified suffixes; the original shuffle,
  cavity flood fill and entire output maze are retained. Position IDs are inline
  pairs; neighbor collections are temporary vectors. This is the flood-fill
  algorithm, distinct from the separate hexagonal union/find maze workload.
- Hexagonal maze generation retains the original wall order, seeded random
  permutation, union-by-size/path-compression rules, depth-first neighbor order,
  longest exit path and complete linked character output. Stable cell indices
  preserve identity in an owned arena; source cell and auxiliary vectors are
  inline fields. The character buffer survives until the next printer reset.
- Paraffins enumerates the original ordered partitions and constrained radical
  combinations. Each carbon is shared by reference counting; each final center
  and outer list cell is separately allocated. All 5,731,580 molecules are
  materialized at canonical size. The optimizer sees each center during the
  original result-count traversal; this opacity barrier adds no full comparison
  inside the timed loop. Complete small molecular topologies are checked later.
- Browse retains the linear property tables, shared pattern roots, named
  single/sequence-variable backtracking, deterministic shuffle and fresh
  name conversions. Matching an empty datum returns Scheme's truthy empty
  list. Persistent sequence-prefix append copies cells rather than mutating a
  fresh prefix; allocation traffic differs while retaining linear append work.
  Each discarded match result crosses an optimizer barrier.
- Earley performs the original forward prediction/reduction and backward
  filtering passes, followed by unmemoized derivation of every parse tree.
  Canonical size materializes 2,674,440 trees. Rule and child identities remain
  shared; outer list cells are owned. Copying outer lists uses explicit cursors
  to avoid native recursive stack growth; complete small forests retain order.
- Conform keeps cyclic node identity, coinductive red assumptions, green
  proofs, ordered meet/join caches and the source's unstable name-length sort.
  Canonicalization rewrites graph endpoints and tables. An owned arena retains
  removed nodes until each lattice run ends; tracing GC may collect them earlier.
- Matrix keeps shared numeric row tails, persistent matrix cells, exact modular
  reduction, original permutation cursors, column partitions and include-first
  subset enumeration. It materializes all maximal matrices in source order;
  coefficient prime testing stops at the same square-root boundary.
- Both Boyer provers retain symbol-record lookup, constructor identity,
  source-order lemma attachment, directional unification, numeric-pattern
  constraints, substitution, full recursive rewriting and tautology assumptions.
  Canonical size performs exactly 51,507,739 rewrites. `sboyer` reuses unchanged
  call and argument cells by pointer identity; substitution always creates fresh
  compound cells in both versions. Constructor IDs expose the logical cycles
  through an owned table without reference-count cycles. Each invocation owns
  and releases that table; source global record/binding roots can survive until
  the next setup and tracing collection. Quoted constants remain shared outside
  timing, while lemma translation/setup stays inside every iteration, matching
  the actual wrapper rather than its introductory timing comment.
- Partial evaluation performs every original alpha-renaming, substitution,
  reference-count scan, destructive branch/binding replacement, primitive fold,
  recursive specialization and empty-call fixed-point pass. Actual shared mutable
  expression cells and linked environments retain frame/branch identity; traversal
  sees bindings appended during specialization. All ten results cross the
  optimizer boundary, while the original predicate checks the tenth result.
  Rust evaluates renaming maps left-to-right; R7RS leaves map application order
  unspecified and Chez chooses another schedule. The untimed complete ten-result
  audit compares lexical alpha equivalence, preserving free and quoted symbols.
  Capture, free/quoted-symbol changes and swapped parameter uses are rejected.
  AST cells use reference counting and interior mutation, temporary cursors use
  Rust vectors, and the symbol interner retains generated names. `not-constant`
  is a typed knowledge marker instead of the source's shared one-cell list;
  bounded exact rational constants cover the canonical arithmetic domain.
- Parsing uses the original LexGen transition graph, separate token/character
  lookahead, 1,024-character accumulator and strong LL(1) grammar. List parsing
  retains the temporary data list and copies its tail through `pseudoAppend`;
  the terminus remains shared. Both do-loop datum values survive the next parse.
  File loading constructs/reverses character lists inside the timed outer call,
  then repeats parsing exactly 2,500 times. Source quirks remain visible: string
  escapes are not decoded, the character action returns the token's first `#`,
  and the literal `eof` symbol/recovery rules can terminate parsing early.
  Character-name chains are represented by their remaining spelling, with the
  same transitions; generated forwarding states disappear. Rust interns names
  in an owned table and releases parsed cells by reference counting. Integer and
  rational storage is bounded to the canonical domain; reals use binary64.
- Nucleic preserves all 46 quoted conformations, fixed relation matrices,
  trigonometric alignment, domain/candidate order, distance constraints and
  sequential backtracking. Candidate variables and partial lists share identities;
  solution append copies its first list and shares the second. Atom enumeration
  constructs the common/specific lists and copies the common prefix. All three
  distance-map lists and maximum traversals remain materialized. Fresh points
  and transforms use owned boxes/reference counting, with explicit opacity
  barriers on computed points/compositions, solutions and mapped distance lists;
  these barriers retain allocation/work and perform no extra result comparison.
  Scalar numeric list payloads are inline binary64 values. Rust reclaims owned
  distance chains iteratively. An untimed extra search compares all 50 ordered
  solutions, all 23 variable IDs/conformation identities per solution and every
  12-component transformation against an independent original Chez oracle, with
  `1e-11` relative/absolute binary64 tolerance. The timed predicate remains the
  original `0.999999 < result/output < 1.000001` scalar check.


- Scheme compiles the complete supplied expression on every one of its 100,000
  iterations, then executes the generated graph. Every source syntax form has
  a concrete compilation path; the unchanged 151 primitive registrations retain
  their original order outside timing. Generated Rust operation nodes replace
  native Scheme generator closures, adding operation dispatch. Compiler argument
  collections and some temporary lists use vectors; calls with zero through
  three arguments use stack arrays, while larger calls materialize argument lists.
  Actual mutable global binding pairs, linear association lookup, lexical mutation,
  reversed internal-definition collection, recursive scopes and shared list tails
  remain. Global bindings/macros survive all repetitions and escaped closures keep
  their captured frames. Owned frame indices retain cycles without Rc cycles;
  root tracing and sweep run after each complete invocation inside the timer,
  retaining dead frames until that boundary and adding a root traversal per call.
  Input, expected, previous and new result values remain roots during that sweep.
  Each runtime frame owns a boxed slot slice with a separate parent index instead
  of the source's vector slot zero. The primitive implementation covers the
  canonical string/list domain and independent binding/quotation/vector probes;
  exact numbers are bounded integers, reals are binary64, and unused file-port,
  exact-rational and some numeric primitive domains fail explicitly. This is not
  a general Scheme implementation; collection of arbitrary mutated pair/vector
  cycles is outside this checked domain. The source's truthy empty list, frameless
  zero-argument lambdas and ignored extra arguments for fixed arities above three
  are preserved. All 30 canonical sorted elements and four independent complete
  results are checked against original Chez, with wrong-result rejection.


- Dynamic opens and reads the original inferencer file on each of 500 calls,
  parses every command into shared typed AST nodes, builds every equality
  constraint, performs union-by-rank/path-compression normalization and constructs
  the entire tagged program. The source's null-as-pair type, duplicate checks,
  rest formals, definition prepass, binding visibility and unsupported do/quasiquote
  errors remain. All ten original primitive type environments are represented by
  constructor recipes; every forall/fix instantiation performs fresh original
  construction work. Primitive type graphs persist and can stay mutated across
  calls; resetting the outer environment does not rebuild these graphs. Actual
  type/argument sharing and recursive cycles survive through stable owned indices.
  Type variables use boxed records and shared argument cells instead of chained
  mutable pair records; polymorphic captures use owned vectors. AST records retain
  shared defining occurrences, while temporary map/zip cursors use vectors.
  Discarded normalization/equivalence maps and the complete tagged output cross
  explicit opacity boundaries; these retain work without extra timed comparisons.
  A per-call root sweep keeps primitive groups and the current top-level graph,
  including old definitions behind parent links. It retains dead variables until
  the boundary and adds tracing work per call. Rust buffers file text/characters
  and closes its input port before parsing; the source leaves that port for GC.
  The returned three counter pairs use an inline array. Rust evaluates constructor
  and parser operations left-to-right where R7RS leaves host operand order open.
  Four independent small complete tagged programs, all six counters, wrong-answer
  rejection and exact type-construction totals agree with original Chez. An
  additional inference after timing produces a 107,970-character tagged program
  that is compared with the corresponding original Chez run; this is a new
  inference snapshot over persistent state, not the last timed output.
  The cumulative original type-variable counter after 500 calls plus that one
  audit is exactly 11,360,332 in both implementations. These diagnostics are
  correctness evidence, not profiling or retained performance observations.

- SLaTeX reads the complete TeX/Scheme file graph on every original repetition,
  creates and closes actual buffered files, scans two reusable 200-character line
  buffers and applies the original whitespace/alignment and quote/macro/case
  transitions. Token databases, aliases, scanner continuation state and auxiliary
  counters persist between snippets and all 500 calls. The primary counter is
  deliberately not reset; include restores its saved counter even without a
  separate include file, preserving the source's overwrite behavior. Protected
  regions create, reprocess, inline and delete their actual temporary files.
  Character escaping and token assembly use fresh owned linked cells with the
  source's destructive append/reverse operations; quote frames are separately
  boxed, while their outer stacks and linear databases use Rust vectors. Rust
  drops unreachable cells and buffers through ownership rather than tracing GC.
  String tokens compare by spelling; case-insensitive comparison uses Rust
  lowercase strings and adds temporary allocation. Source Unix path/newline and
  200-column assumptions remain. Numeric token recognition covers the checked
  integer, rational, real and complex spellings; this is not a general Scheme
  numeric reader. The source searches an arrow spelling different from its own
  greater-than escape, so ordinary `->` keeps the source's escaped spelling.
  Setup occurs before timing; file lookup, scanning, formatting, mutation and
  file I/O occur inside each iteration. Only the supplied filename crosses an
  explicit opacity boundary; I/O and the externally observed files retain output
  work. The original predicate is always true and ignores both expected datums.
  A separate complete generated-file comparison after execution checks names,
  lengths and SHA-256 digests in isolated Rust/Chez directories: all 28,500 files
  and 2,865,500 bytes agree. Three independent complete small file graphs cover
  fonting/alignment, database and protected-region controls, and repeated includes.
  Additional file-oracle probes reject changed bytes, missing/extra files and
  changes to plain-TeX marker files; they do not strengthen the timed predicate.

`checkpoint.json` records each successful source/binary snapshot. New structural
canonical checks are in `build/rust-maze-paraffins-browse-full/validation.json`,
`build/rust-earley-full/validation.json`, `build/rust-conform-full/validation.json`,
`build/rust-matrix-current-full/validation.json` and
`build/rust-paraffins-current-full/validation.json`; complete small checks are
in `build/rust-cohort6-small-current/validation.json`. Default/optional Ackermann
results coexist in `build/rust-ack-variants/validation.json`. These correctness
reports freeze source/tool/binary hashes without retained performance samples.
The two prover and partial-evaluation snapshots are
`build/rust-boyer-current-full/validation.json` and
`build/rust-peval-current-full/validation.json`. Peval's audit runs after the
timer and is separate from the unchanged canonical predicate.
`build/rust-parsing-full/validation.json` freezes the complete parser's original
file/count and independent grammar/action/EOF/zero-count checks.
`build/rust-nucleic-current-full/validation.json` freezes the 50-repeat nucleic
workload and the complete untimed numeric solution audit.
`build/rust-scheme-current-full/validation.json` freezes the per-iteration
compiler/evaluator, unchanged 100,000 repetitions and complete independent checks.
`build/rust-dynamic-current-full/validation.json` freezes the original 500
self-inference calls, independent complete programs and post-timer canonical
additional-inference program/construction-count audit. Its oracle tail and cumulative-count metadata
are in `tests/dynamic-oracle-tail.scm` and `tests/dynamic-oracle-meta.json`.
Append the tail to the generated original Chez program after removing only the
final `(run-benchmark)` invocation, then compile at level 2. It reads a count and
filename, prints the original counters, and performs one extra untimed complete
program audit.
`build/rust-slatex-current-full/validation.json` freezes all 500 file-processing
iterations and complete file-set comparisons. Its source, binaries, full outputs,
independent fixtures and retained-work disassembly are committed under
`benchmarks/results/2026-10-13-rust-slatex`.
The reviewed exact arithmetic source/artifacts are committed under
`benchmarks/results/2026-10-13-rust-exact-arithmetic`.

## Complete compiler reference and remaining reviews

The Compiler port performs the original complete Scheme-to-68000 compilation
2,000 times and checks all 497 assembly strings. `src/compiler.rs` owns located
syntax, parsing and normalization; `src/compiler_gvm.rs` owns virtual operands,
frames, closures and instruction graphs; `src/compiler_blocks.rs` performs the
original purification/order/slot passes; `src/compiler_68000.rs` emits physical
instructions; `src/compiler_asm.rs` owns object words, symbols, shared labels,
relocations and branch tensioning. Catalog registration occurs before timing;
fresh syntax/global state and all 10,000 virtual entries are allocated inside
each compilation before processing source. The final complete predicate is timed.

The exact source, binaries and outputs are archived under
`benchmarks/results/2026-10-13-rust-compiler`. Eighteen complete line/object-word
checks, 26 complete GVM/slot checks, five assembler diagnostics and complete-list
wrong/truncation/extension checks pass in actual Node/Wasm and original Chez.
Fifteen focused native tests and the all-suite native checks pass. Fresh focused
explanations/debates covered GVM/blocks and frontend/assembly/emission separately.

Typed arenas retain obsolete parse/GVM records through compilation; persistent
lists, stable mutable pairs and shared environment-root handles retain source
identity/sharing. `Vec<String>` holds assembly lines and Rust immediately drops
owned records, whereas Scheme traces them. Traps copy their metadata slot spines;
descriptors share mutable positions with labels. Additional per-word/descriptor
opacity preserves original work with disabled binary/debug output, while complete
word diagnostics remain separate from timed result equality. Synthetic arithmetic
identity values and a cell's null helper argument emit direct immediates rather
than late GVM interning; the canonical program does not use that adaptation.
Additional target/options, tasks, unsupported primitive families and compound
literal dumping fail explicitly outside the checked input domain.

Fresh independent reviews of linked-list sharing, later structural groups and
SLaTeX remain pending and are separate from successful execution and timing.

The focused Scheme/Dynamic ownership explanation, debate and test-only review
are recorded in `reviews/scheme-dynamic.json`. The nine native tests pass;
`reviews/scheme-dynamic-runtime-hashes.json` verifies their reviewed sources emit
byte-identical release Wasm to the frozen canonical binaries. Historical source
snapshots and observations remain unchanged.
