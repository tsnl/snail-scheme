# Typed tables and cached views

**Proposed API, not implemented.** The [application model](applications.md#proposed-application-processes)
proposes preserving server and browser data through durable typed tables and
disposable views. This chapter develops that state model for review; its forms
are illustrative library syntax, not runnable examples. Storage semantics,
checking rules and performance need proof before replacing current save/restore.
[The state issue](https://github.com/tsnl/snail-scheme/issues/459) tracks that review.

## One owner for retained state

All base tables are durable. A view computes a value from a consistent database
snapshot and explicit arguments; caching that value is optional. There are no
independently mutable volatile tables, application `resume` methods or automatic
heap migrations. A new program starts at its ordinary entry point, opens its
store, recreates platform resources and asks for the views it needs.

| Concept | Representation | Lifetime |
| --- | --- | --- |
| Entity | Stable typed key, shared by its component tables | As long as the application retains the identity |
| Component | Ordinary struct/enum stored as a table row | Committed database data |
| View | Typed computation over a snapshot and explicit arguments | Cached result may be evicted at any time |
| System/action | Ordinary computation inside a write transaction | One invocation |
| Resource | Socket, window, renderer or other ordinary runtime resource | Its owning runtime/task |

Split components by how they are used, not by a rule requiring a table for
every field. Key types distinguish domains; they do not prove that an entity
or component exists. Missing-row results and referential constraints remain
explicit. IDs are values, not array positions or pointers.

## Schema from ordinary types

```scheme
(struct EntityId
  ((value I64))
  (deriving Serialize Deserialize))

(struct Paragraph
  ((text String)
   (font-size F32))
  (deriving Serialize Deserialize))

(struct Document
  ((title String)
   (paragraphs (Vector EntityId)))
  (deriving Serialize Deserialize))

(define-store Notes
  (table documents EntityId Document)
  (table paragraphs EntityId Paragraph))
```

`define-store` names one database schema and generates concrete operations.
The prototype starts with lookup, insert, replace, delete and scans. It does
not compile arbitrary Scheme predicates into SQL. A server may use a concrete
SQL database and a browser may use IndexedDB behind the same record operations;
this is one storage contract with platform bindings, not a provider/plugin API.
SQL indexes and richer typed queries are separate additions.

Illustrative generated operations use existing effect syntax:

```scheme
(effect NotesRead
  ((paragraphs-ref (-> EntityId (Option Paragraph)))
   (documents-ref (-> EntityId (Option Document)))))

(effect NotesWrite
  ((paragraphs-insert! (-> EntityId Paragraph Bool))
   (paragraphs-replace! (-> EntityId Paragraph Bool))
   (paragraphs-delete! (-> EntityId Bool))))
```

Insert returns false if the key exists; replace/delete return false if it is
missing. Other tables receive the same operations. Ordinary helper functions
can combine them. Scans have a documented stable key order or require explicit
sorting before order affects a result; storage iteration order is not an input
to application behavior. A durable document referring to a paragraph must
check existence and enforce deletion policy in the same write transaction.

Rows are a deliberately limited data subset: scalars, text, immutable vectors,
structs and enums composed of supported data. No procedures, mutable references,
opaque managed values or platform handles. Durable keys/rows additionally need
codecs. `Serialize`, `Send` and `Sync` each serve their existing purpose; none
alone is a certificate for this complete storage contract. This does not add
a general-purpose `Immutable` marker.

## Reads and writes have scopes, not exposed tokens

The examples use the existing `(Result A E)` from `(snail-core base)`, with `(Ok A)`
and `(Err E)`.
The following signatures are schematic generated API contracts:

```scheme
(: notes-read
   (All (A)
     (-> (-> A ! NotesRead)
         (Result A StoreError) ! store)))

(: notes-write
   (All (A E)
     (-> (-> (Result A E) ! NotesRead NotesWrite)
         (Result A (WriteError E)) ! store)))
```

`notes-read` binds one consistent snapshot for the whole computation, including
nested views. `notes-write` binds one transaction and reads its own staged writes.
Both execute their action once; the first version has no automatic retry or
nested transactions. A conflict is a result the caller may explicitly retry.
Writes require serializable isolation, not merely snapshot isolation: checks
across several rows must not admit write skew. The backend must either serialize
writes or detect conflicts that would violate this contract.
Pure helper calls are permitted. Networking, rendering, timers and task dispatch
are absent from the action's closed effect row. Storage operations themselves
may suspend; an unrelated application wait cannot keep a transaction open.

Returned values must satisfy the structural data restriction too. No cursor,
transaction token, borrowed row or effectful closure escapes. Static checking
must also reject mutable hidden captures/globals, using the same kind of
reachability checks as ordinary handler installations. The arrows above do
not, by themselves, establish those restrictions. `define-view` and named
action declarations are possible checking boundaries; this is a compiler gap
to settle before implementing the API.

There are no top-level defaults for `NotesRead` or `NotesWrite`. Their handlers
exist only in the appropriate scope. A test can intercept the underlying
`store` effect; runtime implementations own the actual synchronized storage.
A reusable, shareable handler is not itself a lock or an isolation guarantee.

The simple operation results above require a runtime-owned recoverable abort
boundary: an engine failure aborts the enclosing action and becomes its
`StoreError`, rather than being reported as a missing row or false result.
Ordinary value-returning effect handlers do not establish this boundary.
Implementing it is explicit runtime/compiler work; an alternative is to expose
typed storage errors on every operation. User-defined control handlers are not
required, but pure library expansion of the runner is not yet established.

An edit action might be:

```scheme
(: replace-text
   (-> EntityId String (Result Unit EditError)
       ! NotesRead NotesWrite))
(define (replace-text id text)
  (match (paragraphs-ref id)
    ((None) (Err (MissingParagraph id)))
    ((Some paragraph)
     (begin
       (paragraphs-replace! id (Paragraph-text-set paragraph text))
       (Ok (unit))))))

;; Called from an ordinary event handler with the store effect available.
(notes-write (lambda () (replace-text paragraph-id edited-text)))
```

The read and replacement share a serializable transaction. This action overwrites
the text; it cannot detect that a client prepared it from an older UI snapshot.
To reject stale-editor writes, pass an expected row version/value and compare
it inside the action. Transaction isolation alone does not supply that policy. Domain
errors roll back; storage errors remain distinct. A trap also aborts unpublished
work. Once commit succeeds, later cancellation cannot undo it. A lost response
may leave the caller uncertain whether the operation committed; no exactly-once
delivery guarantee is implied. Send a response or present UI only after the
write result, outside the transaction.

## Views are ordinary typed computations

Assume `Layout` is ordinary immutable data and `typeset` is a pure function:

```scheme
(: paragraph-layout
   (-> EntityId F32 (Option Layout) ! NotesRead))
(define-view (paragraph-layout id width)
  (match (paragraphs-ref id)
    ((None) (None))
    ((Some paragraph)
     (Some (typeset paragraph width)))))

(: document-layout
   (-> EntityId F32 (Option (Vector (Option Layout))) ! NotesRead))
(define-view (document-layout id width)
  (match (documents-ref id)
    ((None) (None))
    ((Some document)
     (Some (vector-map (lambda (paragraph-id)
                         (paragraph-layout paragraph-id width))
                       (Document-paragraphs document))))))
```

These are cacheable read functions, not mutable derived tables. Calling a view
with caching disabled must produce the same result. Arguments such as viewport
width, locale or a font asset's identity are explicit. There is no hidden clock,
random generator, mutable capture or renderer dependency. Changing database
rows requires a write action. Changing parameters selects a different view
result. Changing code discards the cache.

One frame/response obtains all related values through one read scope:

```scheme
(match (notes-read (lambda () (document-layout document-id viewport-width)))
  ((Ok layout) (present layout))
  ((Err error) (show-storage-error error)))
```

Presentation happens after the read scope ends. No database transaction spans
the wait for the next frame or request. Nested views share the snapshot; they
do not begin independent reads. The result is internally consistent, not a
promise that no newer commit exists by the time presentation finishes.

## Cache correctness before fine-grained invalidation

The first cache key includes the database identity/incarnation, its revision,
the code generation, the view identity and argument values. Initially use an
exact structural encoding with bit-preserving floating-point arguments, including
signed zero; numeric equality alone can merge observably different inputs.
Hashes require collision checks against that encoding.
Read the revision inside the same snapshot that supplies the rows. A view that
started under revision 8 may finish after revision 9 commits; its result remains
an answer for revision 8 and cannot populate revision 9's cache.

Every managed write advances the revision in the same database transaction.
Multiple server processes therefore agree on it. Replacing/restoring a database
also changes its incarnation or invalidates every associated cache. If arbitrary
external writers bypass this protocol, disable reuse across read scopes until
the backend supplies reliable change detection. A local counter is insufficient.

Initially any committed write makes all earlier cached results ineligible for
new snapshots. Keep caching bounded and evict freely; old read scopes retain
their own consistent result. Inside a write transaction, bypass shared view
caches because a committed revision does not identify its staged writes.

This coarse policy can be expensive. Later table-version tracking can avoid
invalidating unrelated views, including dependencies inherited from nested
views and missing-row lookups. Row-level dependencies, incremental query
maintenance and subscriptions are not prerequisites for the first contract.

## Startup, reload and schema changes

The runtime opens the configured store and binds `store` around the ordinary
entry point. A new application may perform a transaction that inserts missing
initial records. There is no special `init` or `resume` method, and no second
authoritative in-memory world to reconstruct. Sockets and windows are created
by the entry point in the normal way. Views are computed when requested.

On code replacement, finish or abort the old instance's transactions according
to their commit boundary, close its resources, discard its view cache and start
the new code against the same durable tables. No Wasm object or continuation
crosses. If startup fails, retain the database and report the failure; automatic
old-code rollback is not promised, and reverting code cannot undo committed
writes. Database files and journals stay outside compiler watch inputs and
build directories. Independent browser applications have distinct store names.

Changing a view implementation or result type needs only cache invalidation.
Changing a durable row schema requires an explicit migration. Existing wire
TypeIds detect mismatches; they do not migrate data. Keep stable table identity
and schema versions separate from compiler type hashes. Refuse incompatible
data without clearing it. Automatic migration inference is outside this design.
Initially migrations are offline/exclusive: stop every store user and exclude
concurrent access before changing the schema. Old instances must not continue
using an incompatible schema. Online migration and fencing live instances are
separate work; checking only when an instance first opens is insufficient.

A successful write means the backend completed its configured transaction
commit, preserving records across code/process replacement under that platform's
storage contract. It is not an identical power-loss or retention promise on
every host; browser storage eviction remains a platform policy. Do not report
success merely because a write request was accepted or a RAM cache changed.

## Performance and implementation boundaries

Reads may use memory and indexes; durability does not imply a physical disk
read for every lookup. Durable writes still cost work. A game's live positions
can be derived only if durable inputs, a journal or checkpoints reconstruct
them. Otherwise they are authoritative data that must be stored. View caches
cannot preserve facts absent from those inputs.

Batch work and return ordinary typed values for inner loops. Do not promise
ECS array-loop performance from one host call or SQL query per entity. An actual
SQL database plus generated typed record access is enough for the first server
proof; this project does not need its own database engine. Browser transaction
lifetime, cancellation and commit failures must be proved against its actual
storage API, not inferred from the server implementation.

| Existing foundation | Work still required |
| --- | --- |
| Structs/enums, generic functions, concrete effect operations | Schema/library forms and generated typed operations |
| Serialize/Deserialize and schema-sensitive TypeIds | Stable database schema identity and explicit migration boundary |
| Closed effect rows and handler capture checks | A precise structural data/capture check for cached views and actions |
| JSPI task suspension and cleanup | Recoverable storage-abort boundary, serializable writes, consistent snapshots and commit/cancel ownership |
| Compiler generation identity | Bounded view caching tied to database identity and snapshot revision |

No associated types, borrow checker, user-defined control handlers or new
application typeclass is required by the surface model. Whether its proposed
forms can expand entirely to existing checks is still to be proved. Transactions
and cache coherence remain runtime work; a type annotation cannot supply them.

## Review and verification

Before adopting this API, prove: a typed key/row mismatch is rejected; a view
cannot write or depend on mutable hidden state; a write cannot perform network
I/O; an engine failure reaches the runner as an error; an aborted write exposes
no changes; writes reject write skew; migration excludes old instances; two views
share one snapshot; a late
old view cannot contaminate a newer revision; another process's write invalidates
reuse; database replacement cannot collide with an old cache; and code reload
preserves committed data while permitting view result types to change.

Measure whole-frame/request cost, transactions at realistic write rates,
cache misses after writes and first-view latency after reload. These determine
whether coarse invalidation is sufficient. These measurements and checks are acceptance criteria for adopting the API,
not claims about the current runtime.

Related prior art: [SpacetimeDB tables](https://spacetimedb.com/docs/tables/) and
[transactional reducers](https://spacetimedb.com/docs/functions/reducers/) combine
typed records and transactions; [Flecs queries](https://www.flecs.dev/flecs/Queries.html)
illustrate component-oriented access. The prototype borrows those organizing
ideas without adopting their entire runtimes or claiming their performance.
