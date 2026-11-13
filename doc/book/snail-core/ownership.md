# Ownership

Snail Scheme distinguishes values that can be shared from values that must be
used exactly once. This is a property of the type. Structs always have heap
identity; primitives remain unboxed. There is no borrow type, borrow checker,
or exclusive access mode.

## Linear and shared values

`(FnOnce A → B ! e)` is linear. Calling it, moving it to another owner, or
passing it to `drop` consumes that value. A normally returning path must consume
each linear local exactly once. Both branches of an `if`, and all alternatives
of a `match`, must consume the same linear owners.

A struct or enum containing a linear field is itself linear, including when
that field can be mutated. Substituting type arguments can therefore change a
container's grade: `(List I64)` can be shared, while `(List (FnOnce → Unit))`
is linear. An enum's grade describes all its variants, even when the current
variant has no fields. A user `Drop` instance or `(deriving Move)` also makes
a nominal type linear.

`Rc` is the only owning type that can hold linear content without becoming
linear itself. `WeakRc` does not own its content. Vectors require
`Copy` elements; they cannot hide a linear owner. An `Any` conversion cannot
hide linear content or cleanup effects. A linear value cannot be a top-level
constant or an exposed host value.

Type variables are linear unless constrained by `(Copy T)`. This lets a generic
body move an arbitrary `T`, while duplication requires an explicit proof:

```scheme
(define (swap (pair (Pair A B))) (→ (Pair B A)) (∀ (A B))
  (match pair ((Pair left right) (Pair right left))))

(define (twice (value T)) (→ (Pair T T)) (∀ (T)) (⊨ (Copy T))
  (Pair value value))
```

`Copy` permits sharing and omission of a value. It does not promise that
releasing the last reference is effect-free. A generic function that owns and
disposes of shared arguments also needs `(Drop e T)`, and its signature must
allow `e`. This matters for an `Rc` or a closure that owns counted resources.

## Mutable records

Struct fields are mutable by default. A field declaration is `(name Type)`;
there is no per-field `mut` annotation and no separate `Ref` cell type. Local
bindings themselves are not reassigned. Aliases of a record observe writes to
that record, including writes through another enclosing record.

```scheme
(struct Counter
  ((value I64)))

(define (increment (counter Counter)) (→ Unit) (! mut)
  (set! (● counter value) (+ (● counter value) 1)))
```

Selecting a field is pure. Its result has the field's ordinary ownership
contract; disposing of that result can have cleanup effects. Updating a field
requires `mut`, even when its receiver was allocated locally. The compiler does
not infer a mutation exemption from allocation locality.

A `Copy` field can be read repeatedly. Reading a linear field while leaving it
in its owner would duplicate it and is rejected. Use `match` to consume the
whole record, or `replace!` to exchange a field for another value and receive
the old owner. Replacing an optional work item with `None` is a useful pattern.
`set!` cannot silently discard a linear field.

`Name-field-set` is a pure replacement operation. It returns another record;
when its input is linear, it transfers that record's other fields to the result.
`Name-field-set!` mutates a field, and `Name-field-replace!` also returns the
previous value. The `!` distinguishes mutation from a pure replacement.

## Reference-counted ownership

`(rc value)` moves its argument into an `(Rc T)`. Copying an `Rc` creates another
strong reference. The compiler inserts retains and releases for assignments to
local bindings, argument passing, results, aggregate fields, closure captures,
and scope exits. Programs do not write a retain/release pair for an ordinary
copy.

The inner value remains mutable. Field paths project through `Rc`, so a
function can update `(● owner field)` without extracting or borrowing the
whole payload. `rc-get` is available only when the payload is `Copy`; it cannot
extract a second owner of a linear payload.

```scheme
(struct Work
  ((pending (Option (FnOnce → Unit ! output-port)))))

(define (run-pending (work (Rc Work))) (→ Unit) (! mut output-port)
  (match (replace! (● work pending) (None))
    ((Some run) (run))
    ((None) (unit))))
```

An `Rc` retains its payload until the last strong reference is released. That
release first marks the cell dead and clears its payload, then runs the
payload's selected `Drop` implementation. Cleanup therefore runs exactly once,
and a finalizer cannot revive its own dead cell through a weak reference.
Dropping an `Rc` requires `mut` and the payload's cleanup effects.

`(rc-downgrade owner)` produces a `(WeakRc T)` without adding a strong reference.
`(weak-rc-upgrade weak)` returns `Some` containing a new strong reference while
the cell is alive, and `None` after finalization. Weak references do not delay
finalization. Strong ownership cycles keep their resources alive; use a weak
edge or explicitly detach an edge when that relationship should not own its
other endpoint. WasmGC reclaims managed memory, but supplies no source-language
finalizer that could repair a strong reference cycle.

A local shared binding owns its reference until its scope ends. Calling `drop`
on a shared variable releases the reference passed to that call; another local
alias, including the original binding, remains an owner. Use a smaller lexical
scope when cleanup must finish before the next operation.

## Releasing

`drop` is the method of `(Drop e T)`:

```scheme
(typeclass (Drop e T)
  (: drop (Fn T → Unit ! e)))
```

The compiler derives cleanup from the concrete type, using a user instance when
one exists. A user instance belongs to the type's defining library and makes
that type linear. Other libraries consume such a value through its API or its
`Drop` implementation; they cannot bypass the instance by destructuring it.

```scheme
{{#include ../../../tests/programs/drop-instance.sld:handle}}
```

Derived cleanup takes linear data apart and releases its owned fields. Mutable
fields participate in ownership exactly as other fields do. Shared aggregates
own their fields once, regardless of how many aliases refer to the aggregate.
Their last release recursively releases the fields that contain counted owners.
Scalars and managed data with no counted content need no reference counter.

A `FnOnce` is dropped without invoking its ordinary body. Dropping an uncalled
closure releases its captures; dropping a resumption releases its suspended
frames. Cleanup effects are included in its callable row, excluding control
effects. A `Drop` implementation runs to completion and cannot itself declare
a control effect.

Cancellation releases saved scopes from inside out, with each scope's owners
in reverse binding order. Linear values and counted owners follow the same
ordered cleanup. A frame holds one ownership credit per captured owner, shared
by its mutually exclusive resume and cancel paths; hidden backup references
must not postpone a counted payload's finalizer past later cleanup actions.

A generic owner that disposes of `T` declares `(Drop e T)`. The compiler resolves
this requirement from `T`, including the effects of its fields and any user
instance. For example, a labelled resource can add its own cleanup effect to
its payload's:

```scheme
{{#include ../../../tests/programs/drop-requires.sld:labelled}}
```

### Drops that may run

The checker accounts for cleanup at explicit drops, ordinary shared scope
exits, and possible cancellation points. Inference defers these obligations
until the relevant types and effect rows are known. Tail calls retain their outgoing
arguments, then release the caller's remaining shared locals before entering
the callee. This keeps tail recursion at constant stack depth and makes that
cleanup order observable to finalizers. A function's effect row
must cover cleanup that can occur when its owned arguments or captures lose
their last reference.

A control handler's `resume` is a `FnOnce`. An implementation must invoke it,
transfer it to another owner, or drop it. An abortive operation returning
`Never` has no resumption argument: its abandoned owners are released before
the handler recovers. Catchable conversion failure uses the same control and
cleanup mechanism.

A stored resumption retains its nested handlers. Resuming or dropping it uses
the invocation or drop site's surrounding handlers outside its captured
delimiter. An explicitly inherited callable keeps the handlers captured by
`inherit-handlers` for both invocation and cancellation.

Fatal panic, a terminal Wasm trap, and divergence are different from handled
control flow. They do not promise source-level unwinding. Hosts close the
failed run or instance; they do not continue an interrupted source activation.

## Cloning

Sharing a `Copy` value preserves its identity. `clone` is a separate operation,
selected by `(Clone e T)`, that produces the two owners specified by its class
contract. For an unrestricted value it can share the value. A linear resource
needs an explicit cloning implementation or derived cloning of its fields.
There is no implicit deep clone when a record is assigned to another local.

Top-level lazy values follow the same sharing rule. Their initializer runs once,
and every read observes its cached object graph. Copy a vector or construct a
new record explicitly when a caller needs independent mutable state.

## Closures without an environment

`(Fn A → B ! e)` and `(FnOnce A → B ! e)` are built-in callable type formers.
`Fn` is reusable and may capture only non-linear values. Wrapping a linear owner
in `Rc` gives a reusable closure an ordinary shared capture. `once` constructs a
one-shot callable and can move linear captures into it. Applying `once` to an
existing reusable closure owns one reference to that closure; its other aliases
remain usable.

`(fn A → B ! e)` is noncapturing code. A `fn` expression cannot refer to an outer
local, and named top-level functions have no capture environment. There are no
callable classes, `FnMut`, `dyn`, or `impl` forms.

## Representation

Every nominal aggregate is a WasmGC object. A field contains one scalar or one
managed reference; nested structs are never flattened into their owners.
Vectors have fixed runtime lengths and may contain boxed aggregate elements.
A vector of counted elements counts aliases of the vector itself and releases
all its elements when the last owner leaves. Uncounted vectors are raw GC arrays
and need no owner counter. Elements must be `Copy`; use `Rc` to put a linear
resource in a slot. Replacement installs the incoming owner before releasing
the old element, and overlapping copies retain a snapshot before changing slots.

The reference-counting pass makes ownership operations explicit after specialization.
Reads of counted owners retain, calls transfer their owned operands, and scope
exits release them. Control preparation then records exactly which owners a
suspended frame must clean up. Ordinary functions and lazy initializers use
that same cleanup evidence. A lazy cache owns its result for the module's
lifetime, and each counted read retains a caller credit.

The `Rc` control cell stores a strong count, payload and finalizer. A `WeakRc`
uses the same cell without contributing to its count. Closures, dynamic boxes
and aggregate containers receive counts only where their representations need
to keep counted content alive. WasmGC traces their memory; explicit ownership
controls external resource lifetimes.
