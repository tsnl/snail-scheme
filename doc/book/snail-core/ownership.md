# Ownership

A value has a **grade**: how many times a program may use it. Grades
belong to types, not to individual bindings. This chapter states the rules
the compiler enforces today, then the rest of the linear design, which is
proposed in [#550](https://github.com/tsnl/snail-scheme/issues/550) and
not yet implemented.

## Implemented: linear one-shot work

`Once` makes a procedure **linear**: every path that returns uses it
exactly once. Ordinary procedures and ordinary data have grade `omega` and
can be reused or ignored.

```scheme
(import
 (snail core base)
 (snail core io))

(: greeting (-> String (Once (-> Unit ! console))))
(define (greeting name)
  (once (lambda () (write-line name))))

(let ((work (greeting "hello")))
  (call-once work))

(let ((unused (greeting "nobody")))
  (drop unused))
```

`call-once` consumes the work item before entering its body, and so does
calling it directly, as `(work)`. `drop` releases one without calling it.
A `Once` may hold a procedure of any arity, such as `(Once (-> I64 I64))`;
`once` builds thunks, and a control handler's `resume` is the other kind
([effects and handlers](effects.md#control-handlers)).

The compiler inserts no drops. A linear name still live at the end of the
scope that bound it is a compile error, "linear value never consumed", and
so is a second use.

- **Moves.** Moving a `Once` to another binding, an argument, a result or
  a one-shot closure consumes the old binding.
- **Alternatives.** Both arms of an `if`, and every clause of a `match`,
  must consume the same linear values, because only one of them runs.
- **Paths that never return.** A path that panics, or reaches a value of
  type `Never`, need not consume what it holds: it never reaches the end of
  its scopes. An abortive operation answers `Never`
  ([effects](effects.md#operations-that-never-return)), so
  `(absurd (fail diagnostic))` ends a path as a panic does.
- **Linear data.** A struct or enum containing a linear field, or applied
  to a linear type, is itself linear: `(List (Once (-> Unit)))` is. Destructure it with `match`, which moves the fields out;
  a wildcard cannot discard a linear field, and the generated accessors and
  replacements cannot be used, since they would give a field two owners.
  An enum is linear even when its current variant has no fields.
- **Captures.** Only a lambda supplied directly to `once` may capture
  linear values, and constructing it moves them in. An ordinary procedure
  is reusable, so capturing a linear value in one is an error. Taking a
  linear argument is fine: each invocation receives its own owner.
- **Type variables.** A type variable is linear unless its definition
  requires `(Copy A)`, so a generic body may only move a value of type
  `A`. Using one twice, discarding it, or passing it where `Copy` is
  required is an error that names the missing requirement. A definition
  that requires `(Copy A)` may duplicate and discard, and is used only at
  unrestricted types, so a generic `duplicate` cannot be instantiated with
  a work item. No class implies `Copy`: `max` requires `(Ord T)` and
  `(Copy T)`. An instance requires `Copy` the same way, in its `requires`.
- **What cannot hold one.** Linear values cannot be globals, elements of
  `Ref`, `Array` or `Vector`, payloads erased into `Any`, or exports, and a
  statement cannot discard one. Reading an element of a vector leaves it in
  place, so the vector and array primitives require `(Copy A)`, as do
  `ref-get` and `ref-set!`.
- **Handlers.** `resume` is a `Once`. An implementation that does not
  resume writes `(drop resume)`; one whose operation answers `Never` is
  handed no `resume` at all.

```scheme
(: swap (All (A B) (-> (Pair A B) (Pair B A))))
(define (swap pair)
  (match pair
    ((Pair a b) (Pair b a))))

(: twice (All (A) (requires (Copy A)) (-> A (Pair A A))))
(define (twice value)
  (Pair value value))
```

`swap` exchanges two work items; `twice` cannot take one. `map`, `for-each`
and the folds move each element once, so they take lists of work items;
`length`, `filter` and `member?` discard or duplicate elements, and require
`Copy`.

The check runs on each library's checked items, before specialization, so
a generic body is checked once for every instantiation.
Dropping a `resume`, or ending a path that never returns, abandons the
linear values held there, since nothing runs them. Leaks are safe, as in
Rust.

### Representation

The backend represents a linear value as a cell holding a nullable
managed reference. A move clears the old cell and creates a new cell for
the same payload, without copying the payload. Calling and dropping clear
the final cell. Pattern tests only peek; a successful pattern then moves
its fields and clears the consumed containers.

These rules release ownership and keep old aliases from retaining what
they no longer own. WasmGC still decides when to reclaim memory. There are
no user destructors, and clearing a closure is not a substitute for
cancelling an I/O registration: the runtime owns and cancels those
explicitly.

## Proposed: linear types, cells and `Drop`

*Proposed, not implemented; the remaining steps are in
[#550](https://github.com/tsnl/snail-scheme/issues/550).* The flavour is
Rust's, with GC as the only heap.

### Grades

A type stays **linear** or **omega**, and linearity reaches beyond `Once`:

- A concrete struct or enum is omega unless a field is linear, it carries
  the compiler-owned `Move` marker, or it has a `Drop` instance. Most
  declarations need no annotation.
- `(Clone e A)` duplicates explicitly, with
  `clone : (-> A (Pair A A) ! e)`. Like `Drop`, it is a class over an
  effect row; `(Copy A)` is implemented, above.
- `Vector`, `Array`, `Any`, globals and exports hold omega values only.

### Drop as a class

Today `drop` takes only a `Once`. It becomes the method of a class:

```scheme
(: drop (All (A e) (requires (Drop e A)) (-> A Unit ! e)))
```

`Drop` is polymorphic over its effect, so a drop's effects appear exactly
where `drop` is written, in the row of the code that writes it. Control
effects in a drop's row are refused. A data type without an instance gets
derived glue; a type with an instance can be matched apart only inside its
own library.

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

A linear value left in an unreachable `Cell` is never released, as a
dropped `resume` abandons what its frames hold. Leaks are safe; this is
documented, not prevented.
