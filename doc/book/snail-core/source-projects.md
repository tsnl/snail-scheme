# Proposed projects without `project.datum`

**Design proposal for review; not implemented.** The direction is to remove
`project.datum`, consolidate sources under `src/`, and resolve applications on
demand from explicit build requests. A datum shared by the CLI and an artifact
macro identifies an application type and desired output. Macro expansion
discovers further artifact requests; the builder follows those dependencies and
rejects cycles. No application-enumeration scan or target registry is required.
Exact syntax and packaging contracts remain open; none of the proposed forms
below is implemented.

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
resolve an `Application` instance. Aliases are valid references: the current
Siegework entry is an alias for `SceneApplication Game`. The compiler can check
that evidence after resolving the requested library and type through the usual
source mapping.

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
Exact CLI syntax, defaults, alias identity and output naming are undecided.
Runtime arguments would belong to an invocation; whether the IDE needs saved
launch settings is a separate question.

## One datum for an application and its output

Represent a build request as inert S-expression data: a path of symbols
identifies a concrete application type, paired with a symbol from a defined
set of output kinds. For illustration only:

```scheme
((apps frontend application Frontend) browser)
```

Here `(apps frontend application)` would identify a library under `src/`,
`Frontend` its concrete application type, and `browser` the requested browser
artifact. The path uses the ordinary library namespace. This illustrates the
information required, not a settled grammar or file-extension rule.

The CLI, IDE and artifact macro would supply the same datum to the same request
parser and resolver. Parse it into an application reference and output kind,
then use ordinary compiler evidence to establish that the referenced type
satisfies `Application`. Keep source locations for macro requests and useful
input locations for CLI errors. No manifest target name or separately registered
dependency list participates in resolution.

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
2. Expanding the server's source reaches an artifact macro whose datum requests
   the frontend's browser output.
3. The builder produces that artifact and supplies its files as data to the
   server's compilation.
4. The server implements the routes and communication using those files.

This would replace the manifest-name lookup in
[`artifact-bundle`](projects.md#artifact-bundles). Consuming the artifact would
establish the build dependency; a second application dependency list would not
be required.

Prefer keeping `Application` concerned with the runtime entry contract. A
`build` method on it was considered, but risks coupling host-side build
execution to code that expects the application's platform. Producing a browser
artifact must not require starting the browser application. The working design
uses the expansion-time artifact request and existing build staging for that
separation.

## Dependencies discovered through expansion

Compiler support for the artifact macro is acceptable in this design. Its
dependency information must be a result of actual macro expansion in the
selected application's import closure. Use the expander's resolved operation,
not a search for the macro's textual name: renamed imports, wrapper macros and
generated invocations must work. An invocation stored in an unused macro
template establishes no dependency until expansion reaches it.

At that boundary, the expander records a structured request with its source
location. The builder resolves the application and output, builds the artifact
if this invocation does not already have a completed result, and supplies it
as a compiler input. Expansion can then use the resulting artifact data. The
expander need not perform host IO or start application processes itself.

Repeated requests for the same resolved application and output should share a
build within an invocation. This does not introduce a new persistent-cache
contract. Request identity must account for output-affecting configuration and
resolve aliases consistently, rather than treating arbitrary datum spellings
as distinct builds.

Track dependencies while discovering and satisfying requests. Detect a request
that depends on itself and longer cycles, reporting the application/output
chain and the source locations that introduced its edges. A cycle can pass
through a generated-library producer. Generated syntax may reveal more requests
only after its producer runs; refine the plan and check for cycles before
running the newly dependent phases. A failed or cyclic dependency must not
publish a replacement for the consuming application's accepted output.

The existing [artifact planner](projects.md#artifact-bundles) already uses
discovery expansion, generated-library phases and cycle detection. Reuse those
contracts while replacing manifest-name resolution with application/output
requests. The concern about unnecessary compiler machinery remains a design
constraint: dependency edges should come from artifact consumers, with no
second user-maintained target registry or general-purpose build DSL.

## Remaining decisions for review

- How browser HTML, CSS, public filenames and host files become part of the
  requested artifact. Content-addressed linked resources do not by themselves
  specify public URLs or the page shell.
- How a request distinguishes output kinds and build modes for the same
  application, and how it identifies an application across aliases.
- The precise library/type-path and output-kind grammar, including how the
  shared parser and resolver report invalid requests.
- How build selection, development watching and run controls work without
  manifest build names or run targets.

## Implementation sequence to review

First settle the common `src/` source mapping and application-reference
contract. Prove that an explicit request resolves a concrete alias without
enumerating applications or registering a target. Move application libraries
under `src/apps/` with matching imports and source-relative assets, preserving
generated recipes and the stage-0 boundary.

Then provide one request parser and resolver for the CLI, IDE and artifact
macro. Exercise requests for Siegework, Hearsay and the IDE itself, including
an unrelated broken application that does not block the selected build and a
requested alias supplied by a generated library. Keep source-file scripts and
compiler tooling in view when deciding how existing entry paths migrate.

Use a server embedding a browser frontend to exercise expansion-time artifact
requests and decide the packaging contract. Verify that CLI and macro requests
resolve the same output, repeated requests share a build, wrapper and generated
macros expose dependencies, and unused templates request no build. Check direct
cycles, indirect cycles and cycles revealed through generated libraries. Building
the server must produce the frontend without running it; resource changes must
invalidate the consuming output, and failures must preserve existing
publication guarantees.

Once those responsibilities have homes, remove manifest parsing and target-name
lookup, update the development service, commands, fixtures and book, and retire
the affected `project.datum` files. Preserve the current reload and resource
behavior through that transition. The eventual implementation needs the
repository's compiler, bootstrap, native and browser checks; this PR proposes
the work and changes documentation only.
