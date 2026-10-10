# Application Wasm interface (AWI)

Wasm is the substrate. Rust extensions compile to Wasm and link with the Scheme
module. Native execution is a subsequent translation step, not a different
extension ABI. AWI v0 consists of named Wasm functions using scalar parameters
and opaque root handles; it is not a standardized Component Model interface.

## Calling Scheme and Rust

Each exported Scheme-callable Rust function accepts one `u32` borrowed
argument-vector handle and returns one `u32` owned result handle. Functions have
separate import/export names, `snail:<Scheme-name>` in module `snail.rust`.
There is no builtin-number dispatcher. The prefix avoids collisions with libc
symbols such as `exit` and `write`.

The single Rust runtime crate exposes ordinary scalar C-ABI functions with
explicit Wasm export names. There is no procedural macro or implicit conversion:

```rust
#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:example"))]
pub extern "C" fn example(raw: u32) -> u32 {
    let args = unsafe { crate::awi::Arguments::borrow(raw) };
    args.check("example", 1, 1).expect("wrong argument count");
    args.get(0).expect("missing argument").into_handle()
}
```

`src/awi.rs` supplies checked conversion and root ownership. `Root::call` makes
a synchronous Scheme callback, which may allocate and reenter Rust. Do not hold
a `RefCell` borrow or a lock that the callback could reacquire. Existing roots
remain in the GC table across callbacks. Scheme `apply` and `call-with-values`
remain in Wasm so tail calls do not retain Rust frames.

The [example](../examples/extension/README.md) lives in `src/interop_example.rs`
and is built into the standard runtime. Its Scheme build script supplies an
alist mapping callable Scheme names to the `"snail.rust"` Wasm import module.
Those names are exposed through `(snail-scheme extensions)`. This naming scope
does not imply dynamic loading or a separate Rust crate. Independent extension
packaging is deferred; all current Rust services share one runtime linear memory.

Cargo builds/reuses the root runtime crate as Wasm. The runtime exports
`_initialize`; the linked entry invokes it once before Scheme executes.

## Root contract

`src/runtime/awi.wat` owns a table of GC references and a free list of reusable slots.
An integer handle does not itself retain a value: the corresponding live table
slot does. The SDK's `Root` owns exactly one slot in the current instance.

- `Arguments` borrows the caller's rooted vector for the exported call.
- `Arguments::get` and child accessors return separately owned roots.
- `Root::clone` retains a separate slot; `Drop` releases that slot.
- `Root::into_handle` transfers ownership to the Scheme caller.
- `Root::from_handle` is unsafe: the handle must be live, instance-local, and
  exclusively owned. Raw handles are not generation-checked durable IDs.
- Roots cannot cross threads or instances. A fatal trap can bypass Rust cleanup;
  discard the failed instance instead of promising recoverable trap cleanup.

Scalar helpers are imported from `snail.awi`. They construct and inspect Scheme
values while keeping the references in engine-visible locals or table slots.
Rust strings, files, vectors, and other ordinary Rust allocations use Rust's own
allocator. Copying into a Scheme string constructs WasmGC data and leaves the
Rust allocation to normal Rust ownership. Rust's substring search copies only
the search pattern and accesses the Scheme haystack by Unicode scalar index.

## External resources and finalization

An extension wrapper contains a resource kind and ID, not a native address or
Rust trait object. The initial runtime reserves kind 1 for ports; IDs are never
reused. Current ports have durable roots. Explicit `close-port` closes promptly;
an output-string port remains readable after close until its wrapper dies.

AWI imports `snail.host/register-finalizer(object, kind, id)`. The browser/Node
implementation in `src/runtime/host.mjs` uses `FinalizationRegistry`, holding only
resource IDs. Cleanup invokes `snail:drop-resource`; the Rust implementation
drops the port payload and marks its slot closed. Repeated cleanup is harmless.
`Root::from_raw_extension` is unsafe: create exactly one owning wrapper per
resource and clone its roots to share it. Constructing a second wrapper for
one ID could finalize the resource while the first wrapper is still live.
Other extension resource kinds need an explicit release implementation before
claiming automatic cleanup. Generic registration of extension destructors is
future work.

The registry and its held values must not strongly retain the watched object.
A Rust resource that retains its own Scheme wrapper through `Root` creates such
a cycle and requires explicit release. Finalization is nondeterministic and is
not guaranteed at shutdown. Explicit close/cancel remains the prompt path.
A native Wasm executor can implement the same import with BDWGC finalization;
the translator need not know about Scheme.

## Continuations: planned, not implemented

Single-shot continuations prevent duplicate resumption, but do not by themselves
make arbitrary Rust frames suspendable or cancellable. The initial planned rule
is a foreign-call barrier: ordinary callbacks work, while a continuation may
not capture or transfer across an active Rust call boundary. A delimiter inside
a Scheme callback can still contain Scheme-only coroutines.

Supporting Rust frames later requires valid suspended borrows, separate
linear-memory stack storage where needed, and a cancellation/unwinding protocol.
A finalizer can enqueue a coroutine for cancellation on its owning thread,
keeping its stack alive until cleanup completes. It cannot manufacture missing
Rust unwind metadata or replace that protocol. Current release builds abort
on panic; no forced Rust unwinding is implemented.

The [stack-switching proposal](https://github.com/WebAssembly/stack-switching/blob/main/proposals/stack-switching/Explainer.md)
provides single-shot delimited continuations, not reusable snapshots.
[WasmGC post-MVP work](https://github.com/WebAssembly/gc/blob/main/proposals/gc/Post-MVP.md#weak-references)
explicitly defers finalization primitives. Our host import supplies an optional
execution-environment service rather than pretending it is a core Wasm opcode.

For coroutine finalization, a retained stack must not strongly reference its
watched wrapper, even transitively through mutable Scheme data. A registry
holding only an integer stack ID does not avoid this cycle if a global table
still retains the stack and its roots. Automatic cancellation of arbitrary
cyclic suspended computations therefore needs more than this finalizer shim.
