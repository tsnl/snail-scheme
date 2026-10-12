# Static typeclasses and specialization

A typeclass declares operations on a type. An instance supplies checked
implementations for a concrete type. The compiler resolves calls using static
type information and emits ordinary Scheme functions. Users can define new
classes and instances; the runtime needs no class registry or dictionary argument.

Import `(snail typing)` for the declaration forms. They belong to the Snail-Scheme
compiler: Chibi hosts the build, rather than interpreting these forms itself.
See [the build guide](builds.md) for the development environment.

## Define an operation and its implementations

This complete program, `examples/typeclasses/main.scm`, gives `combine` an integer
implementation and a string implementation. `twice` uses either one:

```scheme
{{#include ../../examples/typeclasses/main.scm}}
```

The type annotation `(: combine (-> T T T))` describes two arguments and a
result of the same type. `define-class` introduces the method; each
`define-instance` supplies its implementation. An inline lambda is checked
against that instance's concrete signature. Named immutable functions can also
serve as implementations.

`All` quantifies the type variable in `twice`. The constraint
`(=> ((Combine T)) ...)` declares which operations its body may use. The compiler
checks the body under that constraint even before a concrete caller exists.
It then generates the requested `i32` and `String` specializations. Small integer
literals infer as `i32`, so `(twice 21)` selects the integer instance.

Build and execute the program with `examples/typeclasses/build.scm`:

```scheme
{{#include ../../examples/typeclasses/build.scm}}
```

The build owns a trace file under `build/`. Its scope closes before the script
returns the program's process status.

From the repository root, in the development shell:

```sh
chibi-scheme -I src examples/typeclasses/build.scm
```

Expected output:

```text
42
"hellohello"
"xx"
```

The first command compiles, links, and executes Wasm. Compile and execute the
same Scheme program natively with:

```sh
chibi-scheme -I src tests/build-native.scm . examples/typeclasses/main.scm build/typeclasses
build/typeclasses
```

Both targets produce the output above.

## Selection uses exact static types

Inference determines the method's type arguments before instance lookup.
The lookup key is the class identity and its complete type tuple. There is one
instance per key across the imported program. Missing, duplicate, or incomplete
instances are compile-time errors. Import order does not choose an implementation.

An instance for `ExactInteger` does not implicitly cover `i32`. An explicit
`(inst combine ExactInteger)` can select that instance, after which ordinary
argument checking applies. `Any` may have an explicit instance, but unknown `?`
information cannot silently select it. A result-only method needs a concrete
expected result type or an explicit instantiation. Available instances do not
fill in missing type information.

Classes can have multiple parameters. Both argument and result contexts can
determine those parameters. Instance heads currently support concrete scalar and
nominal record types; variables and unions are rejected. There are no generic
instance heads, local overrides, superclasses, or associated types in this MVP.

## A selected operation is a first-class value

`(inst twice String)` in the example selects a concrete specialization. The
result is an ordinary procedure: it can be stored, passed to another function,
or called indirectly. An expected concrete arrow can also select a method:

```scheme
(: concat (-> String String String))
(define concat combine)
(apply concat '("a" "b")) ; "ab"
```

Selection happens at compilation. Calling an escaping procedure value still uses
the language's ordinary procedure invocation. An unresolved overloaded value
cannot escape into runtime storage; give it a concrete view first.

Constrained functions require explicit `All` signatures and immutable
module-level lambda definitions. Their constraints are not inferred. Ordinary
and mutual recursion can reuse a specialization; type-changing polymorphic
recursion remains rejected.

## Follow the compiler

Expansion resolves hygienic class and method identities and records instance
declarations in IR. `src/snail-scheme/typeclasses.sld` checks the instance universe
and abstract generic bodies using the type checker's pure rules. Its traversal
retains overloaded uses and lambda signatures needed for rewriting. It creates
each specialization once per original function and concrete type tuple.

Specializations retain free binding identities, receive fresh local identities,
and initialize at the original definition site. Selecting a method still reads
its implementation binding. Closure initialization and argument effects retain
their ordinary execution order.

The pass removes class declarations, qualified signatures, and unresolved
overloads, then checks that none remain. Normal type analysis and Wasm emission
receive ordinary resolved IR. The same lowered program can run through WasmGC
or the native translator.

The [tensor tutorial](tutorials/tensors.md) applies this mechanism to two nominal
representations: immediate tensors and symbolic graphs. Carrier selection is
static; element dtype and shape checks remain runtime contracts for now.
