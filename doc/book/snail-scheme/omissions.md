# Notable omissions

`snail-scheme` is deliberately smaller than its first plan. These parts were dropped
because they would cost more than they give the programs `snail-scheme` runs today;
each can return if a program needs it.

## Cut from the plan

- **The dependent elaborator.** Generic code is served by Hindley–Milner
  checking with typeclasses, rows and monomorphization. Normalization
  by evaluation and implicit arguments would add type-level computation
  no program uses.
- **Linear types and counted ownership.** Every value may be shared, and
  the collector reclaims it ([values](values.md)). There is no `FnOnce`,
  `Rc`, `WeakRc`, `Drop` or `Copy`, and no finalizer: a resource has an
  explicit close operation. A second call of `resume` panics at run time
  instead of being rejected by the checker
  ([#767](https://github.com/tsnl/snail-scheme/issues/767)).
- **Algebraic effects.** Effect declarations, handlers and rows of named
  effects are gone
  ([#877](https://github.com/tsnl/snail-scheme/issues/877)). What they
  gave is had with less: a [capability](effects.md#capabilities) is a
  value a function is given, `mut` is the one effect a row names, and
  [suspension](suspension.md) is three functions. What went with them: a
  row no longer says which part of the world a function touches, only that
  it touches something, and nothing in a type says a call may suspend.
- **Incremental compiler state.** Every build expands, checks and emits its
  complete dependency closure. There is no retained compiler Session,
  interface hashing or checked-code/Wasm reuse.
- **Actor destinations.** Tasks schedule one-shot closures and share
  `Mailbox` queues, which are values, not addresses of tasks. Request/reply
  protocols and network transports are application concerns.

## Simplifications made on the way

- Local bodies are sequential: a local function may call itself but not a
  later local definition.
- Named functions require an annotation on every parameter. Generic variables
  and class obligations appear on the definition. A lambda either takes
  that whole header or annotates nothing and is inferred; values also use
  inference.
- Classes have no superclasses, no associated types, and no row or
  higher-kinded parameters.
- Wire TypeIds are 32 bits, and every record and enum value carries its
  case's TypeId.

`snail-scheme` deliberately omits R7RS compatibility, `call/cc`, `dynamic-wind`,
a dynamic numeric tower, source borrows, callable classes, `dyn`, `impl`,
`FnMut` and inline records. These are design decisions, not compatibility
bugs waiting for implementation. A top level has no statements: a
program's entry is its `main`. A top-level value's initializer performs
no effect. Instance
dispatch, named instance sets, plugins, code pointers, declaration metadata,
implicit Any conversions and resizable arrays have also been removed.

Mutually recursive local functions, class superclasses, literals at generic
numeric types and overflow-checked arithmetic remain possible future work.
The [roadmap](https://github.com/tsnl/snail-scheme/issues/729) tracks the
current priorities.
