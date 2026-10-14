# Nucleic source correspondence and focused review

The full 3,485-line upstream source is pinned at
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`; its kernel has 3,469 lines.
The declared workload remains 50 invocations of `run` with the empty partial
assignment and expected value `33.797594890762724`. The original acceptance
predicate compares `result / expected` strictly against `0.999999` and `1.000001`.
The strict worker also preserves the original false result for nonpositive
repeat counts. Actual input datums are read with Chez before execution; the
current adapter accepts the declared empty partial assignment, not arbitrary
Scheme values.

The algorithm retains every source definition, 46 nucleotide constants, six
relation matrices, the identity transform, 6,719 decimal tokens in order,
and the original ordered search. The adapter records counted substitutions;
reversing them reconstructs the original kernel byte-for-byte. The complete
original program and input are retained. The adapted Chez control receives
exactly the strict kernel plus the corresponding representation helpers.

Each nucleotide becomes a concrete base variant plus a mutable vector of
coordinate/transform vectors. Original slots 0 through 28 keep their positions;
the symbol tag at slot 29 moves into the base field; later fields shift by one.
All 57 getter/setter pairs remain. Point and transform vectors retain their
original mutable homogeneous F64 storage and alias relationships. Four base
predicates inspect the concrete base code. Mutable assignment records become
one shared Ref containing an immutable product of ID, transform and nucleotide;
a setter replaces that product while retaining the other fields. This is two
allocations at construction instead of the original vector's one, and a fresh
product on a setter. The canonical search does not call those setters, but
separate probes check them and their retained aliases.

Quoted database vectors become explicit constructor calls before the timed
worker. Every inner numeric spelling and order is unchanged. Binary arithmetic
macros preserve the original left-associated sums and evaluate each operand
once. Unary negation multiplies by -1.0, preserving both zero signs in this F64
geometry. The map helper calls its callback before traversing the tail; append
copies its first list and shares its second. Lists remain linked Scheme lists.
The one source `case` becomes a single ID read and equivalent integer tests.
No data slice, precomputed result, reduced repeat count, alternate search or
bulk host implementation replaces the workload.

The original `math-atan2` branches remain intact, including the special x=0
branches and `(0, 0)` returning positive pi/2. The library supplies only scalar
binary64 sin, cos and unary atan, with ordinary typed externs that call the same
Rust implementations in Wasm and native code. Platform transcendental rounding
need not be bit-identical. Tests compare complete computed results with a stated
tolerance and test signed zero explicitly.

The complete-value probes cover all database values; every ordered pseudoknot
and anticodon solution with variable ID, nucleotide identity and all transform
coordinates; geometry operations; all nucleotide/point/transform/assignment
setters with retained aliases and unchanged-field identities; sixteen atan2
zero/quadrant combinations; maximum tie behavior; and the actual final run
value. These are complete ordered result probes, not a trace of every pruned
search node. Unchanged search code establishes the algorithm's traversal rule.

A fresh no-history explainer received a neutral behavioral brief without files,
implementation decomposition or favored changes. The independent model kept
scalar math at the foreign boundary, typed mutable geometry in Scheme, and
source correspondence separate from runtime result checks. The informed critique
retained the explicit Ref for mutable assignment identity and required complete
numeric and ordered observations because the original ratio predicate is coarse.
A generic trigonometry registry, host geometry implementation and generic probe
framework would add machinery without strengthening those contracts.

The adapter remains one file about this source's representation and verification.
The Node host has one responsibility: instantiate the linked module, supply
scalar inputs/observations, validate the worker, and close resources on success
or failure. Counted source transformation, complete field-probe generation and
raw-record-preserving validation loops exceed ten logical lines where splitting
would hide an atomic correspondence or checking operation. The original long
geometry functions are retained unchanged rather than cosmetically refactored.

Two fresh independent explanation/critique passes covered the compiler blockers
separately. Graph copying keeps its existing traversal, reserves shells before
children and replaces only the linear identity association list with the
repository identity table. Reachability shares discoveries within one query,
marks before traversal, tests the target on an edge, and leaves input exclusions
unchanged. These choices preserve positive-length self reachability, cycles,
recursive-group membership, scheduling and diagnostics. Broader SCC/inference
redesign and a speculative iterative copier were rejected. Existing traversal
and initialization order remains visible in the landed frontend.

The supplementary Rust reference was inspected, not used as algorithm authority.
It uses Rc/Box geometry and Vec-backed domain descriptions instead of these
Scheme linked lists and closures, parses embedded constants at startup, and
accepts nonnegative repeat counts. Its representation and zero-count behavior
must remain explicit in any later comparison. This preparation task contains
no clean performance measurements.

A second fresh no-history explanation/critique reviewed the completed adapter,
probes and preparation ownership boundary. It distinguished complete ordered
solutions from an unobserved internal pruning trace and required reporting actual
numeric differences beside the tolerance. It also identified the closed-output
child cleanup gap. The retained reproduction leaves the old child running;
the corrected cleanup terminates it even after the leader exits and both pipes
close. Success and ordinary nonzero-exit behavior remain checked separately.

The final reviewer suggested a loop of paired field operations as an optional
way to reduce generated probe source. The existing exhaustive field fixture is
retained: each operation snapshots the current field identities before mutation,
allocates its own replacement, and checks the alias and every unchanged field.
This bounded test expansion keeps the independent field ledger visible and
avoids changing already validated observations for a cosmetic reduction. It is
an explicit exhaustive-test exception to the ten-line target, not a production
builder abstraction.

The timeout-only supervisor correction follows the successful compilation.
`nucleic-source-amendment` preserves the original helper and preparation metadata,
compares every other top-level Python AST definition, regenerates the exact
canonical/probe Scheme programs, and verifies all compiler and case artifacts.
The final frozen helper therefore governs future builds without claiming that
it produced earlier compilation records. Logs are buffered and saved on handled
completion or timeout; an abrupt death of the Python supervisor itself is not a
covered log-durability guarantee.
