# Proposed artifacts and staged linking

**Design proposal; not implemented.** This develops the artifact and lifetime
model for [projects without a manifest](source-projects.md). The recommendation
is one workspace content store, immutable artifact manifests, and deferred
resource references in compiled code. Building another application becomes one
way to obtain a linked resource tree. Programs do not start a compiler at runtime.

The main distinction is between **inputs needed to produce an artifact** and
**resources retained by that artifact**. Sharing their physical storage does not
make them share a deployment or lifetime. Source programs should describe the
resource they need; the builder handles ordering, storage and export.

## What changes from the implementation

Today [`link-file`](types.md#linked-files) records a use during expression
expansion. At the end of library expansion, `bind-links` reads and hashes its
file and binds a foreign import named by that digest. The builder later copies
the file into the output store; runtime reads remain lazy. This is earlier than
whole-program reachability, so moving copying alone cannot avoid building an
unused generated artifact.

The current [`artifact-bundle`](projects.md#artifact-bundles) goes further:
expansion receives a completed file inventory and embeds its bytes. Development
builds already share a content store, and embedding a development bundle copies
its required objects into a portable snapshot. The proposal retains the useful
store and snapshot properties while moving ordinary resource binding later.

The existing specialization pass also sets a practical limit: whole programs
retain functions reached from statements, explicit exposures and initializers;
initializers are roots even if nobody uses their values. Separately compiled
libraries retain their monomorphic definitions. The first implementation should
use those rules, not promise a new whole-program optimizer for development mode.

## A small source-level model

Keep `link-file` for existing files and introduce an artifact request that
produces a resource-tree reference. Ordinary resource operations enumerate a
tree, select a file and read bytes. Static directories can use the same tree
representation when needed; they do not require a separate build language.

The artifact macro and CLI accept the same inert application/configuration
datum. For illustration only:

```scheme
((apps frontend application Frontend)
 (browser ((title "Frontend"))))
```

Parse configuration into a closed record with defaults made explicit. A title,
page options and source-relative stylesheet references are plausible browser
fields; exact field names and syntax remain for review. Resolve path anchors
before comparing requests, so the same relative spelling at two source sites
does not accidentally identify different files as one input. The CLI needs an
equally explicit workspace-relative interpretation.

An artifact request returns a tree handle with a known type. It does not return
a mutable build directory, run the requested application's entry point, or
immediately embed every file's bytes. Runtime reads use the resource interface;
they can fetch stored bytes but cannot cause compilation. This changes the
current pure byte-inventory API of `ArtifactBundle`, and its consumers must be
migrated explicitly.

## Requests, content and locations are different identities

| Identity | Purpose | What belongs in it |
| --- | --- | --- |
| Build request | Share work during one attempt and detect recursive requests. | Qualified application binding, source-resolution context, normalized output configuration, build mode and toolchain context. |
| Content reference | Identify immutable bytes or a completed artifact. | A digest of the bytes, or of a canonical artifact manifest. |
| Materialized location | Locate those objects in a particular deployment. | Local directory, store URL and chosen HTTP mount. |

A request is known before its result exists. Its key is not the result's content
digest. Keep distinct qualified aliases as distinct request identities initially;
do not merge applications merely because their types have the same runtime
representation. Repeated requests for the same binding and configuration share
work, while identical output bytes deduplicate even across different requests.

Mounting a frontend at `/ui/` instead of `/` or exporting a directory instead of
a tar file should not change its compilation request. Relocatable output makes
those publication choices. Configuration deliberately compiled into a program
does belong in the request and its input evidence.

## One physical store, explicit artifact references

Use one content store per workspace to start, extending the existing development
store. It contains immutable byte blobs and canonical artifact manifests. A
manifest describes:

- Named files: normalized relative paths and their content references.
- Resource bindings: module-local resource slots mapped to a file blob or
  another artifact manifest.
- The entry and host information required to load that artifact.

This is a generated description of an output, not a replacement source manifest.
Sort entries, reject conflicting paths, and version the representation. Do not
put timestamps, scratch paths or deployment addresses into content identity.
Record dependencies as typed references, rather than searching arbitrary file
bytes for strings that happen to resemble hashes.

An artifact's retained closure consists of its manifest, named files and the
transitive resources referenced by its bindings. A child application is a tree
reference, not a private copy of every file in that child. Two parents can
reference the same completed child, and unrelated outputs can share blobs.

Keep store locations outside the canonical content record. A loader option or
small deployment descriptor supplies the selected root and store base. Generated
pages refer to a stable local descriptor name, not to their own artifact digest;
otherwise hashing the page and its containing manifest would create a self-reference.

## The concrete output and how a host loads it

A completed application build returns the content reference of its artifact
manifest. It does not return only an executable filename. The requested output
configuration determines the payload described by that manifest:

| Output | Payload |
| --- | --- |
| Release program | A linked `program.wasm` and its retained resources. The current compiler does not emit a machine-native executable. |
| Browser | An HTML entry page, JavaScript host support, Wasm and retained resources. |
| Development program or browser | Per-library Wasm modules, their loading information, the appropriate host entry and retained resources. |

For illustration, a server artifact could contain the following manifest.
The encoding, hash placeholders and slot names are explanatory, not an ABI:

```json
{
  "version": 1,
  "entry": {"kind": "program", "file": "program.wasm"},
  "files": {"program.wasm": "sha256:SERVER_CODE"},
  "resources": {
    "main": {
      "r0": {"file": "sha256:LOGO"},
      "r1": {"artifact": "sha256:FRONTEND"}
    }
  }
}
```

Hashing this manifest gives the server artifact's identity. `SERVER_CODE` names
Wasm bytes, `LOGO` names image bytes, and `FRONTEND` names another manifest with
its own files and bindings. Each object is read from `store/sha256/DIGEST`, or
through the equivalent store resolver. Hashes identify content; the manifest's
typed references supply its meaning and relationships.

The host starts with a root manifest reference and a store location. It reads
the entry module and supplies its symbolic resource imports from that manifest's
bindings. A file resource can then fetch its blob. A tree resource first resolves
a logical path through the child's named-file table and then reads the selected
blob. Programs use resource handles; they do not construct store paths or parse
hashes themselves. The compiler emits the symbolic references, the builder writes
the bindings, and the loader performs the runtime resolution.

The server's reference to a browser artifact does not link the frontend's Wasm
functions into the server. It retains that independent application's files for
serving. Ordinary library imports and Wasm module linking still establish code
dependencies within an application; artifact references establish relationships
between independently built outputs. A raw Wasm file alone does not reconstruct
the latter bindings.

An exported directory materializes the named files and a local store/descriptor
for this graph. A tar archive packages the same graph. These are views of a
completed artifact, not different meanings of the artifact reference.

## Two dependency relations

The builder records which inputs produced an output for invalidation and ordering.
The output manifest records what that output retains for later execution or
serving. These relations can overlap, but neither implies the other.

For example, a generator can read a large schema artifact and emit a small lookup
table. The schema and generator executable are build inputs; they do not ship
unless the generated program also links them. Conversely, a server holding a
frontend tree retains the frontend's resources even though it never executes
the frontend itself.

Define the operations independently:

```text
build(request)         -> completed artifact reference
retained(root)         -> root and its transitive content references
export(roots, format)  -> materialize the union of retained(roots)
```

Export follows output references, never the complete history of how an output
was built. Provenance and cached compiler evidence can have their own retention
roots without becoming files in the deployed program.

## Defer references through compilation

During macro expansion, parse a resource request into a located symbolic
reference with a fixed resource type. Keep it on the expression in the compiler's
representation. Do not turn every encountered reference into an eager global
initializer or an unconditional build dependency.

Assign that reference a predetermined logical output path without consulting
its future contents. For example, an application reference can name
`deps/REQUEST_KEY/`, and a linked file can have a stable, source-qualified resource
path. These names are illustrative. They can become real relative paths in a
materialized output, or be resolved through its resource manifest. Neither the
target file nor the directory needs to exist for the compiler to emit a use of
that path. A request key can be computed in advance; the content hash of its
future output cannot.

Malformed request syntax is still a source error. Reading a linked file, loading
the requested application's library, and proving its `Application` instance can
wait until the reference survives compilation. A CLI root is always forced.
This deliberately allows an unused request to avoid both a child build and a
missing-child diagnostic; it does not suppress ordinary source type errors in
the requesting program.

After specialization and whatever elimination the compiler actually performs,
collect resource slots from retained code and required initializers. Dead
functions can then lose their artifact requests. An unknown runtime branch,
exported callback or retained initializer conservatively keeps its references.
There is no claim to determine whether an arbitrary function will ever execute.

Complete code generation against these paths: `link-file` and application
artifact requests do not require the linked bytes to emit the requesting Wasm
module. Keep the path-to-request association as output metadata. Only a dependency
whose contents are actually needed to produce code, such as generated source or
included bytes, can interrupt compilation.

Prefer leaving stable symbolic resource imports in the compiled module and
binding them to content references in the completed artifact manifest. Scope a
slot by its owning module, so reused module bytes cannot accidentally read
another module's resource. Existing browser and native loaders must learn this
binding table; the current digest-named imports resolve content too early.

This permits a file-only change to replace a resource binding and artifact
identity without repeating type checking and code generation when no compile-time
read depends on it. If a file is included into syntax or read by a producer, its
bytes are compiler inputs and must invalidate the affected compilation normally.
Both paths need correct watcher evidence and a changed publication identity.
Compiled-module reuse can remain keyed by code bytes; module-instance reuse must
also account for resource bindings. A new binding can require a fresh instance
even when its Wasm bytes are unchanged. Existing resource handles keep their old
immutable content references and read contexts across a reload; a reused symbolic
slot must not silently redirect those handles to the newest content.

A smaller migration could patch the existing digest-named imports after forcing
resources. It would still permit pruning before child builds, but asset-only
changes would keep changing module bytes. Manifest bindings are the preferred
design because they separate code reuse from resource updates; their cost is
an explicit loader ABI change that must work on both native and browser hosts.

## One build loop, including generated libraries

Use the existing request/driver boundary and staged planner, extended to return
finished code with unresolved resource paths. The compiler describes missing
compile-time inputs; the builder owns IO and execution. Use a queue of work and
a map of compiled outputs, processed by one worker initially:

```text
pending  : Queue<Job>
compiled : Map<RequestKey, CompiledOutput>
```

A `CompiledOutput` holds emitted code objects, output layout information and
retained logical-path-to-resource-request associations. Insert it into `compiled`
as soon as code generation finishes, even if none of its resource dependencies
has been produced. It is completed compiler output, not yet a deployable artifact.
Resource completion later adds the finalized bindings and artifact reference;
it does not require compiling the parent again.

Keep this map distinct from the content store, which maps content digests to
bytes. The emitted Wasm can already be interned there because its bytes contain
stable resource names rather than the unknown digests of future dependencies.
The compiled map provides sharing within an attempt; persistent reuse additionally
requires validated compiler input evidence.

1. Enqueue the root application request. Take a compile job and skip duplicate
   compilation if its `CompiledOutput` is already in the map.
2. Compile it to emitted code against predetermined resource paths. Record the
   finished output immediately, then enqueue retained resource requests that have
   not yet been processed. Ordinary resource dependencies do not suspend this job.
3. If compilation instead needs generated syntax, suspend only that compilation
   and schedule the producer stages. Compile the producer's code without waiting
   for its resource contents, complete its required resources, execute it, and
   supply its result to the waiting compilation. Preserve the existing checked
   session where the compiler's missing-input protocol requires a retry.
4. Process queued applications and static file snapshots the same way. Track
   compile-time prerequisite edges separately from ordinary resource-completion
   edges. Deduplicate queued work or skip it when its result is already recorded.
5. Once an output's resource results exist, bind its logical paths, finish its
   named files and intern its artifact manifest. This completion phase can run
   after the ordinary compilation queue drains, or earlier when a generator
   needs an executable artifact. Generated-result promotion uses the same store.
6. Publish or export the requested root only after its artifact and retained
   closure are complete. A failed child leaves its parent's compiled code reusable
   but cannot replace the previously accepted deployment.

Thus the ordinary order can be `compile server`, `compile frontend`, `complete
frontend`, `complete server`. The server's Wasm exists before the frontend does.
Only the completed manifest needs the child's content reference. A materialized
directory can similarly reserve the frontend's relative path first and fill it
later; neither representation requires the child to precede parent code generation.

Queue order can start from FIFO order. Waiting jobs must yield only for results
their current phase actually needs: generated syntax before parent compilation,
resources before generator execution, and child artifact identities before
content-addressed manifest completion. Retain edges for cycle checks, including
edges discovered on later visits. No runtime scheduling API is introduced.

Force resources before running an executable phase, rather than starting builds
on arbitrary runtime reads. A producer branch that is retained but never taken
may therefore build an unnecessary dependency. That is a bounded, understandable
tradeoff that avoids making every generator's resource reader a build scheduler.

`include-bytes` and generated syntax remain early inputs. If expansion needs a
producer to know what source exists, it must run that producer even if later
reachability discards the generated code. This is an inherent staging dependency,
not something final-program dead-code elimination can remove.

## Generated outputs must cross stages explicitly

A producer that reads an artifact and emits plain syntax creates no deployment
reference to that artifact. A producer that wants generated code to retain a
file or tree must carry a durable resource reference in its result, alongside
the syntax. The builder must intern generated bytes and preserve that reference
before deleting scratch; a process-local handle or scratch pathname is not a
valid result for a later stage.

This needs an extension to the generated-library result protocol, which currently
carries syntax bytes. The user-facing construction syntax remains open. Its
essential contract is to return immutable resources explicitly, rather than
automatically retaining everything a producer happened to read or write.
References introduced into generated code remain eligible for normal pruning.

Keep existing recipe-relative resolution for source files. Do not make a
`link-file` in generated syntax silently refer to the producer's temporary
working directory. A returned file that merely exists at the end of execution
must either be promoted into the result or remain disposable scratch.

## Cycles, sharing and incomplete work

Maintain pending, waiting, active, completed and failed states for each request
within one attempt. A second use of a completed request reuses it. Record an
edge before deduplicating its queued work and reject an edge that closes a
dependency cycle. A request already in the queue or currently being processed
is not by itself a cycle: two parents can need the same child. A diamond builds
its shared child once.

Track producer phases as well as application requests. For example, building A
can require a producer that links B, whose source needs the original producer.
Report that whole chain with source locations. Do not include an ever-increasing
stage number in request keys and thereby disguise a recursive dependency as
fresh work. Preserve the compiler's existing generated-library import-cycle
checks as well.

Only forced requests form artifact build edges. A self-reference pruned from
unused code need not be a build cycle. Generated syntax can reveal new edges,
so validate each extension before executing dependent work. Future parallel
execution must distinguish waiting on shared work from an actual dependency
cycle; a global "currently building" bit alone would not do that.

The manifest model still rejects cycles of retained artifact references: a
content-addressed parent manifest needs its children's completed identities.
That is a completion constraint, not a reason that the compiler cannot emit code
containing the corresponding predetermined paths. Generated-source cycles can
instead prevent compilation itself from finishing.

## Cache bytes without claiming every computation is cacheable

Content deduplication, sharing work within an attempt, and skipping work across
attempts are three separate properties. Implement the first two immediately.

A persistent result cache additionally needs complete evidence for source,
configuration, toolchain and producer inputs. A source edit can invalidate an
action while reproducing identical output bytes; retain the existing blobs in
that case. Equal request arguments alone never justify reusing an old result.

Generators currently have filesystem effects whose arbitrary reads are not all
tracked. Continue running such producers each attempt. Their identical output
can still deduplicate and allow downstream compiler reuse. Do not promise
persistent producer caching, reproducibility or complete file watching until
that input contract exists. Capture source-file snapshots for resolved links;
source changes during an attempt follow the service's existing reject/retry
rules rather than claiming an atomic snapshot of the entire checkout.

The separation has useful precedents: the
[Nix manual](https://nix.dev/manual/nix/2.34/glossary.html) distinguishes build
and runtime closures, and
[Bazel's cache documentation](https://bazel.build/remote/caching) distinguishes
action results from stored content. This proposal adopts those distinctions,
not either system's user-facing target language.

## Lifetimes are roots, not separate stores

| Owner | What it retains | When it can release ownership |
| --- | --- | --- |
| Build attempt | Active requests, captured inputs and unpublished results. | After publication transfers the result roots, or the attempt is discarded. |
| Generator invocation | Its executable closure, staged inputs and private scratch. | After its result has been captured and any returned resources promoted. |
| Waiting compilation | Generated syntax, returned resource references and compiler input evidence. | After compilation finishes or the attempt is abandoned. |
| Compiler/result cache | Only the immutable objects referenced by retained cache entries. | When those entries are evicted. |
| Published generation | The selected artifact's retained closure. | When no publication, process or retained browser generation needs it. |
| Running host | Resource bindings and old content still held across reloads or dynamic loads. | When those references are no longer usable; initially keep them for the host lifetime. |
| Independent export | Its selected roots and their retained closures. | According to the owner of that exported deployment. |

Deleting generator scratch must never delete a shared object that another
artifact retains. Removing an attempt's ownership similarly does not undo a
successful publication. Failed attempts can leave unreferenced immutable blobs;
that is recoverable garbage, not an accepted output.

Start with the existing conservative store retention and private-scratch cleanup.
Do not add online garbage collection in the first implementation. A later
collector must trace published roots, live attempts, runtime leases and retained
cache entries, coordinating with writers. Keeping only the newest manifest is
insufficient when an old page, process or saved resource handle still uses an
earlier resource. Explicit cleanup without active users is a simpler first step.

## Browser output and independent deployment

A browser output configuration should generate a predictable artifact: an
`index.html`, JavaScript entry and host support, a release `program.wasm`, and
its resource bindings. CSS can be inlined into the generated page or exposed
as a named file. Development may keep per-library modules and a module manifest
behind the same page/loader contract. Requiring exactly one Wasm file in every
mode would discard the current incremental-reload design.

Generate the page and select the necessary existing host adapter from the output
configuration. The canvas and document applications must both fit; title,
stylesheet inputs and host initialization belong in that reviewed configuration.
Avoid requiring an arbitrary `public/` tree just to get a runnable page. Explicit
extra public files, if needed, are named tree entries with collision checks.

Relative references make the artifact relocatable. A server obtains a frontend
tree handle and chooses the HTTP route in ordinary serving code. A filesystem
view can materialize that tree under a subdirectory, but its placement is not
the resource's identity.

For independent deployment, select the frontend root and export precisely its
retained closure. Materialize its named files and enough store content and loader
metadata to run without the workspace. A directory and a tar archive are two
transports for the same closure; neither requires recompilation. The export must
not retain symlinks or absolute paths back to the build checkout. Hard links or
reflinks can reduce copying when available, with ordinary copies as a fallback.

Multiple roots exported together can share the union of their store objects.
Separate self-contained exports necessarily each carry their required bytes;
physical deduplication cannot span independent machines without a shared external
service. Such a service is optional deployment policy, not a correctness requirement.

A selected file is a file resource, not automatically a runnable application.
Extracting `program.wasm` or a JavaScript file alone does not carry its loader,
binding table and other named files. Export the artifact root to preserve that
execution contract. Portability is relative to the declared host/ABI: a native
deployment still needs its compatible runner, supplied by the environment or
explicitly packaged, while a browser artifact includes its browser host support.

Sharing a store is also not sharing an HTTP namespace. Serving a frontend must
expose only its named files and permitted retained objects, never arbitrary
objects from the workspace store. Its closure excludes server-only files,
generator inputs and scratch. If the server intentionally retains the frontend,
the server deployment includes that child; exporting the frontend alone does
not pull in its parent. A frontend deployed elsewhere can instead be referenced
by a runtime URL, which creates no bundled artifact dependency.

## Case inventory

"Retained" below means referenced by the selected output, not merely read while
building it. These cases are acceptance criteria for the eventual implementation.

| Case | Required work and lifetime |
| --- | --- |
| A retained `link-file` names an existing asset. | Snapshot and intern the asset when binding the executable; retain its blob with that artifact. |
| A linked file or child artifact does not yet exist. | Emit the parent's code against its predetermined logical path and record that compiled output; fill the path/binding before execution or publication. |
| A file or artifact reference occurs only in eliminated code. | Do not read the file, resolve the child application, or produce its artifact. Request syntax still must be valid. |
| A reference is in an unused macro template. | Expansion creates no request at all. |
| A reference is in an initializer, export or potentially called callback. | Retain it conservatively under the compiler's actual reachability rules. |
| A development library exports an otherwise unused function. | It may retain more requests than the release whole program; do not claim identical pruning. |
| Two sites request the same application and normalized configuration. | Build once per attempt and reuse the completed reference. |
| Two parents share a child, or two outputs contain equal file bytes. | Share the child result where request identity agrees and deduplicate bytes by content regardless of parent. |
| The same application has different output configurations or modes. | Separate requests; any identical resulting blobs still share storage. |
| Equal relative path spellings originate in different libraries. | Resolve source anchors first; share only when the normalized requests agree. |
| A generator reads a static asset. | Retain it for the producer invocation; it does not ship just because it was read. |
| A generator links another application's artifact. | Compile and bind the producer's retained dependencies first, run it, then continue the waiting compilation. |
| A generator reads a large artifact and emits a small literal. | Retain the resulting program bytes, not the original artifact, unless another runtime reference keeps it. |
| A generator returns a file/tree for generated code to use. | Promote it into immutable store content and carry a typed reference across the stage boundary before scratch cleanup. |
| A generator writes an unreturned temporary file. | Remove it with private scratch; do not infer it is a deployment output. |
| `include-bytes` or generated syntax needs a build-time input. | Force the needed stage early; later pruning cannot undo the work required to obtain source. |
| A server retains a browser frontend. | Retain the frontend's manifest and closure; choose its HTTP mount separately. |
| Only the frontend is exported. | Export its closure without the server, compiler, producer executables or unrelated store objects. |
| Several applications are exported as one deployment. | Export the union of their closures and deduplicate shared objects. |
| An application reads a dynamic path from a retained tree. | Retain the whole selected tree, not only files observed in one execution. A selected subresource can narrow retention where its remaining references are known. |
| A child is requested only to select one generated file. | The child build may still be necessary in full; selecting a file does not by itself make the producer partially executable. |
| A resource changes but program source does not. | Update the binding and artifact identity; rebuild code only when compile-time evidence depends on the changed bytes. |
| A module's bytes are unchanged but its resource bindings change. | Reuse compiled code, but refresh the affected instance/binding context; old handles retain old content. |
| A source changes while an attempt is building. | Preserve captured bytes and reject/retry a superseded publication under the existing observation rules. |
| An arbitrary generator read changes between attempts. | Run the producer again; content storage alone does not justify skipping it or guarantee an automatic watcher trigger. |
| A forced request depends on itself, indirectly or through a producer. | Fail with the mixed-stage dependency chain; publish no replacement root. |
| A cycle exists only in a pruned reference. | It creates no forced artifact edge and requires no child build. |
| A dependency fails after another child has completed. | Preserve the previous published root; completed child blobs may remain reusable or collectible. |
| A resource dependency fails after its parent compiled. | Keep the valid compiler result for reuse; withhold completion and publication of the parent's artifact. |
| A page or process survives a rebuild and keeps an old resource handle. | Preserve the old content and binding context until its owner releases them. |
| The workspace is deleted after an independent export. | The exported directory/archive remains complete and usable. |
| A frontend is hosted externally and addressed by a runtime URL. | The URL does not implicitly request or bundle that application's build. |
| A producer builds a browser or other deployment artifact. | Execute only the producer on the build host; cross-target compilation does not run the produced application. |
| Only a Wasm or JavaScript file is selected from an artifact. | Treat it as data; use the whole artifact root when the loader and resource closure are needed for execution. |
| Several explicit root publications are requested. | Complete their needed artifacts first; do not promise an atomic transaction across multiple publication paths. |
| The compiler, resource ABI or host contract changes. | Invalidate incompatible compiled-unit caches and reject incompatible manifests; cover the bootstrap transition explicitly. |

## Delivery and decisions still needing review

First introduce symbolic resource references and the compiled-unit boundary for
ordinary linked files. Prove that unused function references can disappear and
that static file bindings work on both native and browser hosts. This establishes
the mechanism before adding recursive application builds.

Next add artifact tree references, normalized output configuration and request
memoization. Connect generated-library stages through the same resolver, extend
their result protocol for promoted resources, and test mixed-stage cycles.
Generate the standard browser layout and implement self-contained closure export.

Then migrate the project service and `artifact-bundle` consumers, update reload
binding and observation, and retire `project.datum` as described in the parent
proposal. Keep automatic store collection, remote caches, aggressive program-wide
pruning in development and arbitrary build plugins out of this first change.

The remaining design reviews are the exact datum and resource-tree API, browser
host options, generated-result encoding and the native/browser binding ABI.
The lifetimes, distinction between build inputs and retained resources, and
independent-export contract should be settled before those spellings. Repository
compiler, bootstrap, native and browser checks will be required for implementation;
this proposal itself changes documentation only.
