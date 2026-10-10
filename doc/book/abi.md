# The ABI

The ABI describes how compiled Scheme, the Rust runtime, and a platform call one
another. Wasm signatures are the reference notation. Native compilation gives
those signatures an explicit mapping to the target C ABI.

**Implemented:** scalar [AWI extension calls](awi.md) in linked Wasm and the
[native CLI](platforms/native-cli.md), including direct linkage to Rust's native
archive. **Planned:** native and browser GUI hosting, multiple native instances,
and actor connections. AWI remains the extension boundary; the supported
functions come from Snail's runtime. There is no arbitrary Rust extension
packaging.

| Output | Scheme compilation | Rust compilation | Linkage |
| --- | --- | --- | --- |
| Bootstrap Wasm, current | Scheme → WasmGC | Rust → Wasm | Merge the modules for the existing test runner. |
| Browser, planned | Scheme → WasmGC | Rust → browser-compatible Wasm | Link with the browser bindings; the browser owns DOM access. |
| Native CLI, current | Scheme → WasmGC → LLVM → native object | Rust → native library | Resolve runtime calls using the target C ABI. |

The native route can translate the Scheme module while its runtime calls remain
imports. It need not translate Rust's Wasm output or link the runtime twice.
Translating an already linked Wasm module is also implemented;
it does not establish this native Rust linkage by itself.

## Values and ownership

| Meaning | Wasm type | Native C representation |
| --- | --- | --- |
| Signed/unsigned scalar | `i32` | `int32_t` / `uint32_t`, as declared |
| Signed/unsigned scalar | `i64` | `int64_t` / `uint64_t`, as declared |
| Floating-point scalar | `f32`, `f64` | Matching-width `float`, `double` |
| Owned or borrowed Scheme root | `i32` | Opaque `uint32_t` handle |
| Resource ID | `i32` | Opaque `uint32_t`, in a stated instance/resource domain |
| Linear-memory range | `i32` offset and length | The same offsets, resolved against the selected instance's memory |
| Internal GC reference | `anyref`, `eqref`, typed references | Collector-managed representation; an adapter roots it before a runtime C call |

An `i32` does not reveal whether it is an integer, root, or offset. Each symbol
must state that meaning. An offset is never converted into a native pointer by
casting it. A root is never a network ID. External storage can use explicit
64-bit offsets without enlarging the Scheme heap's addressing model; checked
binary copying is a separate operation from passing a message.

AWI keeps Scheme values in a GC-visible table. The Rust runtime borrows the root
of an argument vector and returns one owned root. Accessors returning children
create separately owned roots; retaining allocates another slot and releasing
invalidates that slot. Slots can be reused, so stale integers are unsafe. Rust's
`Root` expresses ownership and prevents transfer between threads. Raw handles
must also remain within the instance that allocated them.

`anyref` and `eqref` remain meaningful Wasm types. They do not acquire a portable
C pointer representation just because native objects happen to use pointers.
The current finalization hook, described beside `extension` in the
[AWI interface](awi.md), takes a GC reference. Its native adapter needs collector
integration, not a scalar bitcast.

Use `extern "C"` for function calling conventions and explicit unmangled symbols
for native linkage. `#[repr(C)]` describes exposed data layout; it does not select
a function calling convention. The first ABI uses scalars and handles, avoiding
platform-sized integers, Rust containers, aggregate returns, and raw callbacks.
[Rust's function ABI](https://doc.rust-lang.org/reference/items/external-blocks.html#abi),
[symbol linkage](https://doc.rust-lang.org/reference/abi.html#the-no_mangle-attribute),
and [data layout](https://doc.rust-lang.org/reference/type-layout.html#the-c-representation)
have distinct roles.

## Calls stay inside an actor; connections cross actors

An ABI call is local to one instance. Scheme callbacks may allocate and reenter
Rust; roots must remain live, and Rust cannot hold a borrow or lock that the
callback could reacquire. The current call returns synchronously. It cannot
suspend or unwind through arbitrary Rust/C frames. A fatal trap can bypass Rust
destructors, so the failed instance must be discarded.

Actor connections have a separate protocol. Typed message declarations should
derive S-expression encoders and decoders, including validation; received forms
are data and are never evaluated. Copying applies even within one process. A
GPU buffer reference or database key can travel in a message when both endpoints
agree on its namespace, access, and lifetime. Bulk textures and model weights
need not be serialized for every invocation.

An actor owns its heap, globals, and resources. Each connection endpoint owns
its pending calls or streams. Spawning creates a subordinate and establishes
supervision; connecting selects an existing recipient without acquiring its
lifetime. A platform's control service can expose spawning through that same
model. An OS subprocess can participate through an adapter for its streams and
completion; the executable need not understand Scheme messages itself.

The current native CLI deliberately hosts one instance per OS process. A future
host supporting several actors in one process must preserve per-instance state.
One process-global root table or
unscoped thread-local port table is insufficient when several actors share a
thread. Native entry must select the correct instance and restore that context
across callbacks; future suspension needs an equally explicit contract.

## Compatibility

The current `snail.awi`, `snail.rust`, and `snail.host` names are unversioned
implementation interfaces. AWI is informally v0. The platform pages record that
fact; this book does not introduce a version negotiation implementation.

Artifacts should eventually identify required ABI revisions and Wasm features,
independently of an engine's release. Reject unsupported requirements before
entry. A platform page records exact symbol names, signatures, ownership, effects,
and lifecycle. Breaking changes to those rules require a matching compiler and
runtime change; future artifact metadata must make that match explicit.
