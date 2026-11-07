# Proposed artifacts and staged linking

**Design proposal; not implemented.** This develops the artifact and lifetime
contracts within the [query-driven compiler plan](incremental-compiler.md),
including [projects without a manifest](source-projects.md). The recommendation
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

The first implementation would discover application requests during expansion,
without waiting for dead-code elimination. Existing specialization still selects
code from statements, exposures and initializers, and separately compiled libraries
retain their monomorphic definitions. That code selection need not decide which
applications enter the build plan. Avoiding child builds from subsequently unused
code is a possible later optimization, not part of this initial contract.

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
| Target identity | Name a requested output before its contents exist and share work during one attempt. | Qualified application binding, source-resolution context, normalized output configuration, build mode and toolchain context. |
| Content reference | Identify immutable bytes, a target manifest or a completed binding catalog. | A digest of its canonical contents. |
| Materialized location | Locate those objects in a particular deployment. | Local directory, store URL and chosen HTTP mount. |

A request is known before its result exists. Its stable key, `TargetId`, is not
the result's content digest and does not recursively hash its dependencies. Keep
distinct qualified aliases as distinct request identities initially; do not merge
applications merely because their types have the same runtime
representation. Repeated requests for the same binding and configuration share
work, while identical output bytes deduplicate even across different requests.

Mounting a frontend at `/ui/` instead of `/` or exporting a directory instead of
a tar file should not change its compilation request. Relocatable output makes
those publication choices. Configuration deliberately compiled into a program
does belong in the request and its input evidence.

## One physical store, explicit artifact references

Use one content store per workspace to start, extending the existing development
store. It contains immutable byte blobs, target manifests and binding catalogs.
A target manifest describes:

- Named files: normalized relative paths and their content references.
- Resource bindings: module-local resource slots mapped to a file blob or a
  logical `TargetId`.
- The entry and host information required to load that artifact.

This is a generated description of an output, not a replacement source manifest.
Sort entries, reject conflicting paths, and version the representation. Do not
put timestamps, scratch paths or deployment addresses into content identity.
Record dependencies as typed references, rather than searching arbitrary file
bytes for strings that happen to resemble hashes.

A completed catalog maps each needed `TargetId` to its target-manifest digest.
Manifests do not contain the catalog's digest or recursively embed child-manifest
digests. This makes A referring to B and B referring to A ordinary finite data:
finish both manifests independently, then write the catalog. Its own canonical
bytes can be content addressed without solving recursive hash equations.

A completed artifact reference pairs a root `TargetId` with an immutable catalog
reference. Follow logical target references through that catalog, with a visited
set, to obtain its retained closure. A child is a reference, not a private copy of
its files. Two parents can share the same child, and unrelated outputs can share
blobs. An export includes only the catalog entries reachable from its selected
roots; it does not expose every target that happened to be compiled in the attempt.

Keep store locations outside the canonical content record. A loader option or
small deployment descriptor supplies the selected root and store base. Generated
pages refer to a stable local descriptor name, not to their own artifact digest;
otherwise hashing the page and its containing manifest would create a self-reference.

## The concrete output and how a host loads it

A completed application build returns a root target and its immutable binding
catalog. It does not return only an executable filename. The requested output
configuration determines the payload described by the target's manifest:

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
      "r1": {"target": "FRONTEND_ID"}
    }
  }
}
```

`SERVER_CODE` and `LOGO` name immutable bytes. `FRONTEND_ID` names a request whose
result the catalog supplies, for example:

```text
SERVER_ID   -> sha256:SERVER_MANIFEST
FRONTEND_ID -> sha256:FRONTEND_MANIFEST
```

Hashing this table identifies its bindings, including which frontend this server
retains. Updating the frontend can leave the server's code and target manifest
unchanged while changing the catalog. Runtime handles capture the catalog they
were loaded with; a mutable global mapping to the latest target would break old
generations and cache correctness.

The host starts with a root target, catalog reference and store location. It reads
the entry module and supplies its symbolic resource imports from the target's
manifest. A file resource fetches its blob. A tree resource resolves its target
through the same catalog, looks up a path in that manifest, and reads the selected
blob. Content is read from `store/sha256/DIGEST` or an equivalent resolver.
Programs use handles; the compiler, builder and loader manage these relationships.

The server's reference to a browser artifact does not link the frontend's Wasm
functions into the server. It retains that independent application's files for
serving. Ordinary library imports and Wasm module linking still establish code
dependencies within an application; artifact references establish relationships
between independently built outputs. A raw Wasm file alone does not reconstruct
the latter bindings.

An exported directory materializes the named files and a local store/descriptor
for this graph. Reserve one directory per target, such as `targets/TARGET_ID/`,
instead of recursively nesting copies of dependencies; cycles then remain finite.
A tar archive packages the same graph. Both are views of a completed artifact.

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
reference with a fixed resource type. Keep it on the expression and record it
under the requesting target. An application request also adds its target to the
expansion worklist, just as an import adds source work. Reserve its identity
before visiting its source, so repeated or cyclic requests reuse the same entry.
This does not add a runtime initializer or execute the requested application.

Assign that reference a predetermined logical output path without consulting
its future contents. For example, an application reference can name
`targets/TARGET_ID/`, and a linked file can have a stable, source-qualified resource
path. These names are illustrative. They can become real relative paths in a
materialized output, or be resolved through its resource manifest. Neither the
target file nor the directory needs to exist for the compiler to emit a use of
that path. A request key can be computed in advance; the content hash of its
future output cannot.

Load requested libraries during discovery and establish their `Application`
evidence during checking. For the initial implementation, every expanded request
is a dependency of its target, even if later code selection discards that use.
A missing child in an expanded function can therefore fail the build. A request
stored in an unused macro template creates no dependency until actually expanded.
Unrelated libraries are still not scanned. Static linked files can be captured
later because expansion needs their references, not their contents.

Preserve expression associations so a future optimizer can narrow resource
retention. Pruning after discovery cannot undo child expansion or generator
execution already required by this policy. Avoiding that work would require a
different, deferred discovery policy and should be reviewed separately.

Complete code generation against these paths: `link-file` and application
artifact requests do not require the linked bytes to emit the requesting Wasm
module. Keep the path-to-request association as output metadata. Only a dependency
whose contents are actually needed to produce code, such as generated source or
included bytes, can interrupt compilation.

Prefer leaving stable symbolic resource imports in the compiled module and
binding them to file digests or target identities in the target manifest. Scope a
slot by its owning module, so reused module bytes cannot accidentally read
another module's resource. Existing browser and native loaders must learn this
binding table; the current digest-named imports resolve content too early.

This permits a file-only change to replace a resource binding and artifact
identity without repeating type checking and code generation when no compile-time
read depends on it. If a file is included into syntax or read by a producer, its
bytes are compiler inputs and must invalidate the affected compilation normally.
Both paths need correct watcher evidence and a changed publication identity.
Compiled-module reuse can remain keyed by code bytes; module-instance reuse must
also account for resource bindings and the catalog that resolves them. A new
binding can require a fresh instance even when its Wasm bytes are unchanged.
Existing resource handles keep their old
immutable content references and read contexts across a reload; a reused symbolic
slot must not silently redirect those handles to the newest content.

A smaller migration could patch the existing digest-named imports after forcing
resources, but asset-only changes would keep changing module bytes. Manifest
bindings are the preferred design because they separate code reuse from resource
updates; their cost is an explicit loader ABI change on native and browser hosts.

## Prepare the plan before dispatching emission

Plan the work before dispatching target code generation. Imports and expanded
artifact requests grow one discovery worklist to a fixed point. A target already
registered is an edge to existing work, including when the edge closes an ordinary
artifact-reference cycle. No pass that repeatedly compiles each whole application
is needed to discover that graph.

The boundary is therefore:

```text
explicit application requests
  -> expand and resolve imports and application requests to a fixed point
  -> check shared libraries and specialize from all application roots
  -> dispatch independent emission jobs in parallel
  -> finish target manifests and bind them in a completed catalog
```

Expansion discovers targets; specialization still reaches a fixed point of code
instances, including instances needed by compiler lowering. Preserve both sets
of results rather than restarting earlier passes for each target. A shared IR
graph can contain multiple application roots without combining their entry points,
initialization or execution. Prepared units are partitioned into their output
modules before emission; workers receive immutable inputs.

`generate-library` joins the same worklist but introduces an evaluation boundary:
its result supplies source that discovery cannot otherwise see. Discover as far
as possible, prepare and emit the necessary producer closure, bind its resources,
then execute it on the build host. Supply its generated syntax to the suspended
expansion and continue discovery. Generated code may introduce further requests
or producers, so repeat until no compile-time inputs are missing.

Keep the same compatible syntax, checked libraries, specialization bodies and
emitted results across these stages. A producer compiled early need not be compiled
again merely because the final application plan is larger. Separate its executable
from the result of running it: requesting its code is different from needing the
syntax it will generate. The latter cannot be replaced with a future pathname.

Without generators this is one discovery fixed point followed by ordinary
compilation. With generators it is successive stages of the same compiler, not
one universal expansion pass followed by one universal emission pass. The current
`prepare`/`emit` boundary and missing-input protocol provide useful starting points.

## Share compiler work across application roots

Use the [incremental compiler workspace](incremental-compiler.md) to share
results across applications, generator stages and edits. Finishing a producer
does not discard its checked standard library or compatible specializations.
The workspace records each result's semantic dependencies, so the same mechanism
answers both whether another root can reuse it and whether an edit invalidates it.

For example, browser and server applications can share a checked pure library and
the same compatible specialization of a function from it. Different application
entry wrappers or host-specific imports remain distinct. Two browser outputs
whose only difference is their page title can share all code-generation work;
their generated page and artifact manifest differ. Do not put packaging-only
options into every library's compiler cache key.

An artifact selects code and resources from that workspace. Keep those selections
per application and per producer: sharing compiler results must not make each
application retain every other's code, resources or runtime state. Keep analysis
results independent of publication, so an unsuccessful build can still contribute
valid compiler work without replacing the accepted output.

Identical monomorphized IR does not necessarily mean a drop-in Wasm binary fragment:
module indices, imports, exports and assembly still belong to the receiving module.
Reuse semantic preparation first; share emitted whole modules when their emission
context matches. This avoids requiring a new cross-program binary linker merely
to stop repeating type checking or specialization.

## Execute the plan with a queue and result map

Use the existing request/driver boundary and staged planner, extended to return
finished code with unresolved resource paths. The compiler describes missing
compile-time inputs; the builder owns IO and execution. Use a queue of planned
work and a map of compiled outputs:

```text
pending  : Queue<Job>
compiled : Map<TargetId, CompiledOutput>
```

A `CompiledOutput` holds emitted code objects, output layout information and
retained logical-path-to-resource-request associations. Insert it into `compiled`
as soon as code generation finishes, even if none of its resource dependencies
has been produced. It is completed compiler output, not yet a deployable artifact.
Resource completion later adds file bindings, target manifests and a catalog;
it does not require compiling the parent again. The plan records targets before
compilation; this result map records outputs only after emission succeeds.

Keep this map distinct from the content store, which maps content digests to
bytes. The emitted Wasm can already be interned there because its bytes contain
stable resource names rather than the unknown digests of future dependencies.
The compiled map provides sharing within an attempt; persistent reuse additionally
requires validated compiler input evidence.

1. Prepare a plan from the root application request, obtaining checked, specialized
   units and any staged prerequisites. Enqueue ready emission jobs and skip work
   whose compatible compiler result is already available.
2. Emit code from the prepared units against predetermined resource paths. Record
   the finished output immediately. Resource jobs are already represented in the
   plan and can advance independently; ordinary resource dependencies do not
   suspend this emission job.
3. If preparation needs generated syntax, suspend only the affected preparation
   and dispatch the producer stages. Emit the producer's code without waiting
   for its resource contents, complete its required resources, execute it, and
   supply its result to the waiting compilation. Preserve the existing checked
   session where the compiler's missing-input protocol requires a retry.
4. Process queued applications and static file snapshots the same way. Track
   compile-time prerequisite edges separately from ordinary resource references.
   Deduplicate queued work or skip it when its result is already recorded.
5. Once an output's own files exist, intern its manifest with logical references
   to other targets. This does not wait for child manifests. When a selected
   closure's manifests all exist, freeze its binding catalog, either for final
   publication or earlier to run a producer. Generated-result promotion uses
   the same store.
6. Publish or export the requested root only after its catalog and retained
   closure are complete. A failed child leaves its parent's compiled code reusable
   but cannot replace the previously accepted deployment.

Thus `compile server` and `compile frontend` can happen in either order or
concurrently. Each target's own manifest can finish independently too. Only the
completed catalog requires both results. A materialized directory can reserve
their relative paths first and fill them later, including mutually referring
targets, without a topological order among ordinary artifact references.

Dispatch independent ready jobs to a bounded worker pool. A server and its browser
resource can emit code concurrently; the resource edge constrains readiness of
the server's deployment, not emission of its code. Independent library
preparation can also overlap once imported interfaces are available. A generated
source prerequisite constrains preparation and therefore emission of its consumer.

The planner owns pending identities and shared result publication. Reserve a job
once so two workers do not prepare or emit the same unit concurrently. Workers
consume immutable inputs and return completed values; they do not concurrently
mutate one symbol table or compiler session. Per-job scratch and atomic content
insertion keep independent jobs isolated. A serial executor can consume the same
plan for bootstrap, debugging and reproducibility checks.
Symbol identities and artifact contents must not depend on worker completion
order: reserve stable identities during preparation and combine results by their
canonical keys, leaving emission's temporary indices local to each module.

Queue order can start from FIFO order. Waiting jobs must yield only for results
their current phase actually needs: generated syntax before parent compilation
and a complete resource closure before generator execution or publication.
Retain prerequisite edges for cycle checks, including edges discovered on later
visits. Ordinary reference edges do not impose these code-generation prerequisites.
No runtime scheduling API is introduced.

Force resources before running an executable phase, rather than starting builds
on arbitrary runtime reads. An expanded producer branch that is never taken may
therefore build an unnecessary dependency. This conservative policy avoids making
every generator's resource reader a build scheduler; it can reject a staging
cycle even when a particular execution would not read the problematic resource.

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
References introduced into generated code follow the same expansion-driven
dependency policy as handwritten references. A promoted reference must retain
its immutable binding context, or be explicitly rebound to the same contents in
the consumer's catalog; passing a bare `TargetId` across attempts is insufficient.

Keep existing recipe-relative resolution for source files. Do not make a
`link-file` in generated syntax silently refer to the producer's temporary
working directory. A returned file that merely exists at the end of execution
must either be promoted into the result or remain disposable scratch.

## Cycles, sharing and incomplete work

Register each target before expanding its dependencies. Repeated requests and
ordinary reference cycles reuse that registration: A may link B while B links A,
and an application can refer to its own artifact. A diamond builds its shared
child once. Catalog construction and export walk a finite graph with a visited
set rather than recursively expanding directory copies or content hashes.

Reject cycles in the actual prerequisites for producing source or executing a
stage. For example: expanding A needs generator G's result; executing G needs B's
artifact; compiling B needs the same result from G. Neither G nor B can finish
first. Report this phase-specific chain with source locations. A resource cycle
among already compilable producer executables is not itself such a deadlock.

Keep producer executable readiness distinct from producer result readiness.
Preserve existing generated-library import-cycle checks; allowing artifact cycles
does not change the language's rules for source imports or recursive declarations.
Do not include an ever-increasing stage number in request keys and disguise a
dependency on the same pending computation as fresh work.

Finite repeated requests converge through memoization. A macro or generator that
keeps inventing different requests can still diverge, just like arbitrary macro
expansion or compile-time execution; stable identities do not prove termination.
Failures must preserve the previous published root even when other targets have
already produced reusable code or content.

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
| Published generation | Its root targets, immutable binding catalog and retained closure. | When no publication, process or retained browser generation needs it. |
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
objects from the workspace store. Its closure excludes unrelated server files,
generator inputs and scratch. A server retaining a frontend does not by itself
make the frontend retain the server. If the frontend explicitly links the server
artifact in return, both belong to its export closure; a visited set prevents
duplication, not retention. Communication through a runtime URL creates no bundled
artifact dependency and is appropriate when the deployments should be independent.

## Case inventory

"Retained" below means referenced by the selected output, not merely read while
building it. These cases are acceptance criteria for the eventual implementation.

| Case | Required work and lifetime |
| --- | --- |
| A retained `link-file` names an existing asset. | Snapshot and intern the asset when binding the executable; retain its blob with that artifact. |
| A linked file or child artifact does not yet exist. | Emit the parent's code against its predetermined logical path and record that compiled output; fill the path/binding before execution or publication. |
| An expanded file or artifact reference occurs only in subsequently eliminated code. | The initial policy still includes that dependency. Avoiding its build requires a later change to discovery, not merely a final DCE pass. |
| A reference is in an unused macro template. | Expansion creates no request at all. |
| A reference is in an initializer, export or potentially called callback. | Include it when expanded; no runtime execution prediction is needed. |
| A development library exports an otherwise unused function. | Its code roots can differ from release mode; the initial dependency discovery policy follows expansion in both modes. |
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
| Only the frontend is exported and it has no server-artifact reference. | Export its closure and catalog projection without the server, compiler, producer executables or unrelated store objects. |
| Several applications are exported as one deployment. | Export the union of their closures and deduplicate shared objects. |
| An application reads a dynamic path from a retained tree. | Retain the whole selected tree, not only files observed in one execution. A selected subresource can narrow retention where its remaining references are known. |
| A child is requested only to select one generated file. | The child build may still be necessary in full; selecting a file does not by itself make the producer partially executable. |
| A resource changes but program source does not. | Update the binding and artifact identity; rebuild code only when compile-time evidence depends on the changed bytes. |
| A module's bytes are unchanged but its resource bindings change. | Reuse compiled code, but refresh the affected instance/binding context; old handles retain old content. |
| A source changes while an attempt is building. | Preserve captured bytes and reject/retry a superseded publication under the existing observation rules. |
| An arbitrary generator read changes between attempts. | Run the producer again; content storage alone does not justify skipping it or guarantee an automatic watcher trigger. |
| Artifact references form a cycle or refer to the requesting artifact itself. | Register targets once, emit independently, bind through the completed catalog and export with a visited set. |
| Producing source or running a generator needs its own unfinished result. | Fail with the phase-specific prerequisite chain; publish no replacement root. |
| A dependency fails after another child has completed. | Preserve the previous published root; completed child blobs may remain reusable or collectible. |
| A resource dependency fails after its parent compiled. | Keep valid compiler results and local manifests; withhold a completed catalog and publication of the root. |
| A page or process survives a rebuild and keeps an old resource handle. | Preserve the old content and binding context until its owner releases them. |
| The workspace is deleted after an independent export. | The exported directory/archive remains complete and usable. |
| A frontend is hosted externally and addressed by a runtime URL. | The URL does not implicitly request or bundle that application's build. |
| A producer builds a browser or other deployment artifact. | Execute only the producer on the build host; cross-target compilation does not run the produced application. |
| Only a Wasm or JavaScript file is selected from an artifact. | Treat it as data; use the whole artifact root when the loader and resource closure are needed for execution. |
| Several explicit root publications are requested. | Complete their needed artifacts first; do not promise an atomic transaction across multiple publication paths. |
| The compiler, resource ABI or host contract changes. | Invalidate incompatible compiled-unit caches and reject incompatible manifests; cover the bootstrap transition explicitly. |
| Two application roots import the same library under the same semantic inputs. | Share expansion and checking; keep target-specific output layout separate. |
| Two roots request the same compatible specialization. | Share its constructed body, preserve per-root code and resource membership and repeat context-sensitive validity checks. |
| A generator emits a previously unknown application-artifact request. | Complete the producer stage, extend preparation, then dispatch the next prepared batch. |
| Parallel jobs need the same prepared or emitted unit. | Reserve the work once, publish an immutable result, and keep symbol identities and output bytes independent of completion order. |
| A child artifact changes while its parent's code and local manifest remain equal. | Publish a new catalog; existing handles retain the old catalog and child content. |
| A frontend and server retain each other's artifacts. | Exporting either root includes both; use runtime communication without an artifact reference for independent deployments. |
| Two independently compilable targets in a generator's resource closure refer to each other. | Complete their finite graph and the producer's catalog, then run it; reference cycles alone do not prevent execution. |

## Delivery and decisions still needing review

First establish the shared input, identity and dependency boundaries described in
the [incremental compiler delivery plan](incremental-compiler.md#delivery-and-checks).
Verify standard-library reuse between a producer and its consuming application,
then reuse across source edits. The compiler's existing passes and per-library
checks provide the starting points.

Introduce symbolic resource references and the compiled-unit boundary for ordinary
linked files. Verify that files bind after code generation on native and browser
hosts, and that asset-only edits change bindings without rechecking code.

Make preparation produce an explicit plan with shared library and specialization
evidence, and consume it with serial and bounded parallel executors. Verify that
multiple roots reuse compatible analysis without retaining each other's resources
and that both execution orders produce the same artifact identities.

Next add artifact tree references, normalized output configuration and request
memoization during expansion. Establish target manifests and immutable catalogs,
including self-references and mutually referring outputs. Connect generated-library
stages through the same resolver, extend their result protocol for promoted
resources, and distinguish allowed reference cycles from evaluation deadlocks.
Generate the standard browser layout and implement self-contained closure export.

Then migrate the project service and `artifact-bundle` consumers, update reload
binding and observation, and retire `project.datum` and its `project.sld` model
as described in the source-project proposal. Keep automatic store collection,
remote caches, avoiding expanded
requests through DCE and arbitrary build plugins out of this first change.

The remaining design reviews are the exact datum and resource-tree API, browser
host options, generated-result encoding and the native/browser binding ABI.
The lifetimes, distinction between build inputs and retained resources, and
independent-export contract should be settled before those spellings. Repository
compiler, bootstrap, native and browser checks will be required for implementation;
this proposal itself changes documentation only.
