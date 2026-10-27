# Continuations and parallel execution

Research recorded on 2026-10-24. This page describes future options, not
shipping features. We ship one WasmGC backend. The language keeps its
multithreaded contract and `Send + Sync` handler restrictions while the
implementation runs one execution agent.

The follow-on [mixed memory and continuations draft](memory-and-continuations.md)
selects one Wasm backend with both GC and owned linear storage, and
compiler-lowered affine and reusable continuations. The native alternatives
below remain research; their implementation is not required by that plan.

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
consumed at most once.

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

Koka supports multiple resumptions. Restricting Snail-Core to affine resumptions
would simplify ownership, but the follow-on draft plans both grades. A C
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
concurrently. In an affine-resumption design, each invocation receives its
own affine resumption.
That does not make the installation, delimiter or captured resources
unrestricted. A continuation must retain the bindings and resources it
needs; cancellation must release them without retaining managed wrappers
through external cleanup records. A precise account of grades, effect
instances and escaping resumptions remains theoretical work before public
`ctl` handlers are added.

When a shared-heap backend exists, a conventional pool is sufficient:
worker-local deques, recently spawned work preferred locally, older work
available for stealing, and an injection queue for external submissions.
Suspended tasks are absent from ready queues. Thread-affine resumptions
remain pinned. This is a future scheduling policy, not part of the language's
observable ordering guarantees.

For now, deploy independent Wasm instances and balance requests externally.
Neither native backend is on the implementation path of the task rewrite.
