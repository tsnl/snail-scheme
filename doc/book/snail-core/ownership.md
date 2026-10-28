# Ownership

A value has a **grade**: how many times a program may use it. Grades
belong to types, not to individual bindings. This chapter states the rules
the compiler enforces today, then the linear design that replaces them,
which is proposed in [#550](https://github.com/tsnl/snail-scheme/issues/550)
and not implemented.

## Implemented: one-shot work

`Once` gives a procedure grade `1`: it may be consumed at most once.
Ordinary procedures and ordinary data have grade `omega` and can be
reused.

```scheme
(import
 (snail core base)
 (snail core io))

(: greeting (-> String (Once (-> Unit ! console))))
(define (greeting name)
  (once (lambda () (write-line name))))

(let ((work (greeting "hello")))
  (call-once work))
```

`call-once` consumes the work item before entering its body, and so does
calling it directly, as `(work)`. Calling it again is a compile error. A
`Once` may hold a procedure of any arity, such as `(Once (-> I64 I64))`;
`once` builds thunks, and a control handler's `resume` is the other kind
([effects and handlers](effects.md#control-handlers)).

- **Moves.** Moving a `Once` to another binding, an argument, a result or
  a one-shot closure consumes the old binding. Both alternatives of an
  `if` may consume the same value, because only one runs; consuming it
  again after the `if` is rejected.
- **Affine data.** A concrete struct or enum containing an affine field is
  itself affine. Destructure it with `match`: its generated accessors and
  replacements would permit duplicate ownership, so they cannot be used.
  An enum is affine even when its current variant has no fields.
- **Captures.** Only a lambda supplied directly to `once` may capture
  affine values, and constructing it moves them in. An ordinary procedure
  is reusable, so capturing an affine value in one is an error. Taking an
  affine argument is fine: each invocation receives its own owner.
- **What cannot hold one.** Affine values cannot be globals, elements of
  `Ref`, `Array` or `Vector`, payloads erased into `Any`, or exports.
  Generic type variables range over unrestricted types only, so a generic
  `duplicate` cannot be instantiated with a work item.
- **Drops.** Unused bindings and fields are dropped on the path that does
  not use them. The ownership pass runs after specialization, before Wasm
  emission, and places each drop at the earliest point on a path where an
  owned binding has no remaining use.

### Representation

The backend represents an affine value as a cell holding a nullable
managed reference. A move clears the old cell and creates a new cell for
the same payload, without copying the payload. Invocation and discard
clear the final cell. Pattern tests only peek; a successful pattern then
moves its fields and clears the consumed containers.

These rules release ownership and keep old aliases from retaining what
they no longer own. WasmGC still decides when to reclaim memory. There are
no user destructors, and clearing a closure is not a substitute for
cancelling an I/O registration: the runtime owns and cancels those
explicitly.

## Proposed: linear values, cells and explicit drops

*Proposed, not implemented; the steps are in
[#550](https://github.com/tsnl/snail-scheme/issues/550).* The flavour is
Rust's, with GC as the only heap.

### Grades

A type is **linear**, used exactly once, or **omega**, duplicated and
discarded freely. Nothing else: the affine grade of today goes.

- A concrete struct or enum is omega unless a field is linear, it carries
  the compiler-owned `Move` marker, or it has a `Drop` instance. Most
  declarations need no annotation.
- A type variable is linear by default. `(Copy A)` makes it omega with
  implicit duplication; `(Clone e A)` duplicates explicitly, with
  `clone : (-> A (Pair A A) ! e)`. Requirements are declared in
  signatures, and a body that duplicates without one is told "this use
  needs `(Copy A)`".
- `Once`, and so `resume`, is linear. `Vector`, `Array`, `Any`, globals and
  exports hold omega values only.

### Using a linear value

The compiler inserts no drops. A linear value is released by a call
someone wrote: `(drop x)`, a consuming operation such as `close-receiver`,
or a `match` that moves its fields out. A linear name that reaches the end
of its scope unconsumed is a compile error, and so is a second use. Both
arms of an `if` or `match` must agree.

```scheme
(: drop (All (A e) (requires (Drop e A)) (-> A Unit ! e)))
```

`Drop` is polymorphic over its effect, so a drop's effects appear exactly
where `drop` is written, in the row of the code that writes it. Control
effects in a drop's row are refused. A data type without an instance gets
derived glue; a type with an instance can be matched apart only inside its
own library. The list function `drop` becomes `list-drop`.

An abortive handler writes `(drop resume)`, unless its operation answers
`Never`, whose implementation already takes no `resume`
([effects](effects.md#operations-that-never-return)).

### Places

Locals are immutable. The writable places are a `Cell`'s content and an
array element, and nothing else: there are no borrows, no `RefMut`, and no
linear memory in the language.

- `Cell` is today's `Ref` cell, a shared mutable slot whose handle is
  omega. It may hold a linear value.
- `cell-get` and `cell-set!` need `(Copy A)`, because they duplicate or
  discard. `cell-replace!` swaps in a new value and returns the old one for
  the caller to consume.
- **The place rule.** Reading a `Copy` field of a linear binding, through
  an accessor or a `match` that moves nothing, does not consume it.
- Read-only borrows may come later, as a second-class `(Borrow T)`, if
  threading values and the place rule prove insufficient.

Shared memory between instances is a separate, unsafe library
([instances](../runtimes/instances.md)).

### Closures

An ordinary closure cannot capture a linear value. A `once` closure may,
and is then linear itself. Independently, the core closure form states
whether it may capture at all; the surface `lambda` defaults to "may
capture", and a closure marked capture-free that captures is an error.

### What linearity does not cover

- Dropping a `resume` abandons the linear values in its frames, because
  nothing runs them.
- A linear value left in an unreachable `Cell` is never released.

Leaks are safe, as in Rust; these are documented, not prevented.
