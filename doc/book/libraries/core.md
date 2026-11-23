# Core

`(snail core …)` imports nothing outside itself, and every program builds
on it. The compiler imports only `base`, `table` and `io`, so it compiles
itself, and Chez runs the same three as stage 0 of the
[bootstrap](../snail-scheme/bootstrap.md).

## `(snail core forms)`

The core forms and the builtin types: `define`, `lambda`, `if`, `begin`,
`let`, `define-syntax` and `syntax-rules`, `quote`, `record`, `new`, `enum`,
`type`, `typeclass`, `instance`, `match`, `ann`, `downcast`, `extern`,
`expose` and the field read `●`, with `I32`, `I64`, `F32`, `F64`, `U8`,
`Bool`, `Char`, `Unit`, `String`, `Array`, `Bytes`, `Fn` and their kin. The
compiler serves it, so it has no file; `(snail core base)` re-exports it,
and a program imports that instead ([terms](../snail-scheme/terms.md),
[types](../snail-scheme/types.md)).

## `(snail core primitive)`

The operations the backend implements directly, each declared with its type
by `(primitive name type)`, a form accepted only here: as `extern` declares
a foreign function, `primitive` declares one the compiler supplies. The
library has no module of its own, since nothing it declares has a body.
`(snail core base)` gives most of these their everyday names, so a program
seldom imports it.

Of all of them, only `array-set!` and `array-copy!` change anything; some,
such as integer division by zero, can trap.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/core/primitive.sld)

## `(snail core base)`

The prelude. Its exports, by kind:

- **Forms**: the core forms, and derived syntax: `let*`, `letrec`, `cond`,
  `case`, `when`, `unless`, `and`, `or`, `do`, `not` and `set!`.
- **Data**: `Option`, `Result`, `Pair`, `List`, `Never` with `absurd`, and
  `Any` with `downcast` ([explicit `Any`](../snail-scheme/types.md#explicit-any)).
- **Numbers**: the classes `Num`, `Ord`, `Integral` and `Fractional`, with
  their operations, and every conversion between `I32`, `I64`, `F32` and
  `F64`, including their bits.
- **Text**: characters, strings, `Show` (`show`) and `Repr` (`repr`,
  `derive-repr`), and `i64->string`, `string->i64` and `f64->string`.
- **Collections**: lists and their operations, arrays, constant arrays and
  `Bytes`. `array-set` answers a new array; `array-set!` and `array-copy!`
  write the one they are given.
- **Control**: `panic`; the cached functions `cache` and `lru-cache`
  ([cached functions](../snail-scheme/terms.md#cached-functions)); and the
  prompts `make-prompt`, `with-prompt` and `suspend`
  ([suspension](../snail-scheme/suspension.md)).

`(list-sort before? items)` is stable: items for which neither precedes the
other keep their input order. It is a merge sort, O(n log n) comparisons,
and the compiler and the build use it; stage 0 supplies a stable sort of
its own on Chez.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/core/base.sld)

## `(snail core io)`

The capabilities a program starts with: `Host`, `InputPort`, `OutputPort`,
`Fs`, `Clock`, `Arguments` and `ProcessEnvironment`. A port, a clock, the
arguments and the environment are records of functions, which a program may
make for itself, to keep what is written or to fix the time. `Fs` holds
nothing: having it is the permission to use the host's file system. The
host's own are made from a `Host` by `standard-input`, `standard-output`,
`host-fs`, `host-clock`, `host-arguments` and `host-environment`, and only
a target holds a `Host`: `unsafe-host` makes one from nothing, which a
target does and nothing else should
([capabilities](../snail-scheme/capabilities.md)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/core/io.sld)

### Ports

An `InputPort` is a record of `(read-char) → (Option Char)`, and an
`OutputPort` of `(write-string text) → Unit`. Every reading and writing
function takes its port first, so a function reads and writes only the
ports it was given, and a program chooses another stream by passing another
port ([making one's own](../snail-scheme/capabilities.md#making-ones-own)).

`((● in read-char))` consumes one character, `None` at the end.
`(read-line in)` answers the next line without its LF: an empty line is
`(Some "")`, the end after a partial line answers that line, and the end
before any character is `(None)`. Every other character, CR among them, is
kept. Reading standard input first flushes pending standard output, so a
prompt appears before the program waits.

```scheme
(let ((empty (new InputPort (read-char (lambda () (None))))))
  (write out (read-line empty))) ; prints (None)
```

An output port receives whole strings. One a program makes can collect
them, drop them, or forward them:

```scheme
(let ((bracketed (new OutputPort
                   (write-string (lambda (text)
                                   ((● out write-string) (string-append "[" text "]")))))))
  (write bracketed (Some "hello"))) ; prints [(Some "hello")]
```

`(display out value)` prints the text a value's `Show` instance chooses, and
`(write out value)` its `Repr`: strings keep their quotes and escapes,
characters use `#\` notation, and containers represent their elements.
Neither adds a newline; `(newline out)` and `(write-line out text)` do.

```scheme
(display out "hello")        ; prints hello
(write out (Some "hello"))   ; prints (Some "hello")
(write out (list "a" "b"))   ; prints ("a" "b")
```

Scalars have `Show` instances; containers such as `Option`, lists, arrays,
`Result` and `Pair` have none, so `(display out (Some "hello"))` is a
compile error. That keeps a string's quotes from vanishing inside a
container's notation: `write` gives the representation, or a program
matches and displays the contents.

`(repr value)` answers the same representation as a `String`. Base gives
`Repr` instances for the numeric scalars, booleans, characters, strings,
`Unit`, lists, arrays, `Option`, `Result` and `Pair`: lists as
`(element ...)`, arrays as `#(element ...)`, and the others by their
constructors, such as `(new Pair (first 1) (second "one"))`. A record or
enum derives constructor notation:

```scheme
(enum Action
  (Rock)
  (Paper)
  (Scissors)
  (deriving Repr))

(write out (Rock)) ; prints (Rock)
```

A derived instance represents each field in declaration order; records
print named construction, `(new Name (field value) ...)`, and enum cases
stay positional. Generic parameters require `Repr`. An explicit
`(instance (Repr T) (define repr (lambda (value) ...)))` chooses other
notation, and a `Show` instance alone gives no `Repr`.

### Files and directories

Every file operation takes an `Fs` first, `(read-file fs path)`, which the
Node target provides; the table below leaves it out. Each path operation
answers a `Result`, so a failure a program can act on is a value: `(Err
(NotFound))` for a missing path, `(Err (AlreadyExists))` for a name already
taken. `read-file`, `write-file`, `read-bytes` and `write-bytes` fail the
program instead; `read-text-file` and `write-text-file` are the
counterparts for a service, which must answer each failure.

| Operation | Result |
| --- | --- |
| `(make-directory path)` | One directory, whose parent must exist. |
| `(make-directories path)` | The directory and each missing parent; one already there is success. |
| `(rename-file from to)` | Renames a file or directory, replacing a file at `to` at once: a reader sees the old file or the new one, never neither. |
| `(remove-file path)`, `(remove-directory path)` | A file or symbolic link; an empty directory. |
| `(remove-tree path)` | What is at `path` and everything in it, never following a link. |
| `(list-directory path)` | The names in a directory, without `.` and `..`, in scalar order whatever the host's order. |
| `(file-status path)` | A `FileStatus`: the `FileKind` (`RegularFile`, `Directory`, `SymbolicLink` or `OtherKind`), the size in bytes and the modification time in nanoseconds since the Unix epoch, without following a link. |
| `(followed-status path)` | The `FileStatus` of what a read of `path` finds, following each link, so never `SymbolicLink`; a link to nothing is `NotFound`. |
| `(make-symbolic-link target path)`, `(read-symbolic-link path)` | A link and its target, kept as given. |
| `(make-hard-link existing path)` | Another name for a file, which is not copied; it fails across file systems. |
| `(read-text-file path limit)` | The text of the regular file at `path`, if it holds at most `limit` bytes of UTF-8, as one version of the file: its length and modification time stayed the same while it was read. A link is not followed. Else a `TextError`: `ReadFailed` with a `FileError`, `NotRegularFile`, `TooLong`, `NotText` or `ChangedWhileRead`. |
| `(write-text-file path text mode)` | The whole text, by a `WriteMode`: `CreateNew` refuses an existing leaf, even a dangling link; `ReplaceExisting` refuses a missing file; `CreateOrReplace` takes either. |

A `FileError` is `NotFound`, `AlreadyExists`, `NotADirectory` (a path
through a file), `PermissionDenied` or `OtherError`, and `show` describes
it. Each kind is one some program acts on; every other failure, such as
removing a directory that is not empty, is `OtherError`. The runtime does
each operation through WASI preview1
(`crates/snail-scheme-support/src/paths.rs`). WASI has no file modes or
owners, and Rust exposes its device and inode numbers only as unstable API,
so a `FileStatus` holds none of these. A page has no preopened directory,
so every path operation there fails with `OtherError`.

### The clock, arguments and environment

`((● clock monotonic-nanoseconds))` reads a `Clock`. The host's is WASI's
monotonic clock, from an origin the host chooses, so only differences mean
anything.

`(command-line arguments)` lists what the program was started with.
`((● environment variable) name)` is a variable of the `ProcessEnvironment`
the program started with, or `None` when it is unset, and
`((● environment directory))` the working directory, against which a
relative path resolves, or `None` on a host with no file system. The host's
own channel for the working directory, `SNAIL_CWD`, reads as unset.

## `(snail core table)`

Immutable tables from strings to values: `empty-table`, `table-ref` (an
`Option`), `table-set`, `table-remove`, `table-contains?`, `table-count`,
`table-keys` and `table-values`. A table is a Patricia trie on each key's
64-bit FNV-1a hash, after Okasaki and Gill: an update copies the path to
one leaf and shares the rest with the table it came from, so a pass may
keep every version it made.

The order `table-keys` lists keys in is the trie's, which stage 0's tables
on Chez do not share, so the compiler never depends on it.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/core/table.sld)
