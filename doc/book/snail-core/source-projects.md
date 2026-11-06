# Proposed projects without `project.datum`

**Design proposal for review; not implemented.** The direction is to remove
`project.datum`, consolidate application sources under `src/`, and discover
runnable applications from ordinary types. How one application requests
another application's compiled artifact remains open. This document records
the discussion so far; it does not settle a replacement API or command syntax.

The [project chapter](projects.md) describes the implemented manifest and build
contracts. The [application model](applications.md) defines the existing
`Application` class. Related build-tooling decisions are tracked in
[issue #462](https://github.com/tsnl/snail-scheme/issues/462).

## One source tree

A directory would define the workspace, with `src/` as its single application
and library source root. Move the application code now under `apps/` beneath
`src/` and have source discovery scan that tree. Flatten the applications'
current nested source roots so library names continue to match paths. For
example, `src/apps/siegework/application.sld` could define
`(apps siegework application)`; that namespace spelling is illustrative.

Imports would establish source dependencies directly. A shared monorepo
library would not need a separate build-target declaration that each app must
remember to depend on. Libraries would retain their names, interfaces and
separate compilation. The compiler and IDE could resolve imports and declaration
locations through the same source mapping, without per-target library roots or
virtual mounts.

The editor would still open the repository as a whole. Limiting application
discovery to `src/` would not hide host code, documentation or other files from
the editor. Host adapters and bootstrap replacements retain their distinct
roles; scanning `src/` must not admit alternate stage-0 libraries or isolated
test fixtures into the application's namespace. Source layout and packaging
for the existing IDE entry need to be included in the migration.

## Discover applications, then request an output

Discover named, concrete types for which the compiler can resolve an
`Application` instance, including aliases. This is broader than finding structs
with explicit instances: the current Siegework entry is an alias for
`SceneApplication Game`. Generic adapters do not themselves enumerate a finite
set of runnable applications.

Discovery should reuse source indexing and compiler evidence. Syntax indexing
can identify candidates; aliases, imports, macros and generated libraries mean
a text scan alone cannot establish that a candidate is an application. The
design must distinguish incomplete candidates from confirmed entries without
making a complete successful build of the source tree a prerequisite for
using the IDE or building one application. When generated entries become
discoverable, and how much work discovery performs, remain open.

The working proposal is that the CLI or IDE selects a concrete application and
the desired output, such as a browser bundle or native program. Both interfaces
would make the same build request. The compiler would then build only the
selected application's dependency closure. An unrelated unfinished application
must not prevent that build.

Selecting an existing application is different from registering a named target
in a manifest. The source declaration would provide the application's identity.
Exact CLI syntax, defaults, alias identity and output naming are undecided.
We should still look for a simpler way to select outputs before introducing
additional declarations. Runtime arguments would belong to an invocation;
whether the IDE needs saved launch settings is a separate question.

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
2. Compiling the server reaches a source-level request for the frontend's browser
   artifact, identified by its concrete application and the requested output.
3. The builder produces that artifact and supplies its files as data to the
   server's compilation.
4. The server implements the routes and communication using those files.

This would replace the manifest-name lookup in
[`artifact-bundle`](projects.md#artifact-bundles). Consuming the artifact would
establish the build dependency; a second application dependency list would not
be required. This is a candidate design, not proposed runnable syntax.

Prefer keeping `Application` concerned with the runtime entry contract. A
`build` method on it was considered, but risks coupling host-side build
execution to code that expects the application's platform. Producing a browser
artifact must not require starting the browser application. Existing staging
or a separate artifact-producing abstraction may express that separation more
simply; the choice remains open.

## The main question for review

Does the source-level artifact request above need special compiler machinery
or a compiler-generated dependency graph that we could avoid? Removing the
manifest should not merely move a manually declared target registry into
source syntax.

Before choosing a new primitive, compare the artifact request with what can
be expressed through ordinary generated libraries, linked inputs and existing
build staging. Establish where those mechanisms suffice and where requesting
a compilation genuinely needs another operation. Any ordering or dependency
information introduced should serve an actual artifact consumer. The preferred
direction remains removing `project.datum`, even if this mechanism changes.

Other decisions needed before implementation are:

- How browser HTML, CSS, public filenames and host files become part of the
  requested artifact. Content-addressed linked resources do not by themselves
  specify public URLs or the page shell.
- How a request distinguishes output kinds and build modes for the same
  application, and how it identifies an application across aliases.
- How the source index handles incomplete code, generated declarations and
  conflicting library names without checking unrelated programs to build one.
- How artifact requests compose with generated libraries, including ordering,
  cycles and source-located diagnostics.
- How build selection, development watching and run controls work without
  manifest build names or run targets.

## Implementation sequence to review

First settle the source mapping and application-discovery contract, and prove
that a concrete alias can be found and selected without an explicit target
declaration. Move application libraries under `src/` with matching imports and
source-relative assets, preserving generated recipes and the stage-0 boundary.

Then provide one application-selection operation for the CLI and IDE. Exercise
it with Siegework, Hearsay and the IDE itself, including an unrelated broken
application that does not block the selected build. Keep source-file scripts
and compiler tooling in view when deciding how existing entry paths migrate.

Use a server embedding a browser frontend to decide the artifact mechanism and
packaging contract. Verify that building the server produces the frontend
without running it, that resource changes invalidate the consuming output,
and that failed or cyclic dependencies produce useful diagnostics while
preserving the existing publication guarantees.

Once those responsibilities have homes, remove manifest parsing and target-name
lookup, update the development service, commands, fixtures and book, and retire
the affected `project.datum` files. Preserve the current reload and resource
behavior through that transition. The eventual implementation needs the
repository's compiler, bootstrap, native and browser checks; this PR proposes
the work and changes documentation only.
