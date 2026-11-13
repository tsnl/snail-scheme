# Effects and handlers

A function's type says what it returns. Its **effect row** says what calling
it may do besides: write to the console, read a file, wait for a timer. This
chapter builds the effect system up the way
[Koka's tutorial](https://koka-lang.github.io/koka/doc/book.html) does, in
four steps:

- [Basic effects](#basic-effects): rows on function types, and how they are
  inferred and checked.
- [Handlers](#handlers): declaring an effect and deciding, around a piece of
  code, what its operations do.
- [Control handlers](#control-handlers): operations whose handler receives
  the rest of the computation, to resume now, later or never.
- [Latent handlers](#latent-handlers): operations whose implementations
  perform effects for their caller, such as waiting on the caller's
  scheduler.

Effects are the heavyweight way for a program to interact with the world.
Performing an operation searches the handlers in scope at run time, and the
compiler never specializes a function for the handler it will meet, so an
operation costs more than a call. That is deliberate: most logic should be
pure functions, which perform no operations, with effects at the edges,
where a program reads a clock, writes a file or waits.

Every example is part of a program under `tests/programs/`, which
`make test` runs, and the output shown is that program's. Run one with

```sh
./scripts/snail-tool run tests/programs/effects-basic.sld
```

## Basic effects

### Effect rows

A function type may end in `!` and a row of effects. A function without `!`
is total: a call can only compute its result.

```scheme
{{#include ../../../tests/programs/effects-basic.sld:rows}}
```

`write-line` performs `output-port`, so `report` does too. A total function may
not call it. `tests/programs/error-effect.sld`:

```scheme
{{#include ../../../tests/programs/error-effect.sld}}
```

fails to compile:

```text
{{#include ../../../tests/programs/error-effect.err}}
```

`mut` covers writes to object fields and mutable sequence operations.
Reading a record field is pure, including through `Rc`. A function can still
perform cleanup effects when it releases the last counted owner. `(snail core io)` declares `input-port`, `output-port`, `fs` and `clock`, and other
libraries declare their own, such as `tcp` in `(snail shell socket)`. A
program declares more with `effect`, in the [next section](#handlers). Traps
and non-termination are not tracked: a total function may still panic or
loop forever.

### Inference and signatures

Rows are inferred by unification, as types are, Koka-style, so nothing
inside a definition needs a row written. A definition without a signature
gets the row its body performs:

```scheme
{{#include ../../../tests/programs/effects-basic.sld:inferred}}
```

```text
squared 49
```

`report-square` performs `output-port`, through `report`. A call requires its
callee's effects to fit the row of the code around it, so a total function
could call `square` but not `report-square`.

A top-level signature states the row, and the body is checked against it
both ways: the body may perform only what the row names, and the row may
name only what the body performs.

### Claiming only what the body performs

The second half is the unused-effect rule. A top-level definition whose
signature names an effect, or a tail variable such as `e`, that no call in
its body performs is an error at the signature.
`tests/programs/error-unperformed-effect.sld`:

```scheme
{{#include ../../../tests/programs/error-unperformed-effect.sld}}
```

```text
{{#include ../../../tests/programs/error-unperformed-effect.err}}
```

A row is a promise to callers about what may happen, and each caller must
handle or pass on every effect in it. An effect that never happens would
cost every caller that work for nothing.

Some signatures have no body to hold them to. An instance method keeps its
class method's row, which one instance may need less of than another:
in `tests/programs/declared-effects.sld`, the `Bool` instance of
`announce` performs nothing and keeps `! output-port`. A default is held to
its row all the same ([defaults](#defaults-in-snail-scheme)). `extern`
declarations, class method signatures and definitions whose value is not
a lambda are not compared either. A signature that a macro writes is held to each
expansion. Application entries avoid duplicating such signatures: the selected
ordinary `Application e A` instance determines the entry's row, and the generated
browser export infers it ([application model](applications.md)).

### Effect polymorphism

A higher-order function performs whatever its argument performs. A row
variable, quantified like a type variable, stands for those effects:

```scheme
{{#include ../../../tests/programs/effects-basic.sld:polymorphic}}
```

```text
squared 1
squared 4
squared 9
```

Here `e` is `output-port`; with a total `action`, `repeat` is total. `map` in
`(snail core base)` has the same shape:
`(∀ (A B e) (Fn (Fn A → B ! e) (List A) → (List B) ! e))`.

A class may take a row as a parameter too, so that each of its instances
performs its own ([rows as parameters](types.md#rows-as-parameters)).

A row with a tail fits a larger row with the same tail: `e` fits
`output-port e`, and `fs e` fits `output-port fs e`. The reverse does not hold, and
two unrelated tails never fit each other
(`tests/programs/error-effect-row-tail.sld`). This check is about
permission to call; equality of function types still compares whole rows.
The [effects tutorial](tutorials/effects.md) shows a function that adds
`output-port` around its argument's row.

### Local mutation

A function whose signature has no `mut` may still mutate storage that it
allocates and that nothing keeps after it returns:

```scheme
{{#include ../../../tests/programs/effects-basic.sld:local}}
```

```text
sum 14
```

The checker accepts such a body when nothing the function can reach from
outside can hold mutable storage: not its parameters, not its result, and
not any name it reads, including effect operations. Holding storage means
being an array, `Any`, a mutable aggregate or a callable that can reach
mutable storage. Every record is mutable, so the proof is deliberately
conservative. Allocation and field reads do not perform `mut`. A helper defined elsewhere that mutates its argument is
therefore rejected even when the argument is local; define it inside the
function. `unsafe-total` runs a thunk and discards all its effects without a
check, for the cases this rule rejects; each use says in a comment why
nothing escapes. A `gc` effect, "may allocate traced memory", is proposed in
[issue #550](https://github.com/tsnl/snail-scheme/issues/550).

### Defaults from the host

`input-port`, `output-port`, `fs` and `clock` need no handler. Each operation has a
[default](#defaults-in-snail-scheme) implementation that reaches host services
through `extern` imports. An operation performed where no handler of its
effect is in scope calls that implementation. That is why the programs above call
`report` from `main` without installing a handler.

Every platform effect is declared the same way. `(snail core io)` declares
its externs beside its effects, since core imports nothing; a shell
library imports a `(snail runtime …)` library, which declares the host's
imports and nothing else, under the prefix `host-`. For example, `(snail
runtime browser screen)` declares the page's drawing commands, and
`(snail shell app)`'s `screen` effect defaults each operation to one. An
interface's imports take and answer scalars, and the shell builds its own
values from them, as `(snail shell socket)` builds a `Connection` from a
handle ([the native boundary](../runtimes/networking.md#wasm-boundary)).

A handler can
still replace them: `tests/programs/files.sld` handles `fs` to answer
`file-exists?` and `list-directory` from memory. Such a handler may leave
the rest of its row polymorphic, as any can:
`tests/programs/effects-host-handler-row.sld` handles `clock` for a body
of row `(clock e)`, answering through `output-port`, and is itself of row
`(output-port e)`. An effect without a
default must be handled: performing it where no handler is in scope is an
error (`tests/programs/error-unhandled.sld`).

`host` is the row of code that may run anything the host implements, such
as a program's entry function and its task scheduler. It admits `mut` and
effects with host defaults. It is a builtin effect, like `mut`, imported
from `(snail core forms)`; no handler implements it, and a function whose
row names it can be called only where `host` is in the row too. Work closed
over its handlers performs it ([below](#closing-over-handlers)).

## Handlers

### Declaring an effect

`effect` declares an effect and its operations, each with a function type.
An operation is called like a function, and performing it charges the
caller its effect:

```scheme
{{#include ../../../tests/programs/effects-handlers.sld:declare}}
```

`log`'s type is `(Fn String → Unit)`, and calling it adds `Log` to the row,
so `total`'s row is `Log`. `Log` has no default, so something must say what
logging means before `total` can run. Effects take no type parameters, and
operations are monomorphic ([notable omissions](omissions.md)): a handler
implements an operation once, at one type, so an operation's type may not
quantify over types or rows
(`tests/programs/error-effect-operation-polymorphic.sld`).

### Proposed parameterized effects

**Design for review, not implemented.** Represent source capabilities as
parameterized typeclasses and providers as scoped instances. Requirements
following `!` request implicit provider arguments. Dedicated `effect` and
`handle` forms need not be fundamental language forms; any retained surface
sugar must elaborate to this model. One typed application, such as
`(Emit I64)`, fixes the parameters of a provider.

Using the [built-in function types](types.md#functions):

```scheme
(typeclass (Ask T)
  (declare (ask) (→ T)))


(define (greet) (→ String) (! (Ask String))
  (string-append "hello, " (ask)))


(define (welcome (name String)) (→ String)
  (instance (Ask String)
    (define ask (lambda () name)))
  (greet))
```

These forms are illustrative extensions, not accepted syntax today. The
local instance supplies an anonymous concrete provider whose `ask` method
captures `name`. Its method is checked against `(Fn → T)`. `greet` receives
the selected provider as an implicit argument; compilation makes `welcome`'s
supplied argument explicit. Its captured string is runtime data, while its
method code is statically selected.

A parameterized emitting capability has the same interface mechanism:

```scheme
(typeclass (Emit T)
  (declare (emit (value T)) (→ Unit)))


(define (produce) (→ Unit) (! (Emit I64))
  (emit 1)
  (emit 2))
```

The `Fn` contract states the caller-facing interface. Whether the chosen
provider returns directly or uses `ctl` belongs to its concrete
implementation and the compiler's control analysis. A direct discard
provider and a collecting control provider can share an argument/result
shape; their contracts must also expose any control and resumption-effect
requirements. These may be symbolic in generic code, but specialization
cannot introduce control behavior that the checked contract forbids.
Their specialized consumers may use different calling conventions. The exact
syntax for a `ctl` instance method and its continuation binder remains open.

#### Scoped selection and specialization

At a call site, instance lookup selects the nearest provider in scope for a
required class application. A generic body forwards its provider parameters;
it does not search for a new instance independently of those arguments.
Nested providers for the same application require an explicit shadowing
rule, and competing providers at one scope are an ambiguity. Provider
method dependencies remain requirements supplied when the method is invoked,
unless its body explicitly establishes a local provider. Recursive
self-reference must be explicit. These rules differ from today's
global, nonoverlapping class instances and require new checking support.

Specialization keys on the provider's implementation type and concrete
method identities. Runtime captures are arguments, not specialization
keys. Choosing between different provider implementations at runtime
requires specializing the consumer within each branch or another explicit
representation; this design introduces no implicit erased-provider fallback.
Local instances may capture ordinary values and therefore are runtime
closures even though method selection is static. Ambient provider
requirements are parameters rather than automatically captured values.
Capture ownership remains checked.

All methods of one `(State T)` provider share the same `T`; independently
instantiating its read and write methods would break that guarantee.
`(Emit I64)` and `(Emit String)` may both be required. Local provision of
one discharges only that application. A missing or ambiguous application
is a compile-time error. A generic provider-building function may instantiate
this pattern for different `T`, but each installed provider fixes one `T`.
Operation-local universal polymorphism remains outside this proposal.

#### Control still needs a delimiter

Passing provider closures explains ordinary capability calls. It does not
alone capture the remainder of a computation. A `ctl` implementation needs
a one-shot continuation up to a particular boundary. If `emit` answers
`Unit` and the collecting computation answers `(List I64)`, its continuation
accepts `Unit` and returns `(List I64)`; the implementation itself also
returns the collecting computation's answer. Omitting a call to that
continuation abandons the computation up to that boundary, not the whole
program. Ownership must account for the abandoned continuation's captures.

A scoped control provider must therefore establish a typed delimiter, even
if there is no source form named `handle`. The body extent, answer type,
deep reinstatement of the provider, and nesting with other control providers
must be defined. The proposed compilation worklist makes provider arguments
explicit and lowers delimiter and resumption behavior while specializing
each definition. Its output expresses that behavior in Wasm functions,
branches and GC data. Passing a provider argument alone does not discharge
the obligation to implement its delimiter.

#### Caller-supplied providers

Ordinary closures retain their outstanding capability requirements in their
types. Invoking a closure supplies providers from that call site; creating
it does not automatically capture ambient handlers. Apply the same rule to
the outstanding requirements of a stored continuation. Logging before and
after a suspension may therefore use different providers, intentionally.

A continuation still restores the handler scopes established inside the
captured computation, including its delimiting handler under deep resumption.
Those are part of the suspended computation, not outstanding requirements
for the resumer to replace. Its ordinary captured values remain runtime
data; capturing a place retains access to the object, not a snapshot.
Explicitly preserving an outer provider environment would need a separate
operation and contract; it is not the default.

Static call-site resolution requires the continuation's remaining code to
stay generic over its outstanding provider parameters until its invocation
sites are specialized. Already generated calls to provider A cannot simply
be reinterpreted as calls to provider B. Saved values must have compatible
types across those specializations, and imported continuation code must
remain available for specialization. This is a compiler obligation, not a
claim that type erasure or machine-code rebinding supplies it automatically.

[Generalized Evidence Passing for Effect Handlers, section 2.12](https://www.microsoft.com/en-us/research/wp-content/uploads/2021/08/genev-icfp21.pdf)
studies resumption under a changed handler context. That supports the semantic
direction; the static specialization and transition typing proposed here
still need their own rules and correctness argument.

#### Resumption effects and effect transitions

Use **resumption effects** for the requirements of the continuation passed
to a control operation, and **effect transition** for the relationship
between those requirements and the requirements for entering that operation.
These names separate the entry context from the context needed to continue.

Direct-style suspension remains a design requirement: users write the
statements following `yield`, `sleep` or `await` normally, and the compiler
constructs the one-shot continuation. The callable contract records the
control boundary, including calls to wrappers that can suspend. A checked
call-site marker remains a surface-syntax question; the examples use ordinary
operation names. The existing `!` mutation convention need not mark every
effectful function.

For example, schematically, with a delimiter answering `Unit`:

```text
yield()
write("ready")
```

The continuation at `yield` accepts `Unit`, answers `Unit`, and requires
`IO`. If the selected scheduling contract accepts an IO-requiring
continuation and arranges for its resumer to supply IO, the enclosing
function can require `Yield<resume requires IO>` at entry instead of a
separate entry IO provider. This is contract notation, not proposed source
syntax. The nested requirement remains visible: calling such a function is
not classified as pure merely because IO is absent from its entry row.

The operation's contract bounds its continuation requirements, and source
checking at the static delimiter site checks the remaining computation
against that bound. Invoking the continuation supplies its outstanding
providers; enqueueing transfers that obligation with the value. A provider
that resumes immediately must itself supply them and account for the
resulting invocation effects. An operation that merely accepts an IO
continuation has not proved it can resume that continuation in an arbitrary
context. Result types, delimiter answers and cleanup requirements must also
match. A transition changes which context supplies requirements; it cannot
relabel IO as mutation or discard an unsatisfied requirement.

Inference must follow continuation structure, rather than taking a flat
union of the entire function's effects and assigning that union to every
suspension. IO before the yield still requires an entry IO provider. A branch
that can reach the write without yielding also retains that entry requirement.
At a join, every incoming path must satisfy the requirements of the shared
suffix. Wrappers, loops, nested suspensions and recursive calls need
compositional transition contracts: the captured continuation can include
caller code up to the delimiter, not just the next statements in one function.
The checked contract must also distinguish a possible normal return from a
transfer to a resumer. If the suffix has no entry provider, the contract must
prove every route to it transfers that requirement. Compilation must not
emit an ordinary-return route requiring providers the original caller lacks.
The precise inference rules remain to be specified and checked for soundness.

#### Provider requirements and purity

An entry requirement says which provider the caller must supply now; a
resumption requirement says what the deferred computation needs when invoked.
Both remain visible in the callable/control contract. A queue insertion has
its own effects, such as mutation, without executing the job's IO. Invoking
the job performs the effects of its selected provider implementations.
Dropping it must account for cleanup effects of its captures separately.

Providing an implementation may discharge a capability requirement, but
observable effects of that implementation still count. Passing or retaining
a provider cannot make external mutation or host IO pure. Compiler-owned
`mut` and `host`, confinement of local mutation, and foreign calls need
explicit rules in the transition system. Constructing or returning a deferred
callable may be pure; its invocation requirements remain in the returned
type and are checked separately. A list of missing providers alone does not
describe the observable effects of executing locally supplied implementations.

#### Diagnostics for transitions

Report the required resumption effects, the accepted bound, and the operation
that introduced the requirement, with locations at both the suspension and
the offending use. Suggested diagnostics, not implemented output:

```text
error: yield cannot accept this continuation
  write requires IO after the suspension
  this Yield provider accepts resumptions requiring only {mut}
  provide an IO-capable scheduler or handle IO within the continuation

error: IO is required before any effect transition
  this path reaches write without passing through yield
  add IO to the entry requirements or transition on every incoming path

error: resume requires an IO provider
  the continuation was created for the write following yield
  no IO provider is available at this invocation site
```

A queued job outside the queue's bound should point to the enqueue site and
the stored continuation's requirement. A specialization failure should name
the unresolved provider implementation or incompatible captured type, rather
than reporting an unrelated generated closure as ill-typed. If suspension
markers are adopted, missing markers on transitive calls require a diagnostic
at the source call, not only at the underlying primitive.

#### Queuing a continuation

Moving a continuation into a work queue does not invoke it. A control
implementation that only enqueues has the effects of enqueueing, such as
queue mutation, without thereby performing the continuation's latent row
`E`. The queue takes ownership of the one-shot value; the eventual worker
must call or drop it exactly once. A job adapter must supply the operation's
result and account for the delimiter's answer, matching the scheduler's
job interface.

Give a queue an allowed invocation-effect bound `Q`. The following are
contracts, not proposed concrete storage types or surface syntax:

| Operation | Contract |
| --- | --- |
| Enqueue a job with row `E` | Require `E` to be included in `Q`; perform only the enqueue operation's own effects. |
| Run a queued job | Require permission for `Q`, plus the worker's own queue operations. |
| Cancel or reject a job by dropping it | Account for cleanup effects separately; an invocation bound alone is not a drop contract. |

Effect inclusion permits jobs with smaller rows: a queue allowing mutation
and output may also accept a pure job. Insertion of an output-capable job
into a mutation-only queue is a compile-time error. Widen the queue's bound
or handle the output capability with a suitable provider before packaging
the job; merely capturing an output provider does not remove its effects.

The scheduling provider can be generic over the queue's bound, with each
static installation fixing it. A local scheduler may infer the bound from
its uses; a shared queue needs a declared contract. The worker supplies the
job's outstanding providers at invocation; internal captured handler scopes
are restored. The queue bound must preserve nested transition requirements
as well as ordinary effect labels.

Use an **explicit job package with a closed sum of adapter types** at the
queue boundary. Each adapter supplies the operation result and handles the
delimiter answer to satisfy a common job interface. Its captures include a
concrete saved resumption. A source `Fn` type alone does not create
this package. The package names its invocation and cleanup bounds; packing
checks both, including nested transition requirements.

Packaging instantiations register their variants with a named package
boundary. The compiler generates its finite sum and a worker entry specialized
for each provider mapping used to invoke it. The sum is closed for that linked
program version, so every variant's adapter and saved-frame descriptors are
available. A worker selects a variant and passes its own provider values to
that adapter; the creator's outstanding providers are not saved. Source
syntax for this explicit packaging remains to be designed.

Saved resumptions use
[tagged GC frame chains](compilers.md#saved-frame-representation) whose types
do not grow with stack depth. The queue stores managed references to packaged
jobs; it does not create an array of inline struct values or erase arbitrary
source closures and object references. A new package variant rebuilds the
affected dispatchers. Unknown runtime-loaded variants require another ABI
and are outside this design.

#### Compiler obligations

The implemented compiler preserves control rows during monomorphization
and uses a may-yield analysis. The proposal instead uses a memoized emitter
after type checking. It builds
[structured Wasm directly](compilers.md#effects-control-and-frames),
using the instantiated checked contracts as conservative control bounds.
Functions, provider methods, continuation entries and cleanup routines use
the same reservation and emission mechanism. Source contracts remain
available for interfaces and diagnostics; target signatures contain explicit
provider arguments and control paths, with no source effect rows.

At a possible suspension, share a named entry for the remaining computation.
A normal return tail-calls it with ordinary arguments; a yield saves those
inputs in a GC frame. The baseline uses yield bubbling and needs no analysis
to recover local control flow from allocated continuations. Each caller
through which control escapes preserves its remaining work up to the
delimiter. A queued continuation retains its captures and ownership, with
outstanding providers supplied when invoked. Tail-call instructions transfer
control but do not capture a Wasm activation. Separate compilation must
expose the checked generic bodies and identities needed for downstream
provider specialization.
The worklist reserves nominal frame families, registers their concrete
members and generates typed dispatch cases for requested provider mappings.
Runtime chain length and captured predecessors never enter specialization
keys. Nested scope frames retain internal handlers without retaining the
ambient providers that invocation must supply.

Validation must cover a direct and a control provider for the same class,
a generic higher-order consumer under each, nested providers, runtime
captures with shared specialized code, early exit and stored one-shot
resumption under a different local provider. Verify that outstanding
requirements use the resumer's providers while internal handler scopes are
restored. Check that both ordinary closures and resumptions enforce their
invocation and cleanup contracts. Reject inconsistent
provider method types, ambiguous instances, operation-local polymorphism,
erased provider selection and repeated use
of one-shot continuations. Execute linked Wasm and check simple direct-provider
specializations for ordinary calls without unnecessary continuation environments.
Also execute yielding paths and resumptions without relying on optimization.
Queue tests must accept smaller job rows, reject effects outside the queue's
bound, separate enqueue effects from invocation effects, and check cleanup
when jobs are cancelled. Exercise distinct concrete job types through the
closed package, and rebuild its dispatchers when a variant is added.
Transition tests must cover
IO before and after yield, paths that bypass suspension, wrapper calls,
multiple suspension points and recursive constraints.
Bootstrap and compiled execution must agree. The language's remaining gaps
are tracked in [issue #456](https://github.com/tsnl/snail-scheme/issues/456).

### Handling an effect

`(handle Name ((operation implementation) ...) body ...)` runs the body with
each operation of `Name` implemented:

```scheme
{{#include ../../../tests/programs/effects-handlers.sld:handle}}
```

```text
adding 3
adding 4
7
```

A handler implements each operation of its effect exactly once
(`tests/programs/error-handler.sld`). It names operations within its effect,
so they need not be imported. An implementation is a function with the
operation's type. The implementation of an ordinary operation returns to
the operation's caller exactly once, as a function call would; Koka calls
these `fun` operations.

### A handler removes its effect

```scheme
{{#include ../../../tests/programs/effects-handlers.sld:quietly}}
```

`quietly`'s argument may perform `Log` and anything else, `e`. The handler
removes `Log`, so `quietly` performs only `e`, and `quiet-total`, whose
action performs nothing else, is total. `(quiet-total (list 1 2 3))` is `6`.

### Implementations run outside their handler

An implementation runs with the handlers outside its own `handle`, so an
operation it performs goes to the next handler out:

```scheme
{{#include ../../../tests/programs/effects-handlers.sld:indented}}
```

```text
order
  adding 3
  adding 4
  total 7
```

`indented`'s implementation of `log` performs `log`, which reaches the
printing handler around it. Were it to reach its own handler, it would call
itself forever. Its row shows the rule: the handler removes the body's
`Log`, and its implementation adds `Log` back, for the handler outside. Of
two handlers of one effect, the inner one catches.

### A test double

A program written against an effect can run against a different handler in
a test:

```scheme
{{#include ../../../tests/programs/effects-handlers.sld:files}}
```

```scheme
{{#include ../../../tests/programs/effects-handlers.sld:run-files}}
```

```text
bonjour, disk
hello, memory
```

`greeting` is the same in both runs. `from-disk`'s implementation calls
`read-file`, which performs `fs`; by the rule above that goes to the
handlers outside `from-disk`'s, here the host, so `from-disk`'s row names
`fs`. `from-memory`'s does not: the test touches no file system at all.

### Handlers may hold state

An instance of a program runs on one thread, so a handler's implementation
may capture mutable state and change it. That includes a cell, an alias of
a procedure that reaches one, or a callback passed in
(`tests/programs/handler-shared-state.sld`):

```scheme
{{#include ../../../tests/programs/handler-shared-state.sld:counter}}
```

prints `23`. A handler must still be reusable, since a deep handler runs
its implementation again for each operation. Ordinary closures always are,
because they cannot capture a one-shot value. Fresh storage allocated
inside an invocation, and the operation's arguments, belong to that
invocation (`tests/programs/handler-captures.sld`).

### Defaults in Snail Scheme

After its operations, an effect's declaration may give a `default` clause,
which implements operations in Snail Scheme as a handler does:

```scheme
{{#include ../../../tests/programs/effects-handlers.sld:default}}
```

```text
shown by default
shown when verbose
```

A default runs when no handler of its effect is in scope. An ordinary
operation with a default works much like a Scheme parameter, with `handle`
in the role of `parameterize`. A default has its operation's type without
the operation's own effect, so it performs at most the operation's
[latent row](#latent-rows), here nothing: a default that writes to the
console is rejected (`tests/programs/error-default-effect.sld`). It also
performs at least that row. Every performer is charged the row, so the
[unused-effect rule](#claiming-only-what-the-body-performs) holds a
default to it, at its entry
(`tests/programs/error-default-unperformed.sld`). A default is a lambda or
a function's name, and an operation has at most one.

A control operation has no default. An effect declared with `(around-main)`
says the runtime supplies a delimiter around the root entry. `tasks` uses
this facility: `main` runs as a scheduled task and can yield or wait.
Loading a library runs no source initializer: top-level definitions bind
functions. Each call performs only the effects in its signature.

## Control handlers

### Control operations

An ordinary operation always returns to its caller. An operation declared
with `ctl` need not. Its implementation receives one more argument,
`resume`, the rest of the handled body, and decides what to do with it.
`resume` is linear, so the implementation uses it exactly once. The
simplest choice is to drop it, with `(drop resume)`, as an exception does
(`tests/programs/control-exception.sld`):

```scheme
{{#include ../../../tests/programs/control-exception.sld:parse-or}}
```

```text
123
not a digit: x
0
```

An implementation's result is the handler's answer: the value of the whole
`handle` expression. Its type, the answer type, is the type of the handled
body, here `I64`. `raise`'s own result type, also `I64`, is what `resume`
would take. This implementation drops `resume`, so nothing after the
`raise` runs, in `digit`, in `number`'s fold, or anywhere between them and
the handler, and `parse-or` answers `default`. A `FnOnce` held across an
abandoned operation is dropped and never called, and dropping it drops
what it captured ([drops that may
run](ownership.md#drops-that-may-run)); there is no `finally` clause
(`tests/programs/control-early-exit.sld`). An implementation that raises
again reaches the handler outside it, as an ordinary one does.

A control operation has no default: a default runs where no handler is,
and nothing there can be handed the rest of a computation
(`tests/programs/error-control-default.sld`). Its implementation runs
in the handler's outer context, like an ordinary one.

### Operations that never return

An exception's implementation never calls `resume`, but nothing in
`raise`'s type says so. An operation can say it: one that answers `Never`,
the type with no values in `(snail core base)`, cannot return to its
performer, so its implementation takes the operation's arguments alone
(`tests/programs/control-abortive.sld`):

```scheme
{{#include ../../../tests/programs/control-abortive.sld:fail}}
```

```text
added 1
added 2
added 3
6
added 1
failed: negative: -2
```

`(absurd never)`, of type `(∀ (A) (Fn Never → A))`, gives the call whatever
type the code around it needs, here `checked`'s `I64`. It is a `match` with
no clauses, which only a value of a type with no cases may have
(`tests/programs/error-match-empty.sld`). An implementation of such an
operation that takes `resume` is a type error
(`tests/programs/error-control-never-resume.sld`).

Since nothing resumes them, these operations cost less. A call that may
yield only to effects whose control operations all answer `Never` saves no
frame when it yields, and no code is compiled for resuming what follows
it. A failure inside a resumed computation still unwinds through every
handler between it and its own, as the fixture's generator shows.

### Resuming

`(resume answer)` runs the rest of the handled body, with `answer` as the
operation's result, to the handler's answer, and returns that answer, so
the implementation may build on it. A generator yields values to its
handler:

```scheme
{{#include ../../../tests/programs/effects-control.sld:collect}}
```

```scheme
{{#include ../../../tests/programs/effects-control.sld:run-collect}}
```

```text
1 2 3 4 5
```

Each `yield` stops `range` and hands its value to the implementation, which
conses it onto whatever the rest of the body produces. The body ends with
`(Nil)`, the answer when nothing more is yielded. An implementation may also
choose, value by value, whether to resume:

```scheme
{{#include ../../../tests/programs/effects-control.sld:first-above}}
```

```text
4
-1
```

### Storing `resume`

`resume` is a `FnOnce`: a function that is called, or dropped, exactly once. It is
also first-class. An implementation may return it inside a value, and
whoever holds that value may call it later, after the `handle` has
returned:

```scheme
{{#include ../../../tests/programs/effects-control.sld:step}}
```

```text
1 10 2 11 3 12 13 14
```

`start` runs a generator to its first `yield`, and the implementation
returns the value with `resume` instead of calling it. `interleave` calls
each `next` long after `start` returned. A `Step` that holds a `FnOnce` is
linear itself, used exactly once ([ownership](ownership.md)).

The handler is deep: resuming re-installs it around the rest of the body,
so the generator's next `yield` reaches the same implementation, and
`(next (unit))` returns the next `Step`. That holds even where another
handler of the same effect is in scope: resumed inside a second `Gen`
handler, the generator still yields to the first, and the second receives
only what its own body yields
(`tests/programs/control-resume-same-effect.sld`). Outside the
re-installed handler, the resumed computation runs under the handlers in
scope where `resume` is called, not those that were in scope when it
started: `tests/programs/control-stored-resume.sld`
resumes two logging generators under a different `Log` handler from the
one they began under. Called inside another handler's implementation,
`resume` runs under that implementation's handlers: those outside its
`handle`, not those where its operation was performed. The re-installed
handler's own implementation runs outside it there too
(`tests/programs/control-resume-in-implementation.sld`).

### Closing over handlers

`inherit-handlers`, from `(snail core primitive)`, closes a one-shot thunk
over the handlers in scope where it is called, and `inherit-handlers-1`
closes a procedure of one argument, such as a `resume`. Wherever the `FnOnce`
it makes is called, the procedure's operations reach those handlers, even
after their handles have returned:

```scheme
{{#include ../../../tests/programs/control-inherit.sld:thunk}}
```

```text
second log: before the thunk
first log: a thunk
```

The caller of `inherit-handlers` is charged the procedure's row, as if it
ran the procedure there. The `FnOnce` it makes performs `host` instead: the
captured handlers answer the effects the row declares, and what remains,
`mut` and the effects the host implements, happens when it runs. So pure
code cannot call it (`tests/programs/error-inherit-pure.sld`), and one type
serves work of every row, as the steps of a scheduler need:

```scheme
{{#include ../../../tests/programs/control-inherit.sld:resume}}
```

Each step resumes under the log in scope where the generator yielded,
unlike `control-stored-resume`'s. A closed procedure cannot yield to a
control effect, whose handle may be gone by the time it runs, except to
a handle that cannot be gone: one inside the procedure, or inside a
function it calls, and the handle whose implementation closes its own
`resume`, which runs the rest of the body under that handler again.
These are how a scheduler closes each step of a task
([task operations](../runtimes/tasks.md#how-a-task-runs)).

### The type of `resume`

`resume` takes the operation's result and returns the handler's answer,
and it performs the row of the code around the `handle`, its **context
row**. For `(ctl yield (Fn I64 → I64))` handled in a function of row `Log`,
whose handler answers `Step`, `resume` is `(FnOnce I64 → Step ! Log)`.

Calling `resume` runs under the caller's handlers everything the `handle`
would perform outward: the rest of the body, and, since the handler is
deep, each implementation that runs again when the body performs the
effect once more. Both are in the context row. So a `Step` that stores
`resume` must name the effects its implementation performs
(`tests/programs/error-control-resume-row.sld`):

```scheme
{{#include ../../../tests/programs/error-control-resume-row.sld:step}}
```

```text
{{#include ../../../tests/programs/error-control-resume-row.err}}
```

Typed `(FnOnce I64 → Step ! Log)`, the stored `next` is resumed under a
`Log` handler, the one where it is called, and the `rest` left unrun is
dropped under one too, since dropping a resumption performs its row
([Drops that may run](ownership.md#drops-that-may-run))
(`tests/programs/control-resume-row.sld`):

```text
{{#include ../../../tests/programs/control-resume-row.out}}
```

The context row over-approximates, as Koka's does: a stored resumption
demands every effect of the handle's context row, even one that only the
code around the `handle` performs. And since calling `resume` performs
that whole row, a function whose control implementation calls `resume`
counts every effect of its signature as performed, so the
[unused-effect rule](#claiming-only-what-the-body-performs) cannot flag
one there. A row of the `handle`'s own, the body's and the
implementations' effects alone, would need row inclusion that the checker,
must preserve once a rigid tail
such as `e` is involved.

### Loops in constant stack

An implementation that calls `resume` in tail position runs in constant
stack (`tests/programs/control-tail-loop.sld`):

```scheme
{{#include ../../../tests/programs/control-tail-loop.sld:count-down}}
```

```text
10000100000
```

A hundred thousand yields grow neither the loop's stack nor the handler's.

### One shot

`resume` is one-shot, so the checker rejects calling it twice. Nothing
checks again at run time: a linear value cannot reach `Any`, a global or
an export, so no unchecked path can call it twice either.
`tests/programs/error-control-resume-twice.sld`:

```scheme
{{#include ../../../tests/programs/error-control-resume-twice.sld}}
```

```text
{{#include ../../../tests/programs/error-control-resume-twice.err}}
```

Multi-shot continuations are out of scope: they would need every frame to
be reachable twice, a cost paid by code that never captures one.

### Where control cannot reach

A yield returns through each frame between the operation and its handler,
so every frame on that path must expect it. A control row cannot reach a
`vector-generate` or `string-generate` callback, which a WAT loop calls; an
`unsafe-total` thunk, whose row the call discards; dispatched work, which
runs later under its task's own handler of `tasks`, and so may yield to
`tasks` alone; a procedure closed over its handlers, which may run after
their handles have returned; or the
implementation of an operation declared without `ctl`, the subject of the
next section. Each is
an error after specialization. A generic function used where a control
operation may be performed is specialized at that row, so its callback rows
name the effect too: `vector-map`, which calls `vector-generate`, cannot be
used in such a body even with a callback that cannot abort.

Nor can a control row pass through `Any`, whose TypeId records no rows: a
yielding function converted to `Any` and back could be called as a total
one, with no test for its yield. No function that performs effects, of any
kind, converts to `Any`
(`tests/programs/error-any-control-function.sld`,
[dynamic values](types.md#dynamic-values)).

## Latent handlers

### One handler for every task

Suppose a program puts one handler of an effect `Io`, say for its sockets,
around everything it does, and runs each task under a scheduler of its own:
a handler of a control effect, `Async`, whose implementation of `await`
keeps the task's `resume` until its data arrives. `Io`'s operation `fetch`,
a read, must wait for data, and the wait must suspend the task that read,
not the whole program.

The implementation of `fetch` cannot just perform `await`. It runs outside
its own handler, where no task's scheduler is in scope. And the
implementation of an ordinary operation may not perform a control operation
its type does not name at all
(`tests/programs/error-control-implementation.sld`):

```scheme
{{#include ../../../tests/programs/error-control-implementation.sld}}
```

```text
{{#include ../../../tests/programs/error-control-implementation.err}}
```

### Latent rows

An ordinary operation's type may name effects besides its own, its
**latent row**: those its implementations perform where it is performed.
`tests/programs/control-latent.sld` has `fetch` name `Async`:

```scheme
{{#include ../../../tests/programs/control-latent.sld:effects}}
```

Performing `fetch` charges the caller `Io` and `Async`, so the call may
suspend. An implementation of `fetch` may perform `Async`, and those
operations go to the handlers **in scope where `fetch` was performed**, not
to those outside the `Io` handler. Its other operations go to the handlers
outside `Io`'s, as for any implementation. A yield leaves the
implementation through the performer, and `resume` comes back into it.
After that, its latent operations still go to the handlers where `fetch`
was performed, as the resume left them: the task's own handler,
re-installed, and beyond it the handlers in scope where the task was
resumed. Resumed inside another task, `fetch` still waits on its own
task's handler, and logs to the log around the resume
(`tests/programs/control-latent-resumed.sld`).

### A way to avoid sneaking effects into callers

The rule is a way to avoid sneaking effects into callers. The caller of
`fetch` is charged `Async` in its own type, so it can see that `fetch` may
wait, and it must provide the `Async` handler that `fetch` waits on.
Whatever `fetch` does to its caller, the caller's type says.

Suppose instead that `fetch`'s `await` went to an `Async` handler outside
the `Io` handler, where the caller cannot see it. Then `fetch` would suspend
more than its caller. It would also suspend the caller's own scheduler,
whose type says it never waits because it handles `Async` itself, and
everything between that scheduler and the outer handler. `Async` would
have been sneaked into code whose types do not mention it.

That code was also compiled believing `Async` was already handled: only a
call whose callee's row names a control effect checks for a yield
(`control.sld` in the [compiler tour](compilers.md)). A yield aimed
further out would return through frames compiled without a test for one.
The error above closes the other way in: an operation whose type names no
control effect may not yield at all.

`tests/programs/control-latent-performer.sld` installs an `Async` handler
on each side of `Io`'s; the inner one answers:

```scheme
{{#include ../../../tests/programs/control-latent-performer.sld}}
```

```text
{{#include ../../../tests/programs/control-latent-performer.out}}
```

### Tasks with schedulers of their own

The rest of `control-latent.sld` is the program from the start of this
section. Each task runs under its own `Async` handler, which hands back the
rest of the task at each `await`:

```scheme
{{#include ../../../tests/programs/control-latent.sld:tasks}}
```

One `Io` handler surrounds both tasks. `alternate`, not shown, answers each
wait with ten times its ticket, switching between the tasks long after
their handlers returned:

```scheme
{{#include ../../../tests/programs/control-latent.sld:io}}
```

```text
task 1 fetches 10
task 2 fetches 20
waiting on 10
fetched 101
task 1 fetches 11
waiting on 20
fetched 201
task 2 fetches 21
waiting on 11
waiting on 21
done with 212
done with 412
```

Each `fetch` asks the task that performed it for its id, and its `await`
suspends that task alone.

Can an `Io` handler whose implementation performs `await` be installed
where no `Async` handler is in scope at all? Yes: this one is, at the top
level of the program. The `Async` that `fetch` performs is resolved where
`fetch` is called, so a later `handle Async` inside the `Io` handler, here
each task's, is what lets code call `fetch`. Calling `fetch` where no
`Async` handler is in scope is still an error, as for any unhandled effect
(`tests/programs/error-control-latent-unhandled.sld`).

### Ordinary effects in a latent row

An ordinary effect in a latent row goes to the performer's handler the same
way:

```scheme
{{#include ../../../tests/programs/control-latent.sld:notes}}
```

```text
outer log: before
inner log: note inside
```

`note`'s implementation logs to the `Log` handler in scope where `note` is
performed, the inner one, not to the one around the `Notes` handler.
Without `! Log` in `note`'s type, it would log to the outer one, as any
implementation does.

### Defaults that perform latent effects

A default runs under the handlers in scope where its operation is
performed, so it may perform its operation's latent row there
(`tests/programs/control-default.sld`):

```scheme
{{#include ../../../tests/programs/control-default.sld:clock}}
```

`sleep-until`'s default, `wait-for`, awaits on its caller's `Async`
handler. That program runs a task that sleeps twice under a scheduler that
wakes each sleeper at its deadline:

```text
waiting until 1005
woke at 1005
waiting until 1006
done at 1006
```

### The rules

- An implementation may yield only to the control effects its operation's
  type names (`tests/programs/error-control-latent-implementation.sld`).
- A control operation has no latent row, since its implementation runs
  where its handler is, once the body has unwound to it
  (`tests/programs/error-control-latent-ctl.sld`).
- No latent row names its operation's own effect.

The runtime's own tasks follow this pattern. `(snail shell task)` runs
each task under its own handler of `tasks`, whose control operations hand
the rest of the task to a scheduler written in Snail Scheme, and a host
operation's default awaits a ticket on the caller's `tasks`
([task operations](../runtimes/tasks.md)).
