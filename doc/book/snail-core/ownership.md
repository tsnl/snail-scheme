# Ownership

A value has a **grade**: how many times a program may use it. Grades
belong to types, not to individual bindings. This chapter states the rules
the compiler enforces, then what
[#550](https://github.com/tsnl/snail-scheme/issues/550) still proposes.

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
  linear field. A pure replacement, `(Job-attempts-set job 2)`, consumes a
  linear record and answers it with the other fields moved along, so it
  may replace an omega field, but not a linear one, whose content it would
  discard. An enum is linear even when its current variant has no fields.
- **The place rule.** A field operation other than a replacement acts on
  its record where it is, so applying one to a linear local does not
  consume the local. It may read only an omega field: a linear field
  leaves its record by destructuring. A linear record that is not a local
  has nowhere to stay, and such a field operation used as a value would
  consume the record it is applied to; both would leave the other fields
  with no owner, and are refused. A replacement's other operand is checked
  first, so it may read the record in place, as `(Job-attempts-set job (+
  (Job-attempts job) 1))` does.
- **Cells.** Locals are immutable, and so is every struct: a struct is a
  value with no identity, and a program that changes one holds it in a
  cell. `Ref` is the one struct with a mutable field, declared in
  `(snail core base)` as `(struct (Ref A) ((contents mut A)))`, the way
  OCaml declares `ref`; no other library may declare one. The writable
  places are a cell's content and an `Array`'s elements, and nothing else:
  there is no linear memory in the language.

  ```scheme
  {{#include ../../../tests/programs/cells.sld:counter}}
  ```

  - `(ref v)` builds a cell, purely. `ref-get` reads its content whole
    and `ref-set!` writes it, and both perform `mut`; `ref-replace!`
    swaps in a new value and hands back the old. A function whose type
    has no `mut` may still use them on a cell it allocates.
  - A *place* is a cell's content, `(ref-get r)`, or a chain of struct
    fields read from one, `(::count (ref-get r))` or `(::last::x (ref-get
    c))`. `(set! place v)` writes it and `(replace! place v)` swaps `v` in
    and answers the old content. The content lies in the cell, so a place
    is one slot of the cell's object and a write stores there. Each link
    of a place is a struct's own field: an enum's case, a computed field
    and a field read through a requirement have no slot to write.
  - A chain of reads copies one value, the last field, out of its root:
    the fields along the way are addressed, not read, so `(::live
    (ref-get scheduler))` reads an unrestricted count out of a cell whose
    content is linear.
  - A cell's handle is unrestricted even when its content is linear, so a
    cell of work items may be shared, captured by an ordinary procedure,
    or named by a global. Linear content leaves only by a swap, which may
    reach a field of the content: `ref-get` would duplicate it and
    `ref-set!` or `set!` discard it, so neither accepts it.
  - A pattern can only skip a cell's content with `_`, since reading it
    performs `mut`. Skipping linear content abandons it if the cell is
    consumed there, as a lost cell abandons its content.
  - Two names for one cell see the same writes; a cell has identity, so it
    has no pure replacement and derives no instance.
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
  `(Copy T)`. An instance requires `Copy` the same way, in its `requires`,
  and is used only where its head gives that variable an unrestricted
  type: an instance of `(Twice (Option A))` that pairs a value with
  itself cannot be used at `(Option (FnOnce Unit))`.
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

`drop` is the method of a class over a row
([rows as parameters](types.md#rows-as-parameters)), declared in
`(snail core base)`:

```scheme
(typeclass (Drop e T)
  (: drop (-> T Unit ! e)))
```

What a drop runs, and so the row it performs, is found from `T` rather
than matched (`lifecycle-plan` and `lifecycle-rows` in
`capabilities.sld`):

- An omega value is released at no cost, and performs nothing; so is a
  `FnOnce`, without running it, and so is linear data whose drop would
  run nothing else, such as a list of `FnOnce`s, which is not walked. A
  `FnOnce`'s type does not say what it captured, so what a `once` lambda
  moved in is abandoned with it, not dropped: release it in the lambda,
  or keep it where a drop can reach it.
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
  whose glue would need a function for every depth. An instance of any
  class may require one too, with a row its method allows, as
  `(requires (Drop (! log) A))`, and each use is charged the same way.

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
dropped, or given to a function of its library, and so is a replacement
of one of its fields.

The compiler still inserts no drops, so an instance runs exactly where a
`drop` was written, or in glue such a drop runs. What a path that never
returns holds, what a dropped `resume`'s frames hold, what a dropped
`once` lambda captured, and what an unreachable cell holds are never
released, so an instance's method is not guaranteed to run. Leaks are
safe.

### Cloning

`clone` duplicates a value explicitly, and is the method of the other
class over a row:

```scheme
(typeclass (Clone e T)
  (: clone (-> T (Pair T T) ! e)))
```

It takes the value and hands it back with a copy, since a linear value
cannot be read without being consumed. What it runs is found from `T`,
as a drop's is:

- An omega value is shared: both halves of the pair are the one
  reference, and nothing is performed.
- A type with a Clone instance runs its method, and performs the row the
  instance's head names, as a Drop instance does, under the same rules. A
  type that a Drop instance or `(deriving Move)` made linear is copied
  only by an instance, since its library decides what a copy of one is:

  ```scheme
  {{#include ../../../tests/programs/clone.sld:ticket}}
  ```

- Other linear data runs glue, which takes the value apart, clones each
  linear immutable field, shares the others and builds the two values:
  cloning `(Pair (Ticket 2) "row two")` copies the ticket and shares the
  string, and a list of tickets is cloned element by element.
- A `FnOnce` runs once, so it has no clone, and neither has linear data
  with a mutable field without an instance, since a clone could only
  share that field's content.
- A definition that clones a value of a type variable `A` requires
  `(Clone e A)`, and an instance may require the clones of its
  variables, as a Drop instance may require their drops.

A clone's effects are charged where it is written, as a drop's are.

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
copy.

An interface asks for a function without an environment by its type,
`(Fn A B ! e)`, a third arrow beside `->` and `FnOnce`. It is
unrestricted, and it is a reference to code alone, which takes the
evidence and then the arguments and no closure, so a host or another
instance could call it with nothing to hand it:

```scheme
{{#include ../../../tests/programs/fn-type.sld:fn-type}}
```

A `fn`, and the name of a top-level function, have type `Fn` where it is
expected: as an argument to a parameter of that type, under `ann`, or as
a definition with that signature. Nothing else has it, not even a local
bound to a `fn`. A value called before its type is known is taken to be
an ordinary arrow, so a lambda that calls its `Fn` parameter, `(lambda (f)
(f x))`, needs that type from somewhere first, such as a pattern over a
list whose type is known. And no value converts on its own: an `Fn` is called
directly, as `(f x)`, and goes where a closure is expected inside a
lambda, `(lambda (x) (f x))`. Calling one passes the caller's handlers,
so it performs what its row says where it is called. An `Any` holds no
`Fn`, since a code reference is not the GC reference an `Any` holds;
data that holds one is, and crosses. `unsafe-cast` at an `Fn` is the
engine's cast of a `Funcref` alone, with no closure around it.

### Representation

A linear value is represented as an omega value of the same shape would
be: a `FnOnce` as the closure of its function type, and a linear struct
as the struct. Linearity is a fact the checker proves; nothing at run
time records it, and calling a `FnOnce`, matching a linear struct or
reading a field of one compiles as it would for an omega value. `drop`
releases its argument and does nothing else. The one thing linearity
changes is a replacement, below.

A struct is a value with no identity, since only `Ref` has a mutable
field and the language has no reference equality, so nothing can tell it
from a copy with the same fields. The compiler lays such a struct out inline where an immutable
field holds it: the parent is one GC struct whose fields include the
inner struct's, and no object of the inner type exists there. A
`Segment` of two points and a label is five Wasm fields:

```scheme
{{#include ../../../tests/programs/inline-fields.sld:segment}}
```

Building one nested, `(Segment (Point 1 2) (Point 3 4) "d")`, writes five
values into one allocation; `(Point-y (Segment-to s))` is one field read;
and a nested pattern reads the fields where they lie. A `Point` is its
own struct only where it is a value on its own: a local, an argument, a
result, a closure's capture, an Any or an element of an array, and reading
an inlined field as a whole builds one. A cell's content lies in the cell
the same way: a `(Ref Counter)` is one object whose mutable slots are the
counter's fields, and a place names one of them. A field keeps a
reference when it holds a cell, an enum, an array, a closure or an Any:
those have identity, or no single shape. An enum
case's fields follow the same rule after its tag, and a generic struct is
laid out at each instantiation, so a `(List Point)` cell holds its point's
two numbers beside the tail. A replacement of an inlined field copies or
writes each of its fields, and one that reads the record it replaces
evaluates every new field before writing any. No program can observe the
layout, so a later layout, such as arrays of inlined structs, changes
none. The test program `tests/programs/inline-fields.sld` shows each
case.

A linear struct leaves only by being taken apart, dropped or replaced, so
its reference has one owner, and a replacement of one writes the field
where it is and answers the same reference, where an omega struct is
copied:

```scheme
{{#include ../../../tests/programs/replace-linear.sld:retry}}
```

The decision is made for each ground type, so a generic body that the
checker treated as linear copies at an omega instantiation, whose caller
may still hold the record; a linear struct's fields are `mut` in Wasm for
that write.

So a moved-from local still refers to what it held until its frame
returns, and WasmGC decides when the payload is reclaimed: the engine's
liveness, not the language, bounds that retention. A Drop instance runs
where a drop is written, not when memory is reclaimed, and abandoning a
closure is not a substitute for cancelling an I/O registration: the
runtime owns and cancels those explicitly.

## Proposed: the rest of the linear design

*Proposed, not implemented; the remaining steps are in
[#550](https://github.com/tsnl/snail-scheme/issues/550).* The grades are
Rust's, with GC as the only heap; cells, OCaml's `ref`, with places,
`Drop`, `Clone` and in-place replacement are implemented, above. There are no
borrows, and none are planned: a linear value is passed to each operation
that uses it and handed back, however many calls that threads it through.

Shared memory between instances is a separate, unsafe library
([instances](../runtimes/instances.md)).
