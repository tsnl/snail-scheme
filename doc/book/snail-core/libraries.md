# Libraries

## Standard library

| Library | Contents |
| --- | --- |
| `(snail-core core)` | The core forms, the builtin types, and the `mut` and `tasks` effects. The compiler serves it; it has no file. |
| `(snail-core primitive)` | The operations the backend implements, each declared with its type by `(primitive name type)`. `(snail-core base)` gives most of them their everyday names. |
| `(snail-core base)` | Forms, numeric classes, `Option`, `Result`, `Pair`, lists, vectors, arrays, strings, `Show`. |
| `(snail-core io)` | The `console`, `fs` and `clock` effects: text output, lines of input, files as text or bytes, [directories and names](#files-and-directories), and a monotonic clock. |
| `(snail-core resource)` | Files a library links rather than embeds: `link-bytes`, the `Resource` handle, and `read-resource` through the `resource` effect ([linked files](types.md#linked-files)). |
| `(snail-core task)` | One-shot local dispatch, cooperative yield, timer waits, and `Mailbox` queues between tasks, through the runtime-owned `tasks` effect ([task operations](../runtimes/tasks.md)). |
| `(snail-core process)` | Child processes with piped standard streams, through the `process` effect: `spawn`, reading output, writing and closing input, signals and exit; and `termination`, SIGINT or SIGTERM as a value, through the `signals` effect ([child processes](../runtimes/networking.md#child-processes)). |
| `(snail-core table)` | Immutable tables from strings to values. |
| `(snail-core math)` | Elementary functions on `F64`. |
| `(snail-core text)` | Unicode character properties, case mapping and decimal digit values, from the runtime's tables. `(scheme runtime)` is built on it, so Scheme's character procedures are Unicode's. |
| `(snail-core random)` | A deterministic generator as a value. |
| `(snail-core wire)` | `Serialize`, `Deserialize` and the byte encoding. |
| `(snail-core utf8)` | `string->utf8`, and `utf8->string`, which rejects ill-formed bytes as a fatal `TextDecoder` does, giving the offset of the first bad sequence. |
| `(snail-core json)` | The `Json` value, with integer numbers and objects as ordered members, and `json->string`, which writes what `JSON.stringify` writes for the same value. |
| `(snail-core sha256)` | `sha256` over bytes, giving the 32-byte digest, and `bytes->hex`, the lowercase hex Node's `digest('hex')` writes. |
| `(snail-core http)`, `(snail-core http exchange)` | An HTTP/1.1 subset: request heads and targets, response and stream heads, and one exchange over a connection ([HTTP protocol](http.md)). |
| `(snail-core app)` | Applications, frames, pictures, materials and sprites, and the `screen` effect. |
| `(snail-core wasm)` | Loading WebAssembly modules while a program runs, and `unsafe-cast`. |
| `(snail-core sprite)` | Spritebooks: animations on sheets of equal cells, posed as sprites facing the camera. |
| `(snail-core format)` | Indenting and formatting Lisp source as `scripts/format-scheme` does. |
| `(snail-core highlight)` | Source text as tokens that tile it, classed for coloring by the compiler reader's lexical rules ([code highlighting](toolchain.md#code-highlighting)). |
| `(snail-core integer)`, `(snail-core rational)`, `(snail-core number)` | Exact integers of any size, rationals, and Scheme numbers. |
| `(snail-core datum)`, `(snail-core read)`, `(snail-core write)` | Scheme data and its external representation. |
| `(snail-core syntax)` | The syntax a `generate-library` recipe returns, and the bytes its producer writes. |
| `(snail-core explore)` | Bounded model checking of a total state machine's invariant. |
| `(scheme base)` | R7RS names (`cons`, `car`, `vector`, `char=?` ...) over the typed language. |
| `(scheme compiler)`, `(scheme runtime)` | The R7RS translator, and the standard procedures its output calls. |

## Files and directories

`(snail-core io)` reads and writes whole files, and works on the names a
filesystem keeps. Each path operation returns a `Result`, so a failure a
program can act on is a value: `(Err (NotFound))` for a missing path,
`(Err (NotEmpty))` for a directory that still holds something.

| Operation | Result |
| --- | --- |
| `(make-directory path)` | One directory, whose parent must exist. |
| `(make-directories path)` | The directory and each missing parent; a directory already there is success. |
| `(rename-file from to)` | Renames a file or directory, replacing a file at `to` at once: a reader sees the old file or the new one, never neither. |
| `(remove-file path)`, `(remove-directory path)` | A file or symbolic link; an empty directory. |
| `(remove-tree path)` | What is at `path` and everything in it, never following a link. |
| `(list-directory path)` | The names in a directory, without `.` and `..`, in scalar order whatever the host's order. |
| `(file-status path)` | A `FileStatus`: the `FileKind` (`RegularFile`, `Directory`, `SymbolicLink` or `OtherKind`), the size in bytes and the modification time in nanoseconds since the Unix epoch, without following a link. |
| `(make-symbolic-link target path)`, `(read-symbolic-link path)` | A link and its target, kept as given. |

A `FileError` is `NotFound`, `AlreadyExists`, `NotEmpty`, `NotADirectory`,
`IsADirectory`, `PermissionDenied`, `InvalidPath` (a path holding a NUL, or
reading a link that is not one), `NotSupported` or `OtherError`, and `show`
describes it. A relative path is resolved against the working directory the
host passes. The runtime performs each operation through WASI preview1
(`crates/runtime/src/paths.rs`); a page has no preopened directory, so every
path operation there fails with `OtherError`. WASI preview1 has no file
modes or owners; it reports device and inode numbers and a status-change
time, but Rust's standard library exposes them on WASI only as unstable
API, so `FileStatus` has none of these yet.
`(monotonic-nanoseconds)`, of the `clock` effect, reads WASI's monotonic
clock, from an origin the host chooses; only differences mean anything.

## Wire types

`(deriving Serialize Deserialize)` at the end of a struct or enum generates
instances of `(snail-core wire)`'s classes. `serialize` writes a value as bytes and
`deserialize` reads it back:

```scheme
(struct Point
  ((x I64)
   (y I64))
  (deriving Serialize Deserialize))

(ann (deserialize (serialize (Point 1 2))) Point)
```

Each struct and enum case has a 32-bit TypeId hashed from its library, name
and field schema. Every struct or enum value is written as its case's TypeId
followed by its fields, so reading data written for another schema fails at
the first changed type instead of misreading it.
