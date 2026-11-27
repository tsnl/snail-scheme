# Tasks, files, processes and networks

The libraries that wait on the world. Each operation that waits suspends
the task that called it, through `(snail shell task)`, while the host does
the work; each capability is a record of its operations, so a test makes
its own ([runtimes](../runtimes/index.md)).

## `(snail shell task)`

Cooperative tasks on a scheduler, written in `snail-scheme`. A host makes
the scheduler, hands it to each turn and wake, and closes it; a program
starts tasks with `dispatch` (or `dispatch-in` a scheduler) and waits with
`yield`, `sleep` and `await`. Those stop the task wherever it is, however
deep in its calls, and the scheduler keeps the rest of it to run later. No
function between the wait and the task's start says so in its type, and
none takes anything for it ([suspension](../snail-scheme/suspension.md)).
`through-host` is how every host operation waits: it starts the operation
under a `ticket` and suspends until the host wakes it. A `Mailbox`
(`make-mailbox`, `mailbox-post`, `mailbox-receive`,
`mailbox-try-receive`) carries values between tasks.

A task runs until it finishes: nothing cancels one, and tasks that want to
stop each other arrange it, through a mailbox. `tasks-turn`, `tasks-wake!`
and `tasks-close!` are the host's side, which a program never calls.

[Task operations](../runtimes/tasks.md) and [driving the
scheduler](../runtimes/scheduling.md) describe the model in full.
[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/task.sld)

## `(snail shell async-files)`

`Files`, a capability for whole-file reads that wait as a task while other
tasks run, made by `host-files` on Node. `((● files read-file) path limit)`
reads at most `limit` bytes, up to 16 MiB, and fails as a `FileError`:
`Unavailable`, `InvalidInput`, `TooLarge`, `NotFound`, `PermissionDenied`
or `Failed`. Neither the read nor its result promises a snapshot of the
disk. Node does the read with its asynchronous file system
(`host/native/async-files.mjs`)
([native asynchronous file reads](../runtimes/tasks.md#native-asynchronous-file-reads)).

Use it rather than `(snail core io)`'s `read-bytes` when the program has
other work while a large file arrives; `read-bytes` holds the whole program.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/async-files.sld)

## `(snail shell resource)`

Files a library ships beside the program instead of embedding them, as
Python's `importlib.resources` names a package's data. `(link-file
"path")` ties the file beside the library's source to the library; the
build copies it beside the program's module and gives the program a
`Resource`. `read-resource` reads one through a `Resources`, waiting as a
task does, since a page can only fetch it, and `read-resources` reads
several at once. On secure origins the browser verifies the SHA-256 digest and stores the response in Cache Storage. The page looks up the digest before fetching. Apps on the same origin can reuse a file, and a changed file has a new digest. If the browser evicts the entry or storage is unavailable, the next read can download it again.

`Resource` is exported without its constructor, so holding one is evidence
that its file ships ([linked files](../snail-scheme/types.md#linked-files)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/resource.sld)

## `(snail shell static-resource)`

`fetch-catalog` takes a `Fetch` and a catalog URL and returns a `Result` containing named `StaticFile` records. Pass the same URL and the desired files to `acquire-files` with the browser’s `StaticResources` capability. It returns a table of verified bytes by name or an error identifying the failed file. A progress callback receives `StaticProgress` with `downloaded`, `cached` and `total` byte counts. The first two add up to the completed portion. The total counts each distinct digest once and uses uncompressed byte lengths, including when HTTP omits Content-Length.

```scheme
(match (fetch-catalog fetch "resources.json")
  ((Err why) (Err why))
  ((Ok files) (acquire-files store "resources.json" files show-progress)))
```

On HTTPS or localhost the browser looks up each digest in Cache Storage, promotes verified entries from the earlier IndexedDB cache, and counts incoming response bytes when it needs a download. An interrupted or invalid response never enters the cache. If storage fills up, the current run can still use the verified response. The page, Wasm and small catalog load on navigation. An offline application shell requires separate handling. Saved application state continues to use IndexedDB.

Above 25 MiB the browser fetches numbered parts in order. Progress counts bytes across part boundaries. The browser checks each length and the SHA-256 of the complete file before storing it. Each cache entry holds at most 26,214,400 bytes. Writing part zero last marks a multipart entry complete. A retry after an interrupted download starts with the first part. Older whole-file entries and 25,000,000-byte parts migrate on read, including offline. When the first request returns HTTP 404, the browser can try an older publisher’s layout.

For a Snail HTTP server, call `static-resource-service` from `(snail shell static-resource serve)` once with the server’s `Resources` and the linked path/resource pairs for the bundle. The returned function takes the request method and decoded path segments relative to the mount. It answers `Some Response` for a known catalog or object on GET or HEAD, and `None` lets the server try its next route. The HTTP exchange writes the correct HEAD framing. [Publishing a catalog](../snail-scheme/scripts.md#static-resource-catalogs) · [Linking a client build into a server](../snail-scheme/workspaces.md#embedding-a-build)

## `(snail shell blob-store)`

The compiler, build tools and archive cache share a disk format for immutable bytes. A file at or below 25 MiB occupies one object. Larger files occupy as many numbered parts as needed under the digest of the complete file. An exact multiple has a full final part.

`store-file!` accepts the filesystem, store root, source path, byte length and an optional expected SHA-256. It reads a file in bounded pieces and returns its hexadecimal digest. Supplying the known digest lets a build reuse existing parts. `put-blob!` accepts an in-memory byte array. `read-blob` takes a digest and byte length and returns the verified bytes when available. Reading a complete file into a Snail byte array is subject to the runtime’s array length limit. Programs can fold a file one buffer at a time with `fold-file-chunks` from `(snail core io)`.

## `(snail shell process)`

Child processes, as the capability `Processes`, made by `host-processes`:
spawn a `Command` with piped standard streams and read its output, write
and close its input, signal it and wait for its `Exit` (`Exited` or
`Signaled`); `run` a command to its end and answer what it `Captured`; or
`exec` one in place of the program. `Signals`, made by `host-signals`,
answers the termination signal the program was sent
([child processes](../runtimes/networking.md#child-processes)).

Stage 0's tool runner on Chez, `host/chez/snail/stage0/process.sls`, has
the same name; Chez never sees `src/`.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/process.sld)

## `(snail shell socket)`

TCP and UDP as the capabilities `Tcp` and `Udp`, made by `host-tcp` and
`host-udp`: listen, accept, connect, read, write and finish a `Connection`,
and bind, send and receive `Datagram`s on a `UdpSocket`. An `Endpoint` is
parsed once, by `endpoint`; the type is exported without its constructor,
so holding one is evidence that its address is IPv4 and its port in range,
and nothing checks either again ([native networking](../runtimes/networking.md)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/socket.sld)

## `(snail shell http)`

A deliberately bounded subset of HTTP/1.1: ASCII heads, origin-form targets,
`Content-Length` bodies, one exchange per connection, and response streams
that end when the connection closes. `parse-request-head` and
`parse-target` read a request, `encode-response` and `encode-stream-head`
write the answer, and `head-limit` and `body-limit` bound what is read; an
`HttpError` says why a request was refused
([HTTP protocol](../snail-scheme/http.md)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/http.sld)

## `(snail shell http exchange)`

One request and its response over a `Tcp` connection. `serve-one` is the
whole exchange with one handler. A server that chooses between reading and
answering calls the halves itself: `read-request`, then `respond`, which
needs only the request's method, so a server can answer a request it could
not read. A failure of either leaves the connection open for the caller to
close, as `serve-one` does.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/http/exchange.sld)

## `(snail shell web)`

`Web`, the web as a program on Node reads it, made by `host-web`:
`((● web size) url)` answers the length of the file at a URL, and
`((● web parts) url spans)` the bytes of each `Span` of it, asked for
together, each a GET with a Range header. Node's fetch makes the requests
(`host/native/web-imports.mjs`), over HTTPS or HTTP, following redirects,
while the task that asked waits. A server must answer a part with exactly
its bytes: one that answers with the whole file is stopped before its body
comes, so a program can read a few megabytes of a file of many gigabytes,
as `(snail shell web zip)` does. The page's requests are `(snail shell
fetch)`'s.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/web.sld)

## `(snail shell web zip)`

Zip archives on the web, read a member at a time and kept in the machine's
cache, for the recipes of generated libraries. A `WebZip` names an archive
by its URL and pins it by the SHA-256 of its end: its directory and the
records after it, which give every member's name, length, CRC-32 and
place. `zip-members` answers, for each member whose name a predicate
takes, the path of its file in the cache, reading those not yet there
eight at a time, checked against the pinned directory's CRC-32:

```text
CACHE/zip/PIN.end       a pinned archive end up to 25 MiB
CACHE/zip/PIN.end.size  the byte length of a larger end in CACHE/zip/store/
CACHE/zip/PIN/NAME   each member read, by its name in the archive
```

The pin is what makes the cache correct. A file in the cache was read
from the archive the pin names, whatever its server later serves, so a
build that finds it there needs no network and any checkout on the
machine may share it. A server whose archive has another end fails the
build, naming the digest it has. `machine-cache` is `snail-scheme` in
`$XDG_CACHE_HOME`, or `~/.cache/snail-scheme`. Each file is written in a
folder made beside its place, which no other writer can share, and renamed
into it, so a reader never sees part of one. Nothing reclaims the cache:
deleting it costs only fetching again.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/web/zip.sld)

## `(snail shell wasm)`

WebAssembly modules loaded while a program runs, through the capability
`Wasm` both targets provide. `compile-bytes` compiles a module,
`module-imports` lists its imports, and `link-module` takes one `Provider`
per import, in order: `(ExportOf instance name)`, an instance's export;
`(HostProvided)`, a host service; `(ConstantOf n)`, a constant function; or
`(Unprovided)`, a function that traps if called. A provider that is missing
or does not fit answers `LinkFailed`. Linking runs `_initialize` when the
module has one.

`module-export` answers an untyped `Funcref`, and `unsafe-cast` makes it an
`Fn` at the type the caller asserts: WebAssembly's cast checks the
representation, not `snail-scheme`'s nominal types, so the caller
establishes that contract. `run-export` calls a scalar export by name
([linking by hand](../snail-scheme/compilers.md#linking-by-hand)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/wasm.sld)

## `(snail shell explore)`

Bounded model checking of a total state machine: from an initial state,
`explore` applies every move each state allows, breadth first up to a
depth, and answers the first state that breaks the invariant as a
`Violation`, with the moves that reach it. States are identified by their
wire encoding (`(snail shell wire)`), so each is checked once and the path
reported is a shortest one.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/explore.sld)
