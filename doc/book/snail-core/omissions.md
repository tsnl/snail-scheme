# Notable omissions

Snail-Core is deliberately smaller than its first plan. These parts were dropped
because they would cost more than they give the programs Snail-Core runs today;
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
  interface to decide what to rebuild, but stores none: the compiled
  compiler checks Siegework, the largest program, in a fraction of a second,
  so an interface file would add a format and its invalidation without a
  measurable gain. Wire schemas come from the checked program.
- **The WGSL backend.** The renderer's shaders are WGSL text that shares no
  structs with Snail-Core code beyond fixed instance and material layouts. The
  runtime and graphics plan proposes shaders written as S-expressions.
- **Actor destinations.** Tasks schedule one-shot closures and share
  `Mailbox` queues, which are values, not addresses of tasks. Request/reply
  protocols and network transports are application concerns.

## Simplifications made on the way

- Local bodies are sequential: a local function may call itself but not a
  later local definition.
- Only unannotated top-level functions are generalized; other definitions
  are monomorphic unless they have a signature.
- Effect labels take no type parameters, and operations are monomorphic.
- Classes have no superclasses and no higher-kinded parameters.
- Wire TypeIds are 32 bits, and every struct and enum value carries its
  case's TypeId.

Some smaller features are planned but not yet implemented: complex numbers
and mutable pairs in the dynamic Scheme libraries, mutually recursive local
functions, superclasses, literals at a generic numeric type, and
overflow-checked arithmetic. The [language issue](https://github.com/tsnl/snail-scheme/issues/456)
tracks these gaps.
