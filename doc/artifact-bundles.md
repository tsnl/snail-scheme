# Artifact bundles

The compiler and `(lofi artifact)` library implement named artifact requests.
`lofi build PROJECT TARGET` resolves them to browser targets in that project's
`project.datum`. Standalone `compile` and `run`, and the old development
commands, have no project resolver and reject these requests. Compiler clients
can also supply the in-memory inputs described below.

```scheme
(import
 (lofi base)
 (lofi artifact))

(: frontend ArtifactBundle)
(define frontend (artifact-bundle "client"))

;; A lookup in embedded data, without file IO or a runtime build.
(artifact-ref frontend "index.html")
```

The target name must be a literal string. The public macro constructs an
ordinary `ArtifactBundle` containing a list of `ArtifactFile` values. Each file
has a relative `path` and immutable `bytes`. `artifact-ref` returns `Option
Bytes`; the records' accessors also expose the list for ordinary application
code. MIME types, routes and transport policy belong to serving code.

Requests occur during expression expansion, including macro uses and generated
library syntax. An unused macro template makes no request. Constructor names
retain their definition scope, so importing only the macro, renaming it, or
shadowing constructor names does not change the value it builds. The private
core form lowers into ordinary constructor applications and literals; there is
no special backend representation or runtime artifact service.

## Compiler boundary

The compiler entry points and `build-session` take the current generated-library
provider and an `ArtifactInputs` value. `make-session` takes only library
directories; a retained session owns evidence, never a provider closure:

```scheme
(Table (List (Pair String Bytes)))
```

The table maps target names to ordered file snapshots. The native builder establishes
unique, canonical relative paths sorted by path, with bytes loaded from one
completed immutable output. Expression expansion performs only memory lookups;
it has no filesystem capability. Inputs belong to the current invocation, not
the retained session. `no-artifacts` is an empty input table.

The project implementation owns target lookup, browser-kind checking,
serial traversal and cycle detection. A missing input records a typed request
and aborts the invocation. The native builder obtains the request only after
the compiler stack has unwound.

Each library's expansion records its direct requests and the exact file values
embedded. Ordinary source/import eligibility is checked before replaying those
requests, so an edited body can remove an obsolete dependency. A cache hit
still looks up every recorded input and compares paths and every byte using the
reader's byte comparison. A missing input fails the build; changed contents cause
fresh expansion. No lookup rereads a backing file.

An artifact-bearing expansion receives a fresh revision stamp from the
session's existing expansion counter. Replaying it preserves that stamp. Its compiled
key is constructed once with its source key and stamp; its interface also
includes the stamp, so changed bytes also
invalidate generic importers that embed specialized bodies. These stamps are
local to one session lineage, not persistent content identities. Failed builds
publish no replacement session. This keeps bundle bytes out of string keys
without trusting a content checksum.

Generated syntax is obtained before deciding whether to replay its library.
The native project builder uses the same target traversal while compiling
producer programs. Persistent producer caching remains separate work; current
producer output lasts only for its enclosing compile.

## Native compiler requests

The compiler cannot start a producer or build another project target. It records
one pending `CompilerRequest` in memory and exits immediately. Artifact expansion
and request signaling have no filesystem effects; library loading and
generated-source IO still do. The host consumes the request after the compiler
stack has unwound.

Standalone source builds service generated-library requests and reject artifact
requests with their source location: an artifact needs a project build. Chibi
and Node compiler entries publish the pending request in `request.datum` after
unwinding. `(lofi compiler inputs)` owns this grammar:

```scheme
(generate "123456")
(artifact "client" "server/main.sld" 12 8)
```

Each attempt deletes the preceding request before starting the compiler. Only
exit status 1 permits a request. Publication failures use status 2; any other
exit or signal cannot fulfill work from a leftover file. Success with a pending
request and a request already answered are errors. Scratch directories are
created exclusively, so stale files cannot become inputs. Stderr carries only
diagnostics. Standalone builds have no artifact resolver or reply accumulation.

The resident compiler returns the pending request in `CompilerFailure.request`;
no request file is written or parsed. Each invocation clears pending request and
diagnostic state before work. Trusted exits preserve the instance but return no
successor Session. Both cold project builds and `dev` use this boundary.

Only `scripts/project.mjs` resolves named browser targets, including during
producer compilation. It passes each completed target's canonical file inventory
to `addArtifact`, which reads the bytes once and returns an opaque immutable
input table. A failed read returns no replacement; the preceding table remains
usable. There is no artifact reply manifest or second parsing step.

Each logical compilation retains its table through retries and passes it to
`static` or `modules`. Nested producers own separate inputs and scratch while
sharing the builder's active/completed target traversal. These opaque values
belong to their originating compiler instance, like Sessions. Successful
Sessions retain only the per-library evidence already used for cache reuse.
Applications embed the bytes and need no runtime file access.

## Project traversal

Each invocation parses the project once and binds one resolver around the
entire root build. A request names a browser target in that project; missing
targets and program targets fail at the requesting source location. Recursive
build calls discover dependencies as they occur. A list of active target names
detects cycles, including requests made while compiling a generated-library
producer. Errors include the traversal path, such as `client -> admin -> client`.

A completed-target list stores sorted relative names paired with files in
the target's immutable generation. Repeated requests use those same files
throughout the invocation. There is no source scanner, second dependency graph,
persistent artifact cache or runtime lookup. A new attempt builds dependencies
again and regenerates producer output. A resident builder retains successful
compiler Sessions per target when its entry and ordered library roots match;
cached expansion still compares its exact evidence with the current inputs.

Packaging and complete file enumeration precede publication. Enumeration
includes hidden and nested files, excludes only the root `.lofi-target` marker,
and rejects unreadable directories, symbolic links and nonregular entries.
Every artifact inventory names generation files directly, never `build/TARGET`.
The whole traversal returns a private candidate before any public link changes.
A failed parent preserves every previous output, including its dependencies.
Successful compiler Sessions may still advance: their evidence contains bytes,
not references to the discarded directories.

Cold builds accept the candidate immediately. A resident caller can discard it
instead, keeping public outputs unchanged. Publication checks every destination
and prepares its temporary link before renaming any. Each rename is atomic;
several target links are not one transaction. A later rename failure preserves
the published prefix and removes only the unrenamed directories. Publication
consumes the candidate even on failure; callers must not discard it afterward.
