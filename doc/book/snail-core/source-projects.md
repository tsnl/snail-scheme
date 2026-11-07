# Proposed projects without `project.datum`

**Design proposal for review; not implemented.** The direction is to remove
`project.datum`, consolidate sources under `src/`, and resolve applications on
demand from explicit build requests. A datum shared by the CLI and an artifact
macro identifies an application type and output configuration. Macro expansion
introduces symbolic resource references and discovers requested applications
alongside imports. Compilation shares compatible analysis across these roots;
the builder binds their outputs afterward. Ordinary artifact-reference cycles
are allowed, while cycles in generated-source evaluation remain errors.
No application-enumeration scan or target registry is required. The companion
[artifact and staged-linking proposal](artifacts.md) develops storage, forcing,
generator lifetimes and independent deployment. The
[incremental compiler workspace](incremental-compiler.md) shares analysis across
applications, generators and editor requests, including reuse across source edits.
Exact API syntax remains open; none of the proposed forms below is implemented.

The [project chapter](projects.md) describes the implemented manifest and build
contracts. The [application model](applications.md) defines the existing
`Application` class. Related build-tooling decisions are tracked in
[issue #462](https://github.com/tsnl/snail-scheme/issues/462).

## One source tree

A directory would define the workspace, with `src/` as the common source root.
Move the application code now under `apps/` beneath `src/apps/`, flattening the
applications' existing nested source roots so library names match paths. For
example, `src/apps/siegework/application.sld` could define
`(apps siegework application)`.

The `apps` directory is an ordinary namespace grouping. It has no special
discovery rule, and application types can live in other libraries too. Imports
and application references use the same source mapping. There is no separate
`src/bin/` versus `src/lib/` boundary.

Imports would establish source dependencies directly. A shared monorepo
library would not need a separate build-target declaration that each app must
remember to depend on. Libraries would retain their names, interfaces and
separate compilation. The compiler and IDE could resolve imports and declaration
locations through the same source mapping, without per-target library roots or
virtual mounts.

The editor would still open the repository as a whole. Resolving application
sources beneath `src/` would not hide host code, documentation or other files
from the editor. Host adapters and bootstrap replacements retain their distinct
roles; source resolution must not admit alternate stage-0 libraries or isolated
test fixtures into the application's namespace. Source layout and packaging
for the existing IDE entry need to be included in the migration.

## Resolve applications only when requested

An explicit build request names a concrete type for which the compiler must
resolve an `Application` instance when the request is forced. Aliases are valid
references: the current Siegework entry is an alias for `SceneApplication Game`.
The compiler can check that evidence after resolving the requested library and
type through the usual source mapping.

There is no initial scan to enumerate every application type. The CLI supplies
a root request; source expansion can recursively request other applications'
artifacts. Resolve each requested application and compile its dependency closure
as it is reached. A generated library can supply a requested type through normal
library loading; its declarations need not appear in a precomputed catalog.

The IDE can submit the same explicit request as the CLI. Source indexing for
navigation or completion is a separate editor concern, not a prerequisite for
building or resolving artifact dependencies. An unrelated unfinished application
must not prevent a requested build.

Selecting an existing application is different from registering a named target
in a manifest. The source declaration would provide the application's identity.
Exact CLI syntax, defaults and output naming are undecided. The artifact proposal
recommends keeping qualified aliases distinct for initial request memoization.
Runtime arguments would belong to an invocation; whether the IDE needs saved
launch settings is a separate question.

## One datum for an application and its output

Represent a build request as inert S-expression data: a path of symbols
identifies a concrete application type, paired with a well-defined output
configuration. For illustration only:

```scheme
((apps frontend application Frontend)
 (browser ((title "Frontend"))))
```

Here `(apps frontend application)` would identify a library under `src/`,
`Frontend` its concrete application type, and the `browser` record the requested
output and its page configuration. The path uses the ordinary library namespace.
This illustrates the information required, not a settled grammar or
file-extension rule.

The CLI, IDE and artifact macro would supply the same datum to the same request
parser and resolver. Parse its shape into an application reference and typed
configuration without building the application. When forced, use ordinary
compiler evidence to establish that the referenced type satisfies `Application`.
Keep source locations for macro requests and useful input locations for CLI
errors. No manifest target name or separately registered dependency list
participates in resolution.

The request is deliberately small: identify an application and the artifact
needed from it. Build-mode defaults, the output-kind vocabulary and the exact
CLI and macro spellings still need review.

## Dependencies should follow the output being consumed

The motivation for removing the manifest is broader than shortening setup.
Compilation should do work because a requested output needs it, and each check
should establish evidence needed to produce that output. A generated library
has a concrete consumer; imports expose the stages needed to obtain it. Linked
and included files likewise associate inputs with the source that consumes
them. These mechanisms already carry much of the information that a separate
imperative build script would otherwise repeat.

Continue using `generate-library` for build-time computation that produces a
library, and `link-file` and inclusion forms for source-associated inputs. This
does not imply that arbitrary producer IO already has complete dependency
tracking: the [compiler inputs contract](compilers.md#compiler-inputs) describes
the implemented staging and cache behavior.

A server that serves a browser frontend needs the frontend's compiled and
packaged files, not merely its source library. That artifact dependency still
needs an expression after the manifest is removed. The working proposal is:

1. The user selects the server application to build.
2. Expanding the server's source introduces a symbolic tree reference for the
   frontend's browser output.
3. Expansion adds the frontend to the shared worklist. The compiler prepares both
   applications and emits their code against predetermined logical paths, without
   waiting for the other's files. The builder binds their completed outputs in an
   immutable catalog before publishing the server.
4. The server implements the routes and communication using that tree. A
   generated-library producer that needs the frontend uses the same mechanism
   when preparing its own executable stage.

This would replace the manifest-name lookup in
[`artifact-bundle`](projects.md#artifact-bundles). Consuming the artifact would
establish the build dependency; a second application dependency list would not
be required.

Prefer keeping `Application` concerned with the runtime entry contract. A
`build` method on it was considered, but risks coupling host-side build
execution to code that expects the application's platform. Producing a browser
artifact must not require starting the browser application. The working design
uses the deferred artifact request and existing build staging for that
separation.

## Expansion introduces references; linking forces them

Compiler support for the artifact macro is acceptable in this design. Its
references must be a result of actual macro expansion in the selected
application's import closure. Use the expander's resolved operation,
not a search for the macro's textual name: renamed imports, wrapper macros and
generated invocations must work. An invocation stored in an unused macro
template establishes no dependency until expansion reaches it.

Register requested targets before visiting their sources, so repeated requests
and reference cycles converge on existing work. The initial discovery policy
follows every expanded request, including requests whose uses later disappear
from compiled code. Avoiding those builds through dead-code elimination is a
possible later refinement, not a prerequisite for this design.

Ordinary resource references do not block code generation: their paths are known
before the files exist. Generated source can block expansion; prepare, emit and
run its producer using the same worklist and compatible compiler caches, then
resume discovery with the returned syntax. Executing a producer requires its
resources to be complete first. Those inputs do not automatically become
deployment dependencies, and cycles in these evaluation prerequisites are errors.

The [artifact proposal](artifacts.md) specifies the common store, request sharing,
evaluation-cycle detection, resource binding and closure export. It replaces
eager byte embedding with file/tree handles and keeps output manifests separate
from build provenance. Reuse the existing planner's ordering and diagnostic
machinery while changing its discovery/forcing boundary. No manually maintained
target registry or general-purpose build DSL is needed.

## Remaining decisions for review

- The precise library/type-path and output-configuration grammar, including
  browser page and host options and useful errors for invalid requests.
- The file/tree resource API, generated-result encoding and native/browser
  resource-binding contract described in the companion proposal.
- How build selection, development watching and run controls work without
  manifest build names or run targets.

## Implementation sequence to review

Use the [companion delivery sequence](artifacts.md#delivery-and-decisions-still-needing-review)
to establish deferred linking for existing files before adding recursive
application requests. The shared request parser and resolver then provide the
new front door for the CLI, IDE and artifact macro.

Exercise requests for Siegework, Hearsay and the IDE itself, including an
unrelated broken application that does not block the selected build and a
requested alias supplied by a generated library. Move application libraries
under `src/apps/` with matching imports and source-relative assets, preserving
generated recipes and the stage-0 boundary. Keep source-file scripts and compiler
tooling in view when deciding how existing entry paths migrate.

The [case inventory](artifacts.md#case-inventory) includes a server retaining a
browser frontend and a generated library consuming an artifact, exercising both
runtime and build-time lifetimes. Verify that the frontend can be exported
independently, that ordinary artifact-reference cycles work, and that generated
source prerequisites impose only the necessary staging boundaries.

Once those responsibilities have homes, remove manifest parsing and target-name
lookup, update the development service, commands, fixtures and book, and retire
the affected `project.datum` files. Preserve the current reload and resource
behavior through that transition. The eventual implementation needs the
repository's compiler, bootstrap, native and browser checks; this PR proposes
the work and changes documentation only.
