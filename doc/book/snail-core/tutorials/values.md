# Values and mutation

A record is a heap object. Assigning it another name shares that object;
all fields are mutable. The [field-path example](../types.md#data) shows
nominal selection through nested records.

Enum fields are mutable too. Their case-specific accessors and setters
check that the value has the expected case:

```scheme
{{#include ../../../../tests/programs/enum-mutation.sld}}
```

```text
{{#include ../../../../tests/programs/enum-mutation.out}}
```

The first three lines show two names observing one object. The last two
show a different rule for top-level constants: each read of `cycle` gets a
fresh graph, while the link inside each graph still points to itself.
Top-level values therefore provide reusable data without writable global
state. Runtime effects belong in `main` and other functions.

A value with a linear member is linear itself. Use `Rc` when several owners
must share a resource and its last release must run a finalizer; `WeakRc`
observes it without extending that lifetime. The compiler inserts reference
counts, so no borrow syntax or explicit cloning is needed to share an `Rc`.
See [ownership](../ownership.md) for examples and cleanup effects.
