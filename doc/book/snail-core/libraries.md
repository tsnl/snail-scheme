# Libraries

## Standard library

| Library | Contents |
| --- | --- |
| `(snail core forms)` | The core forms, the builtin types, and the builtin `mut` and `host` effects. The compiler serves it; it has no file. |
| `(snail core primitive)` | The operations the backend implements, each declared with its type by `(primitive name type)`. `(snail core base)` gives most of them their everyday names. |
| `(snail core base)` | Forms, numeric classes, `Option`, `Result`, `Pair`, `Never`, lists, vectors, arrays, strings, `Show`. |
| `(snail core io)` | The `console`, `fs` and `clock` effects: text output, lines of input, files as text or bytes, [directories and names](#files-and-directories), and a monotonic clock; and, as total reads, `command-line`, `environment-variable` and `working-directory`. |
| `(snail shell resource)` | Files a library links rather than embeds: `link-bytes`, the `Resource` handle, and `read-resource` through the `resource` effect ([linked files](types.md#linked-files)). |
| `(snail shell task)` | The `tasks` effect and its scheduler, written in Snail-Core: one-shot local dispatch, cooperative yield, timer and ticket waits, waiting on the host, and `Mailbox` queues between tasks ([task operations](../runtimes/tasks.md)). |
| `(snail shell process)` | Child processes with piped standard streams, through the `process` effect: `spawn`, reading output, writing and closing input, signals and exit, `run` to run a command to its end, and `exec` to replace the program with one; and `termination`, SIGINT or SIGTERM as a value, through the `signals` effect ([child processes](../runtimes/networking.md#child-processes)). |
| `(snail core table)` | Immutable tables from strings to values. |
| `(snail shell math)` | Elementary functions on `F64`. |
| `(snail shell text)` | Unicode character properties, case mapping and decimal digit values, from the runtime's tables. `(scheme runtime)` is built on it, so Scheme's character procedures are Unicode's. |
| `(snail shell random)` | A deterministic generator as a value. |
| `(snail shell wire)` | `Serialize`, `Deserialize` and the byte encoding. |
| `(snail shell utf8)` | `string->utf8`, and `utf8->string`, which rejects ill-formed bytes as a fatal `TextDecoder` does, giving the offset of the first bad sequence. |
| `(snail shell json)` | The `Json` value, with integer numbers and objects as ordered members, and `json->string`, which writes what `JSON.stringify` writes for the same value. |
| `(snail shell json read)` | `string->json`, which reads JSON text whose numbers are integers back as a `Json`, and `json-member`. A library of its own, so that a program that only writes JSON does not carry it. |
| `(snail shell assembler)` | `assemble`, WebAssembly text to a binary module in-process, or the parser's message naming the line and column. Only a tool linked with the toolchain's runtime can use it: the plain runtime leaves the parser out, since a development build copies the runtime whole. |
| `(snail shell sha256)` | `sha256` over bytes, giving the 32-byte digest, and `bytes->hex`, the lowercase hex Node's `digest('hex')` writes. |
| `(snail shell http)`, `(snail shell http exchange)` | An HTTP/1.1 subset: request heads and targets, response and stream heads, and one exchange over a connection ([HTTP protocol](http.md)). |
| `(snail shell app)` | Applications, frames, pictures, materials and sprites, and the `screen` effect. |
| `(snail shell wasm)` | Loading WebAssembly modules and plugins while a program runs ([below](#loading-webassembly)). |
| `(snail shell sprite)` | Spritebooks: animations on sheets of equal cells, posed as sprites facing the camera. |
| `(snail shell format)` | Indenting and formatting Lisp source as `scripts/format-scheme` does: Emacs's indentation, each import and field on its own line, and each line whose code runs past 100 columns broken, a call before its arguments and a binding form before each binding and body form. It never joins lines. |
| `(snail shell highlight)` | Source text as tokens that tile it, classed for coloring by the compiler reader's lexical rules ([code highlighting](toolchain.md#code-highlighting)). |
| `(snail shell integer)`, `(snail shell rational)`, `(snail shell number)` | Exact integers of any size, rationals, and Scheme numbers. |
| `(snail shell datum)`, `(snail shell read)`, `(snail shell write)` | Scheme data and its external representation. |
| `(snail shell syntax)` | The syntax a `generate-library` recipe returns, and the bytes its producer writes. |
| `(snail shell project build)` | A project's build, which `snail build` and `snail run` run: `read-project`, `build-project`, which compiles, links and packages each target into a generation of its own, and `publish-project` ([projects](projects.md)). |
| `(snail shell explore)` | Bounded model checking of a total state machine's invariant. |
| `(scheme base)` | R7RS names (`cons`, `car`, `vector`, `char=?` ...) over the typed language. |
| `(scheme compiler)`, `(scheme runtime)` | The R7RS translator, and the standard procedures its output calls. |

## Files and directories

`(snail core io)` reads and writes whole files, and works on the names a
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
| `(followed-status path)` | The `FileStatus` of what a read of `path` finds, following each link to the file it names, so never `SymbolicLink`; a link to nothing is `NotFound`, though `file-status` finds the link. |
| `(make-symbolic-link target path)`, `(read-symbolic-link path)` | A link and its target, kept as given. |

A `FileError` is `NotFound`, `AlreadyExists`, `NotEmpty`, `NotADirectory`,
`IsADirectory`, `PermissionDenied`, `InvalidPath` (a path holding a NUL, or
reading a link that is not one), `NotSupported` or `OtherError`, and `show`
describes it. A relative path is resolved against the working directory the
host passes, which `(working-directory)` gives, or `None` on a host with no
filesystem. `(environment-variable name)` is a variable of the environment the
program started with, or `None` when it is unset; the host's own channel for
the working directory, `SNAIL_CWD`, reads as unset. The runtime performs each operation through WASI preview1
(`crates/snail-core-support/src/paths.rs`); a page has no preopened directory, so every
path operation there fails with `OtherError`. WASI preview1 has no file
modes or owners; it reports device and inode numbers and a status-change
time, but Rust's standard library exposes them on WASI only as unstable
API, so `FileStatus` has none of these yet.
`(monotonic-nanoseconds)`, of the `clock` effect, reads WASI's monotonic
clock, from an origin the host chooses; only differences mean anything.

## Loading WebAssembly

`(snail shell wasm)` loads modules while a program runs, on the Node runner,
into a program compiled one library at a time ([loading modules at run
time](compilers.md#loading-modules-at-run-time)). Every failure is a
`LoadError`, and `load-error-message` describes one.

```scheme
(enum LoadError
  (Unreadable ((file String)))         ; no such file
  (InvalidManifest ((file String)))    ; not a modules.json
  (InvalidModule ((file String)))      ; not a WebAssembly module
  (NameTaken ((name String)))          ; a module of that name is linked
  (LinkFailed ((name String)))         ; an import has no provider of its type
  (MissingExport ((name String)))
  (NotDynamic ((name String)))         ; exported, but not with `dynamic`
  (SignatureMismatch ((name String)))) ; compiled with other types

(: load-module (-> String String (Result Module LoadError) ! wasm fs))
(: module-export (-> Module String (Result Funcref LoadError) ! wasm))
(: unsafe-cast (All (A) (-> Funcref A)))
(: load-plugin (-> String (Result Plugin LoadError) ! wasm fs))
(: plugin-function (All (A) (-> Plugin String (Result A LoadError) ! wasm)))
```

`(load-module name file)` links the module in `file` into the program's
own namespace under the library name `name` and runs its `main`;
`module-export` gives a function it exports, which `unsafe-cast` makes a
function of the expected type, unchecked. `(load-plugin manifest)` links a
plugin, the program a `modules.json` names, into a namespace of its own,
sharing the runtime. `(plugin-function plugin name)` gives the function the
plugin exposes as `name` with `(expose name "symbol" dynamic)`, at the
expected type, a function of data; it refuses a function whose signature
is not that type's. Values cross by reference. A dynamic export is pure,
a plugin's `main` runs under its effects' defaults, and a trap in a plugin
ends the program.

## Wire types

`(deriving Serialize Deserialize)` at the end of a struct or enum generates
instances of `(snail shell wire)`'s classes. `serialize` writes a value as bytes and
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
