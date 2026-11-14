# Proposed query-driven incremental compilation

**Design proposal; not implemented.** The primary objective is a clearer compiler
architecture: each pass leads with its input and output languages, its semantic
operations, and the evidence it establishes. A small general-purpose framework
composes those operations and owns query scheduling and reuse. Incrementality,
performance and editor analysis follow from those boundaries; adding memo tables
to the current control flow alone does not satisfy the goal.

The build process and LSP process use the same query implementation, each with its
own compiler workspace and generational cache. Within a workspace, finishing one
request does not discard the results needed by other requests.

This chapter is the main architecture and delivery plan. The
[source-project proposal](source-projects.md) specifies application selection and
removal of the manifest model; the [artifact proposal](artifacts.md) specifies
resource linking, staging and deployment. Those are outcomes of the broader
compiler work, alongside reuse across edits and a shared basis for editor services.
The [unified roadmap](https://github.com/tsnl/snail-scheme/issues/729) tracks this
work alongside callable classes, async engines and the other language/runtime plans.

The implemented [session](compilers.md#separate-compilation) already reuses library
expansion, checking and emission across builds of a target. The
[resident builder](compilers.md#the-resident-builder) retains a session per target;
specialization state is constructed during preparation, and some identities are
local to a session lineage. The proposal extends that foundation with shared
identities and explicit dependencies, rather than promising that combining today's
session tables is sufficient.

## Scope and intended outcomes

| Goal | Completion evidence |
| --- | --- |
| Make the compiler's architecture legible. | Pass modules expose their languages and semantic operations; composition and cache ownership have explicit boundaries without requiring cache checks in every function. |
| Make compilation incremental from its inputs through emission. | Typed results record dependencies and can be reused across edits, targets and generator stages without changing their meaning. |
| Optimize compiler work. | Repeated requests avoid redundant expansion, checking and specialization; timings, work counts and retained memory show the costs of both fresh and reused results. |
| Simplify the compiler. | Query ownership replaces overlapping cache and orchestration paths; the migrated paths are removed, and passes retain explicit inputs, outputs and invariants. |
| Support editor analysis through the same compiler. | Scopes, declarations, types and diagnostics are available without requiring application emission, with incomplete-source and snapshot contracts. |
| Replace manifest targets with source requests. | CLI, IDE and artifact macros use the same application/output request; retire `project.datum` and `src/snail/shell/project.sld` after migrating its required responsibilities. |
| Unify staged generation and artifact production. | Producers and applications share compiler results while keeping execution prerequisites, runtime resources and publication lifetimes explicit. |

Compiler simplification and performance are deliverables in their own right.
Removing the manifest alone does not complete this plan. The migration may change
compiler responsibilities and representations where needed to establish these
boundaries, while preserving language semantics, type/ownership/effect evidence,
the Chibi bootstrap and native/browser behavior.

Implementation should arrive in reviewable steps with working clients throughout.
Begin with in-memory query reuse and appropriate existing inference units; expand
granularity where measured invalidation costs justify it. Full LSP protocol coverage,
persistent or remote query caches, and new optimizer passes can be separate work
once the shared compiler contracts are established.

## A workspace per process, many requests

The compiler accepts explicit inputs and derives immutable results from them.
Each reusable operation has a key, its result and the inputs or other results it
actually read. A request uses an existing result when that evidence still holds;
otherwise it computes the result and records fresh evidence. The scheduler owns
the pending work and memo tables; compiler passes remain functions of their inputs.

There are three uses of the same mechanism:

| Situation | What reuse means |
| --- | --- |
| Two applications need the same library or specialization. | Both use the same compatible result. |
| A generator completes before its consuming application. | Its compiler results remain available when the application resumes. |
| Source changes between editor or build requests. | Recompute affected results and reuse those whose dependencies still agree. |

An output selects a closed set of code and resource references from this workspace.
Emitting that selection does not seal the entire workspace or end compilation.
A generator runs one completed selection and contributes new source inputs; work
then continues. Each program keeps its own entry, initialization and runtime state.
Shared compiled code does not imply shared runtime instances.

The intended deployment uses separate LSP and build processes. The LSP owns its
analysis snapshots and cache; the builder owns a cache shared by all application
targets and generator compilations in that build. Executing a producer in another
process does not move or discard the builder's compiler results. This separation
prevents short editor requests from determining retention of build-only work.

The processes share compiler code and contracts, not an in-memory memo table.
They may perform some of the same analysis independently. Cross-process reuse of
semantic results is not required for this design; any later persistent cache needs
its own compatibility evidence. Sharing immutable artifact-store bytes remains a
separate matter from sharing compiler objects.

## The standard-library example

Suppose a producer imports the standard library and uses a specialization
`f<I32>`. The compiler expands and checks the required libraries, constructs that
specialization and emits a runnable producer. Running it returns source for the
application. If the application needs the same libraries and `f<I32>` under the
same semantic inputs, those results are reused. A new use of `f<String>` constructs
one new specialization and its newly required dependencies.

Importing a generic definition does not instantiate it at every possible type.
Nor does crossing a generator stage by itself invalidate a checked library or
specialized body. Producer and browser code can share semantic results while
requiring different emitted modules because their host imports or ABI differ.
Reassembling an output module is distinct from rechecking its source.

The invariant within one workspace is: compute each distinct result once per valid
set of inputs, regardless of which target or stage asked for it. A stage number or calling
target must not enter a key unless it genuinely changes that result's meaning.

## Results and their dependencies

Use a small set of typed operations at existing pass boundaries. The names below
describe responsibilities, not proposed surface APIs or a generic plugin system.

| Result | Relevant dependencies |
| --- | --- |
| Parsed syntax | Source text, origin and reader configuration. |
| Expanded library and scopes | Syntax, imported macro and binding interfaces, features and generated inputs. |
| Checked library or definition | Resolved code, imported type interfaces and the relevant instance environment. |
| Specialized body | Checked definition, concrete type/effect arguments, selected class evidence and representation/control context. |
| Emitted module | Prepared bodies, module boundaries, backend ABI, compiler version and code-generation options. |
| Artifact bindings and layout | Compiled modules, linked resources and output configuration. |

Begin with library-grained checking where the language's inference and recursion
require it. Refining body-level results later must preserve those inference units;
mutually dependent definitions may need to be solved together. Stable declaration
interfaces already let importers avoid depending on unrelated implementation
bodies. Specialization and inlining must explicitly depend on the bodies they use.

Shared storage does not create one global name or instance environment. Each
result keeps its resolution context; adding another application's declarations
must not retroactively change an earlier result's instance selection. Runtime
handler instances are not specialization keys. Context-sensitive ownership/control
checks remain attached to their relevant use, even when body construction is shared.

Give files and definitions stable semantic identities with macro origin and
hygiene preserved. Source offsets and traversal counters alone are insufficient:
inserting a declaration must not rename every unchanged definition. Keep identities
distinct from result versions, and track source locations so an unchanged semantic
answer cannot display an old diagnostic span after an edit. The global edit revision
belongs to validation bookkeeping, not every semantic cache key.

## Pure rules and their composition

Keep semantic rules as ordinary typed functions with explicit dependencies. A rule
for a function call receives the relevant callee and argument facts and returns a
structured result. The composing layer obtains those facts, sequences the work and
connects operations across passes. This preserves the ability to interleave passes
while keeping their recursors and semantic operations in cohesive modules.

| Responsibility | Contract |
| --- | --- |
| Semantic rule | Compute from explicit immutable facts and context; return checked code, types, effects and the evidence or obligations needed downstream. |
| Recursor or query implementation | Obtain dependencies, supply rule inputs and choose evaluation order, including calls into other passes. |
| Query engine | Reuse or compute selected operations, record dependency evidence and maintain the workspace's memo generations. |

For an already-inferred call, the separation might look like this. These are
illustrative responsibilities, not proposed Snail syntax or settled APIs:

```text
check_call(callee_facts, argument_facts, context) -> CallResult

check_library(library_identity, context) -> CheckedLibrary
    obtain resolved syntax and imported interfaces through tracked queries
    run the checker, composing ordinary semantic rules
```

The invariant is that every input affecting a cached result appears in its
immutable arguments or recorded dependencies. Rule identity distinguishes different
computations over the same arguments. Equal relevant inputs permit reuse; the
composing layer records how those inputs were obtained so it can establish their
validity after an edit. Avoid passing the whole workspace or revision where a
specific interface or piece of evidence suffices.

Rule boundaries and cache boundaries need not coincide. Memoizing a call rule
after recursively checking every argument still traverses those arguments. Cache
expensive enclosing units too, so a valid hit can skip their recursors. Ordinary
helpers need no cache checks, and declaring a rule does not allocate a cache for
every node. Query entry points own the reuse machinery.

Inference need not follow a bottom-up fold. Expected types can inform child checks;
unification, effects and instance selection can produce obligations and require
joint solving. Thread solver state explicitly within its inference unit. Initially
cache completed checking results at that boundary; temporary inference variables
must not escape into reusable answers with identities meaningful only to one solver
invocation. Reusing constraint recipes with fresh variables would require a separate
contract. Local recursion and fixed points remain visible compiler algorithms.

## Framework boundaries to sketch

The working direction is a small typed framework that supports these boundaries,
with semantic operations written as ordinary functions. The exact declarations,
generated interfaces and use of Nanopass remain open for sketches and review.
Adopting a complete Nanopass implementation is not a prerequisite.

### Constructor structs and fixed-arity queries

This revised sketch uses ordinary structs, sums and typeclasses with associated
outputs. Those language facilities exist; the tree/query declarations and generated
cache wrappers described here do not. The names and signatures below are for
review, not a new library API.

As with the archived `define_tree!` macros below, a tree declaration generates a
sum and a distinct struct for each constructor. For example, its public shape
could be:

```scheme
(struct Literal
  ((value I64)))

(struct Call
  ((callee Expr)
   (arguments (List Expr))))

(enum Expr
  (LiteralExpr (node Literal))
  (CallExpr (node Call)))
```

A call rule can take `Call`, not an `Expr` that it must inspect again. Recursive
children remain ordinary `Expr` fields; a higher-kinded recursion framework is
not required. Input and output languages use separate types where their invariants
differ. This sketch describes the typed interface, not a requirement to allocate
both a wrapper and a payload object for every node.

Give `ask` one fixed signature and an instance for each pass/input pair:

```scheme
(typeclass (Query Pass Input)
  (type Output)
  (: ask (-> Workspace Pass Input (Pair Output Workspace))))
```

`Workspace` represents the compiler's explicit inputs and memo state. A pass value
identifies an operation and carries relevant inherited context or configuration.
An input can be a constructor struct or a request struct bundling additional facts.
For example, `(Query Lower Literal)` and `(Query Lower Call)` can both produce
`LoweredExpr`, while a checking request includes its environment and expected type.
Selection uses the pass and input types, never just the desired return type.
There is no need for variadic templates: more inputs become named record fields.

The generated instance owns validation, cache lookup, dependency recording and
publication. On a miss it invokes the composing function, which obtains child
results through `ask` and calls ordinary semantic rules. A thin sum dispatcher
routes `Expr` to the appropriate constructor instance. A hit at that constructor
can therefore skip its entire recursive computation; caching only the final rule
after visiting every child would not provide that saving.

Do not automatically cache both a sum dispatcher and every arm. Choose boundaries
that skip useful work. A language declaration supplies constructor types and
dispatch; a query declaration selects which computations are cached. The pass
identity, relevant pass fields, input and observed dependencies all contribute to
validity. Equal-looking syntax in different scopes is not sufficient.

The framework must also provide typed storage for each query's key and output.
One starting point is a generated workspace with a concrete table per declared
query family. Adding a family then regenerates that workspace. Associated output
types alone do not make an arbitrary heterogeneous memo table type-safe. Keep the
table layout and any equality requirements behind the generated query boundary.

### State propagation and callable classes

Explicit state threading works with the language today. `ask` above returns the
updated workspace alongside its answer; a sequencing macro can name those steps.
The current checker's `learning` macro already sequences pairs of answers and
checker state. This does not require a first-class higher-kinded `Monad` class.

Likewise, a substitution computation can be described as
`Solver -> Result<Pair<Value, Solver>, Diagnostic>`. Preserve the order in which
expected types and solutions reach child computations. Caching that computation's
execution requires its relevant solver inputs and a reusable account of the
resulting changes; caching a closure that will later run is not the same thing.
Begin with completed inference units rather than caching results containing
temporary unification variables from another invocation.

Callable classes are a related language proposal, not a prerequisite for `Query`.
Today's `Fn` is a noncapturing function representation and `FnOnce` is a linear
callable; neither is a Rust-style user-implemented callable class. A migration
toward `Fn`, `FnMut` and `FnOnce` contracts must define repeatable, exclusive and
consuming invocation, associated results, effects and capture cleanup. The current
language has no superclass implication, and the ownership meaning of an exclusive
mutable receiver needs review. Do not silently rename today's code-only `Fn` into
a different contract. See the [callable proposal](types.md#proposed-callable-typeclass).

Passes can use explicit class methods now. Making pass values ordinary callables
later may improve the interface, but it should not block sketching or testing the
framework with existing class machinery.

### What the framework guarantees

Three kinds of support are worth distinguishing:

- Tree declarations can generate typed representations and constructors. Separate
  input and output types should express meaningful pass invariants, such as replacing
  unresolved names with binding identities. Language extension and removal of
  variants are options to evaluate where they reduce repetition.
- Types, effect restrictions and module boundaries should keep semantic rules
  dependent on their supplied facts. Rules do not receive unrestricted workspace
  or IO access. External-input adapters remain an explicit trusted boundary;
  generated traversal alone cannot prove that all semantic dependencies were supplied.
- Typed query declarations can generate entry points for lookup, dependency
  recording and result publication. Query implementations use tracked operations
  to obtain inputs, while their semantic helpers stay independent of caching.
  This avoids adding cache boilerplate to every compiler function.

[Nanopass](https://docs.racket-lang.org/nanopass/index.html) describes intermediate
languages and transformations and can generate traversal for compatible forms.
Its tree and pass machinery is a useful reference; a statically typed Snail
adaptation would still need the dependency and cache contracts above. Keep
evaluation order, inference units and specialization worklists explicit rather
than requiring every computation to use one recursive traversal scheme.

### Prior tree macros

The archived Rust implementations provide a smaller starting point for the
representation declarations:

- Unit's [`define_tree!` on `archive/main-v8`](https://github.com/tsnl/unit/blob/9a6d5ceb89aa4f98bd80e0b6864ff12f248ef3be/src/tree.rs)
  generates an enum, a distinct struct for each variant and constructors. Its
  [call checker](https://github.com/tsnl/unit/blob/9a6d5ceb89aa4f98bd80e0b6864ff12f248ef3be/src/typer.rs#L200-L282)
  dispatches from `Term` to a helper accepting specifically `term::Apply`.
- Gamma's [`define_tree!` on `dev-28`](https://github.com/tsnl/gamma-lang/blob/46ed3d625453a4e3db5bd773e489faebd5c186d5/src/tree.rs)
  uses the same representation approach, including conversions from variant structs.

These macros establish node shapes and convenient helper signatures. They do not
generate dependency tracking or enforce the explicit-input rule style: Unit's
call helper still recursively resolves children and uses mutable checker
state. A Snail version should generate native Snail representations; Rust boxing
and constructor naming are not architectural requirements.

A declaration could distinguish recursive children, semantic payload and occurrence
metadata, supporting generated reconstruction, equality and fingerprints alongside
routine traversal. Source locations, scope and hygiene must retain the distinctions
in the syntax-reuse contract below. Supplying child results to semantic rules is
another possible generated interface; query declarations remain a separate concern.

Before settling the framework, sketch a simple lowering and a contextual checking
operation, including a cache hit that skips an enclosing traversal. Review:

- Which invariants deserve separate IR types, and which declarations can be shared?
- How are child results and inherited context supplied without hiding evaluation
  order or inference state?
- Which traversal and representation operations benefit from generation, and where
  are ordinary functions clearer?
- How do query declarations express keys, dependency reads and immutable results
  while preserving the generational lifetime rules?

Any generated forms must remain usable by the compiled compiler and Chibi stage 0,
preserving the bootstrap's explicit library boundary. The sketches should determine
the smallest useful API before implementation; no macro syntax is selected here.

## Reparse, then reuse predecessor syntax

Start by parsing a changed file in full. An unchanged file can reuse its existing
parse directly. As parsing constructs immutable content nodes, compute each node's
fingerprint from its kind, payload and ordered child fingerprints. These are
Merkle-style content summaries; no global intern table is required.

After parsing, reconcile the fresh tree with the predecessor generation's tree:

1. Find candidate old subtrees using fingerprints, with an optional temporary
   index of the predecessor's nodes to handle moved or reordered syntax.
2. Establish structural equality before reusing a candidate. A hash match alone
   is not proof of equality. Shared-node identity is a fast positive test; distinct
   identities can still represent equal content.
3. Reuse a matching old subtree as a whole. Otherwise reconcile the children and
   keep or construct the new parent with those child references.
4. Release the temporary index and redundant freshly parsed nodes when no longer
   needed. The resulting tree retains only the predecessor nodes it actually uses.

This is sharing between generations, not a promise that all equal nodes everywhere
have one canonical identity. Cache lookup must still support structural equality;
it cannot assume unequal pointers imply unequal syntax. Avoid repeated full-tree
comparisons at every ancestor: stop once a whole subtree matches, or memoize pair
comparisons within reconciliation. Hashing combines child summaries rather than
rehashing every descendant. Measure parsing, reconciliation and temporary allocation
costs; this approach still reads the entire changed file.

If a leaf changes, every ancestor whose child reference changes needs a new node,
up to the root. Unchanged sibling subtrees remain shared. This is intentional for
immutable trees: a single edit changes the path to the root, and several edits
change the union of their paths. The final retained tree can share most of its
nodes even though full parsing temporarily allocated a fresh tree first.

Separate reusable syntax content from occurrence-specific source locations and
origins. Moving a subtree must not leave diagnostics pointing at its old location.
Scope and macro hygiene still belong to resolution and expansion context; identical
syntax in different scopes is not the same binding or checked expression. An
operation that observes source location or origin must record that dependency.
Content fingerprints also do not replace stable declaration identities: editing a
function's body changes its syntax value while its binding can remain the same.

A changed file root does not establish that every descendant's semantic result
changed. Reuse depends on query boundaries and the inputs they observe. Initially
a whole checking unit may still be a library; finer reuse requires smaller sound
units, not merely hashes on every syntax node. This separation permits a later
incremental parser without making one a prerequisite for incremental analysis.

## Simplify ownership and control flow

Give each responsibility one home. The workspace owns query identities, dependency
evidence and memoized semantic results. Compiler passes compute those results with
explicit contracts. The scheduler owns pending requests and shares ready work;
the driver captures external inputs, executes producers and publishes completed
artifacts. Each application owns only its selection of code/resources and its
runtime state.

Replace duplicated mechanisms as their clients migrate:

- Target-specific compiler sessions become clients of shared result storage,
  retaining only the context and output selection that actually differ.
- Separate discovery expansions and later full expansions consume one recorded
  expansion result, including its import, generation and artifact requests.
- A producer's completion preserves compatible checked libraries and constructed
  specializations for later requests instead of starting another isolated compiler.
- Reuse and invalidation use the same dependency evidence, with precise ownership
  of input versions, result equality and diagnostics.

Each migration step should identify which old responsibility disappears and remove
the corresponding code once callers move. Keep local worklists and fixed points
where they express a real compiler algorithm, such as recursive specialization or
type inference. Query scheduling does not replace those algorithms. Use concrete
typed operations at useful pass boundaries; ordinary helpers need not all become
queries, and a generic callback framework is not a prerequisite.

## What happens on an edit

Inputs include file contents, file existence and resolution information, features,
compiler settings and supplied generated results. An unsaved editor buffer can
override the disk input in its own analysis snapshot. Missing-file lookups also
need dependencies, so creating the file can repair the result.

An input change makes dependent results potentially stale. Validate or recompute
them when demanded. If a recomputed result has the same relevant value, downstream
results can remain valid. Dependencies discovered while recomputing replace the
old dependency list: after an edit removes an artifact request, do not force that
obsolete child merely to validate the old plan.

| Change | Expected propagation |
| --- | --- |
| A function body changes under an unchanged signature. | Recheck its checking unit and rebuild affected specializations/emission; callers using only its interface can remain checked. |
| A type signature, macro or selected instance changes. | Invalidate consumers of that evidence. |
| A linked image changes. | Rebind and republish affected artifacts; leave semantic code unchanged unless compilation reads the image's bytes. |
| A producer runs again and returns identical syntax/resources. | Retain downstream semantic results when their other inputs still agree. |
| Another root requests an already available specialization. | Add it to that root's selection without constructing it again. |

This dependency and result-equality model follows the useful principle described
in the [Rust compiler's incremental algorithm](https://rustc-dev-guide.rust-lang.org/queries/incremental-compilation.html):
changed inputs can produce unchanged results, which should stop unnecessary
recomputation. Disk persistence and remote caching are separate implementation
choices; the first milestone can keep these results in memory.

## Cache generations and ownership

A generation consists of an input snapshot and query results established for it.
When an input revision changes, build the new memo index while consulting the
predecessor. Check the current index first, then validate a predecessor result's
dependency evidence. Carry forward a reference to the immutable result when valid;
otherwise compute and record a replacement. Retain the dependency evidence needed
to validate reused results later. Prior-generation membership alone proves nothing
about validity under changed inputs.

Do not create an empty cache generation for each hover, type query or application
root. Requests against the same snapshot accumulate results. Generator execution
can supply additional inputs, but the builder must preserve compatible results
through that staging transition and across all participating application roots.

The predecessor index is a construction aid, not a permanent fallback chain.
Once its required results have been carried forward and no pending work needs that
fallback, release it. Results and dependency evidence must not accidentally capture
the entire old workspace. Old readers retain their snapshots until completion or
cancellation; immutable values shared with the new generation remain reachable.
Other old values can then be reclaimed without explicitly freeing each result.

Discarding an unused result can cost recomputation if a later request needs it.
Begin with this explicit retention policy and measure it separately in the LSP and
builder. A bounded set of recent or active roots can be retained if needed. Separate
processes prevent the two workloads from evicting each other's compiler results,
but do not eliminate retention tradeoffs within either process. Syntax reconciliation
indexes follow the same lifetime rules; disk artifact cleanup remains separate.

## Generation and artifact references

A resource reference records the identity of another output without reading its
finished bytes. A generated library consumes its producer's result as source.
The first adds work and a relationship; the second can suspend a consuming query
until the producer has been compiled, bound and executed. Both use the same
workspace, while execution remains an explicit driver operation.

Keep the graph of artifact references distinct from the graph of computations
waiting for values. A and B may refer to one another's artifacts. Their manifests
can contain stable target identities, so neither computation must first evaluate
the other's complete output. A generator that needs its own unfinished source
result instead has an evaluation cycle. Ordinary recursive code is handled by
reserved declarations and the compiler's explicit fixed points, not by blindly
recursing into an unfinished cache entry.

Generation has effects. A reusable producer executable does not prove its previous
execution result is reusable: arbitrary filesystem reads are not all tracked
today. Continue running such producers once per build attempt and feed their
returned values into the workspace. Sharing their analysis and stopping propagation
when their output is unchanged still provide reuse. Persistent execution caching
requires a complete input/effect contract.

## Editor queries are compiler clients

An LSP adapter asks its own workspace for scopes, declarations, types and diagnostics.
Navigation does not require monomorphization, code generation or a deployable
application. Builds and editor features use the same binding and checking operations
in their respective processes; the protocol adapter does not implement a second
semantic model.
The [rust-analyzer architecture](https://rust-analyzer.github.io/book/contributing/architecture.html)
provides a useful example of explicit inputs and incrementally derived semantic
results with separate syntax and semantic representations.

Incremental caching alone is insufficient for an editor. The interfaces also
need incomplete syntax with diagnostics, source maps through macro expansion,
partial answers where dependencies are unavailable, and cancellation/supersession
of old requests. A recovered syntax tree is not evidence that a program is well
typed: code generation still requires successfully constructed checked values.

Each request observes a consistent snapshot of explicit compiler inputs. This does
not claim an atomic snapshot of arbitrary filesystem IO by generators; captured
files and publication still follow the service's
[observation rules](toolchain.md#observation-and-acceptance).
Results and diagnostics identify their snapshot, so an old response cannot overwrite
a newer answer. Completing one query can retain reusable evidence even if another
query fails; publishing an application still requires a successful complete root.
Existing running artifacts
remain separate from the editor's current, possibly broken, source revision.

Effectful generator execution stays under driver control. An editor query can
report a needed generated input or use an explicitly identified older snapshot;
it must not silently present stale generated declarations as current. The exact
policy for scheduling generators during editing remains a review decision.

## Delivery and checks

Use this sequence for the overall compiler migration; the companion chapters
provide the detailed source-request and artifact contracts.

1. Review one lowering and one contextual checking sketch, starting from their
   languages and explicit semantic operations. Choose the minimal composition and
   query framework before rewriting the compiler. Record fresh-build and
   retained-session baselines, repeated work and ownership of existing caches.
   Establish explicit input snapshots, stable semantic
   identities and typed query results with dependency evidence. Use the reviewed
   rule/composition sketches to keep semantic functions free of cache boilerplate.
   Introduce predecessor syntax
   reconciliation and generational result retention in each process. Start with
   serial execution so correctness and reuse are visible before concurrency.
2. Migrate expansion, resolution and checking to the shared workspace. Make two
   roots reuse compatible results, and replace duplicated discovery work with
   recorded requests from expansion. Preserve the inference units that establish
   library interfaces and lexical instance evidence.
3. Share specialization bodies and prepared code across applications and generator
   stages. Emit closed immutable selections, and retain valid results independently
   of publication success. Remove the superseded target-specific semantic caches
   as their clients move to query results.
4. Establish edit invalidation, result equality and diagnostics across the migrated
   passes. Expose analysis operations with incomplete-input and snapshot contracts
   for editor clients. Refine coarse dependencies where measurements show work
   that can safely be avoided.
5. Integrate the shared application/output request, staged generation and deferred
   artifact linking. Migrate commands, the IDE and development service, then
   retire `project.datum` and the manifest parser/model in `project.sld` as detailed
   in the [source-project migration](source-projects.md#implementation-sequence-to-review).
6. Measure the complete paths, remove remaining redundant orchestration, and add
   bounded parallel execution of independent prepared work. Keep the serial
   executor for bootstrap and deterministic comparison. Simplification accompanies
   each step; this final review verifies that the old and new architectures do not
   both remain responsible for the same work.

Assess both correctness and cost. On the same source snapshot and configuration,
incremental and fresh compilation must agree on diagnostics and executable behavior;
serial and parallel emission must agree on artifact content. Exercise cold builds,
unchanged requests, function-body edits, interface/macro/instance changes, asset-only
edits, generated libraries and multiple application roots using representative
repository programs. Measure wall time, completed work per pass/query and retained
memory across repeated edits and cancellation. Establish baselines before setting
numeric performance targets, and account for dependency-validation overhead rather
than reporting only a cache-hit count.

Require these specific outcomes:

- A producer and application sharing a standard-library specialization construct
  it once per compatible input set; a new specialization adds only new work.
- An unchanged request repeats no semantic computation whose evidence still holds.
  A producer with untracked effects may execute again; equal output preserves
  downstream results.
- The same semantic rules work with reuse enabled or disabled. A cache hit at an
  enclosing checking unit skips its recursor; changed context or dependency evidence
  invalidates the result. Rule inputs and outputs preserve the typing, ownership
  and effect evidence needed by subsequent operations.
- An asset-only edit rebinds resources without rechecking code. A changed selected
  instance invalidates the affected evidence, and a removed request drops its old
  dependency without forcing an obsolete producer.
- Editor answers use the requested snapshot, tolerate incomplete source where
  possible, and retire stale diagnostics while the last accepted application runs.
- Full parsing followed by reconciliation reuses equal predecessor subtrees,
  confirms equality under deliberately colliding fingerprints, and preserves current
  source locations and scope distinctions. Changed nodes rebuild their ancestor
  paths while unchanged siblings remain shared.
- LSP and build processes keep independent memo generations. Requests on one input
  snapshot accumulate results; old readers keep their snapshots while unused
  predecessors become reclaimable after their readers and construction work finish.
- Each migrated responsibility has one owner, superseded paths are deleted, and
  query retention can be bounded without evicting results still owned by active
  snapshots. Memory reclamation of compiler results is separate from artifact-store
  garbage collection.

Implementation must pass the repository's relevant compiler, Chibi/bootstrap,
native and browser checks, including executing generated code. Keep performance
measurements reproducible and compare fresh-build costs as well as reuse; avoid
trading reduced recomputation for unexplained regressions in baseline compilation.
