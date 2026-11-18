# Libraries

## Standard library

The language libraries live under `src/`, with paths matching their names.
Core imports only core; runtime interfaces import core; the shell builds on
both. The compiler is among the shell libraries and is itself typed `snail-scheme`
Scheme. Chez stage zero executes only its explicit host-adapted source
closure, not arbitrary shell or application libraries.

### Core

`(snail core …)` imports nothing outside itself. The compiler imports only
its `base`, `table` and `io`, so it can compile itself.

| Library | Contents |
| --- | --- |
| `(snail core forms)` | The core forms, the builtin types, and the builtin `mut` and `host` effects. The compiler serves it; it has no file. |
| `(snail core primitive)` | The operations the backend implements, each declared with its type by `(primitive name type)`. `(snail core base)` gives most of them their everyday names. |
| `(snail core base)` | Forms, numeric classes, `Option`, `Result`, `Pair`, `Never`, lists, arrays, constant arrays, strings, `Show` and `Repr`. |
| `(snail core io)` | The `input-port`, `output-port`, `fs` and `clock` effects: [current textual ports and value representations](#current-input-and-output-ports), files as text or bytes, [directories and names](#files-and-directories), and a monotonic clock; and, as total reads, `command-line`, `environment-variable` and `working-directory`. |
| `(snail core table)` | Immutable tables from strings to values. |

### Shell: data and text

`(snail shell …)` is everything else, written in `snail-scheme` over core and
the runtime interfaces.

| Library | Contents |
| --- | --- |
| `(snail shell math)` | Elementary functions on `F64`, ported from fdlibm as Rust's libm crate carries it, and equal to libm's bit for bit. |
| `(snail shell text)` | Unicode character properties, case mapping and decimal digit values, read from the constant arrays of `(snail shell text unicode)`, which `make unicode-tables` generates from Rust's Unicode properties. |
| `(snail shell random)` | A deterministic generator as a value. |
| `(snail shell utf8)` | `string->utf8`, and `utf8->string`, which rejects ill-formed bytes as a fatal `TextDecoder` does, giving the offset of the first bad sequence. |
| `(snail shell compiler sha256)` | `sha256` over bytes, giving the 32-byte digest, and `bytes->hex`, the lowercase hex Node's `digest('hex')` writes; the compiler names linked files with it, the same on stage 0 as in Wasm. |
| `(snail shell json)` | The `Json` value, with integer numbers and objects as ordered members, and `json->string`, which writes what `JSON.stringify` writes for the same value. |
| `(snail shell json read)` | `string->json`, which reads JSON text whose numbers are integers back as a `Json`, and `json-member`. A library of its own, so that a program that only writes JSON does not carry it. |
| `(snail shell wire)` | `Serialize`, `Deserialize` and the byte encoding. |
| `(snail shell syntax)` | The syntax a `generate-library` recipe returns, and the bytes its producer writes. |

### Shell: system and network

| Library | Contents |
| --- | --- |
| `(snail shell task)` | The `tasks` effect and its scheduler, written in `snail-scheme`: local dispatch, cooperative yield, timer and ticket waits, waiting on the host, and `Mailbox` queues between tasks ([task operations](../runtimes/tasks.md)). |
| `(snail shell async-files)` | Explicit native `files` capability for bounded asynchronous reads, backed by Linux `io_uring` or Node's asynchronous filesystem APIs ([file reads](../runtimes/tasks.md#native-asynchronous-file-reads)). |
| `(snail shell process)` | Child processes with piped standard streams, through the `process` effect: `spawn`, reading output, writing and closing input, signals and exit, `run` to run a command to its end, and `exec` to replace the program with one; and `termination`, SIGINT or SIGTERM as a value, through the `signals` effect ([child processes](../runtimes/networking.md#child-processes)). |
| `(snail shell socket)` | TCP listeners and connections and UDP sockets, through the `tcp` and `udp` effects, each wait by ticket, and `endpoint`, which parses an IPv4 address and a port once ([native networking](../runtimes/networking.md)). |
| `(snail shell http)`, `(snail shell http exchange)` | An HTTP/1.1 subset: request heads and targets, response and stream heads, and one exchange over a connection ([HTTP protocol](http.md)). |
| `(snail shell resource)` | Files a library links rather than embeds: `link-file`, the `Resource` handle, and `read-resource` and `read-resources`, which a task waits on, through the `resource` effect ([linked files](types.md#linked-files)). |
| `(snail shell wasm)` | Explicit WebAssembly linking for the engine ([below](#loading-webassembly)). |

### Shell: applications

| Library | Contents |
| --- | --- |
| `(snail shell app)` | `SceneHandler` and `run-scene`, a canvas application's loop, which draws through `gpu`; 3D frames of mesh batches and `draw-frame`, which draws them. |
| `(snail shell gpu)` | The `gpu` effect: WebGPU's operations and descriptors, each object a handle the program keeps across frames until it calls `destroy`; `(snail shell gpu host)` runs it on the host's device, the page's or Dawn's on Node, and `(snail shell gpu record)` records it ([WebGPU](../graphics/plan.md)). |
| `(snail shell graphics pod)` | `Pod`, which a record without parameters derives: its `Shape` gives the WGSL struct declaration, size, alignment and vertex attributes, and `pack` writes values as WGSL lays them out. `Vec2f` to `Mat4x4f` are WGSL's vectors and matrix. |
| `(snail shell graphics wgsl)` | Shaders as S-expressions, printed to WGSL by `shader-library`, a `generate-library` recipe's library of shader texts. |
| `(snail shell graphics atlas)` | Pictures of layered image regions with color swaps, composed on the GPU into padded slots of texture-array pages; `atlas-url` reads a region back as a PNG data URL. |
| `(snail shell graphics quad)` | 2D quads in world units under a 2D camera, pixel-snapped, each a tinted region of a texture-array page; a run of quads is one instanced draw. |
| `(snail shell graphics mesh)` | Eight shapes in one geometry table, `Pod` instances packed by shape, and one indirect draw per shape from its own first instance. |
| `(snail shell graphics raster)` | Cameras with their inverses, a G-buffer of albedo, normal, material and depth, with screen motion and instance ids when its `Planes` ask, mesh instances rasterized into it, and translucent ones lit at once over what is drawn. |
| `(snail shell graphics passes)` | Full-screen passes: `draw-sun` lights a G-buffer under the sun, in the pass `begin-lit` opens over a background, into an HDR light target that `draw-post` tone-maps and smooths with FXAA into the canvas. |
| `(snail shell tensor)` | Lazy tensor graphs of nodes and views (offset, shape, pitch), built by `Num`, `Fractional` and torch-like operations; `(snail shell tensor grad)` adds reverse-mode gradients, `(snail shell tensor adam)` Adam's step, `(snail shell tensor compile)` compiles a graph into WebGPU dispatches run by `run-program`, and `(snail shell tensor eval)` evaluates it on the CPU ([tensors](../graphics/tensors.md)). |
| `(snail shell png)` | `rgba->png`, PNG files of RGBA pixels with stored zlib blocks, and `png-data-url`. |
| `(snail shell sprite)` | Spritebooks: animations on sheets of equal cells, by motion and heading; `cell-at` is the cell a strip shows at a moment. |
| `(snail shell page)` | The shared browser lifecycle: `run-page` boots from the page's save, or fresh, and saves. The `events` and `storage` effects bind the host's queue, readiness, save timer and persistence. |
| `(snail shell dom)` | The `dom` effect: a document's nodes as handles, built and changed by elements, text, attributes, typed properties and insertion, and listeners that declare what their events carry (`Capture`) and when the host prevents their default action (`Prevent`); a listener with chords hears only them. Selections count scalars. Commands find nodes by `id` (`element-by-id`) to focus, select or read a selection, insert text undoably, and `measure` them; on a node the view has since removed, these do nothing. `confirm` asks a question, and `window-node` is the window, which holds the interface's window listeners. `next-event` waits for the next `Delivery`: a listener `Fired` with its `Event`, `Woken` by another task's `wake`, a `SaveRequested`, the page `Hidden`, or the document `Closed`. It has no default: a program runs under a handler of it. |
| `(snail shell dom memory)` | `with-memory-dom`, a handler of `dom` over a document in memory that delivers a script of cues (`Fire`, `FireWindow` and `Hide`), and answers the work's value with the document it left: `document->html` prints its tree, and `document-trace` gives a line per operation. It panics where a page would forgive, at a removed node or listener used again, a node inserted into itself, or a key fired at a listener that does not hear it, so an interface's tests catch it. |
| `(snail shell dom page)` | `with-page-dom`, the handler of `dom` over the browser page's document (`host/browser/dom.mjs`), delivering the events its listeners fire, wakes, hiding and reloads from the page's event queue. |
| `(snail shell fetch)` | The `fetch` effect: `request method url headers body`, answering a `Reply` or why there was none; `fetch-bytes url`, a GET's body as `Bytes` or why there was none; `page-address`, the page's URL; and streams of server-sent events of the kinds named, `stream-open`, `stream-next`, which answers a `StreamEvent`, and `stream-close`; a stream that names `error` hears each dropped connection. |
| `(snail shell fetch page)` | `with-page-fetch`, the handler of `fetch` over the page's `fetch` and `EventSource` (`host/browser/fetch.mjs`). |
| `(snail shell files)` | The `files` effect: the files a user hands the program, each a `Chosen` path within the choice and an address `fetch-bytes` reads. `open-picker` asks the user for `SomeFiles` or a `Folder` without waiting; a `FilesEvent` says files were dropped or picked, and `chosen-files` lists the latest choice. |
| `(snail shell files page)` | `with-page-files`, the handler of `files` over the page's pickers and drops (`host/browser/files.mjs`). |
| `(snail shell ui)` | [Document interfaces](applications.md#document-interfaces): `Html` and `Attribute` trees, the keyed reconciler, and `run-ui`, which runs a model, `view` and `update` with commands as tasks, the window's listeners, and messages to start with, commits completed presentations, and saves on request, hiding or close. |
| `(snail shell ui page)` | `InterfaceHandler` and `run-interface`, a document application's loop, and `Command`, the type of its commands. |

### Shell: tools

| Library | Contents |
| --- | --- |
| `(snail shell compiler)`, `(snail shell compiler …)` | The compiler, written in `snail-scheme`: its passes from a program's source to WebAssembly text, with every build checking and emitting the complete dependency closure ([compiler architecture](compilers.md)). |
| `(snail shell assembler)` | `assemble`, WebAssembly text to a binary module in-process, or the parser's message naming the line and column. Only a tool linked with the toolchain's runtime can use it: the plain runtime leaves the parser out, since a development build copies the runtime whole. |
| `(snail shell format)` | The formatter `scripts/format-scheme` and `snail-scheme lsp` share: conventional Scheme indentation, each import and field on its own line, and each line whose code runs past 100 columns broken, a call before its arguments and a binding form before each binding and body form. Names `let`, `let*`, `*-let` and `*-let*` use binding layout. It never joins lines. |
| `(snail shell highlight)` | Source text as tokens that tile it, classed for coloring by the compiler reader's lexical rules ([code highlighting](toolchain.md#code-highlighting)). |
| `(snail shell explore)` | Bounded model checking of a total state machine's invariant. |
| `(snail shell lsp)` | `snail-scheme lsp`: `serve-language` answers the Language Server Protocol on standard streams for one project, with diagnostics from each saved build, formatting, and hover and definition from its checked libraries ([editors](toolchain.md#editors)). |
| `(snail shell project web-app)` | Default installable web manifests and their page links, for browser packaging. |
| `(snail shell project build)` | A script's build, which `snail-scheme build` and `snail-scheme run` run: `build-script`, which compiles, links and packages it into a generation of its own and publishes it, and `check-script` and `check-library`, which the language server checks with ([builds](projects.md)). |

### Runtime interfaces

A `(snail runtime …)` library declares one host interface's Wasm imports as
externs, and nothing else, so it emits no module of its own. A shell library
imports it under the prefix `host-` and exports a handler of its effect,
`provide-NAME`, that answers each operation with an extern, for its
targets to install ([handlers from the host](effects.md#handlers-from-the-host)).

| Library | Contents |
| --- | --- |
| `(snail runtime browser events)` | The page's event queue and its fields, the random seed, the canvas's size and the boot report, and the started and finished wait for the next event. |
| `(snail runtime browser storage)` | Loading and storing the page's checkpoint, read back a byte at a time. |
| `(snail runtime browser dom)` | The page's document: nodes and listeners as handles, and text as UTF-8 bytes. `(snail shell dom page)` implements `dom` over it. |
| `(snail runtime browser fetch)` | The page's requests and event streams, staged a part at a time. `(snail shell fetch page)` implements `fetch` over it. |
| `(snail runtime browser files)` | The page's pickers, opened without waiting, and its latest choice of files, listed a scalar at a time. `(snail shell files page)` implements `files` over it. |
| `(snail runtime gpu)` | The host's WebGPU device, the page's or Dawn's on Node: each object a handle, a descriptor staged as words and texts, and the device, reads and decodes waited for by ticket. `(snail shell gpu host)` implements `gpu` over it. |
| `(snail runtime native socket)` | Node's TCP and UDP sockets as handles, each wait started under its ticket and answered with numbers, and the bytes an answer holds ([the native boundary](../runtimes/networking.md#wasm-boundary)). |
| `(snail runtime native process)` | Node's child processes and termination signals, answered as the sockets are, with a command sent a character at a time. |
| `(snail runtime resource)` | A linked file's bytes, read on every host when a task asks for them. |
| `(snail runtime wasm)` | Compiling and instantiating modules, and finding their exports, on Node. |

There are no `(scheme …)` compatibility libraries or dynamic numeric tower.

`(list-sort before? items)` in `(snail core base)` sorts an immutable list
with a pure strict comparator. It is stable: items for which neither
precedes the other retain their input order. A merge sort bounds comparisons and
traversal by O(n log n); the compiler and project builder use this
same operation. Stage 0 supplies the corresponding stable sort on Chez.

## Current input and output ports

The current textual input and output are independent effect bindings.
`input-port` supplies `(read-char) → (Option Char)`; `output-port` supplies
`(write-string text) → Unit`. The targets' handlers, `provide-input-port` and
`provide-output-port`, use standard input and standard output. A handler selects a different stream for its body, including calls
made by that body. When the handler ends, the previous binding applies again.
This gives current ports the dynamic scope of
[Scheme's current ports](https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-8.html#node_sec_6.13.1)
through ordinary effect handlers.

`read-char` consumes one Unicode character, returning `None` at EOF.
`read-line` uses the same operation and returns the next line without its LF:
an empty line is `(Some "")`, EOF after a partial line returns that line,
and EOF before any character is `(None)`. Other characters, including CR,
are preserved. Both reads perform only `input-port`; standard-input reads
flush pending standard output before waiting, so prompts appear.

```scheme
(handle input-port
    ((read-char (lambda () (None))))
  (write (read-line))) ; prints (None) through the current output
```

An output handler receives complete strings. It can collect them, discard
them, or forward them to the enclosing output binding. Input keeps its own
binding throughout:

```scheme
(handle output-port
    ((write-string (lambda (text)
                     (write-string (string-append "[" text "]")))))
  (write (Some "hello"))) ; prints [(Some "hello")]
```

`(display value)` prints the text chosen by its `Show` instance. Scalars have
standard instances; containers such as `Option`, lists, arrays, `Result`
and `Pair` require an explicit presentation instance.
`(write value)` prints its `Repr` representation: strings keep quotes and
escapes, characters use `#\` notation, and containers represent their
elements recursively. Both perform `output-port` and append no newline;
`(newline)` adds one.
The socket library has its own `write`; import `(except (snail core io) write)`
when only the socket operation is needed, or rename one of them.

```scheme
(display "hello")        ; prints hello
(write (Some "hello"))   ; prints (Some "hello")
(write (list "a" "b"))   ; prints ("a" "b")
```

`(display (Some "hello"))` is a compile error without an explicit `Show`
instance. Use `write` for the container's representation, or match and
display its contents to choose the presentation. This prevents a string's
quotes from disappearing inside a container's printed notation.

`(repr value)` returns the same representation as a `String`, without
effects. `(snail core base)` supplies `Repr` instances for numeric scalars,
booleans, characters, strings, `Unit`, lists, arrays, `Option`, `Result`
and `Pair`. Lists use `(element ...)`, arrays use `#(element ...)`, and
the other containers name their constructors, such as `(Some "hello")`
or `(new Pair (first 1) (second "one"))`.

A record or enum can request constructor notation with `(deriving Repr)`:

```scheme
(enum Action
  (Rock)
  (Paper)
  (Scissors)
  (deriving Repr))

(write (Rock)) ; prints (Rock)
```

Deriving generates a pure instance that matches each constructor and
represents its fields in declaration order. Generic type parameters require
`Repr`. Records print named construction syntax, `(new Name (field value) ...)`; enum
cases keep positional notation.
An explicit `(instance (Repr T) (define repr (lambda (value) ...)))` chooses custom
notation. A `Show` instance alone does not supply `Repr`; missing instances
are compile errors.

`(snail shell write)` supplies `Repr Any` using its existing Scheme datum
printer, so `(write datum)` replaces `(write-string (datum->string datum))`.
Translated Scheme's `write` uses this same operation. Foreign values in
`Any` retain the datum printer's `#<opaque>` notation; deriving does not add
runtime reflection. Constructor notation describes a typed value but does
not promise that the Scheme reader reconstructs its original type.

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
| `(make-hard-link existing path)` | Another name for a file, which is not copied; it fails across file systems. |
| `(read-text-file path limit)` | The text of the regular file at `path`, if it holds at most `limit` bytes of UTF-8, as one version of the file: its length and modification time stayed the same while it was read. A link is not followed. Else a `TextError`: `ReadFailed` with a `FileError`, `NotRegularFile`, `TooLong`, `NotText` or `ChangedWhileRead` (`tests/programs/text-files.sld`). |
| `(write-text-file path text mode)` | Whole-text write with mandatory `WriteMode`: `CreateNew` refuses existing leaves (including dangling symlinks), `ReplaceExisting` refuses missing files, and `CreateOrReplace` permits either. Creating an empty file is writing `""` with `CreateNew`. |

A `FileError` is `NotFound`, `AlreadyExists`, `NotADirectory` (a path
through a file), `PermissionDenied` or `OtherError`, and `show` describes
it. Each kind is one some program acts on; every other failure, such as
removing a directory that is not empty or a path holding a NUL, is
`OtherError`. A relative path is resolved against the working directory the
host passes, which `(working-directory)` gives, or `None` on a host with no
filesystem. `(environment-variable name)` is a variable of the environment the
program started with, or `None` when it is unset; the host's own channel for
the working directory, `SNAIL_CWD`, reads as unset. The runtime performs each operation through WASI preview1
(`crates/snail-scheme-support/src/paths.rs`); a page has no preopened directory, so every
path operation there fails with `OtherError`. WASI preview1 has no file
modes or owners; it reports device and inode numbers and a status-change
time, but Rust's standard library exposes them on WASI only as unstable
API, so `FileStatus` has none of these yet.
`(monotonic-nanoseconds)`, of the `clock` effect, reads WASI's monotonic
clock, from an origin the host chooses; only differences mean anything.

## Loading WebAssembly

`(snail shell wasm)` supplies the engine's explicit linker on Node and in
the browser. Compile bytes with `compile-bytes`, inspect `module-imports`, then
supply `link-module` with one provider per import. `(ExportOf instance name)`
selects an export, `(HostProvided)` selects a host service, `(ConstantOf n)`
provides a constant function, and `(Unprovided)` traps if called.

`module-export` returns a `Funcref`; `unsafe-cast` constructs an `Fn` at the
caller's asserted type. `run-export` calls a scalar export directly.
`LoadError` has two cases: `LinkFailed` and `MissingExport`.
`loading-program` refers to the loader, and `bind-runtime` selects the loaded
program's runtime for staging memory. See [linking by hand](compilers.md#linking-by-hand).

## Wire types

`(deriving Serialize Deserialize)` at the end of a record or enum generates
instances of `(snail shell wire)`'s classes. `serialize` writes a value as bytes and
`deserialize` reads it back:

```scheme
(record Point
  ((x I64)
   (y I64))
  (deriving Serialize Deserialize))

(ann (deserialize (serialize (new Point (x 1) (y 2)))) Point)
```

Each record and enum case has a 32-bit TypeId hashed from its library, name
and field schema. Every record or enum value is written as its case's TypeId
followed by its fields, so reading data written for another schema fails at
the first changed type instead of misreading it.
