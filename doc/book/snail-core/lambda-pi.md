# Experiment: explicit passes with LambdaPi

This is a working experiment for reviewing compiler organization. It is not
a migration of the Snail compiler, an incremental engine, or a proposed new
Snail type system. Start with the examples below; the architectural assessment
comes afterwards.

The starting point is the LambdaPi of Andres Löh, Conor McBride and Wouter
Swierstra's [*A Tutorial Implementation of a Dependently Typed Lambda
Calculus*](https://www.andres-loeh.de/LambdaPi/), originally presented as
[*Simply Easy!*](https://www.andres-loeh.de/LambdaPi/SimplyEasy.pdf). This
independent Snail-Core implementation covers its bidirectional core, natural
numbers, and length-indexed vectors, including their dependent eliminators.
It omits equality types, finite sets, a text parser and a REPL.

Run all the worked examples from the repository root:

```sh
./scripts/snail-tool run examples/lambda-pi.sld
```

The four modules are under `src/snail/experiment/lambda-pi/`:

| Module | Responsibility |
| --- | --- |
| `language.sld` | Input trees, semantic values, normal forms, and constructor shapes. |
| `rules.sld` | Local decisions on supplied facts; constructing scope and branch expectations. |
| `driver.sld` | Dependency ordering and recursion for checking, evaluation, and quotation. |
| `normal.sld` | Structural equality, readback into input syntax, and printing. |

There is no pass macro, query dispatcher, global state, or caching here. The
experiment asks whether these explicit languages and ordinary functions are
enough to make the dependencies readable before introducing any machinery.

## 1. A variable

We construct trees directly. `star` is the universe of types; `pi` constructs
a dependent function type. `assume` checks a declaration's type and adds an
opaque variable to an immutable context. `context-of` is an example helper
that unwraps success or reports the typed error.

```scheme
{{#include ../../../examples/lambda-pi.sld:variable}}
```

`default-context` is just the example context we build here, containing
`A : *`, `x : A`, and `f : A → A`. It has no special role in the checker.

`result-let*` is a binding macro for computations returning `Result`, with
the sequential scope of `let*`. Each `Ok` supplies the bound value to the
remaining steps. An
`Err` becomes the result immediately, skipping the remaining computations.
For example:

```scheme
(result-let* ((c1 (assume empty-context "A" star))
               (c2 (assume c1 "x" (reference "A"))))
  (Ok c2))
```

expands, with temporary names made explicit, to:

```scheme
(match (assume empty-context "A" star)
  ((Err problem1) (Err problem1))
  ((Ok c1)
   (match (assume c1 "x" (reference "A"))
     ((Err problem2) (Err problem2))
     ((Ok c2) (Ok c2)))))
```

The macro does not wrap the final body in `Ok`; the body above does that
explicitly. In the full example, the last `assume` already returns a
`Result`, which `context-of` unwraps. Reusing the name `context` in its
bindings shadows the previous immutable value, just as in `let*`.
The shared CLI and IDE formatter recognizes the `-let*` suffix: bindings
align with each other, and the body is indented two spaces from the form's
opening parenthesis. User-defined `-let` and `-let*` macros follow the same
[naming convention](toolchain.md#browser-editor).

`x` has type `A` and normal form `x`. Checking a variable needs its binding's
type; evaluating an opaque variable produces a *neutral*: a computation
blocked on something unknown. It does not invent a value for `x`.

`Infer` contains expressions that synthesize their type. `Check` also admits
expressions, such as lambdas, that need an expected type. `Inf` embeds an
inferable expression in checkable syntax. These are separate enums, so a
caller cannot accidentally ask the synthesis function to infer an unannotated
lambda.

## 2. A call, with its dependencies visible

```scheme
{{#include ../../../examples/lambda-pi.sld:call}}
```

The result has type `A`. Its normal form is `(app f x)`, because `f` is
unknown. Here is the complete driver operation for checking an application:

```scheme
{{#include ../../../src/snail/experiment/lambda-pi/driver.sld:application}}
```

Read it as a sequence of prerequisites:

1. Synthesize the callee's type.
2. Give that result to `require-product`, a local rule that extracts a
   dependent function's domain and codomain or returns `ExpectedFunction`.
3. Check the argument against the supplied domain.
4. Evaluate that checked argument.
5. Enter the codomain closure with that value and evaluate the result type.

The fifth step matters: in a dependent call, the result type can mention the
argument's **value**. Merely supplying the argument's type is insufficient.
`require-product` does not recurse, check an argument, or call an evaluator.
The driver obtains and orders those dependencies explicitly.

```scheme
{{#include ../../../src/snail/experiment/lambda-pi/rules.sld:product-rule}}
```

The same `result-let*` form sequences these checking prerequisites. All
dependencies are explicit at the call site.

## 3. A lambda and beta reduction

```scheme
{{#include ../../../examples/lambda-pi.sld:identity}}
```

`ann` supplies an annotation, making the lambda inferable. `local 0` means
the innermost bound variable. The identity's type prints as `(Pi A A)` and
its normal form as `(lambda #0)`. Applying it to `x` normalizes to `x`.

The annotation builder is `(ann term type)`, implemented as
`(IAnn (:: term type))`. `::` is the struct holding those two fields.
The example imports exclude Snail-Core's own `ann` form so the name refers
unambiguously to this LambdaPi builder.

Checking a lambda starts with an expected function type. It introduces a
fresh unknown argument, computes the expected body type, extends the context,
and checks the body:

```scheme
{{#include ../../../src/snail/experiment/lambda-pi/driver.sld:lambda}}
```

The two environments have different jobs. The checking context records the
local's type. The evaluation environment records its semantic value, initially
a fresh neutral. They are extended together by `under-binder`.

Evaluating a lambda produces `Scope(body, environment)`. Applying it is an
explicit local decision followed, if necessary, by recursive evaluation:

```scheme
{{#include ../../../src/snail/experiment/lambda-pi/driver.sld:evaluation-call}}
```

`application-step` returns either an entered scope or a completed neutral
application. It never evaluates a body. A closure is inspectable data rather
than a Snail function closing over hidden compiler state.

## 4. A genuinely dependent identity

```scheme
{{#include ../../../examples/lambda-pi.sld:polymorphic}}
```

Its type is `Π A : *. Π x : A. A`. The inner domain uses index zero for `A`;
after introducing `x`, that same `A` is at index one. The type prints as
`(Pi * (Pi #0 #1))`.

Applying the function to `Nat` instantiates the second argument's expected
type with `Nat`. Applying that result to two gives type `Nat` and normal
form `(succ (succ zero))`. This is the call driver above, with a nonconstant
codomain; no extra driver mode is needed.

## 5. Types compute, and normalization enters binders

```scheme
{{#include ../../../examples/lambda-pi.sld:conversion}}
```

The first annotation computes to `Nat`, so zero checks against it. The second
example normalizes a call *inside* a lambda, producing `(lambda #0)`.

Normalization by evaluation has two parts: evaluate syntax into semantic
values, then **quote** those values into normal forms. To quote a closure,
enter it with a fresh neutral and quote its result one binder deeper:

```scheme
{{#include ../../../src/snail/experiment/lambda-pi/driver.sld:quotation}}
```

Input syntax counts binders outwards with indices. Semantic locals use
levels, which count from the outside and do not change when another binder
is entered. Quotation converts a level to `depth - level - 1`. For example,
the outer variable in `λx. λy. x` has level zero and index one at depth two.
An assertion catches an impossible level outside the current scope.

Type conversion quotes both semantic types and compares the resulting trees
structurally. It never compares their printed text. This experiment uses
beta and constructor-elimination reduction, without eta conversion:
opaque `f` and `λx. f x` have different normal forms.

## 6. Natural numbers: dependent elimination

```scheme
{{#include ../../../examples/lambda-pi.sld:naturals}}
```

The eliminator takes a motive `m : Nat → *`, a zero branch `z : m zero`,
a successor branch, and the natural to eliminate. The successor branch has
type:

```text
Π k : Nat. Π ih : m k. m (succ k)
```

The example uses the constant motive `λk. Nat`, starts with two, and increments
the induction result three times. Its normal form is five.

The driver checks the motive before evaluating it, then uses that value to
check the branches and compute the result type. `nat-step-type` constructs
the dependent expectation as syntax plus captured semantic values. The usual
scope evaluator interprets it; there is no second substitution algorithm or
special-purpose host callback.

During evaluation, `reduce-natural` distinguishes zero, successor, and a
neutral scrutinee. Only the successor case asks the driver to recurse. An
unknown natural retains an eliminator in normal form, including its motive
and branches.

## 7. Vectors and dependencies between arguments

```scheme
{{#include ../../../examples/lambda-pi.sld:vector}}
```

`Vec A n` is a vector of elements of type `A` with length `n`. A cons node
explicitly gives the tail's length. The checker verifies the head's type and
the tail's indexed type, then gives the whole cons length `succ n`.

The vector identity takes a length first, then a vector of that length. The
ordinary application driver instantiates these dependencies in order.
Supplying length two followed by a singleton is rejected by conversion.

## 8. Vector elimination: the induction hypothesis is dependent

```scheme
{{#include ../../../examples/lambda-pi.sld:vector-elimination}}
```

The motive now sees **both** the length and the vector:

```text
m : Π n : Nat. Vec A n → *
base : m zero (nil A)
step : Π n : Nat. Π h : A. Π t : Vec A n.
       Π ih : m n t. m (succ n) (cons A n h t)
```

Copying the vector uses motive `λn xs. Vec Nat n`. The recursive result
already has the right tail length; the step constructs one cons around it.
The driver performs recursion and passes the tail's length, head, tail,
and induction result explicitly to the checked step.

This is also where the explicit environments deserve scrutiny. The step
type captures `[A, m]`; under its four binders the environment is
`[ih, t, h, n, A, m]`. That invariant is written beside `vector-step-type`
in `rules.sld`. No generated framework hides the indexing.

## 9. Same length, different contents, different result types

The final example makes the dependency on the vector itself observable:

```text
tag-type zero     = Nat
tag-type (succ n) = Nat → Nat

tag-value zero     = zero
tag-value (succ n) = λx. x

vector-type nil        = Nat
vector-type (cons h t) = tag-type h
vector-value n xs      : vector-type n xs
```

These are ordinary transparent definitions checked by `define-global`.
Unlike an opaque `assume`, a definition contributes an evaluated value that
can unfold when computing types. The full construction is in the
`inhabitant-motive` section of `examples/lambda-pi.sld`.

Two singleton vectors produce these results:

| Input | Result type | Normal result |
| --- | --- | --- |
| `[zero]` | `Nat` | `zero` |
| `[succ zero]` | `Nat → Nat` | `λx. x` |
| `[h]`, where `h : Nat` is unknown | A blocked natural elimination on `h` | A blocked natural elimination on `h` |

The final row is essential: the compiler cannot choose the first two rows
from the vector's length alone. Both the result and its type remain open.

## What the boundaries establish

The representations deliberately have different contracts:

| Boundary | Established fact |
| --- | --- |
| `Infer` / `Check` | Which syntax admits synthesis, and which may need an expected type. Not yet well-scoped or well-typed. |
| `Context` | Under the driver API, declarations were checked and their type/value environments agree. |
| `Checked` | The term was checked in the exact immutable context retained with it. Its constructor is private to the driver. |
| `Value` / `Neutral` | Computation has entered the semantic domain; unknown applications retain their arguments. |
| `Normal` / `NeutralNormal` | Applications have neutral heads and eliminators have neutral scrutinees: beta and constructor-elimination redexes cannot be represented. |

Node payloads such as `Application<Function, Argument>` and
`Product<Domain, Codomain>` are structs. The enums specify which constructor
shapes each language admits. Their type parameters express different child
languages; they are not an untyped universal tree with flags for each pass.

The implementation exposes representation constructors for this experiment.
Clients should create contexts from `empty-context` using `assume` and
`define-global`. Forging a `Context` or semantic value bypasses the driver's
invariants. Normal-form types alone likewise do not prove scope or typing.
The internal evaluator assumes checked premises and asserts impossible
cases; malformed **input terms** passed through the driver return typed
errors before evaluation.

The tutorial universe axiom `* : *` is retained. This is not a consistent
proof kernel, and type checking does not establish termination of every
normalization. A production dependent language would need a different
universe/termination design. That question is outside this pass experiment.

## What this tells us about the Snail compiler

**The experiment is feasible and useful as an architectural test.** It runs
in current Snail-Core with ordinary structs, enums, pure functions and a
small sequencing macro. It demonstrates dependency injection for downward
expectations, upward inferred results, and checking that invokes evaluation.
The call, lambda, and eliminator drivers expose where each prerequisite
comes from. A single linear pass pipeline would obscure that interleaving.

It also provides a useful constraint on a future framework: do not require
every semantic operation to fit a bottom-up tree fold. A codomain must be
evaluated *after* its argument is checked and evaluated. An eliminator's
branches need the evaluated motive. The ordinary driver already expresses
this ordering without a universal callback protocol or a plan object for
every constructor.

**It does not establish the architecture of the whole Snail compiler.**
LambdaPi has no inference metavariables or substitution state, overload
selection, ownership, effects, hygienic expansion, monomorphization, staged
generators, or Wasm emission. Its `Checked` result pairs existing syntax
with a semantic type; it is not an elaborated Snail IR carrying evidence
at every node. Those differences must remain visible in the next sketch.

Before migrating production passes, review this shape and then try a small
slice of Snail checking: resolved calls, expected types, substitutions and
class/effect evidence. Define that input and output language first. Keep
the rule operations ordinary functions receiving explicit inputs, with
substitution state returned explicitly if needed. Let the driver obtain
children and sequence state. Introduce generated glue only where that
second example demonstrates repetitive, stable structure.

## Where incrementality could fit later

Nothing checks a cache at the top of a rule function. A future query layer
could wrap meaningful driver operations such as checking an expression in
a particular context or evaluating a term in an environment. It would reuse
the same local decisions and representations.

The keys cannot be just AST identity. Checking also depends on the expected
type and context; evaluation depends on the captured environment; quotation
depends on binder depth. Two identical-looking bodies with different
captures must remain distinct. These explicit data dependencies make that
requirement inspectable, but this prototype provides neither stable
identities nor dependency tracking, invalidation, or performance evidence.

That leaves the agreed order intact: first review the languages and uncached
transformations, then try a real Snail pass, then consider generations and
query reuse as an additional layer. Removing `project.datum` and changing
artifact requests remain separate later work in the
[broader design draft](https://github.com/tsnl/snail-scheme/pull/728).

## Executable checks and review order

`examples/lambda-pi.out` records the expected output of all fifteen examples.
`tests/programs/lambda-pi.sld` additionally checks capture avoidance,
normalization under binders, beta conversion and the absence of eta,
transparent definitions, duplicate declarations, immutable contexts,
open eliminators, invalid indices, and wrong branch or vector-length types.
Successful test terms are read back, checked against their normalized types,
and normalized again to check preservation and idempotence. These programs
run through the normal `make test` suite.

For review, read examples 1–5 with `language.sld`, then the call and lambda
drivers, then `application-step` and quotation. Read natural and vector
elimination afterwards. The questions for this draft are whether those
boundaries teach the computation, whether the driver owns the right work,
and what the next real Snail example must add. Caching is deliberately not
needed to answer them.
