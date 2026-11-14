# Values and mutation

A record is a heap object. Assigning it another name shares that object;
all fields are mutable. The [field-path example](../types.md#data) shows
nominal selection through nested records.

Select an enum case with `match`. Put mutable payload in a record, then use
`●` and `set!` to read or change its fields:

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

Any value can be shared this way, with no borrow syntax or explicit cloning;
the collector reclaims it once nothing reaches it. See [values](../values.md)
for sharing, closures and resources.
