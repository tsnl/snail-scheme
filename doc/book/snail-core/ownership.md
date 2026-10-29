# Ownership

A value has a **grade**: how many times a program may use it. Grades
belong to types, not to individual bindings. This chapter states the rules
the compiler enforces today, then the rest of the linear design, which is
proposed in [#550](https://github.com/tsnl/snail-scheme/issues/550) and
not yet implemented.

## Implemented: linear one-shot work

`(FnOnce A B ! e)` is the **linear** arrow, beside the omega `->`: a
procedure of that type is used exactly once on every path that returns.
Ordinary procedures and ordinary data have grade `omega` and can be reused
or ignored.

```scheme
(import
 (snail core base)
 (snail core io))

(: greeting (-> String (FnOnce Unit ! console)))
(define (greeting name)
  (once (lambda () (write-line name))))

(let ((work (greeting "hello")))
  (call-once work))

(let ((unused (greeting "nobody")))
  (drop unused))
```

`call-once` consumes the work item before entering its body, and so does
calling it directly, as `(work)`. `drop` releases one without calling it,
and releases any other value too. A `FnOnce` may take any number of
arguments, as `(FnOnce I64 I64)` takes one; `once` builds thunks, and a
control handler's `resume` is the other kind
([effects and handlers](effects.md#control-handlers)).

The compiler inserts no drops. A linear name still live at the end of the
scope that bound it is a compile error, "linear value never consumed", and
so is a second use.

- **Moves.** Moving a `FnOnce` to another binding, an argument, a result or
  a one-shot closure consumes the old binding.
- **Alternatives.** Both arms of an `if`, and every clause of a `match`,
  must consume the same linear values, because only one of them runs.
- **Paths that never return.** A path that panics, or reaches a value of
  type `Never`, need not consume what it holds: it never reaches the end of
  its scopes. An abortive operation answers `Never`
  ([effects](effects.md#operations-that-never-return)), so
  `(absurd (fail diagnostic))` ends a path as a panic does.
- **Linear data.** A struct or enum with a linear field, once its
  parameters are bound, is itself linear: `(List (FnOnce Unit))` is. A
  field holding a linear value only inside a `Ref` does not count, so a
  `(Mailbox (FnOnce Unit))` is unrestricted. Destructure linear data
  with `match`, which moves the fields out; a wildcard cannot discard a
  linear field, and a pure replacement cannot be used, since it would copy
  the other fields. An enum is linear even when its current variant has no
  fields.
- **The place rule.** A field operation acts on its record where it is,
  so applying one to a linear local does not consume the local. It may
  read only an omega field: a linear field leaves its record by
  destructuring. A linear record that is not a local has nowhere to stay,
  and a field operation used as a value would consume the record it is
  applied to; both would leave the other fields with no owner, and are
  refused.
- **Mutable fields.** Locals are immutable. The writable places are a
  struct's mutable fields, a `Ref`'s content and an `Array`'s elements,
  and nothing else: there is no linear memory in the language. A field is
  mutable when its declaration says so, `(count mut I64)`:

  ```scheme
  {{#include ../../../tests/programs/mutable-fields.sld:counter}}
  ```

  - `Counter-count` reads the field and `Counter-count-set!` writes it,
    and both perform `mut`. Reading an immutable field and constructing a
    struct are pure, and so a function may build a counter without `mut`.
  - A struct with a mutable field has identity: two names for it see the
    same writes. So it has no pure replacements and derives no instances.
    A struct without one has no identity, so it could later be stored
    inline.
  - A mutable field never makes its struct linear. Its content leaves only
    by `Counter-count-replace!`, which stores a new value and returns the
    old one. Reading linear content would duplicate it and setting would
    discard it, so both are refused.
  - A pattern can only skip a mutable field with `_`, since reading one
    performs `mut`. Skipping one that holds linear content abandons it if
    the record is consumed there, as a lost cell abandons its content.
  - An enum's fields stay immutable: its case accessors are partial. A
    case that needs one holds a struct with a mutable field.
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
- **Cells.** `Ref` is a struct with one mutable field, declared in
  `(snail core base)` as `(struct (Ref A) ((contents mut A)))`, the way
  OCaml declares `ref`. `ref`, `ref-get`, `ref-set!` and `ref-replace!`
  are its constructor and field operations, exported under short names
  beside their own, so a cell keeps the rules of mutable fields. Its
  handle is unrestricted even when its content is linear, so a cell of
  work items may be shared, captured by an ordinary procedure, or named by
  a global. `ref` moves a value in, and `ref-replace!` swaps in a new one
  and hands back the old for the caller to consume. `ref-get` would
  duplicate linear content and `ref-set!` discard it, so neither accepts
  it.
- **What cannot hold one.** Linear values cannot be globals, elements of
  `Array` or `Vector`, payloads erased into `Any`, or exports, and a
  statement cannot discard one. Reading an element of a vector leaves it in
  place, so the vector and array primitives require `(Copy A)`.
- **Handlers.** `resume` is a `FnOnce`. An implementation that does not
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
the final cell. Pattern tests only peek, as do field operations on a
linear local; a successful pattern then moves its fields and clears the
consumed containers.

These rules release ownership and keep old aliases from retaining what
they no longer own. WasmGC still decides when to reclaim memory. There are
no user destructors, and clearing a closure is not a substitute for
cancelling an I/O registration: the runtime owns and cancels those
explicitly.

## Proposed: linear types and `Drop`

*Proposed, not implemented; the remaining steps are in
[#550](https://github.com/tsnl/snail-scheme/issues/550).* The grades are
Rust's, with GC as the only heap; the mutable fields, OCaml's, are
implemented, above. Safe borrows may come later.

### Grades

A type stays **linear** or **omega**, and linearity reaches beyond
`FnOnce`:

- A concrete struct or enum is omega unless an immutable field is linear,
  it carries the compiler-owned `Move` marker, or it has a `Drop`
  instance. Most declarations need no annotation. A linear struct leaves
  only by being destructured or dropped, so its reference has one owner,
  and a functional update of it may reuse the object in place.
- `(Clone e A)` duplicates explicitly, with
  `clone : (-> A (Pair A A) ! e)`. Like `Drop`, it is a class over an
  effect row; `(Copy A)` is implemented, above.
- `Any`, globals and exports hold omega values only. A `Vector`'s elements
  are immutable, so it may later take their grade, as `List` does; that
  waits for vector constructors that need no `Copy`.

### Drop as a class

Today `drop` takes any value, and only releases it, clearing a `FnOnce`
so nothing can call it. It becomes the method of a class:

```scheme
(: drop (All (A e) (requires (Drop e A)) (-> A Unit ! e)))
```

`Drop` is polymorphic over its effect, so a drop's effects appear exactly
where `drop` is written, in the row of the code that writes it. Control
effects in a drop's row are refused. A data type without an instance gets
derived glue; a type with an instance can be matched apart only inside its
own library.

Shared memory between instances is a separate, unsafe library
([instances](../runtimes/instances.md)).

### Closures

An ordinary closure cannot capture a linear value. A `once` closure may,
and is then linear itself. Independently, the core closure form states
whether it may capture at all; the surface `lambda` defaults to "may
capture", and a closure marked capture-free that captures is an error.

### What linearity does not cover

A linear value left in an unreachable `Ref` or mutable field is never
released, as a dropped `resume` abandons what its frames hold. Leaks are safe; this is
documented, not prevented.
