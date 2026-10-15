# Strict text-file input and output

Import `(snail io)` alongside `(snail strict)`. The Scheme library owns character
iteration, line construction and integer formatting. The ordinary Rust runtime owns buffered UTF-8
files. Its scalar interface carries characters and integer IDs, with no Scheme
reference, value wrapper, root table, or dynamic dispatch.

| Operation | Signature |
| --- | --- |
| `file-exists?` | `String -> Bool` |
| `delete-file` | `String -> Unit` |
| `open-input-file` | `String -> InputPort` |
| `close-input-port` | `InputPort -> Unit` |
| `read-line` | `InputPort -> LineResult` |
| `eof-object?` | `LineResult -> Bool` |
| `line-text` | `LineResult -> String` (line case only) |
| `call-with-input-file` | `All (T). String, (InputPort -> T) -> T` |
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
filesystem errors. Opening an output file creates or truncates it; opening an
input file preserves its contents. Deletion and every write
remain explicit source effects. No pathname conversion, formatting, or output
is cached across calls.

An `InputPort` or `OutputPort` contains a private shared `Ref` to its handle. Aliases refer to
the same file. Close first marks that Ref closed, then flushes and releases the
Rust file. Repeated Scheme close is a no-op, including when a callback already
closed its borrowed port. A callback's returned alias is closed before the
result is returned. Reading or writing through a closed alias fails. Rust validates raw
handles independently, issues each ID only once, and checks exhaustion before
creating or truncating a file.

`LineResult` has the cases `(end-of-file)` and `(line text)`. `read-line` returns
EOF only when it sees EOF before any character or terminator. LF, CR and CRLF
each terminate one line and are omitted from its text. A final unterminated line
is returned once. Empty lines contain a fresh mutable empty String, so they stay
distinct from EOF. NUL and all other Unicode scalars are preserved. Invalid or
truncated UTF-8 and I/O failures report errors; they do not become EOF.

The Rust scalar reads return a Unicode code point or `-1` for EOF. Its existing
`TextInput` owns one lookahead, so a CR followed by a non-LF character leaves that
character for the next read. Scheme grows each line's private String buffer by
doubling from 64 characters, bounded by the native String limit. It copies only
the initialized prefix during growth, trims spare capacity once, and reuses an
exact fit. This takes amortized linear work without allocating a list node for
each character. Rust does not construct Scheme strings or hold Scheme roots.

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

`call-with-input-file` and `call-with-output-file` close after a normally returning callback. A Scheme
trap cannot run the following Scheme close, so the invocation host must call
`close-resources` in its cleanup boundary. That boundary starts before reactor
initialization and Scheme `main`, since top-level code can open a file and trap
before a worker is invoked. The original failure stays primary
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
The Node/WASI tests execute real files, malformed scalar callers, alias behavior,
initialization and callback traps, injected read/flush errors and Unicode/line
boundaries through both linked compiler forms. `scripts/test-native` exercises
the same Rust services and line operations through the native compiler path,
including malformed UTF-8, growth boundaries and observed release before exit.
