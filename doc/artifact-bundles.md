# Artifact bundles

The compiler and `(lofi artifact)` library implement named artifact requests.
The native project builder's target traversal and request bridge are the next
integration step: current `lofi build`, `compile`, `run` and development commands
explicitly reject these requests. Compiler clients can already supply the
in-memory inputs described below, as the linked-Wasm integration fixture does.

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

The compiler entry points and `build-session` take an `ArtifactInputs` value:

```scheme
(Table (List (Pair String Bytes)))
```

The table maps target names to ordered file snapshots. Its provider establishes
unique, canonical relative paths sorted by path, with bytes loaded from one
completed immutable output. Expression expansion performs only memory lookups;
it has no filesystem capability. Inputs belong to the current invocation, not
the retained session. `no-artifacts` is an empty input table.

The project implementation will own target lookup, browser-kind checking,
serial traversal and cycle detection. A missing input currently produces a
located error; the following integration will turn it into a structured request
to the native builder after the compiler invocation has unwound.

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
The native bridge must also keep the project resolver active while compiling
producer programs. Persistent producer caching remains separate work; current
producer output lasts only for its enclosing compile.
