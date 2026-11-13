# Notable omissions

Snail Scheme is deliberately smaller than its first plan. These parts were dropped
because they would cost more than they give the programs Snail Scheme runs today;
each can return if a program needs it.

## Cut from the plan

- **The dependent elaborator.** Generic code is served by Hindley–Milner
  checking with typeclasses, effect rows and monomorphization. Normalization
  by evaluation and implicit arguments would add type-level computation
  no program uses. Ownership has two grades, linear and omega, found from
  a type's structure, a declaration's `Move` or `Drop`, and the
  `(Copy A)` a definition requires ([ownership](ownership.md)); there are
  no grade variables.
- **Checked interfaces.** Separate compilation hashes each library's
  interface to decide what to rebuild, but writes no interface file.
  Development sessions retain checked code and module text in memory; a
  cold process checks from source. Wire schemas come from the checked program.
- **The WGSL backend.** The renderer's shaders are WGSL text that shares no
  structs with Snail Scheme code beyond fixed instance and material layouts. The
  runtime and graphics plan proposes shaders written as S-expressions.
- **Actor destinations.** Tasks schedule one-shot closures and share
  `Mailbox` queues, which are values, not addresses of tasks. Request/reply
  protocols and network transports are application concerns.

## Simplifications made on the way

- Local bodies are sequential: a local function may call itself but not a
  later local definition.
- Named functions require an annotation on every parameter. Generic variables
  and class obligations appear on the definition; unannotated values retain
  the existing inference rules.
- Effect labels take no type parameters, and operations are monomorphic.
  [Parameterized effects](effects.md#proposed-parameterized-effects) are
  proposed with one fixed application per handler; operation-local
  polymorphism remains outside that design.
- Classes have no superclasses and no higher-kinded parameters.
- Wire TypeIds are 32 bits, and every struct and enum value carries its
  case's TypeId.

Snail Scheme deliberately omits R7RS compatibility, `call/cc`, `dynamic-wind`,
a dynamic numeric tower, source borrows, callable classes, `dyn`, `impl`,
`FnMut` and inline records. These are design decisions, not compatibility
bugs waiting for implementation. Mutable top-level state is also excluded:
compile-time values are forced lazily and read as fresh graphs.

Mutually recursive local functions, class superclasses, literals at generic
numeric types and overflow-checked arithmetic remain possible future work.
The [roadmap](https://github.com/tsnl/snail-scheme/issues/729) tracks the
current priorities.
