# Rust interop

The next interop milestone should use ordinary Rust library dependencies built
by Cargo together with the runtime and generated Scheme object. Start with
synchronous Rust functions callable from Scheme. Add reusable Rust embedding
after that boundary is tested. These APIs are proposed; they are not available
in the current runtime.

## What exists today

The compiler emits LLVM instruction handlers and a whole-program entry point.
Cargo compiles that IR for the target and links the object with `snail-runtime`.
The executable CLI generates a Cargo project and invokes `cargo build` or
`cargo run`. The supported host pair is native and `wasm32-wasip1`, using the
same Rust runtime and an adapter based on `std`. The generated entry exports
`snail_program_abi`; the runner checks it against `PROGRAM_ABI` before executing
the program. The current protocol version is 1.

The heap owns boxed `dyn SnailSchemeObject` payloads. Tagged `Value` words name
objects through an ownership table; they are not durable Rust roots. Copying a
word does not retain its object, and an address can be reused after collection.
The trait and raw VM access exist for runtime implementation, without a safe
public embedding or native-function registration facade.

Automatic collection occurs at instruction entry. Allocation does not collect.
During a call, arguments can leave the traced operand stack and live in Rust
locals until the dispatcher publishes results or a new activation. Explicit
`collect-garbage` runs only after consuming its inputs and publishing its
result. Allowing arbitrary native code to collect or reenter Scheme inside
this region would invalidate those assumptions.

See [backend.md](backend.md) for the executable implementation and
[TOUR.md](../TOUR.md) for the module walkthrough.

## First API: scoped leaf calls

A native procedure should hold a VM-local registration ID. Its immutable
registry entry contains the function pointer, original Scheme library/export
identity, diagnostic name, and arity. Initially exports are stateless Rust
function pointers. The dispatcher checks arity and copies the entry's callable
metadata before lending the VM to a restricted context.

One possible signature is:

```rust
pub type NativeFn = for<'call>
    fn(&mut NativeContext<'call>) -> NativeResult<'call>;
pub type NativeResult<'call> =
    Result<NativeValues<'call>, NativeError>;
```

Names and signatures are illustrative. `NativeContext` supplies argument
access, checked conversions, and constructors for built-in values. It does not
expose the VM, heap, raw slots, raw-value constructors, collection, callbacks,
or asynchronous suspension. It and its values are initially thread-confined.
Native code may call ordinary Rust helpers and allocate; it cannot introduce
a Scheme safepoint.

`NativeValue<'call>` has private representation and an invariant invocation
lifetime. The runtime creates each scope through a higher-ranked boundary.
Constructors return values with that invocation lifetime, allowing several
allocations and a composite result. References such as `&str` instead borrow
the context briefly: allocation or mutation requires `&mut self`, preventing a
borrowed object view from surviving it. Generative scopes or explicit owner
checks must also prevent mixing values from distinct VMs; a lifetime spelling
alone does not establish ownership. Rust's [higher-ranked bounds](https://doc.rust-lang.org/reference/trait-bounds.html#higher-ranked-trait-bounds)
and [variance rules](https://doc.rust-lang.org/nomicon/subtyping.html) provide the
language mechanisms, not a complete proof of the eventual API.

`NativeValues` distinguishes zero, one, and multiple results. Zero values are
different from one unspecified value. The dispatcher publishes every returned
value into traced VM storage before another safepoint. Expected failures return
an owned `NativeError`; partial results are not published. Errors do not roll
back mutations or IO.

Do not initially expose generic `alloc(T: SnailSchemeObject)`. The trait's
`Any` bound requires a static payload, while invocation-scoped values must not
escape into one. Custom objects containing Scheme references need a separate
checked traced-edge API. A future derive macro can enumerate those edges once
their ownership contract is established.

## Allocation, ownership, and failure

A Scheme string or pair constructed by native code belongs to the managed
heap immediately. It does not wait in an unowned Rust allocation until return.
Temporary Scheme objects remain valid throughout the GC-free call, then
unreachable ones can be collected. Returning an object changes its reachability,
not its allocator or owner. Ordinary temporary Rust buffers use normal Rust
ownership; moving one into an accepted heap payload transfers that ownership.

There are three distinct allocation conditions:

| Condition | Contract |
| --- | --- |
| Soft collection threshold | Schedule collection at the next safepoint. A leaf call may exceed it by its entire allocation burst. This is the current policy. |
| Future managed-heap quota | Constructors return a limit error before admitting an allocation. A leaf call cannot collect secretly, even if garbage could be reclaimed. |
| Host allocator failure | Separate from the managed quota; it may occur in library buffers, runtime tables, result construction, or collector scratch storage. General recovery is not currently provided. |

The current threshold and GC statistics count objects, not bytes. A byte quota
would need a stated accounting policy for payload capacities, headers, tables,
mutable growth, roots, and marking scratch. A buffer constructed outside the
runtime cannot be retrospectively bounded by charging for its admission.
Fallible constructors should leave room for a quota, but `Result` alone does
not make underlying `Box`, `Vec`, or `HashMap` allocation recoverable.

Unrestricted allocation, no native safepoints, a fixed heap bound, and guaranteed
success cannot all be promised. Begin with allocation under the soft threshold
policy, optionally adding explicit quota errors. Long native calls that need
reclamation require the rooted-call design below.

Catch unwinding panics before they cross the LLVM boundary and stop the VM;
do not resume partially mutated state. The current release build uses
`panic = "abort"`. Neither aborting panics nor allocator aborts become ordinary
Scheme errors through `catch_unwind`. Rust documents these limits for
[panic catching](https://doc.rust-lang.org/std/panic/fn.catch_unwind.html) and
[allocation failure](https://doc.rust-lang.org/std/alloc/fn.handle_alloc_error.html).

Unreachable heap payloads drop their Rust resources during sweep or VM
destruction. Files, sockets, and transactions still need explicit close or
commit operations when timing and errors matter. Tracing and destructors must
not reenter Scheme, allocate Scheme objects, or panic. This is trusted native
code: Rust permits leaks through mechanisms such as
[`mem::forget`](https://doc.rust-lang.org/std/mem/fn.forget.html), so the API cannot
promise that arbitrary extensions never leak.

## Later: callbacks and durable roots

Before native code can collect or call Scheme, add dispatcher-owned native
root frames covering the procedure, arguments, local handles, pending results,
and suspended native state. Registration must precede any safepoint. Frame
cleanup occurs on return, error, or unwind after publishing results or stopping
the VM. Child scopes or released slots let long loops discard temporary roots;
retaining every temporary until return would defeat bounded live space.

Prefer a returned invocation request for a native tail call. For a callback
followed by more Rust work, a traced continuation can resume with a fresh
context. Synchronous reentry instead needs explicit save/restore rules for VM
activations, operands, results, continuations, and error/exit state. All borrowed
views must end before collection or callbacks. Stateful native functions also
need a defined policy for recursive invocation of their mutable state.

Embedding needs a separate durable `OwnedRoot` concept backed by a VM registry.
It must enforce VM identity and slot generations, support explicit retain/drop,
and define behavior when the VM closes. Prefer handles that do not accidentally
keep the whole VM alive; access after shutdown fails and dropping a handle
after shutdown is harmless. A raw `Value` returned by today's `Vm::results()`
does not satisfy this contract.

External roots represent host ownership. Do not store them as ordinary edges
inside GC objects: that can permanently root a cycle. Internal edges belong to
tracing, including eventual custom-object fields and native captured state.

## Cargo dependencies and registration

Extensions should be source-built Rust libraries in the final application's
Cargo graph, sharing one `snail-runtime` package identity. A path dependency and
a registry dependency can be different packages despite matching names and
versions. Validate the graph and diagnose both paths before incompatible
runtime types or duplicate ABI symbols reach the linker. Cargo describes the
underlying [version and package compatibility hazards](https://doc.rust-lang.org/cargo/reference/resolver.html#version-incompatibility-hazards).

Keep three identities distinct: Cargo package identity, the Rust dependency
alias/registration path, and the original Scheme library/export identity.
Scheme import renaming preserves the latter. Different libraries may export
the same name. Rust `TypeId` and function addresses are not portable serialized
export identities.

Generate explicit calls such as `native_math::register(&mut registry)` in a
Rust bridge. Ordinary references retain code under native and Wasm dead
stripping; `#[used]` alone does not guarantee retention by the final linker.
[Rust's attribute documentation](https://doc.rust-lang.org/reference/abi.html#the-used-attribute)
describes that distinction. Freeze the registry before execution and reject
duplicate, absent, or mismatched exports with library-qualified diagnostics.

The compiler needs declarative export metadata before code generation. It
cannot run a target WASI library to discover exports while cross-compiling.
A Scheme library stub or metadata file supplies names and arities; registration
checks them and fills compiler-assigned foreign global slots. Rust function
pointers, containers, and trait objects remain inside Rust.

Future dependency configuration should persist outside temporary build jobs:
source/version, alias, registration path, features, and Scheme metadata. Resolve
path dependencies relative to that declaration, retain a project lockfile, and
make dependency updates explicit. Generated manifests must preserve selected
features and use the chosen alias in Rust source. The current transient project
only links the repository runtime; user-supplied dependencies are not implemented.

This is static Cargo composition, without a stable Rust binary plugin ABI.
An `rlib` is the normal Rust library artifact; let rustc own the final link.
[Rust linkage guidance](https://doc.rust-lang.org/reference/linkage.html#mixed-rust-and-foreign-codebases)
explains why separately bundled Rust `staticlib` dependencies are a different
packaging choice.

## Reusable embedding and targets

The current build script supplies the generated object through
`cargo:rustc-link-arg` for an executable. A Scheme library consumed through an
`rlib` needs an object archive and `rustc-link-search`/`rustc-link-lib` directives,
plus a Rust wrapper referencing its program descriptor. A final-binary link
argument alone does not propagate the code through an ordinary Rust library.
See [Cargo's linking directives](https://doc.rust-lang.org/cargo/reference/build-scripts.html#rustc-link-arg).

A reusable program descriptor needs separate initialization and execution or
resumption. The host must be able to call exported Scheme procedures repeatedly,
retain rooted results between calls, and receive normal completion, VM failure,
or an exit request without the library terminating its process. Define explicit
idle, running, failed, and exited states.

Start with one generated whole-program image per instance. Namespace generated
symbols so multiple program crates can coexist, but do not mistake that for
cross-program Scheme calls: today's closure PC is a `u32` without program
identity. Separately compiled images calling each other would require qualified
instruction destinations and appropriate global/constant ownership.

On WASI, the generated program, runtime, and extensions are linked into one
Wasm module sharing its linear memory. Extension dependencies must themselves
support the chosen target and features. Browser hosting, Wasm components,
dynamic loading, asynchronous callbacks, and cross-VM value transfer remain
separate work. The current host uses filesystem IO and clocks; the
[`wasm32-wasip1` target](https://doc.rust-lang.org/rustc/platform-support/wasm32-wasip1.html)
and the [minimal Wasm target](https://doc.rust-lang.org/rustc/platform-support/wasm32-unknown-unknown.html)
have different host capabilities.

## Implementation and acceptance sequence

1. Implement the scoped leaf API and a Rust library exporting one Scheme-callable
   function. Test allocation bursts without collection, argument aliases, fresh
   containers, zero/multiple results, arity errors, ordinary/tail/`apply` calls,
   result publication under GC stress, and error/panic cleanup. Compile-fail
   tests reject escaped values, mixed scopes, and borrows across mutation.
2. Add declarative exports and generated dependency/registration code. Build and
   run the extension example on native and WASI, including explicit features,
   transitive dependencies, paths with spaces, release dead stripping, stale
   metadata, duplicate exports, and conflicting runtime package identities.
3. Add a Rust embedding example: register the Rust library, initialize generated
   Scheme once, call an exported Scheme procedure repeatedly, and retain a rooted
   result between calls. Package its object through an archive. Test independent
   instances, wrong-VM and expired handles, resource destruction, and controlled
   errors/exits on both targets.
4. Only then add rooted callbacks or hard managed quotas. Test nested collection
   with outer locals alive, temporary-root release, reentrancy policy, and injected
   allocation failures where recovery is promised. Keep actual OOM/abort tests in
   subprocesses. Decide separately whether cross-program Scheme calls are needed.
