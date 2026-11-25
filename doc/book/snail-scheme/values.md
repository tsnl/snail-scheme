# Values

Ordinary values may be shared. Records and enums are heap objects with identity;
primitive numbers and booleans remain unboxed. Passing a record, binding it
to another name, storing it in a field or capturing it in a closure refers to
the same object. The runtime reclaims unreachable shared objects, including
cycles, in the instance's linear memory. Call-scoped refs can instead use
private storage for the lifetime of an activation. Creating or forwarding
a scoped slot requires no managed allocation. Other allocations in the
same function can still trigger collection.

## Mutable records

Record fields are mutable by default. A field declaration is `(name Type)`.
Local bindings themselves are not reassigned. Aliases of a record observe writes to
that record, including writes through another enclosing record.

```scheme
(record Counter
  ((value I64)))

(define (increment! (counter Counter)) (→ Unit)
  (set! (● counter value) (+ (● counter value) 1)))
```

Whoever holds a record may select and update its fields: nothing in a
signature says which a function does, so one that writes is named with a
trailing `!`, and one that only reads is not
([capabilities](capabilities.md#what-a-signature-does-not-say)). To exchange a field's value, read it,
then `set!` the new one.

`Name-field-set` is a pure replacement operation: it returns another record
with that field replaced, sharing the values of the others. Use `set!` on a
`●` path for mutation. There are no generated mutable setters.

## Call-scoped refs

A parameter of type `(Ref T)` can read its caller's storage. A parameter
of type `(MutRef T)` can also write it and has exclusive access during
the call. Here the caller's position and velocity have the physics
library's existing `V3` type.

```scheme
{{#include ../../../tests/programs/scoped-refs.scm:integrate}}
```

Use `ref-local` as the initializer of a local binding to create an owner.
The slot takes a snapshot of its initializer. Reading a whole record with
`ref-get` makes an independent snapshot too. Reading or writing a field
through the slot acts directly on that field. Use `ref-set!` to replace
the whole contents from a value.

```scheme
(let ((p (ref-local (v3 1.0 2.0 3.0)))
      (v (ref-local (v3 4.0 -2.0 6.0))))
  (step! (ref! p) (ref v))
  (ref-get p))  ;; (3.0, 1.0, 6.0) as an ordinary V3
```

An argument written `(ref p)` reserves shared access from that argument
until the call returns. Multiple readers can use the same slot.
`(ref! p)` reserves exclusive access. Subsequent arguments are evaluated
left to right and must respect earlier reservations. Compute a scalar
from `p` before passing `(ref! p)` if the same call needs both.

Only a direct call to a named, typed Snail function can forward a ref.
Closures, fields, containers, `Any`, generic value parameters and host
calls cannot retain one. A tail call may forward an incoming parameter.
Lending a local owner in tail position would discard its frame and is a
compile error. A resumable suspension can occur after the last use of a
ref. If a continuation would keep either a ref or its local owner, the
build reports the suspension. A prompt with answer type `Never` discards
the frame.

A slot holds a scalar or a record whose fields are all scalars. Each slot
occupies aligned storage in the caller's frame. A loan passes its address.
Returning or tail-calling releases the frame. Reading a field compiles
to a load, and writing it compiles to a store. Nested records, array payloads
and loans of individual fields or elements are outside the current language.

## Sharing

Sharing a value preserves its identity. There is no general `Clone` class or
implicit deep copy. Construct a new record or copy an array when independent
mutable state is needed.

A function that constructs a value makes a fresh one at each call. A
[top-level value](types.md#top-level-values) is constructed once and shared
by every reader.

## Closures

`(Fn A → B)` is the built-in callable type former. A closure may capture
ordinary values, and may be called any number of times. A named top-level function
has no capture environment. The backend represents any closure without
captures as an immutable global. There is no separate code pointer type,
callable class, `FnMut`, `dyn`, or `impl` form.

A `with-prompt`'s `resume` is an `Fn` too, but the frames it holds run at
most once: calling it a second time panics with `resume called twice`. A
handler that never calls it leaves the suspended frames to the collector,
and nothing in them runs ([suspension](suspension.md#resuming-once)).

## Resources

A value that stands for something outside the managed heap, such as a socket,
a child process or a file read in flight, carries a host handle. Its library
offers an explicit operation that releases the handle, such as
`close-connection`; nothing releases it when the value becomes unreachable,
since there are no finalizers.

A fatal panic, a terminal Wasm trap or divergence ends the computation.
Hosts close the failed run or instance; they do not continue an interrupted
source activation.

## Representation

Shared records and arrays have an eight-byte header in linear memory. Its
first word identifies the layout. An array's second word holds its length.
Record fields follow at their natural alignment. A scalar array stores packed
elements at their Wasm width. An array of ordinary records stores addresses
so that updating a record through an alias preserves its identity. A payload
enum stores its case tag before its fields. An `Any` holds its TypeId and
a reference to its payload, with a box for a scalar. A closure holds its code
descriptor and its captures. Indirect calls go through the instance's table.
The compiler identifies the fields and arrays that hold references. The
collector follows those references from active calls, globals and host-held
values. Scalar buffers, record padding and scoped scalar storage are skipped.
