# Notable omissions

`snail-scheme` is deliberately smaller than its first plan. These parts were dropped
because they would cost more than they give the programs `snail-scheme` runs today;
each can return if a program needs it.

## Cut from the plan

- **The dependent elaborator.** Generic code is served by Hindley–Milner
  checking with typeclasses and monomorphization. Normalization
  by evaluation and implicit arguments would add type-level computation
  no program uses.
- **Linear types and counted ownership.** The collector reclaims ordinary
  values. The [scoped ref prototype](values.md#call-scoped-refs) checks
  access during a call. There is no `FnOnce`,
  `Rc`, `WeakRc`, `Drop` or `Copy`, and no finalizer: a resource has an
  explicit close operation. A second call of `resume` panics at run time
  instead of being rejected by the checker
  ([#767](https://github.com/tsnl/snail-scheme/issues/767)).
- **Algebraic effects and effect rows.** Effect declarations, handlers
  and rows are gone
  ([#877](https://github.com/tsnl/snail-scheme/issues/877)). What they
  gave is had with less: a [capability](capabilities.md#capabilities) is a
  value a function is given, and [suspension](suspension.md) is three
  functions. A function's arguments determine which host capabilities it
  can use. Writes through ordinary shared values are a matter of
  convention. [Capabilities](capabilities.md#what-a-signature-does-not-say)
  Divergence was never tracked; a row is the one way it could be, since
  nothing can be handed to a function to let it loop.
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
- Classes have no superclasses, no associated types, and no
  higher-kinded parameters.
- Wire TypeIds are 32 bits, and every record and enum value carries its
  case's TypeId.

`snail-scheme` deliberately omits R7RS compatibility, `call/cc`, `dynamic-wind`,
a dynamic numeric tower, source borrows, callable classes, `dyn`, `impl`,
`FnMut` and inline records. These are design decisions, not compatibility
bugs waiting for implementation. A top level has no statements: a
program's entry is its `main`. A top-level value's initializer is handed
no capability. Instance
dispatch, named instance sets, plugins, code pointers, declaration metadata,
implicit Any conversions and resizable arrays have also been removed.

Mutually recursive local functions, class superclasses, literals at generic
numeric types and overflow-checked arithmetic remain possible future work.
The [roadmap](https://github.com/tsnl/snail-scheme/issues/729) tracks the
current priorities.
