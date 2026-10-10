# Node / WASI

**Implemented command platform.**
[`scripts/run-wasi.mjs`](https://github.com/tsnl/snail-scheme/blob/main/scripts/run-wasi.mjs)
loads one linked Wasm module in Node/V8 and invokes its `_start` export once.
The Rust runtime is already inside that module. Node supplies WASIp1 and the
GC finalization hook; it does not implement the Scheme port API in JavaScript.

## Module interface

This is the **linked command's perspective**: imports come from the platform;
exports belong to the command. The WASI list is the subset consumed by the
current built runtime, not a replacement for the complete WASIp1 standard.
Toolchain changes may alter that subset. Internal Scheme/Rust AWI exports are
not additional host obligations.

```wat
{{#include node.wat}}
```

The stub memory size and `unreachable` bodies only make this an assemblable
interface example. Actual memory size comes from linking the runtime. Compiled
programs require WasmGC, reference types, tail calls, mutable globals, sign
extension, and bulk memory, as selected by the build library.

## Symbols: command exports

- <a id="memory"></a>**`memory` — `(memory …)` with 32-bit indices.**
  The linked Rust runtime's linear memory. WASI buffers refer to offsets in this
  memory. The platform must use the current memory buffer after growth. Scheme
  objects reside in WasmGC; this linear memory is not their object heap.

- <a id="start"></a>**`_start` — `() -> ()`.**
  Calls the Rust reactor initializer once, then the Scheme entry `snail_main`,
  discarding its value. Run once per command instance. The final module must not
  also export `_initialize`; the build removes that export after linking.
  Normal return means success; explicit exit supplies a status.

- <a id="drop-resource"></a>**`snail:drop-resource` — `(i32 kind, i32 id) -> ()`.**
  Releases the native payload after its Scheme wrapper dies. Kind `1` denotes a
  port; its ID is instance-local and never reused. Repeated cleanup is harmless,
  unknown IDs/kinds are ignored, and cleanup errors are ignored. This does not
  run arbitrary Scheme handlers. Explicit `close-port` is the timely cleanup path.

## Symbols: collector hook

- <a id="snailhostregister-finalizer"></a>**`snail.host/register-finalizer` — `(eqref object, i32 kind, i32 id) -> ()`.**
  Watches one non-null resource wrapper and retains only its kind and ID. The
  platform must not keep a strong reference to `object`, even indirectly through
  a rooted Scheme value. When collected, the host calls `snail:drop-resource` in
  the same instance. Registering the same object replaces its previous watch.
  Finalization is nondeterministic and need not happen at shutdown.

The implementation is
[`src/runtime/host.mjs`](https://github.com/tsnl/snail-scheme/blob/main/src/runtime/host.mjs).
It also supplies an `unregister-finalizer` JavaScript helper; generated commands
currently do not import it, so it is not a required symbol in this WAT contract.

## Symbols: WASIp1 imports

All names below belong to **`wasi_snapshot_preview1`**. Except for `proc_exit`,
the result is an `i32` WASI errno: zero on success. Output parameters point into
the exported memory. Their layouts and validity rules are those of the
[WASIp1 declarations](https://github.com/WebAssembly/WASI/blob/snapshot-01/phases/snapshot/witx/wasi_snapshot_preview1.witx)
and [types](https://github.com/WebAssembly/WASI/blob/snapshot-01/phases/snapshot/witx/typenames.witx).
The Rust/WASI toolchain owns the call marshalling; these are not AWI root handles.

- <a id="args-sizes-get"></a>**`args_sizes_get` — `(i32 argc_out, i32 bytes_out) -> i32`.**
  Writes the argument count and required string-buffer size as u32 values.
- <a id="args-get"></a>**`args_get` — `(i32 argv, i32 bytes) -> i32`.**
  Fills the caller-allocated offset array and NUL-terminated argument bytes.
- <a id="environ-sizes-get"></a>**`environ_sizes_get` — `(i32 count_out, i32 bytes_out) -> i32`.**
  Writes the environment entry count and required byte-buffer size as u32 values.
- <a id="environ-get"></a>**`environ_get` — `(i32 entries, i32 bytes) -> i32`.**
  Fills the offset array and NUL-terminated `KEY=VALUE` strings.
- <a id="clock-time-get"></a>**`clock_time_get` — `(i32 clock, i64 precision, i32 time_out) -> i32`.**
  Writes a u64 nanosecond timestamp for the selected clock, with the requested
  precision. This includes the monotonic clock used by the runtime.
- <a id="fd-close"></a>**`fd_close` — `(i32 fd) -> i32`.**
  Closes a WASI descriptor, relinquishing its resource.
- <a id="fd-fdstat-get"></a>**`fd_fdstat_get` — `(i32 fd, i32 stat_out) -> i32`.**
  Writes descriptor type, flags, and rights using the WASI `fdstat` layout.
- <a id="fd-filestat-get"></a>**`fd_filestat_get` — `(i32 fd, i32 stat_out) -> i32`.**
  Writes file metadata using the WASI `filestat` layout.
- <a id="fd-prestat-get"></a>**`fd_prestat_get` — `(i32 fd, i32 prestat_out) -> i32`.**
  Describes a preopened descriptor, including its directory-name length.
- <a id="fd-prestat-dir-name"></a>**`fd_prestat_dir_name` — `(i32 fd, i32 path, i32 length) -> i32`.**
  Copies the preopened directory name into a caller-owned byte range.
- <a id="fd-read"></a>**`fd_read` — `(i32 fd, i32 iovs, i32 count, i32 read_out) -> i32`.**
  Reads into scatter buffers and writes the u32 byte count. May block or return
  a short read. The buffers remain owned by the caller.
- <a id="fd-seek"></a>**`fd_seek` — `(i32 fd, i64 offset, i32 whence, i32 offset_out) -> i32`.**
  Moves the descriptor's file position and writes the new u64 position.
- <a id="fd-write"></a>**`fd_write` — `(i32 fd, i32 iovs, i32 count, i32 written_out) -> i32`.**
  Writes gather buffers and reports a u32 byte count. May block or write fewer
  bytes than requested; a successful call is not a durability guarantee.
- <a id="path-create-directory"></a>**`path_create_directory` — `(i32 fd, i32 path, i32 length) -> i32`.**
  Creates a directory relative to a directory descriptor.
- <a id="path-filestat-get"></a>**`path_filestat_get` — `(i32 fd, i32 flags, i32 path, i32 length, i32 stat_out) -> i32`.**
  Looks up metadata relative to a directory, following the supplied lookup flags.
- <a id="path-open"></a>**`path_open` — `(i32 fd, i32 lookup_flags, i32 path, i32 length, i32 open_flags, i64 rights, i64 inheriting_rights, i32 fd_flags, i32 fd_out) -> i32`.**
  Opens a path with explicit rights/flags. On success, the output u32 descriptor
  belongs to the caller until closed. Path bytes are borrowed for the call.
- <a id="proc-exit"></a>**`proc_exit` — `(i32 status) -> ()`.**
  Terminates the command; it does not return to Wasm. With this runner's
  `returnOnExit: true`, Node's `wasi.start` returns the status to the launcher.

## Lifecycle and capabilities

The invocation is `node scripts/run-wasi.mjs MODULE.wasm [ARGUMENT ...]`. WASI
argv is the module filename followed by those arguments. Stdio uses the Node
process's descriptors. The environment is inherited, with tracing configuration
overridden by the runner. It preopens the working directory under both `.` and
its absolute path, plus `/snail-traces` when that directory can be prepared.
Trace setup failure is reported to the runtime and remains nonfatal.

Loading, compilation, and instantiation happen before `_start`. The command and
its WASI calls run synchronously. This runner supplies neither actor dispatch,
subprocess creation, connection streams, nor Scheme suspension. Separate Wasm
instances do not promise separate V8 collection pauses or enforceable `no-gc`
budgets. Those need additional runtime capabilities.

Keep the finalizer registry alive with its instance. Explicit close releases
resources promptly; process shutdown is the final cleanup boundary of this
one-command launcher. On a fatal trap, discard the failed instance. No recovery
or guaranteed destructor execution is claimed. Node's WASI preopens are also
not a secure boundary for untrusted code, as its
[WASI documentation](https://nodejs.org/api/wasi.html) explains.

## Evidence and compatibility

`wasi_snapshot_preview1` identifies the standard ABI. `snail.host` is currently
unversioned and must match the compiler/runtime checkout. A compatible V8 must
support the emitted Wasm features; unsupported imports/types fail before entry.

The current build demonstrates actual execution:

```sh
chibi-scheme -I src build.scm
scripts/test-build
scripts/test-backend
```

Those runners check linked execution and ownership; they do not establish the
planned actor scheduler or native platform. Use the real compiled module's
imports when updating this reference, rather than assuming Rust's toolchain
always emits the same WASI subset.
