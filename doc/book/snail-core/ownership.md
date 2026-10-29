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
and releases any other value too ([releasing](#releasing)). A `FnOnce`
may take any number of arguments, as `(FnOnce I64 I64)` takes one; `once`
builds thunks, and a
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
  linear argument is fine: each invocation receives its own owner. A
  `fn` captures nothing at all ([below](#closures-without-an-environment)).
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
  statement cannot discard one. A vector is a reference that may be
  aliased, so it is always unrestricted, and reading an element leaves it
  in place, so the vector and array primitives require `(Copy A)`. Linear
  work goes in a vector behind a cell, as `(Vector (Ref (FnOnce Unit)))`.
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

### Releasing

`drop` is the method of a class over a row, declared in `(snail core
base)`:

```scheme
(typeclass (Drop e T)
  (: drop (-> T Unit ! e)))
```

What a drop runs, and so the row it performs, is found from `T` rather
than matched (`release` and `drop-rows` in `capabilities.sld`):

- An omega value and a `FnOnce` are released at no cost, and perform
  nothing; so is linear data whose drop would run nothing else, such as a
  list of `FnOnce`s, which is not walked.
- A type with an instance runs the instance's method, and performs the
  row the instance's head names:

  ```scheme
  {{#include ../../../tests/programs/drop-instance.sld:handle}}
  ```

- Other linear data runs **glue**, which takes the value apart and drops
  each linear immutable field in order: `(drop (Pair (Handle "two")
  (Handle "three")))` releases both handles, and a list of handles each
  of its elements. Glue is made by specialization, one function for each
  type it releases, and only where a field it reaches has an instance. A
  mutable field's content is abandoned, as a lost cell's is.
- A definition that drops a value of a type variable `A` requires
  `(Drop e A)`, with `e` in its row, and its callers are charged what
  dropping their `A` performs. Without the requirement, the drop is
  refused, as it is for a type that holds itself at other type arguments,
  whose glue would need a function for every depth.

A drop's effects are charged where it is written: once a call is checked,
the drops raised in it whose types are known are solved in its scope, so a
signature must allow what its drops perform. A drop whose type a later
use decides is solved with the program's other constraints.

An instance is checked where it is declared. Its row is written in its
head, as `(! log)`, since a drop of a ground type finds its instance by
the type's name alone, where no row variable could be solved. The row is
closed, or it ends with the row `e` of the instance's requirements
`(Drop e A)`, which a drop decides from the type it gives `A`:

```scheme
{{#include ../../../tests/programs/drop-requires.sld:labelled}}
```

Dropping a `(Labelled Handle)` performs `log` and what dropping the
handle performs; a `(Labelled I64)`, only `log`. The row names no control
effect: a drop runs to completion. And the instance is declared in its
type's library, for the type at distinct variables, requiring only
`Copy` and the drops of its variables, since what a drop runs is found
from its type alone.

An instance makes its type linear, as `(deriving Move)` makes linear a
type with nothing to release: `(struct Token ((id I64)) (deriving Move))`
must be used or dropped although its field is omega. Only the type's own
library may take a value with an instance apart with `match`, so the
instance decides how what it holds is released; elsewhere the value is
dropped, or given to a function of its library. A pure replacement is
refused on any linear record already.

The compiler still inserts no drops, so an instance runs exactly where a
`drop` was written, or in glue such a drop runs. What a path that never
returns holds, what a dropped `resume`'s frames hold, and what an
unreachable cell holds are never released, so an instance's method is not
guaranteed to run. Leaks are safe.

### Closures without an environment

The core closure form says whether it may capture. A surface `lambda`
may; a `fn`, written as a lambda is, may not:

```scheme
{{#include ../../../tests/programs/fn.sld:fn}}
```

A `fn` reads its parameters, the locals it binds, globals, and its own
name when a definition binds it, and it may perform any effect. Reading a
local of the code around it is an error, "a fn has no environment", and so
is reading one from a lambda inside it. A top-level function has no locals
around it, so the expander marks every one as a `fn`.

A `fn`'s type is the ordinary arrow, so it goes wherever a lambda does.
The checker establishes the fact, and the backend relies on it: a closure
that may not capture compiles to one immutable global, as any closure
without captures does, and the backend asserts that it found nothing to
copy. Nothing yet asks for one by type; see [proposed](#closures).

### Representation

A linear value is represented as an omega value of the same shape would
be: a `FnOnce` as the closure of its function type, and a linear struct
as the struct. Linearity is a fact the checker proves; nothing at run
time records it, and calling a `FnOnce`, matching a linear struct or
reading a field of one compiles as it would for an omega value. `drop`
releases its argument and does nothing else.

So a moved-from local still refers to what it held until its frame
returns, and WasmGC decides when the payload is reclaimed: the engine's
liveness, not the language, bounds that retention. A Drop instance runs
where a drop is written, not when memory is reclaimed, and abandoning a
closure is not a substitute for cancelling an I/O registration: the
runtime owns and cancels those explicitly.

## Proposed: the rest of the linear design

*Proposed, not implemented; the remaining steps are in
[#550](https://github.com/tsnl/snail-scheme/issues/550).* The grades are
Rust's, with GC as the only heap; the mutable fields, OCaml's, and `Drop`
are implemented, above. Safe borrows may come later.

### Grades

- A linear struct leaves only by being destructured or dropped, so its
  reference has one owner, and a functional update of it may reuse the
  object in place.
- `(Clone e A)` duplicates explicitly, with
  `clone : (-> A (Pair A A) ! e)`. Like `Drop`, it is a class over an
  effect row; `(Copy A)` is implemented, above.

Shared memory between instances is a separate, unsafe library
([instances](../runtimes/instances.md)).

### Closures

An interface will require a function without an environment by its type,
such as a host callback or the entry of another instance: a third arrow
beside `->` and `FnOnce`, unrestricted, represented as a bare function
reference that takes `$ev` first. A `fn` or a top-level name would be
accepted where that type is expected, and converted to `->` explicitly
where a closure is. Its name is open: Rust's `fn` pointer is the meaning,
but Rust's `Fn` names a closure that may capture.
