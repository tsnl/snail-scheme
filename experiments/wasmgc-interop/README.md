# Guest Rust and WasmGC interop proof

This isolated experiment connects an ordinary Rust `wasm32-unknown-unknown`
library to WasmGC code. It does not change the compiler or its extension ABI.
`bridge.wat` owns GC pairs and a reference table; `extension.rs` owns integer
handles into that table. A handle is never a pointer to a GC object.

The JavaScript test instantiates the bridge first and passes its exported Wasm
functions directly as Rust's imports. Pair field access remains Wasm-to-Wasm;
there is no JavaScript callback per accessor and no circular instantiation.
Rust has its ordinary 32-bit linear memory, separate from the GC heap.

Run with Rust's installed `wasm32-unknown-unknown` target, Binaryen's `wasm-as`
and `wasm-merge`, and Node with WasmGC support:

```sh
WASM_AS=path/to/wasm-as WASM_MERGE=path/to/wasm-merge NODE=path/to/node \
    ./experiments/wasmgc-interop/run
```

Verified with Rust 1.95.0, Binaryen 132, and Node 24.15.0. The library has no
crate dependencies; Cargo builds offline. The runner executes the same checks
twice: first with two modules connected at instantiation, then with one module
statically combined by `wasm-merge`. The test checks:

- Rust receives a pair handle plus an ordinary scalar and reads both fields.
- Rust retains a separate table slot, then Scheme releases its original slot.
- The retained pair survives five explicit V8 GC requests after allocation of
  100,000 linked garbage objects each time.
- Rust creates another GC pair through imported accessors and returns its owned
  handle; a WAT adapter takes the reference, releases the slot, then reads it.
- Replacing and clearing Rust's saved owner invokes `Drop` and releases its root.
  All owned slots are empty at the end. Two further GC requests exercise return
  and replacement lifetimes.

The table is deliberately bounded to fifteen live roots. Borrowed handles must
not outlive their owner. Slots have no generation counters: accessing a released
slot traps while it is empty, but a stale handle can alias a subsequently reused
slot. This is a trusted ABI feasibility test, not a production handle framework.
The Rust static owner is single-threaded and no accessor reenters Rust.

Root release is observable through slot counts. Actual object reclamation timing
belongs to V8 and is not asserted. Rust's `Root::drop` releases a table reference;
it is not a WasmGC finalizer. An integer handle stored in a GC object would not
automatically destroy an unrelated Rust `Vec`, file, or other owned resource.
That reverse ownership direction requires an additional contract.
