# Continuations and parallel execution

Research recorded on 2026-10-24. This page describes future options, not
shipping features. We ship one WasmGC backend.

Two decisions have been made since. One-shot `ctl` handlers are implemented
by evidence passing ([effects and handlers](../snail-core/effects.md#control-handlers)).
And each instance of a program is single-threaded, talking to others only
through queues and shared memory ([instances](instances.md), proposed). So
the shared-heap thread pool below is not the plan. The native alternatives
remain research.

## What the Wasm target needs

Existing Wasm threads share **linear memory**. That does not make ordinary
WasmGC objects, closure displays or references transferable between workers.
The [Shared-Everything Threads proposal](https://github.com/WebAssembly/shared-everything-threads)
addresses that larger sharing model. A prototype engine flag is not a
deployment baseline; we require default support in the runtimes we ship on.

[Typed stack switching](https://github.com/WebAssembly/stack-switching/blob/main/proposals/stack-switching/Explainer.md)
provides typed continuation creation, suspension and resumption. JSPI gives
us host-driven asynchronous suspension today, but not a language-level
first-class continuation API or arbitrary migration of suspended stacks.
User-defined `ctl` remains deferred while runtime-provided waits use JSPI.

These extensions solve different problems. Stack switching does not make
the heap shareable. Sharing the heap does not establish ownership, handler
lifetimes or cancellation. An implementation of both still needs to
preserve the language's invariants.

## Option A: restore a Wasm-to-LLVM backend

The archive `archive/llvm-backend-20261012`, at
[`5c277ab6`](https://github.com/tsnl/snail-scheme/tree/5c277ab69f5625a2d3c52c2d0c865d2b8332e66d),
used BDWGC and translated Binaryen's folded text into LLVM. The later
backend removed by [PR #341](https://github.com/tsnl/snail-scheme/pull/341)
was substantially different. Its last revision,
[`fc8bf59a`](https://github.com/tsnl/snail-scheme/tree/fc8bf59ad2bc6f18d8c99547c56689f14d70aa95/src/native),
read Wasm binaries, resolved their types, emitted LLVM, and used a custom
Immix collector. Research should start from that later revision, rather
than assuming the named archive contains the final implementation.

The later backend's exact writable roots are a useful foundation. Reference
locals lived in root slots; temporary references were published before
collecting calls and reloaded after objects could move. The collector was
synchronous and single-threaded. `RUNTIME` and `native_roots` were process
globals explicitly assumed never to be shared between threads. Native
worker isolation was not a shared-heap thread pool. See its
[roots contract](https://github.com/tsnl/snail-scheme/blob/fc8bf59ad2bc6f18d8c99547c56689f14d70aa95/doc/book/native/roots.md)
and [runtime](https://github.com/tsnl/snail-scheme/blob/fc8bf59ad2bc6f18d8c99547c56689f14d70aa95/src/native/native.rs).

A stackful implementation would allocate stacks, switch between them at
delimited suspension points, and represent a continuation as ownership of
a suspended stack chain. The Wasm type checker supplies the continuation's
type; LLVM need not gain a first-class continuation type. Affine resumptions
avoid copying stacks to support repeated resumes. A historical
[WasmFX prototype, section 5](https://kcsrk.info/papers/wasmfx_oopsla23.pdf),
implemented this using Wasmtime's fibers and native register/stack switching.
That establishes feasibility, not readiness of our old backend.

LLVM's [coroutine intrinsics](https://llvm.org/docs/Coroutines.html) instead
support splitting a function into entry, resume and destruction functions
with saved state in a frame. They do not automatically capture arbitrary
nested ordinary calls. We would either transform every potentially
suspending path or supply a stack-switching runtime. The
`coro.id.retcon.once` convention describes a coroutine yielding once; it
does not by itself implement our rule that each captured resumption is
consumed exactly once.

The substantial work is making the runtime correct:

- Give each suspended computation a root chain. Publish live references
  before suspension and reload them after resumption, since other tasks
  may have caused a moving collection in between.
- Enumerate roots from every running and suspended computation. A first
  multithreaded collector can stop all mutators; it need not collect
  concurrently. It still needs safepoints and safe allocation coordination.
- Implement stack limits, foreign-call boundaries, cancellation unwinding
  and exactly-once cleanup. Cross-thread resume must account for thread-local
  state, not just copy a stack pointer.
- Implement the shared Wasm memory/object operations and their atomic
  semantics. Native pointer accessibility alone does not provide them.

A useful first experiment would suspend with live managed references,
force a moving collection in another computation, resume, and check the
references. Cancellation should exercise the same roots and cleanup paths.
Only then should two native mutators run concurrently.

## Option B: a C backend informed by Koka

Koka's usual C backend lowers effects through a selective monadic
transformation and generalized evidence passing. At an operation that
yields, generated code returns through ordinary C frames. Each relevant
caller adds a closure for its remaining computation. At the matching
handler, the collected closures form the resumption. Resuming invokes those
closures with the appropriate handler bindings. It does not preserve the
physical C frames. The
[compiler transformation](https://github.com/koka-lang/koka/blob/dev/src/Core/Monadic.hs)
and [handler runtime](https://github.com/koka-lang/koka/blob/dev/lib/std/core/hnd.kk)
show both halves.

The [generalized evidence passing paper, sections 2.5–2.8](https://www.microsoft.com/en-us/research/wp-content/uploads/2021/03/multip-tr-v2.pdf)
explains the optimizations: effect types help select handler evidence;
tail-resumptive operations can execute in place; generated code builds
continuation closures on the yielding path. A yielding flag distinguishes
ordinary return values from suspension. Capture does work along the
continuation's path, whereas native stack switching can retain the stack
without rebuilding that path as closures. These are different cost models;
neither establishes a performance result for Snail-Core without measurement.

Koka supports multiple resumptions. Snail-Core restricts them to one: `resume`
is linear, so it is called or dropped exactly once. A C
backend would still need closure conversion, effect lowering, a
managed-memory strategy, a foreign ABI and a portable runtime.
Adopting this technique does not mean embedding Koka or obtaining those
pieces automatically. Koka's reference-counting implementation is also not
a requirement of the continuation technique.

Koka explicitly finalizes abandoned resumptions so `finally` clauses run.
Its `raw ctl` exposes a resume context whose owner must eventually resume or
finalize it. This is evidence against treating cancellation as merely
freeing a closure display. The
[tour](https://github.com/koka-lang/koka/blob/dev/doc/spec/tour.kk.md)
describes that contract. The related
[libmprompt](https://github.com/koka-lang/libmprompt) project takes a separate
native stack-switching approach; it is not the mechanism described above.

The compiler transformation could also target today's WasmGC. Therefore
waiting for typed stack switching is a choice to avoid another substantial
lowering strategy, not proof that `ctl` is impossible on today's Wasm.

## Handler ownership and scheduling

An unrestricted handler implementation may be invoked repeatedly and
concurrently. Each invocation receives its own linear resumption.
That does not make the installation, delimiter or captured resources
unrestricted. A continuation must retain the bindings and resources it
needs; cancellation must release them without retaining managed wrappers
through external cleanup records. A precise account of grades, effect
instances and escaping resumptions remains theoretical work before public
`ctl` handlers are added.

A shared-heap backend would want a conventional work-stealing pool. That is
not the plan: each instance schedules its own tasks, and parallel work
runs as more instances ([instances](instances.md)). For now, deploy
independent Wasm instances and balance requests externally. Neither native
backend is on the implementation path of the task rewrite.

## Scheme control and dynamic wind

The Scheme layer needs abortive `call/cc` with reusable continuations of
unlimited extent, multiple values, dynamic parameters and exception
handlers. Invoking an escape continuation replaces the current
continuation. A root delimiter must model the Scheme execution context;
delimiting every ordinary function or temporary browser callback would
truncate it. Other Scheme conformance work remains in the
[language issue](https://github.com/tsnl/snail-scheme/issues/456). See [R7RS sections 6.10 and 6.11](https://standards.scheme.org/official/r7rs.pdf).

Represent `dynamic-wind` scopes as persistent nodes with identity, parent,
entry and exit thunks, and their surrounding dynamic context. A
continuation retains the applicable chain. For a control transfer, find
the common ancestor, exit current scopes from inside outward, then enter
destination scopes from outside inward:

```text
Current: root -> A -> B -> C
Target:  root -> A -> D
Actions: C.after -> B.after -> D.before -> resume target
```

Remove a scope before calling its exit thunk; install it after its entry
thunk returns. Preserve the body's returned values across normal exit.
The transition machinery must participate in control lowering when a
hook performs an effect. The standard library implementation in
[The Scheme Programming Language](https://www.scheme.com/tspl4/control.html#./control:h6)
illustrates the chain and ordering.

Compiler-generated returns used to package a suspension do not themselves
leave a language scope. Ordinary I/O waiting preserves the task's dynamic
context. Actual continuation transfers run the corresponding wind
transitions. Capturing a continuation and collecting an already inactive
continuation do not independently trigger wind hooks. Final resource
destruction and dynamic scope exit remain separate operations.

## Cancellation and foreign callbacks

A pending operation owns its one-shot continuation. Completion and
cancellation race to settle that operation once; only the winner may
enqueue its work or initiate cancellation cleanup. Abandoning a task
disarms its registration or retains the registration's storage until late
callbacks can no longer access it. An empty ready queue is not runtime
exhaustion while waits or cleanup remain live.

Cancellation follows an explicit task cleanup path. It does not rely on
GC reachability or a native Rust/JavaScript exception to walk language
frames. Reusable Scheme continuations require a distinct lifetime policy:
discarding one reference does not cancel every retained invocation or
destroy resources still reachable through another reference.

Foreign callbacks return normally. They copy transient inputs or transfer
an explicitly owned buffer, settle a registration and enqueue Snail-Core work.
They do not capture a foreign stack as part of a continuation. Browser
operations that need an immediate response, such as event suppression,
keep that decision in the synchronous adapter.

