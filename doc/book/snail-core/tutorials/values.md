# Values and mutation

A record is a heap object. Assigning it another name shares that object;
all fields are mutable. The [field-path example](../types.md#data) shows
nominal selection through nested records.

Select an enum case with `match`. Put mutable payload in a record, then use
`●`, `set!` and `replace!` to read or change its fields:

```scheme
{{#include ../../../../tests/programs/enum-mutation.sld}}
```

```text
{{#include ../../../../tests/programs/enum-mutation.out}}
```

The first three lines show two names observing one object. The last two
show a cyclic object's internal alias and a separate call to its factory.
Each call constructs a fresh graph; the second graph keeps its original value.
Bind a factory result once and pass it to callers that should share state.

A value with a linear member is linear itself. Use `Rc` when several owners
must share a resource and its last release must run a finalizer; `WeakRc`
observes it without extending that lifetime. The compiler inserts reference
counts, so no borrow syntax or explicit cloning is needed to share an `Rc`.
See [ownership](../ownership.md) for examples and cleanup effects.
