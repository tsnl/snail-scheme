# Notable omissions

Snail Scheme is deliberately smaller than its first plan. These parts were dropped
because they would cost more than they give the programs Snail Scheme runs today;
each can return if a program needs it.

## Cut from the plan

- **The dependent elaborator.** Generic code is served by Hindley–Milner
  checking with typeclasses, effect rows and monomorphization. Normalization
  by evaluation and implicit arguments would add type-level computation
  no program uses.
- **Linear types and counted ownership.** Every value may be shared, and
  the collector reclaims it ([values](values.md)). There is no `FnOnce`,
  `Rc`, `WeakRc`, `Drop` or `Copy`, and no finalizer: a resource has an
  explicit close operation. A second call of `resume` panics at run time
  instead of being rejected by the checker
  ([#767](https://github.com/tsnl/snail-scheme/issues/767)).
- **Incremental compiler state.** Every build expands, checks and emits its
  complete dependency closure. There is no retained compiler Session,
  interface hashing or checked-code/Wasm reuse. Wire schemas come from the
  checked program.
- **The WGSL backend.** The renderer's shaders are WGSL text that shares no
  records with Snail Scheme code beyond fixed instance and material layouts. The
  runtime and graphics plan proposes shaders written as S-expressions.
- **Actor destinations.** Tasks schedule one-shot closures and share
  `Mailbox` queues, which are values, not addresses of tasks. Request/reply
  protocols and network transports are application concerns.

## Simplifications made on the way

- Local bodies are sequential: a local function may call itself but not a
  later local definition.
- Named functions require an annotation on every parameter. Generic variables
  and class obligations appear on the definition. Direct lambda definitions
  can infer their function types; local values also use inference.
- Effect labels take no type parameters, and operations are monomorphic.
  [Parameterized effects](effects.md#proposed-parameterized-effects) are
  proposed with one fixed application per handler; operation-local
  polymorphism remains outside that design.
- Classes have no superclasses and no higher-kinded parameters.
- Wire TypeIds are 32 bits, and every record and enum value carries its
  case's TypeId.

Snail Scheme deliberately omits R7RS compatibility, `call/cc`, `dynamic-wind`,
a dynamic numeric tower, source borrows, callable classes, `dyn`, `impl`,
`FnMut` and inline records. These are design decisions, not compatibility
bugs waiting for implementation. Top-level definitions bind functions; there
are no global values, lazy caches or top-level statement execution. Instance
dispatch, named instance sets, plugins, code pointers, declaration metadata,
implicit Any conversions and resizable vectors have also been removed.

Mutually recursive local functions, class superclasses, literals at generic
numeric types and overflow-checked arithmetic remain possible future work.
The [roadmap](https://github.com/tsnl/snail-scheme/issues/729) tracks the
current priorities.
