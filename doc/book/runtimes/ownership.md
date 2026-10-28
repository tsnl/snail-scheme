# One-shot work and ownership

`Once` gives a procedure grade `1`: it may be consumed at most once.
Ordinary procedures and ordinary data have grade `omega` and can be
reused. These grades belong to types, not to individual bindings.

```scheme
(import
 (snail-core base)
 (snail-core io))

(: greeting (-> String (Once (-> Unit ! console))))
(define (greeting name)
  (once (lambda () (write-line name))))

(let ((work (greeting "hello")))
  (call-once work))
```

`call-once` consumes the work item before entering its body, and so does
calling it directly, as `(work)`. Calling it again is a compile error. A
`Once` may hold a procedure of any arity, such as `(Once (-> I64 I64))`;
`once` builds only thunks, and a one-shot continuation is the other kind.
Moving it to another binding, argument, result
or one-shot closure consumes the old binding. Both alternatives of an
`if` may consume the same value, because only one runs; consuming it again
after that `if` is rejected.

A concrete struct or enum containing an affine field is itself affine.
Destructure it with `match`; its generated accessors and replacements
would permit duplicate ownership and cannot be used. An enum is affine
even when its current variant has no fields. Unused bindings and fields
are dropped on the path that does not use them.

Only a lambda supplied directly to `once` may capture affine values.
Its construction moves those captures into the work item. An ordinary
procedure remains reusable, so capturing an affine value in one is an
error. Taking an affine argument is fine: each invocation receives its
own owner.

## Last use and representation

The ownership pass runs after specialization, before Wasm emission. It
places drops at the earliest point on a path where an owned binding has
no remaining use. An unused argument is dropped on entry, and an unused
binding just after its initializer. This does not wait for the end of the
lexical scope.

The initial backend represents an affine value as a cell containing a
nullable managed reference. A move clears the old cell and creates a new
cell for the same payload. It does not copy the payload. Invocation and
discard clear the final cell. Pattern tests only peek; a successful
pattern then moves its fields and clears the consumed containers.
Failed tests retain no raw payload temporaries across the selected body.

These rules release ownership and prevent old aliases from retaining its
owned descendants. WasmGC still decides when to reclaim managed memory.
This subset has no user destructors or first-class I/O continuations;
clearing a closure is not a substitute for cancelling an I/O registration.
The runtime must explicitly own and cancel those registrations.

## Deliberate limits

`Once` currently wraps only `(-> Unit ! effects)`. Existing generic type
variables range over unrestricted types: a generic `duplicate` cannot be
instantiated with a work item. Grade-polymorphic containers are future
work. Concrete record fields can contain `Once` today.

Affine values cannot be globals, elements of `Ref`, `Array` or `Vector`,
or payloads erased into `Any`. There are no borrowed references or user
defined drop operations. The static check establishes ownership within
Snail-Core; unsafe foreign code remains a trusted boundary.

A locally owned work item, or an ordinary handler, may capture a local
mutable cell. An instance is single-threaded, so nothing it holds is shared
with another thread.
