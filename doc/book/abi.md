# The ABI

The application binary interface (ABI) specifies **local calls** between
compiled Scheme and its runtime.
Node connections use serialized messages instead. All implemented extension
operations are ordinary Wasm functions.

## Who calls whom

Imports and exports are relative to the module being described:

| Reference | Imports supplied by the other side | Exports supplied by this module |
| --- | --- | --- |
| [Application runtime contracts](platforms/index.md) | Runtime operations called by Scheme | Scheme handlers called by the runtime |
| [Rust runtime module](abi-reference.md) | Value operations supplied by compiled Scheme support | Runtime procedures called by Scheme |

The command runtime links Scheme's WasmGC module, the common Rust-to-Wasm
library, and a selected [platform](effects.md). The loader supplies WASI and
JavaScript host operations. Rust is an implementation language for the current
common library; a provider can be any compatible Wasm module.

## Values and ownership

| Meaning | Wasm representation |
| --- | --- |
| Scalar | `i32`, `i64`, `f32`, or `f64`, as declared |
| Owned or borrowed Scheme root | Opaque `i32` table handle |
| Resource ID | Opaque `i32` in a stated node/resource domain |
| Linear-memory range | `i32` offset and byte length in the shared memory |
| Internal GC value | `anyref`, `eqref`, or a typed reference |

Each symbol states which meaning applies. An integer root handle identifies a
slot in a GC-visible table; releasing it permits slot reuse. An offset must be
resolved against memory, never cast to a pointer. A resource ID identifies a
resource in its stated domain. None of these integers is automatically a node
identity. External storage may use explicit 64-bit offsets without enlarging
the Scheme heap's addressing model.

A runtime procedure borrows its argument-vector root and returns an owned result
root. A child accessor already returns an owned slot. Retaining that root again
creates a second slot that also needs release.
For example:

1. Borrow the argument vector and obtain an owned root for a child.
2. Keep that root live while a Scheme callback allocates or reenters Rust.
3. Release the child root after the callback; transfer the owned result to the
   caller, which releases it when done. The argument vector's owner releases it.

Rust's `Root` encodes this ownership and prevents transfer between threads.
Handles remain in the instance that allocated them. Ordinary Rust helper error
returns release owned roots normally. `Root::call` can report an
argument-validation error inside Rust. This does not add an error channel to a
Scheme-callable ABI export: current CLI runtime errors terminate the command with
status 1. Scheme traps and aborts are also fatal; they are not `Result` errors.

`anyref` and `eqref` have no portable C pointer representation. The finalization
hook beside `extension` in the [ABI reference](abi-reference.md) takes a GC reference. Cleanup data must not retain the
Scheme wrapper it watches.

Use `extern "C"` for calling conventions and unmangled symbols for linkage.
`#[repr(C)]` selects data layout. The ABI uses fixed-width scalars and
handles; Rust containers, platform-sized integers, aggregate returns, and raw
callbacks need additional contracts. See Rust's
[function ABI](https://doc.rust-lang.org/reference/items/external-blocks.html#abi),
[symbol linkage](https://doc.rust-lang.org/reference/abi.html#the-no_mangle-attribute),
and [data layout](https://doc.rust-lang.org/reference/type-layout.html#the-c-representation).

## Calls stay inside a node; connections cross nodes

Local calls are synchronous. Before invoking a callback, release any borrow or
lock it could reacquire. Arbitrary Rust/C frames cannot be suspended or unwound
through. A fatal trap may bypass destructors; the outer runtime must discard
the failed instance instead of reusing its roots.

[Connections](runtime-contracts.md#a-connection-has-a-client-on-each-end)
encode values, transfer them, and decode new values in the receiving node,
including within one process. Received S-expressions are data, never code to
evaluate. GPU resources or database records may be named in messages only when
both nodes agree on namespace, access, and lifetime. Bulk data can stay with its
owner. A runtime can also adapt a subprocess's IO and completion to messages.

The Node.js command host runs one instance per process. A runtime with
several nodes in one process must select each instance's roots, memory, and
resources before entry and restore that context across callbacks. Process-global
roots or unscoped thread-local port tables cannot provide that isolation.

## Compatibility

The linked modules are `snail.abi` (Scheme root operations), `snail.library`
(common library and default provider implementations), `snail.platform`
(selected effect functions), and `snail.entry`. The loader supplies `snail.host`,
`snail.node`, and WASI imports. An effect handler declares the exact interface
revision and complete operation contract. The linker checks descriptors and
Wasm function types; it does not prove documented semantics.

Artifacts must match root ownership, resource lifetimes, shared-memory layout,
and engine features. There is no dynamic ABI-version negotiation. Missing
imports, incompatible signatures, or unsupported Wasm features prevent startup.
