# Snail-Scheme core language

Design proposal for Esker, Snail-Scheme's strict, dependently typed core.
Ownership grades belong to types. Start with syntax matching, libraries, lexical
scoping, and hygienic expansion into the final core AST; elaboration, checking,
and immutable interpretation follow. Memory management, continuations, and C
output remain future work.

## 1. Grammar

`*`, `+`, and `|` below are grammar metanotation. This is one language reference;
the expanded AST contains the forms that survive macro expansion.

`Name` and `Field` are identifiers. `Type-Expr` is an expression checked to denote
a type during elaboration. Special forms are selected by resolved syntax bindings,
which ordinary lexical bindings may shadow.

Built-in syntax IDs use the `#%-` prefix and enter scope only through an explicit
language import; `esker` is the provisional name of the core language. Examples
assume those imports. Surface languages may expose shorter names and expand to
these bindings. The prefix is a naming convention, not a substitute for lexical
identity or an escape from shadowing. The file/library driver recognizes the
outer declaration grammar before imports; this is the bootstrap boundary, not
an implicit import of expression syntax. Ordinary type/value identifiers and
the structural markers `→` and `=` retain their spellings.

**Legend: `◰` = eliminated by macro expansion.** It is a documentation marker,
not a source token. Unmarked forms remain available in the expanded AST.
In particular, `define-library`, `import`, `export`, and library-body `begin`
are retained. Their later lowering into metadata or instruction sequences is
outside the meaning of this marker.

```text
Program       ::= Import-Decl* Item*
Library       ::= (define-library Library-Name Library-Decl*)
Library-Decl  ::= Import-Decl
                | (export Export-Spec*)
                | (begin Item*)
Import-Decl   ::= (import Import-Set*)
Import-Set    ::= Library-Name
                | (only Import-Set Name*)
                | (except Import-Set Name*)
                | (prefix Import-Set Name)
                | (rename Import-Set (Name Name)*)
Export-Spec   ::= Name | (rename Name Name)
Library-Name  ::= (Library-Part+)
Library-Part  ::= Name | Nonnegative-Integer

Item          ::= Definition | Expr
Definition    ::= (#%-def Pattern Expr)
                | (#%-macro Name Rules-Spec)                              ◰

Expr          ::= Name
                | Literal
                | (#%-Π Telescope Telescope → Type-Expr)
                | (#%-λ (Name*) Telescope Telescope → Type-Expr = Expr)
                | (Expr Expr*)
                | (#%-ann Expr Type-Expr)
                | (#%-begin Item* Expr)
                | (#%-struct Telescope Grade)
                | (#%-tuple-of Type-Expr*)
                | (#%-tuple Expr*)
                | (#%-union Type-Expr*)
                | (#%-new Type-Expr (Field-Value*))
                | (#%-match Expr Clause+)
                | (#%-let-syntax (Syntax-Binding*) Item* Expr)            ◰
                | (#%-letrec-syntax (Syntax-Binding*) Item* Expr)         ◰

Syntax-Binding ::= (Name Rules-Spec)
Rules-Spec    ::= (#%-syntax-rules (Name*) Rule*)                         ◰
                | (#%-syntax-rules Name (Name*) Rule*)                    ◰
Rule          ::= (Macro-Pattern Template)

Telescope     ::= (Binder*)
Binder        ::= (Name Type-Expr)
Grade         ::= 1 | omega
Field-Value   ::= (Field Expr)
Clause        ::= (Pattern Expr)

Pattern       ::= Name
                | Literal
                | (#%-is Type-Expr Name)
                | (#%-new Type-Expr (Field-Binding*))
                | (#%-tuple Name*)
Field-Binding ::= (Field Name)
Type-Expr     ::= Expr
```

Application has one grammatical form, `(Expr Expr*)`. Before resolving its head,
keep application-shaped input as syntax: operands may be arbitrary reader nodes,
including binders or pattern data, and a macro may accept an improper tail.
Resolution decides whether to invoke a transformer, dispatch a built-in form,
or build an ordinary `Apply` node. Only the last case requires a proper list
of operator/operand expressions. There is no separate macro-use production or
AST node, and macro operands are not prematurely parsed as expressions.

`define-library` and its `import`, `export`, and body `begin` declarations remain
in the expanded AST, annotated with resolved bindings and dependencies. Expand
items inside each library-body `begin` in the shared library scope; it does not
create the nested scope of `#%-begin`. Later lowering may extract interface
metadata and flatten body sequences. An item-position application may expand to
a definition. The macro pattern/template grammar is in section 5.

The first function telescope is implicit, the second explicit. Both are
mandatory; `#%-λ` also requires its leading capture list. Empty lists are valid.
By convention, write implicit parameters in square brackets:

```scheme
(#%-def id
  (#%-λ () [(Element-Type star)] ((x Element-Type)) → Element-Type = x))

(#%-def id-type
  (#%-Π [(Element-Type star)] ((x Element-Type)) → Element-Type))
```

Matching `()`, `[]`, and `{}` produce identical lists; mismatched delimiters
are errors. Recognize `#%-λ`, `#%-Π`, `→`, and `=` as tokens. The arrow and equals
sign are structural markers in their designated positions.

Use `lower-kebab-case` for ordinary identifiers, including types and explicit
parameters. Reserve `Upper-Kebab-Case` for inferred implicit parameters and
metavariables in rules. Symbolic operators are exempt. Preserve arbitrary
Scheme identifier spelling in macro syntax data.

Core literals are booleans, signed integers, characters, and immutable strings.
Integer literals check against `i32` or `i64`, default to `i64` when synthesized,
and reject out-of-range values. Other reader datums are not automatically core
expressions. Empty `()` is not an expression; `(f)` calls `f` with no explicit
arguments.

`#%-def` binds values using a pattern; `#%-macro` binds one macro name
and is eliminated during expansion. Local syntax-binding forms are also eliminated.
There are no separate type declarations, binder-grade annotations, `quote`, `if`,
`let`, `letrec`, `fix`, rest parameters, `set!`, or user-defined recursive datatype
forms in the initial grammar.
Arithmetic, arrays, `singleton`, and list operations use ordinary applications.
`#%-union`, `#%-tuple-of`, and `#%-tuple` have intrinsic n-ary rules, not first-class
variadic function signatures.

## 2. Semantic rules

### Bindings, scopes, and evaluation

- A **telescope** is an ordered sequence of typed binders. Each binder enters
  scope after its annotation. The implicit and explicit function groups form
  one telescope; all parameters scope over the result type and body. Struct
  fields follow the same rule. No forward references within telescopes.
- Names are distinct within parameter groups, across both function groups,
  within patterns, and among definitions in one scope. Field labels are unique.
  `_` is an ordinary core binder; higher-level wildcards need fresh names.
- Every `#%-begin` creates a scope, executes items in source order, and returns
  its mandatory final expression in tail position. Nonfinal expression results
  are discarded immediately; unused bound owners are cleaned up at scope exit.
  File scope accepts any item sequence and discards expression results.
- Each `#%-def` evaluates its initializer once and initializes its bindings
  together. Its pattern must be provably irrefutable for the result's type and
  refinements. Otherwise use `#%-match`; `#%-def` has no runtime failure branch.
- Collect bindings across the completed scope before checking function bodies.
  Lexical visibility does not imply initialization. Nested scopes do not export
  their definitions.
- Runtime calls evaluate the operator, then explicit arguments, left to right.
  Calls have exactly their signature's explicit arity. `#%-new` checks and evaluates
  every field once, in declaration order; `#%-tuple` evaluates elements left to
  right. `#%-match` evaluates its scrutinee once and only its selected branch.

### Functions, inference, and captures

Every lambda declares parameter types and a result type. Derive its signature
from that header, then check the body against the declared result. `(#%-ann e t)`
checks `e` against `t`; local definitions initially infer monotypes.

Implicit parameters are solved **only from explicit arguments**, including their
dependent types. Expected call results cannot fill unresolved implicits. There
is no implicit-argument override syntax. Later arguments may solve earlier
constraints; reject remaining ambiguity. Start with first-order and dependent
pattern unification plus normalization, not arbitrary equation solving.
Polymorphism is abstraction over type values; local generalization, if added,
must elaborate to that representation without duplicating captured owners.

Capture names resolve in the enclosing scope before parameters. Reject duplicate
capture identities and capture/parameter collisions. The list covers free outer
values in annotations, the result, the body, nested capture lists, and captured
types. Capturing `xs` of type `(array i64 n)` also requires capturing local `n`.
Type-only dependencies follow phase and erasure rules.

Closure construction acquires captures in list order: affine values move
immediately, unrestricted values may be copied. Primitive bindings and verified
closed static top-level definitions need no capture; other outer values,
including runtime globals, must be listed. Optimization does not waive this rule.

A concrete closure's grade follows its captured runtime fields; an empty
environment has grade `omega`. A `#%-Π` exposes a call signature, not a hidden
environment's grade, so an environment-erased callable is initially affine.
Known unrestricted function items may be reused. A later callable constraint
may preserve more information about an environment.

```scheme
(#%-def make-adder
  (#%-λ () [] ((offset i64))
    → (#%-Π [] ((x i64)) → i64)
    = (#%-λ (offset) [] ((x i64)) → i64 = (i64-add x offset))))
```

### Recursion and initialization

Discover recursive functions from `(#%-def Name Lambda)` and direct tuples of
lambdas bound by tuple patterns. Collect complete headers before checking
bodies; compute strongly connected components (SCCs) from resolved references
across the entire scope. Separate definitions and macro invocations do not
limit a component. Arbitrary computations returning functions do not establish
such groups; they can define groups in their own blocks.

Self and peer references in a component are body-only code references, not
captured function copies or header dependencies. Recursive environments must
initially be unrestricted. Other runtime dependencies remain explicit captures;
nonrecursive closures retain the ordinary affine rules.

Headers and type dependencies must be well-founded and phase-correct. Construct
each closure's environment at its definition's source position without running
its body. Check eager initialization dependencies separately from delayed body
references. Reject eager cycles and reads before initialization, including
acyclic forward reads. Before calling a function or exposing it to unknown code,
require its environment and transitive function dependencies to be ready.
Conservatively reject unknown readiness; never reorder initializers to fix it.

```scheme
(#%-begin
  (#%-def even
    (#%-λ () [] ((n i64)) → boolean
      = (#%-match n
          (0 #t)
          (remaining (odd (i64-sub remaining 1))))))
  (#%-def odd
    (#%-λ () [] ((n i64)) → boolean
      = (#%-match n
          (0 #f)
          (remaining (even (i64-sub remaining 1))))))
  (even 10))
```

Calling `even` between these definitions is rejected. The interpreter may use
code references and immutable external environments with internal readiness
bookkeeping; no source `fix` is required.

### Ownership grades

| Grade | Permission |
| --- | --- |
| `1` | Affine: move or consume at most once; abandonment requires cleanup |
| `omega` | Unrestricted: safe duplication and discard |

The permission order `1 < omega` is not a subtyping rule. Passing, returning,
or storing an affine value transfers ownership. Sequential uses accumulate;
exclusive branches are checked per path. Clean up unused owners and abandoned
partial constructions. Safe tag observations do not transfer ownership.

```text
field-bound = min(grade-of(field-type) for each field)
require declared-struct-grade <= field-bound
grade-of(struct-type) = declared-struct-grade
grade-of(#%-tuple-of A ...) = min(grade-of(A), ...)
grade-of(#%-union A ...) = min(grade-of(A), ...)
min of no members = omega
```

Only `#%-struct` accepts a user-written grade. Check its literal grade for every
admitted generic instantiation and preceding dependent field value. A generic
wrapper declared `1` remains affine even with unrestricted payloads. Declaring
`omega` requires all fields to be unrestricted; do not silently add that premise
to an unconstrained family. Grade-constraint syntax remains open.

Refinement can reveal an unrestricted payload but cannot recover a consumed
owner or duplicate its affine wrapper. `share A` means `grade-of(A) = omega`;
it is a constraint, not an overridable instance. For recursive data supported
by trusted constructors or later extensions, solve grade equations from `omega`
to their greatest fixed point. Preserve nominal restrictions under normalization.

### Patterns, unions, and refinement

Patterns are shallow. A name binds the whole value; tuple patterns bind every
element with exact arity; struct patterns bind every field in declaration order.
Dependent field relationships remain in scope after unpacking. A definition's
bindings belong to its containing scope; match bindings belong to their branch.

`#%-match` selects clauses in order using safe observations, then transfers the
selected payload to the pattern bindings. An affine scrutinee becomes unavailable.
Unused fields still receive ordinary cleanup. Failed tests refine the remaining
set of possible values, not merely the list of written union members.

`#%-is` supports known runtime discriminators: primitive tags, supported singletons,
and nominal structs. It cannot test arbitrary dependent type equality. Check
coverage and require a catch-all when necessary; unsupported discrimination or
unproved coverage is a static error.

Check branches against an expected type, or synthesize a common type using a
supported union join. A branch or block result type cannot expose an unavailable
local index: substitute an admitted pure definition or package the index and
payload in a dependent record. General dependent elimination motives remain
unspecified.

A Boolean conditional lowers to `(#%-match (#%-ann Test boolean) (#t Yes) (#f No))`.
Scheme truthiness uses a `#f` clause followed by a named catch-all. Both branches
are checked, although only one executes.

## 3. Types and data

### Universes, dependencies, and erasure

`star` denotes a universe with implicit, internally checked levels. Types such
as `i64` inhabit a universe, which inhabits a higher universe; no universe
inhabits itself. Type descriptions are reusable even when their inhabitants
are affine.

Initially allow dependencies on static type parameters and immutable,
unrestricted indices. Checking types cannot consume affine owners or execute
runtime effects. Implicitness, ownership, phase availability, and erasure are
independent: an implicit length may be needed at runtime, while an explicit
type argument may be erased.

The initial target erases type values unless a later runtime-descriptor facility
reifies them. Symbolic indices need not be known during compilation. Erasure
must preserve required evaluation and cleanup; phantom indices and annotations
are not automatically stored fields or grade restrictions. Explicit relevance
annotations and dependency on resource-bearing values need later rules.

### Nominal structs and structural tuples

`#%-struct` produces a nominal type value without defining constructors or accessors.
Assign a stable key to each elaborated occurrence, parameterized by its enclosing
type-family arguments. Rechecking the same application preserves identity;
distinct occurrences remain distinct even with identical layouts. Aliases retain
identity. Exact keys for modules and serialization remain to be formalized.

```scheme
(#%-def point (#%-struct ((x i64) (y i64)) omega))
(#%-def ticket (#%-struct ((number i64)) 1))

(#%-def pair
  (#%-λ () [] ((first-type star) (second-type star)) → star
    = (#%-struct ((first first-type) (second second-type)) 1)))

(#%-def make-pair
  (#%-λ () [(A star) (B star)] ((x A) (y B)) → (pair A B)
    = (#%-new (pair A B) ((first x) (second y)))))
```

`pair` takes explicit type arguments; `make-pair` infers them from its values.
An empty-container constructor likewise needs an explicit type argument if
nothing else determines it. Declaring an `omega` wrapper containing `ticket`
is rejected. `(pair i64 i64)` is still affine because its declaration says `1`.

`#%-tuple-of` compares ordered element types structurally. `(#%-tuple-of)` is unit,
inhabited by `(#%-tuple)`; unary tuples remain distinct from their elements, and
nested tuples never flatten implicitly. Tuple types have no element binders;
use a struct telescope for dependencies between components. Tuples need not
allocate heap objects.

```scheme
(#%-begin
  (#%-def (#%-tuple left right)
    (#%-begin
      (#%-def shared (i64-add 19 1))
      (#%-tuple shared (i64-add shared 2))))
  (i64-add left right))
```

The initializer runs once; unpacking moves components without retaining another
aggregate owner. `(#%-def x (#%-tuple 1))` binds a tuple; `(#%-def (#%-tuple x) (#%-tuple 1))`
binds its element. Higher-level `let` can lower to a fresh scope and tuple
binding with hygienically distinct names, or to an immediately invoked lambda
when its result type is expressible. Preserve initialization and capture order.

### Dependent records and arrays

```scheme
(#%-def sized-array
  (#%-struct ((length i64) (items (array i64 length))) 1))

(#%-def package-length
  (#%-λ () [] ((value sized-array)) → i64
    = (#%-begin
        (#%-def (#%-new sized-array ((length n) (items unused-items))) value)
        n)))

(#%-def keep-array
  (#%-λ () [(Element-Type star) (N i64)] ((xs (array Element-Type N)))
    → (array Element-Type N) = xs))

(#%-def array-append-type
  (#%-Π [(Element-Type star) (M i64) (N i64)]
      ((xs (array Element-Type M)) (ys (array Element-Type N)))
    → (result (array Element-Type (+ M N)) array-error)))
```

`#%-new` substitutes earlier field values into later field types; consuming a
record opens the same telescope. A dependent pair can be a two-field struct
family; no primitive `Σ` is needed.

Use unrestricted fixed-width `i32` and `i64`, with no separate natural-number
type. Array length indices use `i64`. Type-level arithmetic has runtime semantics:
`+` on `i64`, like `i64-add`, wraps at that width. Constant folding uses the same
signed interpretation; there is no hidden unbounded index arithmetic.

`(array A N)` is well formed for every `i64` index, but invalid lengths have no
inhabitants. Constructors check nonnegativity, arithmetic overflow, byte size,
backend address limits, and allocation failure. Concatenation checks the sum
before allocating; on success it agrees with the wrapping type expression.
`array-error` describes these failures. Merely forming an array type neither
allocates nor proves construction succeeds.

### Unions and library variants

Unions denote sets of values. Members are subtypes; normalize by flattening,
ignoring order, removing duplicates, and removing covered members. Overlap does
not introduce separate variants. `(#%-union)` is `nothing`. `singleton` initially
accepts supported pure scalars; `(singleton #f)` is a type, whereas `#f` is a value.
These are the set-like unions and refinements of
[Typed Racket](https://docs.racket-lang.org/ts-guide/types.html).

```scheme
(#%-def scalar (#%-union i64 boolean))
(#%-def scalar-to-integer
  (#%-λ () [] ((x scalar)) → i64
    = (#%-match x
        ((#%-is i64 integer) integer)
        (#t 1)
        (#f 0))))

(#%-def none (#%-struct () omega))
(#%-def some
  (#%-λ () [] ((value-type star)) → star
    = (#%-struct ((value value-type)) 1)))
(#%-def option
  (#%-λ () [] ((value-type star)) → star
    = (#%-union none (some value-type))))
```

Similarly, `result A E` is the union of nominal `ok A` and `err E` wrappers,
each declared grade `1`, with one field named `value` or `error`. These families
are ordinary type-valued functions. Distinct wrappers distinguish absence from
present `#f`, unlike `(#%-union (singleton #f) boolean)`.

### Immutable primitives

Provide trusted `list-of`, primitive strings, scalar comparison, and diagnostics
without adding recursive datatype syntax. `list-empty` takes an explicit element
type; `list-cons` infers it; consuming `list-view` returns
`(option (pair A (list-of A)))`. Lists inherit the element grade and may share
storage when unrestricted. Inspection, indexing, and conversion preserve ownership
and report checked failures. Arithmetic is defined as wrapping or checked.

## 4. Elaboration and execution

| Representation | Contents |
| --- | --- |
| Syntax objects | Atoms, lists/improper tails, source locations, and lexical context; later vectors |
| Library records | Cached interfaces, binding identities, transformer descriptors, and dependencies |
| Core AST | Libraries with retained import/export/body declarations, expanded core forms, ordinary applications, and resolved references; no `◰` forms |
| Checked IR | Inferred arguments, types, union conversions, captures, ownership operations, and recursive groups |

The existing syntax records already provide structure and locations. Add lexical
context and expansion provenance directly or through a wrapper. The reusable
syntax-pattern matcher extracts captures for both AST builders and macro template
instantiation. AST construction may accompany expansion of recognized forms;
arbitrary macro operands remain syntax until the macro interprets them.
Lexical resolution and expansion proceed together: binders and imports establish
identities needed for dispatch, and expansion can introduce more bindings. An
unresolved application retains its original syntax until dispatch; a completed
`Apply` contains an expanded operator and operands. Resolve `#%-macro` in
this lexical context to install a transformer; dispatch is not a runtime value
test.

The final core AST is still unchecked: type, grade, and initialization analysis
follow. A library node retains its declarations and ordered bodies, annotated
with a resolved interface and dependencies. Retention does not make import/export
declarations executable expressions; later lowering can extract their metadata.

The reader accepts data outside the core expression grammar. An expander must
resolve heads before parsing macro operands as expressions. Locations alone do
not supply lexical identity.

Use checking and synthesis, dependent conversion, union subtyping, and refinement.
The shared evaluator infrastructure has distinct execution contracts:

| Use | Contract |
| --- | --- |
| Program interpretation | Checked runtime operations and recursion |
| Transformer execution | Phase-local data and compiler capabilities |
| Type normalization | Pure terminating reduction, retaining neutral terms |

Normalization may reduce structs, admitted pure nonrecursive type families,
and trusted index operations. Retain neutral variables and applications for
unknown indices. Runtime recursion and recursive transformer helpers are not
initially admitted to conversion. A timeout is a diagnostic, never evidence of
equality. Do not read runtime locals or consume owners during checking.

Interpret checked terms with explicit frames and a trampoline, preserving
proper tail recursion and cleanup. Function interfaces will need latent effects;
plain `#%-Π` currently specifies only arguments and results. Effect syntax,
generic grade constraints, and more general dependent elimination remain open.

## 5. Libraries, lexical scoping, and expansion

### Library loading and binding identity

The driver reads a program or library declaration, resolves its imports, then
expands body forms under the imported language bindings. Initially support the
library declarations in section 1; defer `include`, `include-ci`,
`include-library-declarations`, and `cond-expand`. This is a library subset,
not yet full R7RS support.

Map library names to source locations and cache loaded library records per
compilation. Preserve each library as a distinct AST container through expansion.
Resolve imports before body expansion; process library-body `begin` declarations
in source order in one library scope, retaining their wrappers in the expanded
AST. They do not create the nested scope of `#%-begin`. Reject cyclic library
dependencies initially; this does not prohibit mutually recursive functions
within a library.

Imports and re-exports preserve binding identities through filtering, prefixing,
and renaming. Diagnose missing libraries, nonexistent requested names, unresolved
exports, and conflicting imported bindings. Importing one identity repeatedly
is allowed; replacing an imported binding by a local definition is not. Nested
lexical scopes may shadow it. Validate exports after discovering expanded local
bindings. These are the intended [R7RS import/export rules](https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-7.html).

A binding entry records its identity, scope/phase, and kind: value, built-in
syntax handler, or transformer descriptor. Exported macros retain definition
context, including private helpers. Generated references retain those identities
without requiring callers to import private names. Track resulting library
dependencies as well as explicit imports.

Expansion loads descriptors, not runtime values. Preserve ordered runtime bodies
and dependency metadata for later initialization; do not execute them to expand
imports. Structural scope processing handles lambda binders, captures, telescopes,
definition patterns, and match branches without checking their types.

### Macro definitions and local syntax bindings

`#%-macro` ◰ binds one name directly to a `#%-syntax-rules` ◰ specification.
Install its descriptor and eliminate the macro definition. `#%-def`
statements remain in the core AST; their runtime results are never classified
as macro transformers. The second rules form selects a custom ellipsis identifier.
Bare macro identifiers are not runtime values, and ordinary dotted applications
remain invalid.

```scheme
(#%-macro choose
  (#%-syntax-rules (otherwise)
    ((_ test yes otherwise no)
     (#%-match (#%-ann test boolean) (#t yes) (#f no)))))
(#%-def answer (choose #t 41 otherwise 42))

(#%-macro define-two
  (#%-syntax-rules ()
    ((_ (first-name second-name) initializer)
     (#%-def (#%-tuple first-name second-name) initializer))))

(#%-begin
  (define-two (left right) (#%-tuple 20 22))
  (i64-add left right))
```

In `choose`, `otherwise` is a pattern literal, not a capture. This example matches
when `otherwise` is unbound at both definition and use sites; shadowing it with
a distinct binding prevents the match.

Bootstrap the matcher, rule compiler, template interpreter, and expansion driver
in host Scheme. The adapter passes syntax and a definition binding view to that
engine; it never evaluates arbitrary transformer expressions. No Esker interpreter
or general quotation form is needed. The immutable engine design below supports
a later implementation in Esker. Procedural transformers and `quote-syntax` are
deferred.

`#%-let-syntax` ◰ compiles transformer specifications in the enclosing syntax
environment, then expands its body with the new macro bindings.
`#%-letrec-syntax` ◰ reserves every binding identity first; each specification
and the body see the whole group. Install the descriptors before expanding uses,
without eagerly expanding templates. Reject duplicate keywords. These follow
[R7RS syntax-binding scopes](https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-6.html#TAG:__tex2page_sec_4.3.1).

Both forms introduce local scope and leave an expanded `#%-begin` body when
runtime definitions or sequencing require it. They require a final expression;
macro bindings do not escape. Imported surface `define-syntax` expands to
`#%-macro`; surface `let-syntax` and `letrec-syntax` name the corresponding
expansion handlers.

An item-position macro produces one item; an expression-position macro must
produce an expression. A `#%-def` can bind several names from one initializer.
Returning `#%-begin` creates a nested scope; expansion never splices it away.
The final item of a block must expand to an expression.

### Pattern and template rules

These nonterminals describe reader syntax, not core patterns. `Pattern-Id`
classifies captures, literals, and wildcards; `Template-Id` classifies substitutions
and introduced identifiers. `Constant` is a supported non-identifier datum.
`Ellipsis` is the selected identifier in its active role; `#(...)` is a vector.

```text
Macro-Pattern  ::= (Identifier Syntax-Pattern*)
                 | (Identifier Syntax-Pattern* . Syntax-Pattern)
                 | (Identifier Syntax-Pattern* Syntax-Pattern Ellipsis Syntax-Pattern*)
                 | (Identifier Syntax-Pattern* Syntax-Pattern Ellipsis Syntax-Pattern* . Syntax-Pattern)

Syntax-Pattern ::= Pattern-Id | Constant
                 | (Syntax-Pattern*)
                 | (Syntax-Pattern+ . Syntax-Pattern)
                 | (Syntax-Pattern* Syntax-Pattern Ellipsis Syntax-Pattern*)
                 | (Syntax-Pattern* Syntax-Pattern Ellipsis Syntax-Pattern* . Syntax-Pattern)
                 | #(Syntax-Pattern*)
                 | #(Syntax-Pattern* Syntax-Pattern Ellipsis Syntax-Pattern*)

Template       ::= Template-Id | Constant
                 | (Element*)
                 | (Element+ . Template)
                 | (Ellipsis Template)
                 | #(Element*)
Element        ::= Template | Template Ellipsis
```

The literal-identifier list is mandatory, possibly empty. Its entries match
identifiers by binding instead of capturing syntax. It does not exempt identifiers
from hygiene: template free identifiers retain definition-site bindings, and
introduced binders avoid accidental capture. There is no hygiene-exemption list.

- Ignore the pattern's leading macro identifier. Pattern variables are unique.
  `_` is a wildcard unless declared literal. Literal entries also override the
  ellipsis marker. Compare literal identifiers by binding, with equal unbound
  names matching; compare constants by datum equality.
- Allow one repeated segment per list/vector pattern level, with nesting.
  Select the first matching rule. No match is an expansion error; a selected
  rule's template error does not retry subsequent rules.
- Preserve use-site context on substitutions and definition context on template
  identifiers. `(Ellipsis Template)` disables ellipsis interpretation inside its
  operand while still substituting variables. An active ellipsis is not an
  ordinary pattern/template identifier; an escaped one is.
- Validate repetition depths before installation. Positive-depth variables must
  be substituted at the same depth; depth-zero variables may broadcast inside
  a repetition driven by another variable. Every repetition needs a driver;
  simultaneous drivers must have equal lengths. Reject mismatches, never truncate.
- Consecutive template ellipses and extra depths for positive-rank variables are
  outside this baseline. Quote abbreviations are reader notation and do not
  stop pattern/template traversal. Reject unsupported datum forms explicitly.

The target is [R7RS §4.3.2](https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-6.html#TAG:__tex2page_sec_4.3.2)
and its [grammar](https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-9.html#TAG:__tex2page_sec_7.1.5),
not the additional repetition rules of [SRFI 149](https://srfi.schemers.org/srfi-149/srfi-149.html).
A matcher lacking vectors or other datum forms must identify itself as a subset.

### Immutable engine representation

For the eventual Esker implementation, use unrestricted syntax and immutable
metadata interpreted by known reusable helper functions. Store rule descriptors rather than environment-erased callable
closures. The engine needs lists, records, association lists, and recursive
helpers; it needs neither shared mutation nor user-defined recursive datatypes.

An abstract syntax view distinguishes identifiers, literal atoms, lists with
optional improper tails, and vectors. Inspection and reconstruction preserve
lexical context without exposing mutable references.

| Record | Fields |
| --- | --- |
| `variable-plan` | Slot ID, identifier syntax, outer-to-inner repetition-site IDs |
| `repetition-plan` | Site ID, pattern occurrence path, parent-site IDs |
| `rule-plan` | Pattern syntax, template syntax, variable plans, repetition plans |
| `rules-transformer` | Definition binding view, ellipsis identifier, literal identifiers, ordered rule plans |
| `capture-entry` | Variable slot, repetition index path, captured syntax |
| `repetition-extent` | Site ID, parent index path, repetition count |
| `captures` | Entries and extents |

These records can all declare `omega`. Use `i64` IDs/counts and immutable lists.
Assign stable per-rule variable and repetition IDs during validation, including
variable-free repetitions. Record every repetition instance, even zero-length
ones. Capture entries alone cannot distinguish missing matches from empty inner
repetitions. Parent paths preserve ragged nesting; validate driver lengths at
each parent path before zipping them.

```scheme
(#%-def compile-syntax-rules-type
  (#%-Π [] ((definition-view binding-view) (spec syntax))
    → (result rules-transformer diagnostic)))
(#%-def match-rule-type
  (#%-Π [] ((definition-view binding-view) (use-view binding-view)
         (rule rule-plan) (form syntax))
    → (option captures)))
(#%-def instantiate-template-type
  (#%-Π [] ((introduction introduction-context)
         (rule rule-plan) (matched captures))
    → (result syntax diagnostic)))
```

Compile without expanding templates or resolving their identifiers as runtime
expressions. Match with immutable accumulators; failed candidates discard their
captures without consuming the affine expansion context. Account for fixed
prefixes/suffixes around repetition. Dotted matching uses pair/tail structure:
`(_ x ... . tail)` captures all proper-list elements in `x` and an empty `tail`,
or the improper tail when present. Do not backtrack to assign an arbitrary proper
suffix to `tail`; an explicit dot followed by a proper list is still a proper list.

Instantiate only after selecting a rule. `binding-view` and
`introduction-context` are opaque unrestricted data. The affine driver allocates
one fresh invocation identity/introduction scope, then pure helpers reuse it
with distinct output-position paths. The driver retains `expand-context`;
recoverable failures must return its successor, while fatal errors may abort.
A general transformer signature describes one call, not closure reuse; procedural
registration needs a separate reuse contract.

### Expansion, phases, and hygiene

The driver distinguishes library declarations, body items, expressions, and
transformer specifications, maintaining their lexical environments while expanding.
Application dispatch uses the resolved head binding; source spelling alone cannot
classify a call as a macro invocation. `macro-expand-1` performs one head expansion
and otherwise returns the input unchanged. Full expansion repeats macro dispatch
on results, then traverses the designated positions of resolved forms. Completion
means no remaining macro uses in those positions, not structural equality with
a previous result. Bound runaway expansion with a located diagnostic.

1. Resolve a head by lexical binding and phase. Give an installed macro the
   **whole original form** without evaluating, checking, or expanding operands.
2. Expand its output again in the same syntactic context. Discarded operands
   need never be parsed as core expressions.
3. For a core form, process only designated expression positions. Binders,
   field labels, patterns, and macro specifications are not ordinary operands.
4. Expand ordinary applications in operator/operand order. Collect the completed
   scope's definitions, resolve references, and produce the final core AST,
   retaining library containers. Later elaboration checks signatures, bodies,
   ownership, SCCs, and initialization readiness. Transformers cannot bypass
   those checks or forge checked nodes.

Process `#%-macro` definitions in source order. Reserve the binding identity
before capturing the definition view; compile and register the descriptor on success.
A template may refer to its own binding, but invoking an uninstalled descriptor
is an error. Keep immutable identity views separate from the phase registry so
a view does not freeze an unfinished descriptor.

Defer lambda-body resolution/expansion as needed to recognize later same-scope
function bindings, retaining the source-position macro environment. Do not
prematurely dispatch an outer macro shadowed by such a binding. Scope-wide value
collection does not make future macro definitions available earlier. Macros can
produce independent definitions whose mutual recursion is analyzed afterward.

Transformers execute only phase-available dependencies; never run program
initializers speculatively or share runtime continuations across phases.
Expansion limits produce diagnostics, not type-equality proofs.

Use a complete binding-aware hygiene algorithm, such as
[binding as sets of scopes](https://users.cs.utah.edu/plt/scope-sets/).
Substitutions retain use-site context; template free identifiers retain definition
context; introduced binders and references share fresh introduction information.
Locations, string equality, and fresh names alone are insufficient.

Assign nominal struct occurrence keys during expansion/elaboration, including
invocation and output-position provenance. Separate invocations, or two copies
of one captured struct in an output, have distinct keys. Rechecking the same
expanded occurrence preserves its key. The driver establishes lexical scopes;
helpers cannot mint arbitrary scopes or checked terms.

Keep the declaration grammar separate from expression dispatch: macros cannot
manufacture imports or exports in arbitrary expression/item positions. Scheme's
body-splicing `begin` and `syntax-error` still need surface-language adapters;
neither changes the nested-scope semantics of `#%-begin`.

## 6. Runtime and compilation — future work

### Memory management

Build the Scheme heap and collector in library code over trusted owned
allocation, safe access/update, and reclamation primitives. Initially thread
heap state explicitly; defer dynamic parameters and allocation effect handlers.
Start with one thread and a nonmoving heap.

Candidate policy: reference counting plus tracing for cycles, triggered by
allocation at a heap budget. Reserve collection workspace outside the exhausted
managed heap. Specify how tracing, cycle reclamation, counts, and cleanup interact.
Reference counts alone do not reclaim strong cycles.

Root enumeration must include live temporaries, globals, external roots, and
reachable saved continuations. Share frame-tracing metadata with continuations;
a restricted visitor exposes managed references without extracting or duplicating
affine frame values. General native stack reflection is unnecessary. Suspension
and tracing cannot depend on allocation from the heap being collected.

`drop` and `trace` can be explicit records of operations; type-class syntax and
instance search are not prerequisites. Compiler-inserted cleanup still needs a
protocol. Cleanup must not execute arbitrary user control effects; finalizers
and fallible close operations need separate rules.

An owned `vec A` is affine, with exclusive updates returning its owner. `box`
and `arc` need a trusted storage boundary. The proposed unrestricted `arc A`
shares handles, including to affine payloads, without duplicating those payloads.
Duplication requires retain bookkeeping; an affine handle with explicit cloning
remains an alternative. Copying a payload requires `share A`; unique extraction
returns `A` only when no other handle remains, or returns the handle on failure.
Payloads must be runtime-eligible, independently of their ownership grades.
These policies are WIP and do not let ordinary structs raise field grades.

Shared mutation is also deferred. A candidate `cell A` requires unrestricted
`A` and shares a stable location through unrestricted handles. Reads/writes
preserve its type and are excluded from normalization. Refinements may depend
on immutable snapshots, not assumed future cell contents. Replace dependent
records as a whole to preserve field relationships. Cycles, cross-thread
sharing, and collection coordination need explicit protocols.

### Continuations and vector stacks

Use growable contiguous vectors for execution frames and saved continuations,
with offsets or handles valid across growth. Preserve proper tail calls. Specify
ownership transfer, abandonment cleanup, and growth before multi-shot control.

The initial control proposal uses affine `cont-1 A`:

```scheme
(#%-def capture-1-type
  (#%-Π [(A star)]
      ((body (#%-Π [] ((k (cont-1 A))) → nothing)))
    → A))

(#%-def invoke-1-type
  (#%-Π [(A star)] ((k (cont-1 A)) (value A))
    → nothing))

(#%-def answer
  (i64-add 1
    (capture-1
      (#%-λ () [] ((k (cont-1 i64)))
        → nothing
        = (invoke-1 k 41)))))
; Produces 42.
```

`capture-1` transfers the current continuation to its callback, without retaining
it as the callback's normal return path. `invoke-1` consumes the handle, cleans
up abandoned invoking frames, and resumes the saved computation. Partition
ownership between callback and saved frames. `nothing` prevents normal callback
return; these signatures describe control effects, not pure functions.

Capture initially targets one program execution root; handles cannot cross
interpreter runs or compilation/runtime phases. Full Scheme `call/cc` also
enters its continuation on normal callback return. Multi-shot control requires
duplicable captured frames and control-flow checks across calls. Demotion to
one-shot capture requires at most one total entry across all aliases and paths,
including normal return; one syntactic invocation is insufficient.
See [one-shot continuations](https://www.cs.tufts.edu/comp/150FP/archive/kent-dybvig/one-shot-continuations.pdf)
and [linearity under control effects](https://arxiv.org/abs/2307.09383).

Capture alone does not provide root traversal. The exact frame-tracing and
suspension interfaces remain future work alongside memory management.

### Specialization, C, and Scheme lowering

Specialize reachable code at representation-relevant type arguments, cache
instances, and diagnose unbounded specialization growth. A symbolic array length
need not be a specialization key; an explicit type argument may be static and
erased. Never recreate a captured affine environment per instantiation.

Lower checked terms through specialization, erasure, closure/control conversion,
and ownership validation to C. Unions may need tags, representation conversions,
and variant-specific cleanup; subtyping does not imply a free C cast. A term
needs either a known layout or a supported uniform representation; inability
to compile its representation is distinct from a type error.

Emit defined arithmetic, checked operations, moves, retains, and releases.
Use a trampoline or equivalent: C does not guarantee proper tail calls, and
`setjmp`/`longjmp` cannot restore a returned frame. C output still needs runtime
allocation, sharing, closures, cleanup, and control support.

Scheme lowering makes dynamic values, numeric dispatch, type/arity checks,
and dynamic application explicit. Full R7RS-Small additionally needs mutation,
cyclic storage, exceptions, `dynamic-wind`, and multi-shot continuations. Dynamic
boundaries cannot raise core grades. Core tuples are single values of static
arity; Scheme multiple values need a result-count protocol, not just tuples.

## 7. Implementation milestones

Track the working checklist in [TODO.md](../TODO.md).

1. **Syntax and binding:** extend the existing reader for `#%-` identifiers,
   matching delimiters and required datums; implement syntax matching, binding
   identities, library imports/exports, and lexical scope handling. Define the
   final core AST and its builders alongside this work.
2. **Expansion:** implement hygienic `syntax-rules` in host Scheme, named and
   local macro bindings, one-step expansion, and full contextual expansion.
   Produce library metadata and a resolved core AST without requiring execution.
3. **Elaboration and immutable execution:** infer arguments, check dependent
   types, grades, and initialization, then interpret checked terms. Later port
   the transformer engine to Esker if useful.
4. **Runtime and compilation:** storage/rooting protocols, vector-backed one-shot
   control, specialization, and C. Compare interpreter and compiled behavior.
5. **Scheme:** complete dynamic lowering and libraries after mutation, cyclic
   storage, multiple values, and full control semantics are specified.

The existing `syntax.sld` supplies located atoms and lists, not hygienic context
or this core AST. `#%-` identifiers, square/curly delimiters, `→`, vectors, and
binding scopes still need reader/expander work. Examples specify intended behavior;
they do not yet run.

Implementation checks should cover:

| Concern | Cases |
| --- | --- |
| Libraries | Retained library containers; missing/cyclic dependencies; filtered/renamed imports; conflicts; re-exports; exported macros using private helpers |
| Expansion scopes | `let-syntax` versus `letrec-syntax`; macro availability; shadowed heads; generated definitions; no eliminated forms in final AST |
| Binding and inference | Mandatory lists/results; telescope scope; ambiguous implicits; local index escape |
| Initialization | Cross-definition recursion; eager cycles; acyclic forward reads; premature calls/escapes; nested scopes |
| Ownership | Duplicate affine uses; missing captures; grade escalation; dependent field transfer; cleanup |
| Data | Tuple arity/unit; one-time initialization; irrefutable definitions; union overlap/coverage; stable nominal identity |
| Macro dispatch | One application form; binding-directed dispatch and shadowing; discarded non-core operands; improper macro input; nested expansion; both definition forms rejected in expression position; block scope retained |
| Definition forms | Value patterns survive expansion; named macro definitions install descriptors and disappear; value results never register macros |
| Pattern literals | Same binding matches; distinct shadowed binding fails; equal unbound names match; template hygiene remains intact |
| Macro ownership | Repeated affine input and omitted captures rejected after expansion |
| Hygiene | Use-site `temp`; definition-site `#%-match`; same spelling with distinct bindings; copied struct occurrences |
| Repetition | Fixed suffixes; zero and ragged inner extents; variable-free repeats; incompatible drivers; custom/literal/escaped markers |
| Diagnostics | Unsupported datums; improper lists and vectors; no matching rule; invalid template; runaway expansion |

For repetition tests, `(_ head middle ... last)` must preserve its suffix at
zero repetitions; `(_ ((x ...) ...))` on `(m (() (a b) ()))` records inner extents
zero, two, zero. Repeated wildcards also record zero extents. Escaped `(... ...)`
emits one ellipsis, and `(... (x ...))` still substitutes depth-zero `x`.
