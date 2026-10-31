# Libraries

## Standard library

The libraries come in four families, each with a rule for what it may
import ([#566](https://github.com/tsnl/snail-scheme/issues/566)):
core imports nothing, the runtime interfaces only core, and the shell both. Only
`(snail core …)` runs on Chibi, through shims over R7RS; the shell, the
runtime interfaces and Scheme are compiled by the compiler. `(snail stage0
…)` is Chibi's own: the build driver, its tool runner and the test helpers.

### Core

`(snail core …)` imports nothing outside itself. The compiler imports only
its `base`, `table` and `io`, so it can compile itself.

| Library | Contents |
| --- | --- |
| `(snail core forms)` | The core forms, the builtin types, and the builtin `mut` and `host` effects. The compiler serves it; it has no file. |
| `(snail core primitive)` | The operations the backend implements, each declared with its type by `(primitive name type)`. `(snail core base)` gives most of them their everyday names. |
| `(snail core base)` | Forms, numeric classes, `Option`, `Result`, `Pair`, `Never`, lists, vectors, arrays, strings, `Show`. |
| `(snail core io)` | The `console`, `fs` and `clock` effects: text output, lines of input, files as text or bytes, [directories and names](#files-and-directories), and a monotonic clock; and, as total reads, `command-line`, `environment-variable` and `working-directory`. |
| `(snail core table)` | Immutable tables from strings to values. |

### Shell: data and text

`(snail shell …)` is everything else, written in Snail-Core over core and
the runtime interfaces.

| Library | Contents |
| --- | --- |
| `(snail shell math)` | Elementary functions on `F64`. |
| `(snail shell text)` | Unicode character properties, case mapping and decimal digit values, from the runtime's tables. `(scheme runtime)` is built on it, so Scheme's character procedures are Unicode's. |
| `(snail shell random)` | A deterministic generator as a value. |
| `(snail shell utf8)` | `string->utf8`, and `utf8->string`, which rejects ill-formed bytes as a fatal `TextDecoder` does, giving the offset of the first bad sequence. |
| `(snail shell sha256)` | `sha256` over bytes, giving the 32-byte digest, and `bytes->hex`, the lowercase hex Node's `digest('hex')` writes. |
| `(snail shell json)` | The `Json` value, with integer numbers and objects as ordered members, and `json->string`, which writes what `JSON.stringify` writes for the same value. |
| `(snail shell json read)` | `string->json`, which reads JSON text whose numbers are integers back as a `Json`, and `json-member`. A library of its own, so that a program that only writes JSON does not carry it. |
| `(snail shell wire)` | `Serialize`, `Deserialize` and the byte encoding. |
| `(snail shell integer)`, `(snail shell rational)`, `(snail shell number)` | Exact integers of any size, rationals, and Scheme numbers. |
| `(snail shell datum)`, `(snail shell read)`, `(snail shell write)` | Scheme data and its external representation. |
| `(snail shell syntax)` | The syntax a `generate-library` recipe returns, and the bytes its producer writes. |

### Shell: system and network

| Library | Contents |
| --- | --- |
| `(snail shell task)` | The `tasks` effect and its scheduler, written in Snail-Core: one-shot local dispatch, cooperative yield, timer and ticket waits, waiting on the host, and `Mailbox` queues between tasks ([task operations](../runtimes/tasks.md)). |
| `(snail shell process)` | Child processes with piped standard streams, through the `process` effect: `spawn`, reading output, writing and closing input, signals and exit, `run` to run a command to its end, and `exec` to replace the program with one; and `termination`, SIGINT or SIGTERM as a value, through the `signals` effect ([child processes](../runtimes/networking.md#child-processes)). |
| `(snail shell socket)` | TCP listeners and connections and UDP sockets, through the `tcp` and `udp` effects, each wait by ticket, and `endpoint`, which parses an IPv4 address and a port once ([native networking](../runtimes/networking.md)). |
| `(snail shell http)`, `(snail shell http exchange)` | An HTTP/1.1 subset: request heads and targets, response and stream heads, and one exchange over a connection ([HTTP protocol](http.md)). |
| `(snail shell resource)` | Files a library links rather than embeds: `link-bytes`, the `Resource` handle, and `read-resource` through the `resource` effect ([linked files](types.md#linked-files)). |
| `(snail shell watch)` | `inventory`, each path under some directories with a fingerprint of its kind, size and modification time, and `inventory-changes`, the paths two inventories disagree on: what a watcher reconciles when a native watch may have missed an edit. `watch-tree` and `next-hint` are Node's recursive watch of a tree, as hints that something under it changed, which only say when to take the next inventory (the `hints` effect, on Node only). |
| `(snail shell wasm)` | Loading WebAssembly modules and plugins while a program runs ([below](#loading-webassembly)). |

### Shell: applications

| Library | Contents |
| --- | --- |
| `(snail shell app)` | Applications, frames, pictures, materials and sprites, and the `screen` effect. |
| `(snail shell sprite)` | Spritebooks: animations on sheets of equal cells, posed as sprites facing the camera. |
| `(snail shell page)` | What a page's program shares, whether it draws a scene or shows a document: the `events` effect over the host's event queue, the `storage` effect of one checkpoint and `load-save`, and `app-start`, which runs the root task the host drives and answers to it through `app_outcome` and `app_handover`. |
| `(snail shell dom)` | The `dom` effect: a document's nodes as handles, built and changed by elements, text, attributes, typed properties and insertion, and listeners that declare what their events carry (`Capture`) and when the host prevents their default action (`Prevent`); a listener with chords hears only them. Selections count scalars. Commands find nodes by `id` (`element-by-id`) to focus, select or read a selection, insert text undoably, and `measure` them; on a node the view has since removed, these do nothing. `confirm` asks a question, and `window-node` is the window, which holds the interface's window listeners. `next-event` waits for the next `Delivery`: a listener `Fired` with its `Event`, `Woken` by another task's `wake`, the page `Hidden`, or the document `Closed`. It has no default: a program runs under a handler of it. |
| `(snail shell dom memory)` | `with-memory-dom`, a handler of `dom` over a document in memory that delivers a script of cues (`Fire`, `FireWindow` and `Hide`), and answers the work's value with the document it left: `document->html` prints its tree, and `document-trace` gives a line per operation. It panics where a page would forgive, at a removed node or listener used again, a node inserted into itself, or a key fired at a listener that does not hear it, so an interface's tests catch it. |
| `(snail shell dom page)` | `with-page-dom`, the handler of `dom` over the browser page's document (`host/browser/dom.mjs`), delivering the events its listeners fire, wakes, hiding and reloads from the page's event queue. |
| `(snail shell fetch)` | The `fetch` effect: `request method url headers body`, answering a `Reply` or why there was none, and streams of server-sent events of the kinds named, `stream-open`, `stream-next`, which answers a `StreamEvent`, and `stream-close`; a stream that names `error` hears each dropped connection. |
| `(snail shell fetch page)` | `with-page-fetch`, the handler of `fetch` over the page's `fetch` and `EventSource` (`host/browser/fetch.mjs`). |
| `(snail shell ui)` | [Document interfaces](applications.md#document-interfaces): `Html` and `Attribute` trees, the keyed reconciler, and `run-ui`, which runs a model, `view` and `update` with commands as tasks, the window's listeners, and messages to start with, and checkpoints the model when the page is hidden or closes. |
| `(snail shell ui page)` | `define-ui`, which hosts an interface in a page as `define-application` hosts a scene, and `Command`, the type of its commands. |

### Shell: tools

| Library | Contents |
| --- | --- |
| `(snail shell compiler)`, `(snail shell compiler …)` | The compiler, written in Snail-Core: its passes from a program's source to WebAssembly text or its wire schemas, and a session that rebuilds only what an edit changed ([compiler architecture](compilers.md)). |
| `(snail shell assembler)` | `assemble`, WebAssembly text to a binary module in-process, or the parser's message naming the line and column. Only a tool linked with the toolchain's runtime can use it: the plain runtime leaves the parser out, since a development build copies the runtime whole. |
| `(snail shell artifact)` | `artifact-bundle`, the files of a named project build, embedded when the compiler expands it ([projects](projects.md)). |
| `(snail shell format)` | Indenting and formatting Lisp source as `scripts/format-scheme` does: Emacs's indentation, each import and field on its own line, and each line whose code runs past 100 columns broken, a call before its arguments and a binding form before each binding and body form. It never joins lines. |
| `(snail shell highlight)` | Source text as tokens that tile it, classed for coloring by the compiler reader's lexical rules ([code highlighting](toolchain.md#code-highlighting)). |
| `(snail shell explore)` | Bounded model checking of a total state machine's invariant. |
| `(snail shell development)` | The project development service's decisions as a pure `step`, from the service and an event to the next service and the commands its host, `(snail shell project service)`, carries out: attempts by epoch, supersession, publication and run targets ([the development toolchain](toolchain.md)). |
| `(snail shell project files)` | The text files of one project, as `snail dev`'s editor reads and saves them: `project-text-paths`, `read-project-text`, which gives a text and its revision, the SHA-256 digest of its bytes, and `save-project-text`, which saves only over the revision it names and keeps the file's mode. The `modes` effect, on Node only, reads and sets a file's permission bits ([the development toolchain](toolchain.md)). |
| `(snail shell project service)` | `snail dev`'s service: `develop` serves one project's editor, builds and run targets on a local port, with tasks for the disk, the resident builder in a child process, each run target's process and each connection, carrying out what the step decides ([the development toolchain](toolchain.md)). |
| `(snail shell project bundle)` | A browser application's development bundle as a server mounts it: `bundle-response` answers for the latest build's page, based in its build and carrying its manifest and the reload client, and for each retained build's files under `.snail/builds/EPOCH/`; `bundle-event` is what its pages hear of a build ([browser targets in development](applications.md#browser-targets-in-development)). |
| `(snail shell project build)` | A project's build, which `snail build` and `snail run` run: `read-project`, `build-project`, which compiles, links and packages each target into a generation of its own, and `publish-project` ([projects](projects.md)). |

### Runtime interfaces

A `(snail runtime …)` library declares one host interface's Wasm imports as
externs, and nothing else, so it emits no module of its own. A shell library
imports it under the prefix `host-` and gives each operation of its effect a
default that names an extern ([defaults from the
host](effects.md#defaults-from-the-host)).

| Library | Contents |
| --- | --- |
| `(snail runtime browser screen)` | The page's drawing commands, one import per command; `(snail shell app)`'s `screen` effect defaults to them. |
| `(snail runtime browser events)` | The page's event queue and its fields, the random seed, the canvas's size and the boot report, and the started and finished wait for the next event. |
| `(snail runtime browser storage)` | Loading and storing the page's checkpoint, read back a byte at a time. |
| `(snail runtime browser dom)` | The page's document: nodes and listeners as handles, and text as UTF-8 bytes. `(snail shell dom page)` implements `dom` over it. |
| `(snail runtime browser fetch)` | The page's requests and event streams, staged a part at a time. `(snail shell fetch page)` implements `fetch` over it. |
| `(snail runtime native files)` | Node's file commands, for permission bits and watch hints. |
| `(snail runtime native socket)` | Node's TCP and UDP sockets as handles, each wait started under its ticket and answered with numbers, and the bytes an answer holds ([the native boundary](../runtimes/networking.md#wasm-boundary)). |
| `(snail runtime native process)` | Node's child processes and termination signals, answered as the sockets are, with a command sent a character at a time. |
| `(snail runtime resource)` | A linked file's length and bytes, on every host. |
| `(snail runtime wasm)` | Compiling and instantiating modules, and finding their exports, on Node. |

### Scheme

| Library | Contents |
| --- | --- |
| `(scheme base)` | R7RS names (`cons`, `car`, `vector`, `char=?` ...) over the typed language. |
| `(scheme compiler)`, `(scheme runtime)` | The R7RS translator, and the standard procedures its output calls. |

## Files and directories

`(snail core io)` reads and writes whole files, and works on the names a
filesystem keeps. Each path operation returns a `Result`, so a failure a
program can act on is a value: `(Err (NotFound))` for a missing path,
`(Err (AlreadyExists))` for a name already taken. `read-file`
and `write-file` fail the program instead; `read-text-file` and
`write-text-file` are their counterparts for a service, which must answer
each failure.

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
| `(read-text-file path limit)` | The text of the regular file at `path`, if it holds at most `limit` bytes of UTF-8, as one version of the file: its length and modification time stayed the same while it was read. A link is not followed. Else a `TextError`: `ReadFailed` with a `FileError`, `NotRegularFile`, `TooLong`, `NotText` or `ChangedWhileRead` (`tests/programs/text-files.sld`). |
| `(write-text-file path text)` | Makes the file, or replaces its contents in place. |

A `FileError` is `NotFound`, `AlreadyExists`, `NotADirectory` (a path
through a file), `PermissionDenied` or `OtherError`, and `show` describes
it. Each kind is one some program acts on; every other failure, such as
removing a directory that is not empty or a path holding a NUL, is
`OtherError`. A relative path is resolved against the working directory the
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
