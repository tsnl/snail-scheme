# Proposed query-driven incremental compilation

**Design proposal; not implemented.** The primary objective is to organize the
compiler around incremental, typed queries, improving compilation performance
and simplifying how the compiler owns and schedules work. One compiler workspace
serves applications, generated-library producers and editor requests. Finishing
one request does not discard its knowledge.

This chapter is the main architecture and delivery plan. The
[source-project proposal](source-projects.md) specifies application selection and
removal of the manifest model; the [artifact proposal](artifacts.md) specifies
resource linking, staging and deployment. Those are outcomes of the broader
compiler work, alongside reuse across edits and a shared basis for editor services.

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

## One workspace, many requests

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

The invariant is: compute each distinct result once per valid set of inputs,
regardless of which target or stage asked for it. A stage number or calling
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

An LSP adapter asks the workspace for scopes, declarations, types and diagnostics.
Navigation does not require monomorphization, code generation or a deployable
application. The same resolved bindings and checked evidence serve builds and
editor features; the protocol adapter does not maintain a second semantic model.
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

1. Record fresh-build and retained-session baselines, repeated work and ownership
   of existing caches. Establish explicit input snapshots, stable semantic
   identities and typed query results with dependency evidence. Start with serial
   execution so correctness and reuse are visible before adding concurrency.
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
- An asset-only edit rebinds resources without rechecking code. A changed selected
  instance invalidates the affected evidence, and a removed request drops its old
  dependency without forcing an obsolete producer.
- Editor answers use the requested snapshot, tolerate incomplete source where
  possible, and retire stale diagnostics while the last accepted application runs.
- Each migrated responsibility has one owner, superseded paths are deleted, and
  query retention can be bounded without evicting results still owned by active
  snapshots. Memory reclamation of compiler results is separate from artifact-store
  garbage collection.

Implementation must pass the repository's relevant compiler, Chibi/bootstrap,
native and browser checks, including executing generated code. Keep performance
measurements reproducible and compare fresh-build costs as well as reuse; avoid
trading reduced recomputation for unexplained regressions in baseline compilation.
