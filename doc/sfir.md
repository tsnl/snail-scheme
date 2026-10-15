# SFIR

SFIR (Snail functional IR, pronounced “sphere”) is a typed functional language
and a reusable compiler target. It retains functions, algebraic data, polymorphism
and type inference, with a textual surface practical to write by hand.

This document defines the migration target, starting from the existing strict
compiler. The contracts below describe the intended design, including facilities
that have not landed. Concrete API spellings and transport formats remain open.

SFIR is the sole supported input language. Remove the non-strict Scheme compiler
and the `snail-scheme` executable. `snail-sfir` runs or compiles SFIR programs.
There is no Scheme compilation, Scheme interpretation or macro expansion in the
product. The compiler remains written in Scheme and hosted by Chibi.

Keep `build.scm` outside this migration for now. Scheme elaboration, macro staging
and self-hosting are later projects, after SFIR is robust.

## Language

### Evaluation

For this part, assume imported bindings are already available in the lexical
environment. The next part explains how they get there.

Inside an instance, values are evaluated eagerly. Call operands run left to right,
then the operator runs, then the function is invoked. Lambda evaluation creates a
closure; its body runs only when called. `let` initializers run left to right in
the enclosing scope. `if` evaluates its Boolean condition and only the selected
branch. `begin` evaluates its items in order and returns its final expression.
Bindings are immutable; explicit cells and mutable containers hold mutable state.

Definitions in a lexical block share scope and can be recursive. Their storage is
reserved before initialization; initializers run in source order. A closure can
capture a reserved binding, but reading it before initialization traps.

### Syntax and typing

The notation follows the presentation style of
[Simply Easy!](https://www.andres-loeh.de/LambdaPi/SimplyEasy.pdf): define syntax,
judgments and execution explicitly. The rules below specify the unrestricted,
fixed-arity functional core. They are not a complete calculus for nominal data,
rest parameters, classes or affine ownership; those extensions are described
below and need their own rules. No dependent types are introduced here.

`x` denotes a resolved binding, `a` a bound type variable, and `D` a resolved
nominal type constructor of declared arity. Inference uses fresh solver holes,
which are not source types. `Γ` maps bindings to schemes and records type binders;
`P` is a set of class obligations. `=>` and `<=` in judgments mean synthesis and
checking, respectively; `==>` reads “these premises imply this conclusion.” Repeated
arguments in a rule have equal lengths. Unification solves holes with an occurs
check and never solves rigid quantified variables. Equalities in premises unify
types after following solved holes.

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

## Libraries and builds

A library describes definitions of types and values, the bindings it requires,
and the bindings it exports. Producing a library does not run value initializers.
Loading an executable artifact makes its code available;
instantiation allocates fresh state and runs initializers. Invocation calls an
exported function in that instance. Reusing code preserves independent instance
state; sharing state requires explicitly sharing an instance.

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

Consider an application importing `increment` from `(demo math)`. The build driver
first supplies a library under that key. Resolution looks up its exported
`increment`, then makes that declaration's identity available under the local
name. Renaming the import changes the local name while preserving the identity.
Checking uses the provider's declared or inferred signature; the application must
call it with compatible arguments. A missing provider, missing export or
conflicting local binding is an error. Resolution never searches the filesystem
or executes the provider's initializers.

The following schema fixes the library boundary and illustrates the execution
contracts. `LocatedDeclaration` means a language declaration paired with its
source location. Its bindings have identities independent of printed names.
A supplied map can give multiple keys to the same library identity; these aliases
retain one set of definitions and one initialization event per instance.

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
