# SFIR

> Remove quote blocks, these are my comments to you.

> I cleaned up the below section to remove references to the ongoing migration. 
> I want this document to specify SFIR independently, not in the context of the ongoing migration 
> and simplification.

SFIR (Snail functional IR, pronounced “sphere”) is a typed functional language
and a reusable compiler target (think LLVM, but strongly typed). It offers pure functions, algebraic
data, polymorphism, and type inference, with a textual S-expression-based surface practical to write
by hand.

> We should provide the user a code example here. That will clarify better than anything else what
> we're getting at.

```
(import (sfir base))

(define fibonacci (Pi ((: T Integral)) (-> T T))
  (lambda (n)
    (if (<= n 1)
      n
      (let* ((fn-2 (fibonacci (- n 2)))
             (fn-1 (fibonacci (- n 1))))
        (+ fn-2 fn-1)))))

(define fast-fibonacci ...)
```

> Would be great to have another example here.
> 
> Can you port this example from another PL draft of mine?
>
> Ignore the `rust` code annotation, it's mostly for syntax highlighting, clearly it's a different
> language very similar to SFIR, we should just port the concepts. Let me know if it's not pretty 
> much 1:1.
>
> ```rust
> // color.tachyon
> 
> struct Vec3<T: Scalar> { x: T, y: T, z: T }
> 
> type PrimaryColor = Red | Green | Blue;
> struct Red;
> struct Green;
> struct Blue;
> 
> type Color = Vec3<Float32> | PrimaryColor;
> 
> trait ToHexString {
>   fn to_hex_string(self) -> String;
> }
> 
> impl color_to_hex_string(Color: ToHexString) {
>   fn to_hex_string(self) -> String {
>     match self {
>       (pc: PrimaryColor) => pc.to_hex_string(),
>       (v3: Vec3<Float32>) => v3.to_hex_string(),
>     }
>   }
> }
> impl vec3f_to_hex_string<F: FloatingPoint>(Vec3<F>: ToHexString) {
>   fn to_hex_string(self) -> String {
>     let r: Int = (self.x * 255.0).into();
>     let g: Int = (self.y * 255.0).into();
>     let b: Int = (self.z * 255.0).into();
>     format!("#{r:x2}{g:x2}{b:x2}ff", r, g, b)
>   }
> }
> impl primary_color_to_hex_string(PrimaryColor: ToHexString) {
>   fn to_hex_string(self) -> String {
>     match self {
>       Red => "#ff0000ff",
>       Green => "#00ff00ff",
>       Blue => "#0000ffff",
>     }
>   }
> }
> ```
>
> In addition to adding this example in a second code block, please also amend the first fibonacci 
> code block above to contain a `fast-fibonacci` definition. Will illustrate lambda captures, 
> recursive local definitions using `begin` and `define`, etc etc.
>
> ```rust
> // fibonacci.tachyon
> 
> fn fibonacci(n: Int) -> Int {
>   fn inner(i: Int, x2: Int, x1: Int) -> Int {
>     let x0 = x2 + x1;
>     if i == n {
>       x0
>     } else {
>       inner(i + 1, x1, x0)
>     }
>   }
>   if n <= 1 {
>     n
>   } else {
>     inner(2, 0, 1)
>   }
> }
> ```

Every language we support importing must be translated to SFIR to be compiled and run.
That applies to Scheme, to loaded datums, and to any extension DSLs in the future.
Most of the compiler's front-end is provided as library functions that are driven by user code.

> Diving straight into the nitty-gritty feels abrupt, mainly because the user is likely asking 
> themselves, "so what?" at this point.

SFIR helps us achieve our goals of modeling a distributed, heterogeneous, type-safe programming 
environment by creating a common module graph that we can generate, check, deploy, and program 
against.

The base language is simple enough to be portable across GPU, browser, and native, yet extensible 
via imports. For example, platform capabilities like `call/cc` must be imported, and aren't provided 
on platforms like WASM or GPUs that don't support these features.

Since we run everywhere, we can design the language runtime to be distributed. Builds entail 
running user code to generate compiled artifacts. Deploying and loading these are handled by user
code as well. We build type-safe abstractions that we can enforce because we emit the boundaries
around those compiled artifacts. Network connections, GPU queues, client browsers, etc are all 
modeled explicitly and in a type-safe way.

Finally, users can lower higher-level languages (like Scheme) to SFIR, benefiting from its 
exceptional type-checking and portability.

> Hopefully that wasn't too long-winded. Now to give the reader a brief overview of what's to come.

In the rest of this document, we'll formally specify SFIR, and then go into how 
libraries are imported, exported, and generated. By the end, you will understand 
how an SFIR program is compiled and run, as well as how to generate your own SFIR
as part of the build process from other programming languages.

## Language

### Values and expressions

An SFIR program computes values. A number such as `42`, a string such as
`"hello"`, and the Boolean values `#t` and `#f` can be written directly. An
expression describes a computation that produces a value.

To call a function, put its name first inside parentheses, followed by its
arguments: `(+ 40 2)` adds two numbers and produces `42`. Expressions can be
nested: `(+ (* 6 7) 1)` first computes `42`, then adds `1` to produce `43`.
Whitespace separates the parts; the parentheses determine how they fit together.
The examples here assume standard functions such as `+` are available. The next
part explains how imports make them available.

`define` gives a name to a value. In `(define answer (+ 40 2))`, the initializer
`(+ 40 2)` runs when the definition is evaluated. Later uses of `answer` read its
result without computing it again.
Names follow lexical scope: a reference uses the binding in the surrounding code,
even when a function containing that reference is called from somewhere else.

> "Define gives a name to a value" sounds like we're mutating the value itself, or associating some
> information with the value. I prefer "`define` creates a named place in memory where a value can 
> be stored.". This decouples the value itself from the place it occupies. Alternatively, "`define`
> creates a new variable with an assigned value": that reads much more nicely.
>
> "Give that function a name with ..." mentioned later is okay if we're pedantic here. We may want
> to caveat here that "giving X a name" is an informal way of stating the above, but I think that's
> too pedantic.

> We should explicitly state that `define` definitions can occur out of order. Evaluation can be
> left-to-right (i.e. start to finish) with future bindings evaluated early/lazily/on-demand if 
> needed, then cached/skipped during the regular L2R pass.

### Functions and local names

Functions are values too. `(lambda (x) (+ x 1))` creates a function with one
parameter, `x`, and one body expression, `(+ x 1)`. Creating the function does
not run its body. Calling it with `41` runs that body with `x` bound to `41`
and returns `42`.

Give that function a name with `(define increment (lambda (x) (+ x 1)))`.
Then `(increment 41)` produces `42`. Function bodies are written with explicit
lambdas; `define` has no separate shorthand for functions. Functions can be passed
as arguments and returned as results. A returned function keeps access to the
surrounding bindings it uses; this combination of code and captured bindings is
called a closure.

> Question: do we not want to explicitly mention the full capture list in each `lambda`?
> I suppose not...

`let` introduces names for one body expression.
For example, `(let ((x 40) (y 2)) (+ x y))` produces `42`; `x` and `y` are
available in the body but do not escape that scope. To perform several steps,
use `begin`. In `(begin (define value 41) (+ value 1))`, the definition runs
first, and the final expression gives the block its result, `42`.

> `let` vs `begin`: I think we have a small issue here.
>
> `begin` is useful for multiple interdependent definitions.
> `let` is useful for multiple bindings concurrently.
>
> I think we need `let*` explicitly, as well as `let-values` probably. In fact, I'd rather support
> `let-values` and `let*` or just make `let` behave like `let*` by default.
>
> Actually, best idea:
> - Shorten `define` to `def`: by default, it's a recursive definition, cf `fn` in Rust, `let rec`.
> - Allow `let` to be defined, but its initializer is evaluated in the previous statement's scope.
> - Both `def` and `let` occur in `(begin ...)` blocks. `let` only has access to previous bindings
>   and any `def`, though we need to check for initialization.

`if` chooses a value: `(if (< 1 2) 40 0)` produces `40`. Its first expression
must produce a Boolean, and only the selected branch runs. Both branches are
required and must have compatible types. `lambda` and `let` each have one body
expression, which can itself be a `begin`, `if`, or another compound expression.

### Types and mutable state

A type describes which values and operations fit together. `I64` is a signed
64-bit integer type, `F64` is a floating-point type, and `Bool` is the Boolean
type. The compiler infers types from definitions and uses, so many definitions
need no annotation. For example, `(define answer 42)` gives `answer` type I64.
Passing a string to a function that requires an integer is a type error, reported
before the program runs.

A function type lists its argument types followed by its result type.
`(-> I64 I64)` means one I64 argument and an I64 result. To state that signature
explicitly, write
`(define increment (-> I64 I64) (lambda (x) (+ x 1)))`.
The compiler checks the body against the signature. More general functions can
work at several types; the rules below explain how their uses are checked and
specialized into concrete code.

A binding always refers to the value it was given. To keep changing state, put
it in an explicit cell: `(define counter (ref 0))` binds `counter` to a cell
containing `0`. `(ref-set! counter 1)` changes its contents, and
`(ref-get counter)` then returns `1`. The binding still refers to the same cell.
Cells and mutable containers retain their element types through updates.

> Nothing on proper tail recursion? That's a vital requirement and follows naturally after a section
> on mutation, because we should strongly encourage the user to prefer pure functional programming 
> with tail recursion over mutation. Even if we don't include the guidance, we should specify the
> proper tail recursion requirement. Mutation probably deserves its own section.

> We could use a section here about Top, Never, and subtyping in general, as well as one or two 
> lines explaining that this is the bridge into dynamically typed languages. Should we rename `Top`
> to `Any` like Rust? `Any` and `Never` sound much better to me.

### Evaluation order and initialization

During execution, values are evaluated eagerly. Call operands run left to right,
then the operator runs, then the function is invoked. Lambda evaluation creates a
closure; its body runs only when called. `let` initializers run left to right in
the enclosing scope. `if` evaluates its Boolean condition and only the selected
branch. `begin` evaluates its items in order and returns its final expression.
Bindings are immutable; explicit cells and mutable containers hold mutable state.

Definitions in a lexical block share scope and can be recursive. Their storage is
reserved before initialization; initializers run in source order. A closure can
capture a reserved binding, but reading it before initialization traps.

### Formal core

> I don't like that the formal core is its own section, apart from the previous sections.
>
> I'd prefer it if the types were introduced in a small code block just below the "Types" section
> header, expressions were introduced just after "Values and expressions", etc.
>
> We can introduce the whole grammar piecemeal, with one summary here at the bottom with all the 
> rules.
>
> It is annoying that we'll have to duplicate the rules twice, but it's fine because agents can help
> with this. We should have an XML comment in the Markdown file instructing agents to keep the 
> grammar rules in sync.

> I sort of ad-hoc added `Pi` formers in my earlier example instead of `All`. Let's stick with `All`
> which we already have.

> The scheme spec uses "…" instead of `*` to denote repetition zero or more times, can we do the 
> same?

> Single-character intermediates for the rules are a bit hard to parse.
> It's fine in the dense grammar here, but it would be great if, in the introductory blocks above,
> we had a dedicated line comment per-line explaining what each metavar stands for and what other
> letters we can use in its place.

The following grammar and rules make the preceding explanation precise for the
unrestricted, fixed-arity functional core. Each typing judgment states either
what type an expression produces or what type it is required to produce. The
rules explain how those facts follow from the expression's parts. Nominal data,
rest parameters, classes and affine ownership need additional rules, described
separately below.

> > Nominal data, rest parameters, classes and affine ownership need additional rules, described
> > separately below.
> 
> Let's just not mention this. At the bottom, we can have a TODO quote block stating to add this,
> but the live document's content should not be polluted with this.

`x` denotes a resolved binding, `a` a bound type variable, and `D` a resolved
nominal type constructor of declared arity. Inference uses fresh solver holes,
which are not source types. `Γ` maps bindings to schemes and records type binders;
`P` is a set of class obligations. `=>` and `<=` in judgments mean synthesis and
checking, respectively; `==>` reads “these premises imply this conclusion.” Repeated
arguments in a rule have equal lengths. Unification solves holes with an occurs
check and never solves rigid quantified variables. Equalities in premises unify
types after following solved holes.

> I would like us to break this text block up into multiple smaller blocks. One for the AST, one 
> for the typing rules.
>
> Use the horizontal bar syntax that's conventional rather than spending a paragraph inventing 
> syntax. And use Unicode aggressively, I can see you already do but why not "∀" instead of 'forall'?
> 
> Even the AST/language syntax can heavily use unicode, e.g. ∀, ƛ, ≤, etc.
> Nowadays, agents write all our code. They're more than comfortable with using these unicode chars.
> Besides, even if we do need to hand-write, it's not too inconvenient.

```text
T ::= a | I32 | I64 | F32 | F64 | Bool | Char | Unit | String | Bytevector
    | Never | Top | (Ref T) | (List T) | (Vector T) | (D T*)
    | (-> T* T) | (-> T* (Rest T) T)
q ::= (C T*)                               # C is a resolved class
S ::= T | (All (a*) T) | (All (a*) (=> (q*) T))
d ::= (define x e) | (define x S e)
e ::= literal | x | (lambda (x*) e) | (e e*) | (if e e e)
    | (let ((x e)*) e) | (begin (d | e)* e) | (ann e T) | (inst x T+)

scheme = forall a*. P => T                 # normalized S; P is a set of q
Γ |- e => T ; P                            # synthesize T, collect P
Γ |- e <= T ; P                            # check against T, collect P
literal-type(l, no-expectation) = T
  ==> Γ |- l => T ; {}
literal-type(l, T) = T
  ==> Γ |- l <= T ; {}
Γ(x) = S; fresh-instance(S) = (T, P)
  ==> Γ |- x => T ; P
Ti are fresh holes; Γ,x*:T* |- b => R ; P
  ==> Γ |- (lambda (x*) b) => (-> T* R) ; P
Γ,x*:T* |- b <= R ; P
  ==> Γ |- (lambda (x*) b) <= (-> T* R) ; P
Γ |- f => (-> T* R) ; Pf; Γ |- ei <= Ti ; Pi
  ==> Γ |- (f e*) => R ; Pf union union(Pi)
Γ |- c <= Bool ; Pc; Γ |- a => A ; Pa; Γ |- b => B ; Pb; T = join(A,B)
  ==> Γ |- (if c a b) => T ; Pc union Pa union Pb
Γ |- c <= Bool ; Pc; Γ |- a <= T ; Pa; Γ |- b <= T ; Pb
  ==> Γ |- (if c a b) <= T ; Pc union Pa union Pb
Γ |- e => U ; P; U = T or U = Never or (T = Top and many(U))
  ==> Γ |- e <= T ; P                      # insert representation conversion
Γ |- e <= T ; P
  ==> Γ |- (ann e T) => T ; P
Γ |- e => Top ; P; many(T)
  ==> Γ |- (ann e T) => T ; P              # checked projection; mismatch traps
Γ(x) = forall a*. P => T
  ==> Γ |- (inst x U*) => T[a:=U] ; P[a:=U]
Γ |- ei => Ti ; Pi; (Si,Qi) = close(Γ,ei,Ti,Pi); Γ,x*:S* |- b => R ; Pb
  ==> Γ |- (let ((x e)*) b) => R ; Pb union union(Qi)
Γ |- ei => Ti ; Pi
  ==> Γ |- (begin e1 ... en) => Tn ; union(Pi)   # n >= 1, no definitions

close(Γ,e,T,P):
  A = flexible-free(T,P) minus free(Γ) if nonexpansive(e), otherwise {}
  Pg = obligations in P mentioning A; Q = P minus Pg
  return (forall A. Pg => T, Q)
nonexpansive ::= literal | name | lambda | annotation(nonexpansive) | instantiation
join(Never,T) = T; join(T,Never) = T; join(T,T) = T; otherwise: unify or error
U <: T iff U = T or U = Never or (T = Top and many(U))

literal-type(l, E):
  if integer(l): T = E if E in {I32,I64}, otherwise I64; require fits(l,T)
  else if float(l): T = E if E in {F32,F64}, otherwise F64
  else: T = type-of-boolean-character-string-or-bytevector(l)
  return T
fresh-instance(forall a*. P => T):
  H = one fresh hole per quantified variable
  return (T[a:=H], P[a:=H])

# Surface example; assume (+) : (-> I64 I64 I64).
(define increment (-> I64 I64) (lambda (x) (+ x 1)))
(increment 41)                             # I64, evaluates to 42
```

Numeric literals synthesize I64 or F64 by default. Checking against a known I32
or F32 selects that width for a literal of the corresponding numeric kind.
Unresolved expectations and overload candidates do not choose narrower widths.
Integer literals must fit the selected width. Bool, Char, String and Bytevector
literals have their corresponding types. Fixed-width integer arithmetic wraps; division
has Wasm's traps. Distinct numeric types require explicit conversion functions.

`define` always names a value; function-definition shorthand is rejected. `lambda`
and `let` have one body expression; `if` has both branches. All `let` initializers
are checked in the enclosing environment, before extending it for the body.
A block checks its recursive definition groups with provisional monotypes, then
generalizes eligible bindings after each group is solved. Every initializer and
body is checked, including unused definitions. An attached `All` signature checks
with fresh rigid variables and its declared class assumptions; it cannot override
the value restriction. In sequencing, all expression obligations accumulate and
the final expression supplies the type.

An unqualified `All` has an empty obligation set; a monotype quantifies no
variables. Generalized holes become quantified variables, and each use
instantiates them freshly. Concrete class
obligations must be discharged even in unused definitions; abstract obligations
can remain in generalized schemes. Argument and result constraints jointly select
overloads. Exactly one compatible complete signature must remain; declaration
order and prerequisite availability do not rank candidates. Promotion is an
ordinary implementation of an overload.

Only annotation permits projection out of Top. A declared Top expectation can
request injection; unrelated branch types never silently widen to Top. Top is a
managed reference with complete semantic type witnesses. `many(T)` means values
of T may be copied and discarded. Top has grade many; an affine value needs an
explicit shared-ownership wrapper before injection. The subtyping rule therefore
places only unrestricted types below Top. Ref and Vector are invariant; no
container or function variance conversions are inferred. Specialization must
resolve every reachable representation and class operation; runtime All and
silent generic or JIT fallbacks are unsupported.

> For rules like:
>
> > Numeric literals synthesize I64 or F64 by default.
>
> and
>
> > Only annotation permits projection out of Top
>
> It would be much nicer to have more explanation followed by the corresponding rules.
>
> I know I said to keep the code blocks to under 100 lines, but I'd rather relax that, duplicate
> rules as needed, and include nice explanations along each small bunch of rules.

Nominal data declarations introduce distinct type identities and concrete
constructor signatures. Matching evaluates one subject and requires one shallow
arm for every constructor, with compatible result types. Rest signatures check
fixed arguments positionally and remaining arguments against one element type;
the rest binding receives an immutable list of those remaining values. Cells,
containers and foreign operations have declared primitive signatures. Affine
usage and cleanup rules remain the separate
[ownership design](strict-core.md#proposed-affine-ownership).

There are no user macros, `syntax-rules`, named-let shorthand or derived control
forms such as `cond`, `and`, `or`, `when` and `unless`.

> Maybe move the absence of macros and grades into a section, "Notable Omissions", so we can mention
> once what's WIP and what's already ruled against.

## Libraries and builds

> Too abrupt. The organizational tree of this document as I see it should be:
> 
> ```
> SFIR (h1)
> - Overview
> - Language (within a library, but don't mention this explicitly)
>   - Terms and definitions
>     - Expressions and values
>     - Functions and local names
>     - Definitions
>     - Mutation and tail-recursion
>   - Types
>     - Primitive types
>     - Function types
>     - Struct and union types
>     - Type definitions
>     - Subtyping
>   - Summary: formal grammar and rules (super terse at this point, like a cheat sheet)
>     - AST grammar
>     - Typing rules
>     - Evaluation rules
> - Libraries
>   - ...
> - Compilers as libraries
> ```
>
> I'd actually really like a table of contents to that effect.
> 
> Anyway my main point is that "Libraries" is a whole section. We should add a little more text 
> before transitioning into the Libraries section.

A library describes definitions of types and values, the bindings it requires,
and the bindings it exports. Producing a library does not run value initializers.

> I don't like this definition much:
>
> > A library describes definitions of types and values, the bindings it requires,
> > and the bindings it exports. Producing a library does not run value initializers.
>
> Why not instead state
>
> > A library is a special value representing the typed AST for a single source unit.
> > This value is typically parsed from a file and feeds compilation or other static analysis.
>
> It reuses language we've already defined, i.e. value and AST, to explain what a library is.
>
> As for not running value initializers, maybe it's worth mentioning, but with my proposed 
> definition, that's almost obvious, while making it clear there may still be side-effects from the
> parser/loader.
>
> It's also worth pinning down what exactly is in the `SfirLibrary`, since we already agreed it's
> actually a bit richer than the AST. So maybe my above definition should be extended to be "an 
> elaborated AST" or whatever we decide is actually in `SfirLibrary`. In fact, I'd like to see a
> struct definition, in the SFIR language, of a `SfirLibrary` at the end of the library section so
> we're all on the same page about what's in this.

Loading an executable artifact makes its code available;
instantiation allocates fresh state and runs initializers. Invocation calls an
exported function in that instance. Reusing code preserves independent instance
state; sharing state requires explicitly sharing an instance.

> "Loading an executable artifact": too soon, delete this paragraph. We should first go into exports
> and imports, walk through the entire compilation, and then go, "Hey! Look! That compiled artifact
> produced by running the compilation function from earlier, we can run that now or later via an
> executable interpreter. In fact, this is the definition of the interpreter:" (like three lines of 
> code, without any arg parsing, just trivially parsing/loading/compiling and then running).
>
> ...
>
> Back after reading ahead a bit. I added a third section for "Compilers as libraries". I think all
> these details about invoking compilation via libraries should go _after_ we've explained what a
> library is and how it works in the common case. We can even introduce `generate-library`, but we
> don't need to go into detail on artifacts or how to script a build just yet.

Each library initializes once per instance, after its dependencies. The initial
model rejects library dependency cycles; recursive definitions within one library
remain supported. Repeated imports and re-exports do not repeat initialization.

### Exports and imports

An export maps a public name to a declaration defined in the library or imported
from another library. Exporting or renaming it preserves its identity and does
not copy its implementation or run its initializer. Unexported bindings remain
private to resolution by other libraries; existing references retain their
identities. Exported types preserve nominal identity, and constructors must be
exported separately to be available by name. Duplicate public names with distinct
bindings are errors.

> > An export maps a public name to a declaration defined in the library or imported
> > from another library.
>
> We should really define what exports and imports are and how they behave in a better way.
> For example, before this point, I'd expect an introduction of the `define-library` form.
> In fact, right after our above introduction of a library as a value, we should present 
> `define-library` as an easy way to spell those values, highlighting how top-level definitions can
> be exported. Going into how we load executables that early is pointless.

Consider an application importing `increment` from `(demo math)`. The build driver
first supplies a library under that key. Resolution looks up its exported
`increment`, then makes that declaration's identity available under the local
name. Renaming the import changes the local name while preserving the identity.
Checking uses the provider's declared or inferred signature; the application must
call it with compatible arguments. A missing provider, missing export or
conflicting local binding is an error. Resolution never searches the filesystem
or executes the provider's initializers.

> I hope the import resolution mechanism (for now) is as simple as:
> - Given the import path, search for files that match that name in all `-I` paths, for today with 
>   only the `*.sfir` file extension, maybe we don't care in the future.
> - If a file is found, it must contain either a `(define-library ...)` or a 
    `(generate-library ...)` form. The `#lang` or `#!...` shebang syntax could be used as a 
    shorthand for `(generate-library ...)` in the future, but let's not even mention this today, 
    except for a passing comparison of `(generate-library ...)` to Racket's `#lang ...`.
> - According to the parsed form, we compile and optionally evaluate the imported library to obtain
>   the `SfirLibrary`.

The following schema fixes the library boundary and illustrates the execution
contracts. `LocatedDeclaration` means a language declaration paired with its
source location. Its bindings have identities independent of printed names.
A supplied map can give multiple keys to the same library identity; these aliases
retain one set of definitions and one initialization event per instance.

> Another definition language... Can we not use EBNF here or something?
> 
> Or if the schema is meant to define the `SfirLibrary` type, why not use the existing `struct`
> definition syntax?

```text
LibraryKey, Name = symbolic names
LibraryId, BindingId = opaque identities
Export = {binding: BindingId, kind: Value | Type | Class}
Import = {provider: LibraryKey, exported: Name, local: Name}
SfirLibrary = {id: LibraryId, imports: List Import,
               exports: Map Name Export, declarations: List LocatedDeclaration}
Libraries = Map LibraryKey SfirLibrary
Entry = {library: LibraryKey, export: Name}

parse       : Source -> SfirLibrary
compile     : (Libraries, Entry, Target) -> Artifact
load        : Artifact -> Code
instantiate : (Code, ForeignBindings) -> Instance
invoke      : (Instance, Name, Arguments) -> Value

resolve-import(request, supplied):
  provider = require(supplied[request.provider], "missing library")
  export = require(provider.exports[request.exported], "missing export")
  return (request.local, export.binding)

math = parse(read("math.sfir"))
app = parse(read("app.sfir"))  # imports increment from (demo math)
supplied = coreLibraries + {(demo math): math, (demo app): app}
# app's local increment resolves to math.exports[increment].binding.
artifact = compile(supplied, Entry((demo app), main), wasm)
code = load(artifact)
first = instantiate(code, providers)
second = instantiate(code, providers)  # fresh state, same code
invoke(first, main, [])

generatorArtifact = compile(generatorLibraries, generatorEntry, wasm)
generator = instantiate(load(generatorArtifact), providers)
generated = invoke(generator, generate-library, inputs)  # SfirLibrary result
consumer = parse(read("generated-app.sfir"))  # imports (demo generated)
supplied = coreLibraries + {(demo generated): generated, (demo app): consumer}
artifact = compile(supplied, Entry((demo app), main), wasm)
```

`SfirLibrary` retains declarations and polymorphic implementations needed for
checking and specialization. Producing one library need not obtain its complete
implementation dependency closure. Independent checking requires the relevant
binding and type interfaces; compilation requires the implementations demanded by
the assembled program. Exported inference waits for dependency interfaces.
Composition preserves private scopes, binding identities and nominal type
identities. Export kind and type information come from the corresponding
checked declarations; a producer cannot manufacture trusted type evidence.
The selected entry must resolve to an exported function.

### Compilation and generation

The compiler is a reusable library taking supplied libraries and an executable
entry. It resolves, checks, specializes, optimizes and emits an artifact. A build
driver obtains library values and supplies dependencies; it owns discovery, file
I/O, generation and publication. `snail-sfir` is one client implementing run and
compile commands. Callers explicitly choose loading functions; file extensions
do not dispatch to loaders.

`generate-library` is an ordinary function returning a `SfirLibrary`. It can
construct definitions, parse source or compose supplied libraries. To run a
producer implemented in SFIR, the driver compiles its libraries and dependencies,
loads the artifact, instantiates it and invokes the selected function. The
returned library then participates in another compilation using the same rules.
Artifact dependencies accompany the result through an explicit build protocol.

Nested generation follows the same process. Prerequisites must be available
before invocation, and generation cycles receive diagnostics. Each chain reaches
source or executable code available without further generation. Chibi can host
the compiler throughout this process; it does not require self-hosting.

Generator instances and generated applications have separate state. Live
references and closures belong to their execution contexts. Transferring
information requires explicit data transport or interfaces. A library describing
a function does not transfer an executable closure from its producer.

### Targets and measurements

Preserve source locations and established type facts through resolution,
checking, specialization and emission. Parsing assigns identities and holes;
it performs no inference or optimization. Use established facts to eliminate
redundant work. Source-level import resolution precedes specialization; linking
emitted code with foreign providers is a separate operation.

Always run Binaryen as a Wasm-to-Wasm optimization pass. Execute optimized Wasm
in an engine or mechanically lower it to LLVM for a 64-bit native target with the
in-house collector. Native lowering must not introduce a second SFIR compiler.
Typed foreign declarations map to Wasm or corresponding C interfaces; the same
Rust extern implementations serve both targets.

Port the complete benchmark suite to bare SFIR. Compare SFIR, Chez and Rust on
matched workloads, recording target and host differences explicitly. Preserve
canonical inputs, algorithms, checks, failures and source provenance. Keep clean
timings separate from instrumented runs and compilation separate from execution.
Historical Scheme measurements remain historical evidence.

### Later frontends

A Scheme frontend can be a `generate-library` function producing a `SfirLibrary`
with original source locations. It performs elaboration, including macro
expansion, and uses the same SFIR checking and optimization pipeline. Generated
code can import SFIR functions and types. Other languages use the same boundary.

A frontend may need transformers and helper implementations before it can
produce its library. The driver supplies those values separately from the SFIR
libraries needed by the generated application. SFIR does not interpret macros
or require every library to expose a macro interface. Scheme elaboration, macro
persistence, hygiene transport and frontend-specific interfaces remain deferred.

## References

- Andres Löh, Conor McBride and Wouter Swierstra,
  [Simply Easy! An Implementation of a Dependently Typed Lambda Calculus][simply-easy].
  Background on presenting a small language through evaluation and typing rules.
- R. Kent Dybvig, [Three Implementation Models for Scheme][three-implementations].
  Background on implementing lexical scope, closures and execution.
- Alex Shinn, John Cowan and Arthur A. Gleckler, editors,
  [Revised⁷ Report on the Algorithmic Language Scheme (R7RS-Small)][r7rs-small].
  Background on Scheme expressions, procedures and libraries. SFIR's own rules
  are specified in this document.

[simply-easy]: https://www.andres-loeh.de/LambdaPi/SimplyEasy.pdf
[three-implementations]: https://legacy.cs.indiana.edu/~dyb/papers/3imp.pdf
[r7rs-small]: https://small.r7rs.org/attachment/r7rs.pdf
