# Proposed packages and independent compilation

**Review draft, not implemented.** This proposal was developed against
`origin/main` at `1516436c` on 2026-11-04. The current system is described in
[Projects and targets](projects.md) and [Compiler architecture](compilers.md).
The backend work in other branches is not assumed to have landed.

The recommendation is to make a library target an independently compiled
package, with its own source tree, import namespace and compiler state.
Dependencies arrive as immutable compiled artifacts. A consumer chooses the
names under which it imports them. A workspace collects projects for builds
and development; membership grants no import access.

Keep the project description declarative. Retain its current filename,
`project.datum`: `project.sld` currently names the implementation of its
parser. Renaming the description is independent of this design and provides
no architectural benefit. The examples below extend the existing data
format; the current parser will reject them.

Implement isolated compilation and linking serially first. Parallel workers,
a registry, version solving and remote artifact downloads are later work.
The package boundary should make those possible without another compiler
architecture.

## The contract to build around

A package compiler receives a closed job: its own source and resource
snapshots, a resolved import view, dependency artifact bytes, compiler
options and the target ABI. It returns diagnostics and an immutable
artifact, or a structured request for a missing generated input. It cannot
read another package's source tree, inspect another compiler's live state,
run a producer, resolve a version or mutate a dependency artifact.

The decisive acceptance test is to compile a dependency, terminate that
compiler, remove access to the dependency's source tree, and compile and run
a consumer using only the artifact. Include an exported macro, a generic
calling a private helper, an effect handler and a linked resource. Passing
an ordinary monomorphic function between two Wasm modules is insufficient.

Within a job, immutable values may be shared freely. Between jobs, the
contract is serialized data. A resident builder can cache decoded artifacts
as an optimization, but a fresh process must produce the same result.

Independent compilation still has dependency order: a consumer needs its
providers' completed interfaces. Jobs whose dependencies are ready can
eventually run concurrently, each with a single-threaded compiler if that
is the simplest host model. That is where the concurrency benefit comes
from; it requires neither parallel passes nor a shared compiler heap.

## Project layout and declarations

Use physically separate projects with flat source roots:

```text
project.datum
core/
  project.datum
  src/lib.sld
  src/base.sld
json/
  project.datum
  src/lib.sld
  src/read.sld
  src/write.sld
app/
  project.datum
  main.sld
```

The workspace description lists directories whose own descriptions it reads:

```scheme
((workspace
   (members ("core" "json" "app"))))
```

These are references, not textual includes. Each file keeps its own path
base, target names and dependency declarations. A workspace may also
declare ordinary build and run targets. A project can be built directly;
its dependency references contain enough information without the workspace.
Keep membership flat initially: reject recursive workspace membership and
duplicate canonical member paths. Dependency references may reach a project
outside the membership list; membership controls bulk commands and editor
discovery, while `links` controls compilation access.

The JSON project declares a library target and its direct dependencies:

```scheme
((build-target json
   (library
    (entry "src/lib.sld")
    (library-roots ("src"))
    (exports ((json)))
    (links ((project "../core" core))))))
```

The target name is the package's self name, here `json`. Its entry declares
`(json)`. The other files declare `(json read)` and `(json write)`.
Inside this package, the first name part `json` always means itself.
`core` is the default mount name of the linked target named `core`.

The application chooses a different name for the same JSON package:

```scheme
((build-target app
   (program
    (entry "main.sld")
    (links
     ((project "../core" core)
      (as data (project "../json" json))))))
 (run-target dev
   (run app)))
```

Its source can import the package under that alias:

```scheme
(import
 (core base)
 (data))
```

The JSON entry can re-export bindings from a private library:

```scheme
(define-library (json)
  (export encode)
  (import
   (only (json write) encode)))
```

`(data write)` is refused because `exports` exposes only `(json)`.
Adding `(json read)` to that list would expose `(data read)` to this
consumer. Package `exports` selects libraries; Scheme `export` selects
bindings. A re-export retains the original binding and type identity.

### Exact field rules

Keep the existing `(build-target NAME (KIND ...))`, `(run-target ...)`,
browser `public`, entry paths and argument ordering. Add the `library`
kind, `links`, library `exports`, and a workspace declaration. Each option
remains exactly `(key value)`; lists and paths remain literal data.
Require explicit `exports` on a library target; an empty list exposes no
importable libraries. Omitted `links` means no project dependencies in scoped
mode. Reject duplicate fields and unknown forms as the current parser does.

In the first scoped implementation, a library target has exactly one source
root and one explicit entry. The entry must lie inside that root. A program
or browser target may have zero or one root and keeps its explicit program
entry. Retaining the `library-roots` spelling minimizes format churn; reject
multiple roots in scoped mode instead of retaining precedence rules.

For a library target named `json` with root `src`:

| Requested library in its own view | Source |
| --- | --- |
| `(json)` | The explicit entry, `src/lib.sld`. |
| `(json read)` | `src/read.sld`. |
| `(json codecs utf8)` | `src/codecs/utf8.sld`. |

The entry is excluded from the suffix mapping: it does not also provide
`(json lib)`. Every source declaration must match the expected provider-local
name. There is no sibling-file guessing, prefix search, implicit parent
directory, or first-root-wins behavior. Nested sublibraries remain possible;
the dependency roots are flat names, not a requirement that every package
have only one source file.

A program/browser entry is a program, not a library declaration. An optional
root provides its private `(TARGET suffix ...)` libraries; it does not
invent a `(TARGET)` facade. Intra-package library import cycles remain
errors. Shared implementation belongs in a linked library target with its
own source tree, as opposed to several program targets searching one common
source directory.

`(project PATH TARGET)` selects a library target in `PATH/project.datum`.
`(as ALIAS REFERENCE)` supplies a consumer-local alias; otherwise the target
name is the alias. References to `"."` permit another target in the same
project. Reject duplicate aliases, a dependency alias equal to the self
name, missing targets, links to program/browser targets, duplicate public
libraries and public libraries not owned by the provider. A target sees
only itself and its direct links. An application's links do not augment
its dependencies' views. Cycles of library-target dependencies are errors.

The dependency path needs its own parsed type: `../core` is deliberately
allowed here. Do not relax the current prohibition on `..` in source,
resource, output or browser-public declarations. Resolve references against
the declaring project and normalize them once; two paths to the same
manifest and target select the same provider instance. Workspace membership
does not create a source search path.

Library targets can expose several public libraries, as the core needs to.
They are never executable run targets or browser artifact bundles. Building
a library checks its admitted source libraries and exports a package
artifact; it does not execute their initializers. A selected application
still executes only the reachable initialization closure in dependency
order. Explicit `run-target`s remain the way to run test programs.

### Source and resource ownership

The declared root admits `.sld` files below it. Inventory it deterministically,
validate names and detect collisions before compiling. Adding or removing a
file changes that inventory. Directory enumeration belongs to the builder,
not to import resolution in the compiler. Exclude build output by
construction: refuse a source root containing the project's output trees.

Keep non-source inputs explicit too. Add an optional
`(input-roots ("assets" "schemas"))` to a target. File contents embedded or
linked at compile time must come from these roots; declaring a source file
does not grant its whole parent directory. Existing source-relative
resource spellings can remain, but resolution must produce an owned
`SourceId` or `ResourceId` before bytes enter the compiler. Resolve symlinks
at this boundary and reject escapes from the declared root. An explicitly
selected root may itself resolve to another checkout; that does not grant
access to its siblings.

`include-bytes` and `link-file` consume immutable resource snapshots. A
macro's definition-site resource belongs to its provider; its expansion
carries that resource's identity and bytes/digest, not a consumer-relative
path. A dependency link exposes code APIs and the resources required by
them; it does not grant arbitrary reads of the provider's directories.
Browser `public` remains a separate packaging input with its current
publication rules.

A source inventory is a declaration of eligible inputs, not proof that
arbitrary generator filesystem access has been tracked. Producers must also
run against declared input snapshots or an IO service enforcing those roots.
Until that exists, an unrestricted producer must be marked uncacheable and
rerun; it cannot be advertised as a closed package build. Declared input
directories must be watched, including file creation and removal.

## Names, views and identities

R7RS does not define the mapping from library names to files;
[SRFI 138](https://srfi.schemers.org/srfi-138/srfi-138.html) supplies one
separately. Consumer-local dependency aliases have a direct precedent in
[Cargo's dependency declarations](https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#renaming-dependencies-in-cargotoml).
Here, contextual package resolution is a new Snail toolchain contract. It
preserves Scheme's import/export forms; it is not a claim that stock Chibi
already understands these manifests or contextual names.

Resolve a source import in two steps:

```text
(consumer PackageId, mount name) -> provider PackageId
(provider PackageId, library suffix) -> public LibraryId
```

Inside a provider, its self name also permits private suffixes. Once
resolved, aliases disappear from compiler identities. A macro-expanded
reference already carrying a binding identity does not go back through
the consumer's mount table. Introducing a fresh source import still checks
the view of the package responsible for that import.

Use structured identities throughout:

| Identity | Meaning |
| --- | --- |
| `PackageId` | Resolved source origin, target, dependency-instance bindings and semantic configuration. |
| `LibraryId` | Package identity plus a library's local suffix; the entry has an empty suffix. |
| `DefId` | Library identity plus a definition key. |
| `LocalId`, `ScopeId` | Identities local to one compilation, qualified or remapped when serialized. |
| `ArtifactKey` | Content identity of a compiled result, including source/input bytes, dependencies, compiler and ABI options. |

Do not make `PackageId` a hash of every source body. Editing an implementation
must change its artifact without automatically changing every nominal type.
Two aliases of one provider share definitions, globals and initialization.
Two resolved provider instances remain distinct even when both are called
`json`. A dependency alias must not appear in Wasm symbols, type identities,
wire schemas or macro definition identities.

Initially, canonical local manifest paths can identify source origins.
That intentionally limits cache reuse after checkout relocation. Keep origin
as a tagged value so a later lockfile can supply stable repository/package
coordinates and pinned content without changing `DefId`'s structure. Do not
claim reproducible cross-checkout cache hits until origin normalization is
implemented and tested. The same resolved origin must have one source
snapshot in a linked build; mixing two artifacts from different snapshots
under one `PackageId` is an error.

The job is self-contained even if its provider identities describe
transitive packages. Those identities and needed compiler metadata do not
give the consumer source-level permission to import a transitive package.
This distinction is essential for public APIs that mention dependency types
and for generic bodies that refer to private or transitive helpers.

## Where the existing compiler crosses the proposed boundary

The following observations are about the audited main-branch revision, not
pending changes in other sessions. They identify responsibilities to replace,
not algorithms that should be discarded wholesale.

| Current code | Coupling | Recommended replacement |
| --- | --- | --- |
| `project/build.sld`: `library-directories` | Appends the toolchain's entire `src` tree to target roots. | A resolved dependency view; the standard library is an explicit provider. |
| `compiler/expand.sld`: `find-library`, `load-library` | Searches paths and recursively expands dependency source into the active context. | An owned-source inventory plus decoded dependency interfaces. |
| `core.sld`: `Program` | Combines entity tables, all items and per-library item counts for a closure. | Package-local declarations and separate immutable imported interfaces. |
| `expand.sld`: `Expanded.delta`, `ExpandedProgram` | Replays contributions into a shared program and preserves counters, scopes and top-level tables across its history. | A complete package frontend result with local identities and explicit macro environments. |
| `check.sld`: `Typed`, `primitive-alias?` | Carries a whole `Program`; alias classification can scan its items. | Checked package IR and resolved call/primitive contracts. |
| `mono.sld`: `Specialization` | Receives the combined typed program, instance table and definition bodies. | Package-local worklist over its own IR and selected dependency IR records. |
| `control.sld`: `Callees.reading`, `definition-row` | Walks called bodies to distinguish actual yields from broad effect rows. | Compositional call contracts, with explicit IR fallback while those contracts mature. |
| `session.sld`: `Emission.items` | Retains emitted monomorphic bodies for later handler-safety rechecking. | Artifact contracts whose changes invalidate consumers without retaining another job's state. |
| `core.sld`, `wasm.sld`: `name-owner`, string keys | Infers ownership from printed global names. | `DefId`/`LibraryId`, with names formatted only at diagnostic and Wasm boundaries. |
| `inputs.sld`: `producer-text` | Keys generation partly by search directories and prints a recipe/loading stack into scratch source. | A producer job keyed by resolved identities, recipe bytes and admitted inputs. |
| `project/plan.sld`, `project/build.sld` | Drive compiles using directories and resident Sessions. | A build graph whose nodes accept immutable package jobs/artifacts. |
| `shell/engine.sld`, `host/browser/load.mjs` | Link named library modules produced by one build's compiler state. | A validated link plan with provider-qualified symbols and explicit artifact compatibility. |

This is already substantially functional code. The checker, specialization
and ownership analysis often thread immutable values. Preserve that work.
The problem is the breadth and implicit provenance of those values, not
the mere existence of a struct named `Context`.

## The compiler I would build

Keep a short, visible sequence with an immutable result at each boundary:

```text
project descriptions
  -> resolved graph + source/resource snapshots             [builder]
  -> located syntax -> resolved package                    [frontend]
  -> checked polymorphic package IR + exported contracts   [checker]
  -> prepared monomorphic functions and layouts            [preparation]
  -> Wasm modules + package artifact                        [emission]
  -> validated link plan -> running program/bundle          [linker/host]
```

The builder owns files, project references, generators, artifact storage
and publication. The compiler owns language semantics. The linker owns
artifact compatibility, symbol resolution and initialization ordering.
Release builds may optimize linked Wasm afterwards. Linking does not rerun
name resolution, type inference, instance selection or source expansion.

### Frontend and polymorphic IR

Keep the reader, lexical rules, type/effect inference, explicit conversion
lowering and ownership algorithms. Separate common located syntax and
diagnostics from the compiler-specific request protocol, so project parsing
and highlighting can depend on syntax without depending on compiler
orchestration. This is a substantive new responsibility, not a file split
for line counts.

Expansion produces only the current package's resolved declarations.
Imported interfaces occupy a separate lookup table. Resolve every global
reference to a `DefId` before checking. A checker invocation owns its
metavariables, substitutions and evidence holes; none survive its output.
Continue settling each Scheme library's types before checking its importers
inside the package. Packaging must not introduce consumer-driven inference.

Call the interchange representation **Package IR**. It fills the role of
polymorphic compiler metadata; there is no need to copy Rust MIR's
control-flow graph merely to serialize it. Start with the existing checked
expression tree, made explicit and closed:

- Fully determined types, quantified type/effect parameters, ownership
  requirements and concrete definition identities.
- Resolved conversions, foreign boundaries, selected instance evidence and
  lifecycle plans. Dictionary/evidence parameters remain explicit where
  they are genuinely polymorphic.
- Locations as source identities and spans, with a separate diagnostic path
  map. No dependency on another process's string interners or file handles.
- All helper declarations reachable from exported generic bodies or macros,
  including private helpers, available to the compiler under internal IDs.
  Compiler availability does not imply source import visibility.
- No `unchecked` type placeholders, unification cells, arbitrary syntax
  environments, source search paths, build callbacks or compiler closures.

Represent resolved input, checked polymorphic IR and prepared ground IR as
different data types. Today the same `Expr`/`Program` family spans several
states. Make construction of `CheckedPackage` prove the earlier decisions
have been made, and construction of `PreparedPackage` prove emission can
proceed without semantic discovery. Do not maintain parallel serializers
for whole historical compiler contexts.

### Instances and macros need real interfaces

Typeclass selection cannot use whichever instances happened to enter a
combined program. Freeze the visible instance environment from declared
imports and explicit named instance sets. Diagnose overlapping candidates
in that environment. An already checked provider records its chosen
`InstanceId`s; linking another package never reselects its evidence.
Consumers can use dependency-defined instances only through the interface
policy, including the compiler support closure of public definitions.

Retain the existing named-instance-set semantics. Defining the exact
export/import rule for unnamed instances is a language compatibility
decision: recommend that public library interfaces carry their public
instance candidates and required transitive provenance. A private instance
selected inside a generic remains an internal evidence reference, not a
new candidate in the caller. Test ambiguity at the consumer boundary;
do not quietly introduce a different global coherence rule during linking.

Exported `syntax-rules` macros carry templates and serializable
definition-site binding references. Their local scope graphs are numbered
within the artifact and remapped when decoded; external references are
`DefId`s. A macro may expand to its provider's private helper without
allowing the caller to import the private library. Never store pointers
into `ExpandedProgram.scopes` or make a consumer recreate those scopes by
re-expanding the provider source.

Replace `implicit-libraries`' broad filesystem lookup during deriving with
an explicit compiler-support interface in the job. Builtin forms have a
fixed toolchain identity. Deriving serialization must name the selected
wire provider, whose interface and version enter the job's dependencies.
This preserves hygienic deriving without an undeclared dependency on the
entire shell library tree.

### Preparation owns all semantic backend work

Preparation specializes reachable generics, creates clone/drop glue,
checks specialized call restrictions, determines representations and
normalizes yielding control flow. Use one explicit registry of definition
identities and specialization requests. Queue concrete work and finish it
before emission. Put ordered initializers into this output explicitly.

Emission consumes fixed ground declarations, function bodies, import/export
tables and layouts. It must not import the checker, load a package,
discover an instance, enqueue a semantic helper or reconstruct a typed
program. A local buffer or interning cache used to write Wasm is an emission
implementation detail with one owner; it cannot change the semantic
function inventory.

Use consumer-owned instantiation initially: a package specializes imported
generics at the ground types it needs. Their original binders, evidence and
dependency references retain provider identities. A private monomorphic
helper can be an internal linker export without becoming a source-public
API. A private generic helper joins the artifact's IR support closure.
Instances in different consumer packages may duplicate generated code;
that is an acceptable first implementation. Address deduplication later
without introducing a global mutable specialization service.

The provider must emit monomorphic support helpers reachable from exported
generic bodies even when its own code never calls those helpers. Keep a
specialization request's semantic key (provider definition, ground arguments
and evidence) separate from its code owner. Its linker symbol also identifies
the consumer that emitted it, so two consumers do not accidentally define
the same symbol. Instantiation must still reference the provider's existing
globals and initializers; copying generic code must not copy package state.

### Replace body inspection with explicit call contracts

This is the hardest compiler cleanup, and it must be prototyped before
promising the removal of dependency bodies. The current restriction check
can inspect a helper's body because its declared effect row overstates what
escapes after an internal handler. The task scheduler is an important case.
A single Boolean `may-yield` is not expressive enough.

Recommend a finite summary language describing escaped control labels as
functions of row arguments and callback parameters, together with callback
restrictions, resume behavior and primitive/foreign guarantees. For
example, a helper that runs a callback under handler `E` can summarize
`escapes(callback) minus E`, plus effects of the handler implementations.
The rule for deep resumption must match the current `resuming` analysis;
this example is not a complete effect algebra.

Compute summaries over recursive call components to a sound fixed point.
Use conservative signatures when precision is unavailable. A conservative
answer that rejects currently valid scheduler code is a compatibility
failure to address, not permission to accept an unsafe callback.
Ground specialization evaluates the summary with the actual types, rows
and evidence. Changes to a summary count as interface changes even if the
written function signature is unchanged.

Initially retain the minimal dependency IR needed for the existing analysis
inside the artifact. That still achieves process isolation. Differentially
test summary results against the body-based implementation, especially
recursion, callback forwarding, locally caught yields, cleanup and resumes.
Delete `Callees.reading`, repeated helper-body inspection and retained
`Emission.items` only when the summary contract covers their purpose. Do
not keep both permanently, and do not hide a source fallback behind the
new interface.

## The compiled package artifact

Define one versioned artifact schema consumed by both the next compiler and
the linker. Its logical sections are:

| Section | Contents and consumer |
| --- | --- |
| Identity and requirements | Provider identities, compiler/IR/ABI versions, target features, dependency artifact requirements. |
| Public interface | Libraries, binding exports, types, effects, instances, macro templates and call contracts used by consumers. |
| Compiler support | Checked generic bodies and the private/transitive declarations their references close over. |
| Code and layouts | Wasm modules, internal/public linker symbols, canonical GC layout descriptions and specialization identities. |
| Initialization | Ordered library initialization nodes and dependency edges; program entry remains separate. |
| Resources and diagnostics | Content-addressed resources, source IDs/spans and optional source maps. |

Use a deterministic, versioned data codec over explicit records. Start with
an inspectable canonical datum encoding for metadata and IR, with large
bytes/Wasm stored as content-addressed blobs. Add a textual dump command if
the encoding later becomes binary. Do not create a declaration-only file
and an unrelated hidden generic-body format; declarations alone cannot
serve this consumer. Reject unknown versions, unresolved identities,
malformed references and incompatible ABI contracts when decoding.

The IR is an exact-toolchain interface initially, not a promise of a stable
third-party compiler ABI. Remote artifacts need provenance and compatibility
verification before they can supply trusted checked evidence. Content
hashing detects corruption; it does not prove type safety. An untrusted IR
artifact must be validated/rechecked or rejected under an explicit trust
policy. This is a future distribution boundary, not a reason to weaken
local checked constructors.

### Cache keys and repeated builds

Keep provider identity, interface identity and build content identity
separate. A build key covers the source inventory and contents, resource
snapshots, resolved dependency bindings, relevant dependency interfaces/IR,
compiler and ABI versions, mode and feature settings. No session-local
revision counter is a persistent content key.

A monomorphic implementation edit recompiles its package. A consumer can
reuse its code if all compiler-visible contracts, layouts and initialization
requirements it used are unchanged; the link plan still selects the new
dependency artifact. A generic-body, macro, instance-policy or call-summary
edit invalidates consuming code that used it. Initially use a conservative
package-wide compile-interface digest. Finer dependency slicing is optional
later, after the broad rule is correct.

Never cache a resolution decision solely by the spelled import name.
Removing a dependency or narrowing public exports must fail a new build
even if cached code exists. Validate the current graph before reuse. A
consumer alias edit can reuse the provider artifact, while rechecking the
consumer's changed namespace. Warm and cold builds must agree, including
after failed builds and cancelled attempts.

The resident cache is owned by the build service and keyed by these values.
Package-local incremental frontend caches may be retained, but are
discardable accelerators. They may not contain required semantic state
that a cold artifact-only consumer cannot reconstruct.

## Linking, WasmGC and runtime behavior

A link plan selects one compatible artifact per resolved package instance,
checks every referenced definition, validates compiler/ABI requirements and
orders initialization. Imported metadata can be read by a compiler job
before link; shared mutable compiler state is never required at link either.
The final application may share runtime values and globals across linked
module instances in one runtime application as it does today. Each library
module can have its own `WebAssembly.Instance`; that runtime module boundary
is distinct from the isolated compiler jobs that produced its bytes.

Retain per-library Wasm modules inside a package artifact initially. That
preserves the existing live-reload granularity and avoids making a large
package one unavoidable initialization/relink unit. Package is the compile
job and artifact boundary; a module is a code/linking unit. Static release
linking can combine the same modules. Delete the separate whole-program
semantic compilation path once both outputs use this pipeline.

The WasmGC ABI needs special care:

- Type definitions must have canonical recursion groups and field layouts
  derived from provider-qualified identities and type arguments. Neither
  package discovery order nor consumer aliases may change their ordering.
- Source nominal identity is checked by Snail even when two distinct types
  have structurally identical Wasm layouts. Engine type equality alone is
  not a nominal-type check.
- Effect identities, `Any` tags, dynamic-export signatures and wire schemas
  currently derive from textual names/schema hashes. Replace alias-sensitive
  inputs with canonical identities. A schema edit changes its compatibility
  fingerprint; an unrelated body edit does not. Persistent application data
  and plugin compatibility need explicit migration tests.
- Do not extend the current 32-bit TypeId scheme to more package instances
  without addressing collisions. For statically linked artifacts, include
  full identity-to-tag claims and reject conflicting claims before execution.
  Dynamic loading must perform the same compatibility check or use wider
  descriptors. Silent collisions are never an identity mechanism.
- Link one compatible runtime and control-record ABI into a program. Package
  compilation does not create one independent effect scheduler per library.
  Existing evidence passing and one-shot resume semantics remain intact.

Record the calling convention as part of that ABI: evidence parameters,
closure environments, dictionaries, ownership transfer, cleanup and scalar
host imports must agree across separately emitted code. Exported nominal
types need enough representation information for consumers to specialize
and emit compatible layouts, even when their constructors are source-private.
An opaque representation needs an explicit indirection/API contract; source
privacy alone cannot make its layout unavailable to the compiler.

Initialize each reached library once per provider instance, regardless of
the number of aliases or import paths. Preserve source order within a
library and explicit import order where it determines initialization;
topological sorting must not silently change observable top-level effects.
The artifact records these edges and order, rather than recovering them
from specialized function ownership or linker iteration order.

The linker must verify compatibility across independent builds. The current
assumption that every module came from one compiler Session is no longer
sufficient. Runtime plugins continue to have their explicit dynamic
boundary; loading a package artifact is not automatic permission to load
an unchecked plugin into the application's namespace.

## Generated code and build planning

Keep generated libraries and artifact bundles. A package system does not
make macro-discovered dependencies static. Keep one build graph with nodes
for package compilation, producers and application artifacts, and retain
the existing ability to refine it after generated syntax arrives.

Replace the printed producer protocol incrementally. A producer job carries
its owning package, resolved imports, source/recipe identity, input
snapshots and requested output kind as data. The builder runs it and
parses its output into a located generated-library value. Generated imports
are checked under the owning package's view. A scratch pathname is not the
recipe's semantic identity.

Keep a structured `NeedInput` result for expansion. It is not an instruction
to invoke another compiler from inside the current compiler. Discovery and
real expansion must use the same resolver and semantics; a textual import
scanner cannot replace them. A suspended expansion continuation may stay
inside its package job as an optimization, but restarting the job from
snapshots must produce the same requests and result.

Cycle detection belongs to the explicit graph: a producer that needs the
library it generates is a cycle, even when reached through another package.
Carry dependency provenance in requests so diagnostics can show that cycle.
Once this works, remove the `generating`/`recipe` source headers, rereading
printed producers to reconstruct keys, and duplicate directory-based
producer identities. Keep the cycle invariant, not its current transport.

## What I would delete, and what earns its place

| Delete or replace | Why it can go | What must exist first |
| --- | --- | --- |
| Global ordered library search paths and blanket standard-library fallback | They make dependencies depend on ambient reachability. | Per-package views and owned inventories, including explicit toolchain providers. |
| Inferring ownership from `snail.shell...:name` strings | Aliases and multiple provider instances make spelling an unreliable identity. | Structured definition identities through every pass and ABI formatter. |
| A transitive `Program` as the input to every pass | It lets each pass reach unrelated state and forces dependency source into the job. | Package IR plus immutable imported contracts/support records. |
| Replaying dependency `Program` deltas and preserving their live scope tables | An artifact is already a complete dependency result. | Serialized hygienic macros and local identity remapping. |
| Whole-program and per-library semantic pipelines as separate architectures | Packaging should not choose different typechecking or specialization semantics. | One package preparation pipeline; static and development modes differ at linking. |
| Body scans to rediscover primitive aliases, ownership and call behavior | Those facts can be established at their defining boundary. | Checked call/representation contracts and differential tests. |
| Retaining dependency monomorphic bodies only for later restriction rechecks | This makes a cache part of the semantic input. | Sufficient summaries; explicit support IR is the temporary fallback. |
| Session-counter-based artifact revisions | They describe a process history, not persistent content. | Deterministic input/interface identities. |
| Directory-based generator keys and printed scratch-source headers | They conflate build transport with resolution and source provenance. | Typed producer jobs and graph-owned cycle detection. |
| A globally accumulated instance candidate pool | Loading another package should not change a provider's meaning. | Sealed per-library candidate environments and explicit evidence references. |
| Hidden deriving loads of arbitrary toolchain source | They bypass declared dependency scope. | Explicit compiler-support interfaces. |

Keep library import/export syntax and intra-package libraries, pure state
threading, the established type/effect and ownership rules, located errors,
runtime resource handles, content-addressed resource storage and atomic
publication. Keep runtime checks at unsafe/dynamic boundaries. Keep the
existing backend and host work unless this contract actually supersedes
it. Large cohesive modules are acceptable; creating a crate-like package
for every helper would add ceremony without a useful boundary.

I would not introduce a plugin framework for passes, a global service for
specialization, a general virtual filesystem with mount precedence, or a
second compiler IR solely for Rust familiarity. The import view can be a
small immutable table from an alias to an artifact provider, plus a table
of its allowed public libraries.

## A physical split worth making

Use package directories to make responsibilities visible. Begin with a few
substantial units; these are proposed names and boundaries, not a command
to move the tree before the contracts exist.

| Package | Owns | Dependencies |
| --- | --- | --- |
| `core` | Typed forms, primitives, base collections and scalar boundary declarations. | Toolchain builtin contract. |
| `source` | Locations, datum/syntax reader, lexer and source diagnostics. | Core. |
| Compiler packages | Expansion, checking, ownership, Package IR, preparation and Wasm emission, with the stage boundaries below. | Core and source; fixed compiler-support interfaces. |
| `project` | Declarative descriptions, graph resolution, snapshots, artifact store and build planning/publication. | Core, source and compiler's public job API. |
| Shell libraries | IO-facing libraries and application services, grouped by actual responsibility. | Explicit core/shell dependencies. |
| `editor` and applications | UI and application policy, with their own descriptors and source trees. | Public project/compiler/library APIs as needed. |

Keep the compiler's source closure self-hostable. Its implementation must
not acquire a dependency on the project service, editor, networking stack
or registry client. Compiler input formats and the source reader must be
usable in stage 0. A shared syntax package is justified by existing project
parsing and highlighting consumers; a universal `common` package is not.

Do not leave all compiler passes inside one permanently privileged package.
The compiler directory at the audited revision contains about 20,500 lines;
expansion, checking and emission are substantial subjects already. Once the
closed pass interfaces exist, use them to enforce this dependency graph too:

| Compiler package | Public contract and permitted compiler dependencies |
| --- | --- |
| `compiler-ir` | Definition identities, type/effect algebra, explicit pass representations, artifact records and their codec. No pass implementation imports. |
| `compiler-expand` | Owned syntax and imported macro interfaces to resolved declarations. Depends on IR; cannot invoke checking, emission or the project builder. |
| `compiler-check` | Resolved declarations to checked IR, ownership evidence and call contracts. Depends on IR. Exposes a small pure ground-check operation where specialization still requires it. |
| `compiler-prepare` | Checked IR and dependency support records to fixed monomorphic bodies/layout plans. Depends on IR and that explicit checking API; cannot invoke source expansion or a builder. |
| `compiler-wasm` | Prepared declarations/layouts to Wasm bytes. Depends on IR and encoding support; cannot import expansion, checking or preparation. |
| `compiler` | The public package-job API and composition of those stages. Owns no filesystem search or long-lived semantic cache. |

Shared pure type/capability operations belong beside their representations;
do not move the current aggregate `Program` unchanged into `compiler-ir`.
Keep each pass's existing cohesive implementation modules inside its owning
package. This split establishes meaningful import prohibitions without
turning every helper into a package. Compiler implementation packages are
ordinary users of the same package system they implement.

Bootstrap Chibi needs an explicit projection of the selected package
closure into the library naming/layout it understands. Generate that view
from resolved package identities, rewriting library declarations and import
specifications structurally where aliases require it; never globally
replace identifier strings or rewrite quoted data. Preserve the existing
small bootstrap allowlist and host substitutes for core forms/base/table/IO.
Do not add the repository or every package's `src` to Chibi's path.
Stage 0 may use a restricted single-version compiler closure initially;
it must fail explicitly on unsupported package arrangements.

## Sequence and review gates

1. **Approve the package contract and examples.** Settle contextual names,
   public libraries, relative project references, resource ownership and
   the artifact-only acceptance test. This chapter is that review input.
2. **Introduce identities and a scoped resolver.** Replace spelling-based
   ownership behind existing frontend behavior; add collision and alias
   tests. Implement the declarative manifest extension and explicit
   source/resource inventories. Use a temporary adapter for old project
   roots, with clear diagnostics and an eventual removal point.
3. **Close and serialize the checked frontend result.** Package-local
   declarations, hygienic macro references, instance evidence and generic
   support closure must round-trip in a fresh compiler. Initially carry
   support bodies where summaries are not sufficient.
4. **Make preparation produce fixed backend input.** Keep specialization,
   control normalization and glue creation out of emission. Prototype call
   summaries against the current analysis. This step can overlap the
   artifact work conceptually, but do not merge an interface that loses
   the evidence the backend needs.
5. **Compile and link packages serially in separate jobs.** Run the source
   removal test. Validate GC layouts, nominal identities, initialization,
   resources and ABI requirements on both native and browser hosts. Route
   static and development builds through the same prepared artifacts.
6. **Move real source trees and switch the bootstrap.** Migrate core/source,
   the compiler stages, project and applications deliberately. Audit current
   consumers of compiler internals; expose a justified API or move shared syntax to
   its owner. Delete legacy global roots and the old semantic pipeline
   after both bootstrap stages and applications pass.
7. **Add persistent reuse and development integration.** Cache immutable
   artifacts, watch all declared inputs and carry package/module identities
   through relinking. Publish only complete compatible generations. Verify
   warm/cold equivalence before reducing invalidation precision.
8. **Later, schedule independent jobs concurrently.** The transport already
   consists of bytes and IDs. Worker isolation, cancellation and scheduling
   can then change without changing compiler semantics.

Existing descriptions keep their behavior during migration. Adding `links`
(even an empty list), or declaring a `library` target, selects scoped mode;
its `library-roots` are owned roots and there is no standard-directory
fallback. Refuse mixed legacy/scoped dependency assumptions instead of
silently weakening a scoped target. Convert repository-owned descriptors
in step 6, then remove the adapter rather than supporting both models
indefinitely.

The worker design is already tracked in
[#553](https://github.com/tsnl/snail-scheme/issues/553): separate Wasm
instances communicate through byte messages, with shared memory a separate
explicit mechanism. Do not introduce a shared WasmGC heap or pass live
compiler objects to a thread pool. This package design needs neither
worker queues nor shared memory to establish isolation.
[Issue #462](https://github.com/tsnl/snail-scheme/issues/462) tracks the
existing package/artifact/cache questions. This proposal supplies a
concrete consumer for a compiled polymorphic interface; it does not assume
that work is already implemented.

## Required evidence before implementation is considered complete

| Area | Meaningful checks |
| --- | --- |
| Resolution | Missing direct link; private sublibrary; alias collision; self-name collision; two aliases of one provider; same library spelling in distinct packages; cyclic targets; no ambient source fallback. |
| Interchange | Fresh process with dependency source unavailable; exported macro using private helpers; generic using private/transitive helpers; scope-ID collisions between independently built artifacts; malformed/version-mismatched artifacts. |
| Semantics | Existing inference, conversions, instance sets, ownership, cleanup and handler fixtures; a new sibling dependency cannot change a previously compiled package's evidence. |
| Identity and ABI | Same type through different aliases; different provider instances with identical source names; canonical recursive GC types; conflicting TypeId claims; changed schemas; plugin signatures. |
| Initialization | Diamond dependencies initialize once; aliases initialize once; observable source order; separate provider instances initialize independently; unreachable library bodies do not run. |
| Inputs | Resource changes, additions and removals; escaping symlinks; definition-site macro resources; generated import violations; generator/artifact cycles; failed generation leaves old output usable. |
| Reuse | Cold/warm artifact equality; body-only edits; generic/macro/summary edits; revoked links; narrowed exports; changed compiler/ABI; stale dependency snapshot rejection; failure and cancellation recovery. |
| Hosts | Execute linked Wasm on native and browser hosts; stage-0 source tests; self-host bootstrap; development relink with compatible state; resource cleanup after failures. |

Use the repository's required checks at the implementation stages:
`make test`, `make check`, `make test-chibi`, `make bootstrap`, and
`make test-wasmtime` for native compiler/execution changes. Rust changes
also need the relevant offline Cargo tests and formatting checks. Run the
browser reload suites for changed module identities and load order.

Measure compiler-package builds, application builds, generic-heavy inputs
and repeated callback inspection separately, including peak memory and
artifact bytes. Serialized IR and private support closure add real cost;
separate jobs and narrower retained state may recover it. Make no speedup
claim before those measurements. Parallel execution is not an acceptance
requirement for this first implementation.

## Recommendation and remaining design risks

Approve the package boundary, keep the frontend's proven algorithms, and
rewrite the orchestration and pass interfaces around it. Do not wrap the
current transitive Session in a package name and call that isolation.

The two highest-risk prototypes are hygienic macro serialization and
compositional callback/control summaries. Their fallback is explicit
serialized compiler-support IR, never access to provider source or live
state. The next risk is ABI identity across independently produced WasmGC
modules, especially nominal types whose layouts happen to coincide and
TypeIds used by dynamic values. Resolve those before migrating every file.

The most consequential language-policy choice is which instance candidates
a public library exports. The most consequential build-policy choice is
how generated programs obtain their declared inputs. Both need examples
and tests during review; neither should be concealed in a linker or a
cache. A remote registry and stable cross-toolchain IR are deliberately
outside the first implementation.
