# Artifact bundles

The compiler and `(lofi artifact)` library implement named artifact requests.
The native project builder's target traversal and request bridge are the next
integration step: current `lofi build`, `compile`, `run` and development commands
explicitly reject these requests. Compiler clients can already supply the
resolver described below, as the linked-Wasm integration fixture does.

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

The compiler entry points and `make-session` take an `ArtifactResolver` after
the existing generated-library callback. Its type is:

```scheme
(-> String Loc (List (Pair String Bytes)) ! mut fs)
```

The resolver establishes that entries have unique, canonical relative paths,
sorted by path, with bytes from one completed immutable output. It must return
a stable snapshot throughout a build, including repeated resolution after a
cache mismatch. A project implementation will own target lookup, browser-kind
checking, serial traversal and cycle detection. `no-artifacts` supplies a
located failure for compiler clients without that capability.

Each library's expansion records its direct requests and the exact file values
embedded. Ordinary source/import eligibility is checked before replaying those
requests, so an edited body can remove an obsolete dependency. A cache hit
still resolves every recorded request and compares paths and every byte. An
error propagates; changed contents cause fresh expansion.

An artifact-bearing expansion receives a fresh revision stamp from the
session's existing expansion counter. Replaying it preserves that stamp. Both
its compiled key and its interface include the stamp, so changed bytes also
invalidate generic importers that embed specialized bodies. These stamps are
local to one session lineage, not persistent content identities. Failed builds
publish no replacement session. This keeps bundle bytes out of string keys
without trusting a content checksum.

Generated syntax is obtained before deciding whether to replay its library.
The native bridge must also keep the project resolver active while compiling
producer programs. Persistent producer caching remains separate work; current
producer output lasts only for its enclosing compile.
