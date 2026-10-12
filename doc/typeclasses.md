# Static typeclasses and user-defined overloads

Typeclasses are compile-time interfaces. A class declares method signatures;
an instance provides checked functions for concrete types. Calls select an
instance from static type information, and constrained generic definitions are
specialized into ordinary Scheme functions before Wasm emission. There is no
runtime instance registry or dictionary argument.

```scheme
(import (scheme base) (snail typing))

(define-class (Combine T)
  (: combine (-> T T T)))

(define-instance (Combine i32)
  (combine (lambda (x y) (+ x y))))
(define-instance (Combine String)
  (combine (lambda (x y) (string-append x y))))

(: twice (All (T) (=> ((Combine T)) (-> T T))))
(define (twice x) (combine x x))

(twice 21)       ; 42, through the integer implementation
(twice "hello")  ; "hellohello", through the string implementation

(define double-string (inst twice String))
(double-string "x") ; "xx"
```

This is implemented language syntax reexported by `(snail typing)`. Compile a
program with the existing Chibi-hosted build scripts. Chibi itself does not
implement these forms as an interpreted extension.

## Declarations and instance selection

`(define-class (Name parameter ...) (: method arrow) ...)` creates hygienic class
and method identities. Method domains and results use the existing shallow type
language, including class parameters and stable nominal record types. Methods
have fixed arity. All class parameters are quantified at each method use.

`(define-instance (Name type ...) (method implementation) ...)` supplies every
method exactly once. Heads are concrete scalar or nominal types; `?`, unions,
and type variables are rejected. There may be multiple class parameters:

```scheme
(define-class (Convert From To) (: convert (-> From To)))
(define-instance (Convert i32 String)
  (convert (lambda (value) (number->string value))))

(: text String)
(define text (convert 42)) ; input determines From; result context determines To
((inst convert i32 String) 7)
```

Inference finishes before instance lookup. Lookup uses the exact class identity
and complete type tuple. A missing instance is a located compile-time error.
Two declarations for the same tuple are rejected, including declarations in
different imported libraries. Importing one declaration through multiple paths
does not duplicate it. Declaration order does not choose between implementations.

Subtyping does not create fallback instances. Small integer literals currently
infer as `i32`; an instance for `ExactInteger` does not implicitly cover them.
An explicit view such as `(inst combine ExactInteger)` selects that instance,
then normal parameter checking admits its arguments. `Any` can have an explicit
instance. Unknown `?` information cannot silently select it. A concrete result
context or explicit instantiation can select an instance before a gradual
argument passes through the existing checked boundary.

A result-only method such as `zero : () -> T` requires an expected result type
or explicit instantiation. Even one available instance does not supply missing
type information. Adding another instance therefore cannot change inference.

Instances form one coherent universe for the imported whole program. There are
no local overrides, generic instance heads, superclass rules, associated types,
or instance-driven type inference in this implementation.

## Checked implementations

An inline fixed lambda is checked against the instantiated method signature and
becomes a private function initialized at the instance declaration. A named
implementation must resolve through immutable module-level function bindings.
Its body may have effects or mutate state, but its callable association cannot
be rebound.

If a named lambda has no signature, its instance supplies one. An already
annotated implementation must support the required checked view; a declared
unconstrained `All` function can supply multiple concrete views. The existing
checker does not support general arrow subtyping. An instance implementation
cannot itself require typeclass constraints.

Selecting a method preserves the implementation binding read. Knowing its code
at compile time does not initialize its closure early. A use before its
implementation or concrete alias is initialized still reports the ordinary
uninitialized-binding error. Arguments execute in the compiler's established
left-to-right order before the operator is evaluated; specialization neither
duplicates those effects nor moves them into compilation.

## Constrained functions and first-class views

A constrained function has an explicit rank-one `All` signature with `=>`
obligations. Its body is checked once with rigid variables under exactly those
obligations. Calling a class method on an abstract variable without its declared
constraint fails, even if every current call site happens to have an instance.

A predicate may narrow an argument without changing its declared class. A
method `(-> T T)` selected under `Keep T` still returns `T`: it need not preserve
an input's narrower String category. Check the returned value separately before
using String operations, or explicitly select a concrete String instance.

Each concrete use requests a specialization keyed by original function identity
and type arguments. The compiler reserves the entry before rewriting its body,
so ordinary and mutual recursion share the same specialization. Type-changing
polymorphic recursion remains rejected by the existing checker. Unused valid
generic templates need no generated function.

Constrained templates currently require immutable module-level lambda
definitions. Specializations initialize once, at the original definition site.
They preserve free binding identities and give parameters and local definitions
fresh identities. Specialization duplicates code rather than runtime
initialization. Repeated `(inst twice String)` views return the same initialized
closure; `String` and `i32` views of a constrained template are distinct
specializations. Unconstrained `All` retains its existing erased-view behavior.

Overloaded methods and constrained functions can become ordinary first-class
procedure values through `inst` or an expected concrete arrow:

```scheme
(: concat (-> String String String))
(define concat combine)
(apply concat '("a" "b"))
```

Calls through escaping procedure values may use ordinary indirect invocation.
The instance was already selected statically. There is no runtime overload
selection. Existing gradual `apply` behavior and result checks still apply to
views of unconstrained polymorphic implementations.

An unresolved immutable identifier alias, such as `(define alias twice)`, is a
compile-time alias of the original template. It has no separate runtime value
or initialization site. A chain of aliases currently requires its target aliases
to appear earlier; forward alias chains are unsupported in this MVP.
Unresolved overloaded values cannot escape into ordinary runtime storage.
Effectful unresolved aliases and instantiations of compound
overloaded expressions are rejected; put effects around a selected `inst` view
instead. Concrete aliases remain normal bindings with normal initialization
reads. Type variable names retain their existing scope within the signature;
they are not introduced into the separately written function body.

The `=>` identity is shared with `(scheme base)`, so the standard `cond` and
`case` receiver syntax still works when both libraries are imported. Class,
method, instance type, and implementation identities also survive import
renaming, prefixing, and hygienic macro expansion.

## Eager and symbolic tensor operations

[`(snail-scheme iverson-typed)`](../src/snail-scheme/iverson-typed.sld) supplies
two nominal carriers implementing `TensorOperations`. An immediate carrier
contains a first-class [Iverson Ghost tensor](iverson-ghost.md); a symbolic
carrier contains a GC-visible graph node. The same generic algorithm specializes
to unboxed eager operations or graph construction:

```scheme
(import (scheme base) (snail typing) (snail-scheme iverson-typed))

(define data (tensor '(2 2) '(1 2 3 4) 'f32))
(define graph (tensor-gram (symbolic-input 'x)))
(immediate-values (tensor-gram data)) ; #(10.0 14.0 14.0 20.0)
(symbolic->datum graph)              ; (matmul (transpose x) x)
(immediate-values (evaluate graph (lambda (name) data)))
;; #(10.0 14.0 14.0 20.0)
```

The interpreter's input callback returns a checked immediate carrier. Interpreted
operations then call the statically selected eager instance. The symbolic
instance constructs graphs without executing numeric kernels.

Carrier selection is static. Element dtype and dimensions still follow the
eager library's runtime contracts; this does not introduce parameterized tensor
types or static shape inference. The symbolic interpreter implements tree
evaluation, without graph optimization, memoization, GPU lowering, or graph
program generation. Differentiation remains omitted.

Run the example from the repository root:

```sh
chibi-scheme -I src examples/iverson-ghost/typed-build.scm
chibi-scheme -I src tests/build-native.scm . examples/iverson-ghost/typed.scm build/iverson-typed
build/iverson-typed
```

## Compiler responsibilities and checks

Expansion adds class and instance metadata to resolved IR and retains qualified
signatures. [`typeclasses.sld`](../src/snail-scheme/typeclasses.sld) prepares the
instance universe and checks implementations and obligations with the existing
type checker's pure rules. Abstract method prototypes supply trusted contracts;
their placeholder bodies are never checked or emitted. A dedicated traversal
retains overloaded uses and lambda signatures for specialization. It reconstructs
library bodies while preserving initialization sites. A final structural check
requires every class declaration, qualified signature, and unresolved method
reference to be erased.

The emitter then checks that ordinary IR using transient facts for guards,
occurrence facts, and numeric specialization. It can see through static callable
views to use known function entries while retaining operator evaluation and
initialization reads. No class selection logic enters the runtime.

`make test` checks elaboration and erasure. `scripts/test-typing` exercises
successes and failures in guarded and optimized modes, including exact heads,
unknown types, missing/duplicate instances, initialization, effects, aliases,
renamed imports, macros, and recursive generics. `scripts/test-backend --target
both` executes ordinary overloads and eager/symbolic tensor programs through
Wasm and native translation.
