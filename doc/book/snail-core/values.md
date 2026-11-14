# Values

Every value may be shared. Records and enums are heap objects with identity;
primitive numbers and booleans remain unboxed. Passing a record, binding it
to another name, storing it in a field or capturing it in a closure refers to
the same object, and the Wasm engine's collector reclaims it once nothing
reaches it. There are no linear types, reference counts, destructors or
borrows, and the compiler inserts no ownership operations.

## Mutable records

Record fields are mutable by default. A field declaration is `(name Type)`;
there is no per-field `mut` annotation and no separate `Ref` cell type. Local
bindings themselves are not reassigned. Aliases of a record observe writes to
that record, including writes through another enclosing record.

```scheme
(record Counter
  ((value I64)))

(define (increment (counter Counter)) (→ Unit) (! mut)
  (set! (● counter value) (+ (● counter value) 1)))
```

Selecting a field is pure. Updating a field requires `mut`, even when its
receiver was allocated locally. The compiler does not infer a mutation
exemption from allocation locality. To exchange a field's value, read it,
then `set!` the new one.

`Name-field-set` is a pure replacement operation: it returns another record
with that field replaced, sharing the values of the others. Use `set!` on a
`●` path for mutation. There are no generated mutable setters.

## Sharing

Sharing a value preserves its identity. There is no general `Clone` class or
implicit deep copy. Construct a new record or copy a vector when independent
mutable state is needed.

Factories construct fresh values. Bind a result once and pass it to its users
when they should share one object. There is no implicit global instance.

## Closures

`(Fn A → B ! e)` is the built-in callable type former. A closure may capture
any value, and may be called any number of times. A named top-level function
has no capture environment. The backend represents any closure without
captures as an immutable global. There is no separate code pointer type,
callable class, `FnMut`, `dyn`, or `impl` form.

A control handler's `resume` is an `Fn` too, but the frames it holds run at
most once: calling it a second time panics with `resume called twice`. An
implementation that never calls it leaves the suspended frames to the
collector, and nothing in them runs ([effects](effects.md#resuming-once)).

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

Every nominal aggregate is a WasmGC object. A field contains one scalar or one
managed reference; nested records are never flattened into their owners. An
enum case stores its tag before its fields. Vectors are WasmGC arrays with
fixed runtime lengths, of any element type. An `Any` pairs its type's TypeId
with the value, boxed when it is a scalar. A closure is a struct of its code
followed by its captures. No object carries a header beyond these fields, and
the engine traces all of them.
