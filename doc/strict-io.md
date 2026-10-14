# Strict text-file output

Import `(snail io)` alongside `(snail strict)`. The Scheme library owns character
iteration and integer formatting. The ordinary Rust runtime owns buffered UTF-8
files. Its scalar interface carries characters and integer IDs, with no Scheme
reference, value wrapper, root table, or dynamic dispatch.

| Operation | Signature |
| --- | --- |
| `file-exists?` | `String -> Bool` |
| `delete-file` | `String -> Unit` |
| `open-output-file` | `String -> OutputPort` |
| `close-output-port` | `OutputPort -> Unit` |
| `write-char` | `Char, OutputPort -> Unit` |
| `write-string` | `String, OutputPort -> Unit` |
| `write-i64` | `I64, OutputPort -> Unit` |
| `newline` | `OutputPort -> Unit` |
| `call-with-output-file` | `All (T). String, (OutputPort -> T) -> T` |

```scheme
(import (snail strict) (snail io))
(call-with-output-file "answer.txt"
  (lambda (port)
    (write-string "answer: " port)
    (write-i64 42 port)
    (newline port)))
```

Each pathname operation copies the current Scheme String's characters into a
private Rust UTF-8 buffer when the operation executes. The filesystem operation
takes and consumes that buffer on both success and failure. The provider runs
one invocation at a time; neither its scalar calls nor the intervening Scheme
character loop call user code. Concurrent or reentrant invocation during this
transfer is unsupported. Embedded NUL is rejected by the filesystem API, and
invalid raw Unicode scalars fail without replacement characters.

`file-exists?` uses the same `Path.try_exists` behavior as the ordinary provider:
it follows symbolic links, returns false for a missing target, and reports other
filesystem errors. Opening creates or truncates a file. Deletion and every write
remain explicit source effects. No pathname conversion, formatting, or output
is cached across calls.

An `OutputPort` contains a private shared `Ref` to its handle. Aliases refer to
the same file. Close first marks that Ref closed, then flushes and releases the
Rust file. Repeated Scheme close is a no-op, including when a callback already
closed its borrowed port. A callback's returned alias is closed before the
result is returned. Writing through a closed alias fails. Rust validates raw
handles independently, issues each ID only once, and checks exhaustion before
creating or truncating a file.

`write-i64` handles the entire signed I64 range. Its digit recursion keeps a
nonpositive working value, so it never negates `I64_MIN`. UTF-8 encoding occurs
in Rust; the Scheme loop emits every character and digit in source order.

## Linking and invocation

```sh
scripts/build-strict output.scm build/output.native.wasm
scripts/link-strict-runtime build/output.native.wasm build/output.wasm
scripts/test-strict-io
```

The linker builds the existing Rust crate offline, or accepts `--runtime PATH`
to reuse its compiled artifact. It retains commands and intermediates beside
the output. `--raw` removes unreachable module elements without optimizing the
Scheme body; the default performs the ordinary final Binaryen optimization.
Both forms must eliminate imports from `snail.abi`, `snail.library`, and
`snail.platform`. Application exports may not use the reserved `snail:` or
`diagnostics/` prefixes, or the names `memory`, `_initialize`, and
`close-resources`.

The host supplies WASI, initializes the reactor, and then invokes Scheme `main`
once before any selected worker. The retained `close-resources` export returns
zero if all remaining files close successfully and one if a close fails. It
clears pending pathname text, detaches the live registry, and attempts every
close and drop. It is safe to call when no resources remain.

## Failure and ownership

`call-with-output-file` closes after a normally returning callback. A Scheme
trap cannot run the following Scheme close, so the invocation host must call
`close-resources` in its cleanup boundary. The original failure stays primary
if cleanup also fails. Further Scheme execution in that instance is unsupported
after a trap; the cleanup export remains available for release.

Expected Rust I/O failures end their registry borrow, release any removed file,
and close all remaining files before reporting the original fatal error. In
particular, the adapter explicitly drops a file after a failed flush: Wasm traps
do not run Rust destructors. Returned close errors do not stop the cleanup loop.
A host import that itself traps during cleanup can prevent later closes; this
interface does not claim recovery from arbitrary host failures.

There is no automatic GC finalization. An open file remains owned by Rust until
explicit close or invocation cleanup, even if its Scheme wrapper is collected.
The native tests execute real files, malformed scalar callers, alias behavior,
callback traps, and injected WASI flush errors through both linked compiler forms.
