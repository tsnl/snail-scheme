# Single-shot control handler prototype

This branch explores milestone 3 of the [runtime plan](../../doc/book/graphics/plan.md).
It is an executable compiler/runtime experiment, not the actor or application
host's control-handler implementation. Those hosts and the IDE do not install
these imports.

## Language contract

```scheme
(effect Choice
  ((choose ctl (-> I64))))

(handle Choice
    ((choose (lambda (resume) (+ 1 (resume 20)))))
  (+ 21 (choose))) ; => 42
```

An omitted mode or explicit `fun` keeps the existing direct-call operation.
`ctl` adds a final continuation argument to its handler clause. For an
operation `(-> P ... R)` and handled body with result `A`, the clause has type
`(-> P ... (-> R A ! e) A ! e)`. The continuation and clause preserve the
outer effect row, including effects performed by later clauses. Operation
arguments, resumption arguments, resumption results and clause answers are
checked by the ordinary type checker. No `Any` conversion or `unsafe-total`
is introduced in source code.

The handler may call its continuation once, after other managed waits, or
never. Its own nested computations may also call it. Passing the live
continuation out to an enclosing control clause and calling it there is
explicitly rejected. Calling it twice or after its handler has returned throws. The
prototype enforces this dynamically; the function type does not prove
linearity. A saved, expired continuation retains only an inert host token,
with its stack and boundary references cleared.

`resume` returns the answer of the remaining handled computation, including
the effects of later clauses. This is significant:

```scheme
(handle Choice
    ((choose (lambda (resume) (+ 1 (resume 0)))))
  (choose)
  (choose)
  10) ; => 12
```

The second clause returns 11 to the first `resume`; the first clause then
returns 12. Both resumptions cannot simply await the original body's promise.

A `ctl` clause runs in the context immediately outside its selected handler
at installation. Its continuation reinstates the body context, including
inner handlers. A clause that performs the same operation forwards to the
enclosing handler, and that effect remains in its inferred row. Existing
`fun` clauses keep their direct-call behavior: they pop their own effect's
handler but retain other effects' perform-site handlers. For example, an
inner `Tag` handler established inside a `Choice` body affects a `fun` call
there and the resumed body; it does not affect the `Choice` control clause.
The `context` fixture observes outer `Tag=1` in the control clause and inner
`Tag=2` after resumption, with a foreign wait on each side.

## Compiler boundary

Expansion stores the operation mode with its declaration. Checking first
finds the body's answer type, then checks each clause with that type and the
continuation's residual effects. Monomorphization needs no new expression
form. The backend keeps ordinary operations' calls and global handler stacks.

For a control handle the backend creates a body closure. A host-entered Wasm
adapter installs the new handler and runs that closure on a fresh JSPI stack.
Control clauses have adapters that unpack the checked operation arguments
and construct a typed continuation closure containing an opaque host token.
References cross the host unchanged; scalar handovers use small GC structs.
Every cast recovers a representation established by the paired compiler
adapter, rather than accepting unvalidated source data.

The host-entered adapters are explicit `control.*` exports. Passing only
their `funcref` to an opaque import was insufficient: the current
`--closed-world` optimization removed their bodies. Exporting the boundary
preserves those entry points in both static and separate-module builds.
Each declaring library still owns its effect's exported handler global.

## Physical stacks and logical answers

[`runtime.mjs`](runtime.mjs) has one scheduler for one top-level invocation.
The compiler uses three imports: `handle`, `perform`, and `resume`.

| Value | Responsibility |
| --- | --- |
| Task | One physical JSPI stack, its immutable parent, handler snapshot, pending import and completion promise. |
| Boundary | The body task, the outer handler context and the current answer recipient. |
| Continuation token | An available operation-result suspension, its owning clause and its boundary; the suspension is consumed once and references are cleared at completion. |

The body of a new handle is a child of its caller task. An operation clause
is a child of the selected boundary's caller, hence a sibling of that
boundary's body. This tree directly identifies the captured suffix: the
selected body and its descendants. Earlier clauses waiting on their
resumptions are siblings and survive cancellation of that suffix. No second
captured-stack list is necessary under the no-independent-task-spawning
restriction. Resumption checks that its caller belongs to its original
clause's subtree before consuming the token. Without that restriction, a
continuation passed to an outer clause could restore an outer boundary whose
answer is already owned by that clause. General context splicing for that
case remains open; it is not silently approximated by the task tree.

Performing an operation **takes and clears** the boundary's current answer.
The new clause owns that recipient. Resumption installs its own suspended
caller as the new recipient before waking the operation's body. Physical
body completion consumes the current recipient. Clearing the slot matters
when a clause returns early: cancelling the physical body must not publish
cancellation in place of the clause's answer.

Returning from a clause closes its token, rejects every remaining suspended
import in the captured suffix and waits for all those promising Wasm
invocations to settle. Only then does it answer its caller. JSPI stacks are
actually unwound; they are not left parked behind unresolved promises.
This also handles traps and host promise rejection. A foreign operation
that has already started may continue in its own host; stack abandonment is
not cancellation of external I/O. The source language currently has no
exception-catching form that could intercept the internal cancellation.

## Dynamic context and host restrictions

Only one stack holds the execution lease. Before starting or waking it, the
host installs that stack's entire handler snapshot. The lease lasts until
its next managed suspending import or until its promising invocation
settles. Resolving a promise is itself scheduled; the lease is retained
while V8 queues and runs the resumed continuation. Restoring globals merely
when an entry's promise settles cannot implement this.

Imports start new stacks through later microtasks. No importing JavaScript
frame synchronously calls a Wasm callback and then suspends beneath it.
Rust scalar services have returned before these control imports are reached.
They keep their ordinary linear-memory shadow stack; it is not switched.

The prototype's supported boundary is deliberately narrow:

- All asynchronous foreign imports must be constructed with
  `host.suspending(operation)`. Supplying a raw `WebAssembly.Suspending`
  import bypasses context scheduling and is unsupported. The host does not
  inspect already-instantiated modules to prove this restriction.
- Imports are leaves. They must not reenter Wasm synchronously or launch
  independent work on the same program instance.
- One top-level invocation may run at a time. The prototype rejects overlap
  through its own runner; mixing it with the actor/application entry helpers
  on the same instance is unsupported.
- Control operations have monomorphic declarations and language handlers.
  Polymorphic operation declarations and `ctl` host defaults get compiler
  errors. Effect-polymorphic functions, arbitrary checked answer types and
  mixed `fun`/`ctl` effects work.
- A continuation can be invoked only by its original clause or a task in
  that clause's subtree, while that clause lives. Crossing to an enclosing
  control clause is rejected, even if the continuation has not yet been used.
- Standard `lofi run`, application startup, reload and actor entry points do
  not install this host. The fixture initializes ordinary globals first and
  invokes its exported control computations through `host.run`.
- No multishot continuations, escaping live tasks, native stack switching,
  user-facing cancellation API or integration with Rust suspension.

## Running and verification

Use the repository's pinned Node with `WebAssembly.Suspending` and
`WebAssembly.promising` enabled. With the usual build tools available:

```sh
./lofi compile -I tests/control/lib -o build/control.wasm tests/control/main.sld
node tests/control/check.mjs build/control.wasm
make test
make test-chibi
make bootstrap
make check
```

The two suites also build and execute the fixture as separately linked
modules. A fixture library owns `Choice`; its operations run under handlers
installed in the importing program. The runtime checks 30 cases and checks
that every run leaves zero tasks, boundaries, queued wakeups and live
continuation payloads. It covers early return, repeated operations,
forwarding, nested effects, deferred resume, double and escaped resume,
reference/scalar handovers, effect polymorphism, ordinary operations, traps
and rejected foreign promises. Seven negative programs check the static
contract and explicit prototype restrictions.

`make test` and `make test-chibi` pass **116/116**; `make bootstrap` reaches a
Wasm fixpoint, and `make check` passes. For a browser run after `make test`,
serve the repository root and open `tests/control/`. The repository browser
driver observed ten successful computations, rejected repeated and crossing resumptions,
and reported `data-result="passed"` in Chromium. This is correctness
coverage, not a performance measurement or a production readiness claim.

## Simplification record and open decisions

Two independent behavioral explanations guide the focused review of the new
runtime and backend section; the landed frontend keeps its pass structure.
The first debate replaced an explicit captured-suffix representation with
the immutable task-parent rule and one owned answer slot. A continuation is
an ordinary typed closure, avoiding a new public continuation type. Body and
clause adapters are direct functions, not a second bytecode or CPS pipeline.
The second debate found the crossing-continuation counterexample and adopted
the explicit caller-subtree restriction. With it, separate answer extents,
ownership transfers and a second lifetime token add no necessary behavior.
Redundant task-finishing, suspension-delivered and continuation-state flags
were removed; completion, membership and the remaining payload establish
those facts.

Cuts are the explicit unsupported cases above: production host integration,
polymorphic operation declarations, control host defaults, independent task
spawning, resumption across the owning clause's boundary and multishot
continuations. They are not required to test scoped single-shot handlers.
Keeping them out makes the ownership and scheduling invariants inspectable.

The review stops at this model: the remaining state records an actual stack,
answer recipient, execution lease or one-shot payload. Complete scheduling
transitions and generated Wasm adapter definitions occasionally exceed the
ten-line target to keep their whole contract visible. Further compression
would split those contracts without removing behavior.

Before proposing a production design, decide how actor/application hosts
register every asynchronous import with one scheduler, what cancellation
means for external resources, whether control and ordinary clauses should
retain their distinct dynamic-context behavior, and how escaping
continuations should appear in the type system. The runtime plan's latency
numbers are not measurements of this implementation.
