# Minimal core grammar and a syntax-rules expansion layer

Status: implementation proposal accompanying [the core design](core-ir.md).
The immediate target is the immutable, macro-free language in sections 1–4.
Sections 5–9 describe a later expansion layer and how its matcher can be written
in that language. They do not require macros in the first parser or interpreter.
Shared mutation, cyclic heaps, C generation, and full Scheme lowering remain
later work.

## 1. Reader syntax, source forms, and checked terms

Keep three representations distinct:

| Representation | Responsibility |
| --- | --- |
| Reader syntax | Atoms, proper/improper lists, source locations; later vectors and lexical context |
| Core source forms | Recognized forms, binder groups, field labels, and expression positions |
| Checked terms | Resolved binding identities, explicit inferred arguments, types, refinements, and ownership decisions |

The reader accepts more than the expression grammar. In particular, a dotted
list can be macro input without being a function application. A later expander
must inspect a form's head before parsing its operands as expressions. Templates
and patterns are reader syntax until their enclosing construct interprets them.

Matching `()`, `[]`, and `{}` all produce the same list structure; mismatched
fenders are errors. Square brackets around implicit parameters are a convention.
Preserve locations, but delimiter kind need not affect elaboration. Recognize
`λ`, `Π`, `→`, and `=` as complete tokens. Binder casing follows the
core design; the reader must also preserve arbitrary Scheme identifier spelling
in syntax data instead of applying the core naming convention to it.

For the initial core, literals are booleans, signed integer literals, characters,
and immutable strings. An integer literal checks against `i32` or `i64`, or
defaults to `i64` when synthesized; an out-of-range literal is rejected. A reader
may recognize more numeric forms without admitting them as core expressions.
There is no implicit conversion from quoted Scheme data to a core value.

## 2. Macro-free surface grammar

In this grammar, `*`, `+`, and `|` are metanotation. Parentheses are literal
list delimiters. `Name` and `Field` are identifiers, and `Literal` is an admitted
core literal. `Type-Expr` is the same grammatical category as `Expr`, checked to
denote a type. In both function forms, the first telescope is implicit and the
second explicit. Both are required, including when empty; delimiter shape is
irrelevant.

```text
Program       ::= Item*
Item          ::= Definition | Expr
Definition    ::= (def Pattern Expr)

Expr          ::= Name
                | Literal
                | (Π Telescope Telescope → Type-Expr)
                | (λ (Name*) Telescope Telescope → Type-Expr = Expr)
                | (Expr Expr*)
                | (ann Expr Type-Expr)
                | (begin Item* Expr)
                | (struct Telescope Grade)
                | (tuple-of Type-Expr*)
                | (tuple Expr*)
                | (union Type-Expr*)
                | (new Type-Expr (Field-Value*))
                | (match Expr Clause+)

Telescope     ::= (Binder*)
Binder        ::= (Name Type-Expr)
Grade         ::= 1 | omega
Field-Value   ::= (Field Expr)
Clause        ::= (Pattern Expr)

Pattern       ::= Name
                | Literal
                | (is Type-Expr Name)
                | (new Type-Expr (Field-Binding*))
                | (tuple Name*)
Field-Binding ::= (Field Name)
Type-Expr     ::= Expr
```

Every core pattern name is an ordinary binder, including `_` if used.
Duplicate names within a binder group, definition group, or match pattern
are errors; separate definitions in the same block or file scope also cannot
redefine a name. Telescope binders are distinct across the implicit and explicit
groups. Field labels are unique within a struct.

Grades describe affine or unrestricted ownership. Phase availability and
erasure use separate rules for the same types. Every struct supplies a literal
grade as its final argument. The checker computes its field-grade bound and
rejects a declared grade above it; higher-level syntax can synthesize the
argument. Generic structs must justify their declared grade for every admitted
instantiation. An unconstrained generic wrapper can declare `1`.

Special forms take precedence over the application production when the head
resolves to their built-in syntax binding. Their names are not first-class
runtime functions. Ordinary lexical bindings may shadow syntax bindings; the
resolver, rather than a parser keyed only by spelling, selects the form.
The structural markers `→` and `=` are recognized in their designated
positions. Empty `()` is not an expression; `(f)` is a zero-argument call.

There are no separate declaration forms for types or functions. There is no
general `quote`, `let`, `letrec`, `fix`, rest parameter, `set!`, or user-defined
recursive datatype form in this initial grammar. `begin` provides scoped local
definitions and sequencing. Ordinary applications cover arithmetic, array
operations, `singleton`, and the immutable data primitives described below. An expression
can be checked or run through the interpreter API. A source file processes its
items in a file scope; top-level expression results are discarded, and the
driver may select a defined entry function after initialization.

`union` has an intrinsic n-ary typing rule and a checked union node. A fixed-arity
`Π` cannot describe that arity, so it is not initially a first-class callable.
It remains an expression producing a type value. `(union)` denotes `nothing`.
`singleton` can be a unary intrinsic, initially restricted to supported pure
scalar values. Neither adds a top-level introduction form.

`tuple-of` and `tuple` are intrinsic n-ary forms for a structural product type
and a value of that type. Their arities are fixed by the source operands; they
are not first-class variadic functions. `(tuple-of)` is the unit type, inhabited
by `(tuple)`. A one-element tuple is distinct from its element, and nested tuples
are not flattened. Tuple types compare their ordered element types, without
nominal occurrence identities. See [structural tuples](core-ir.md#structural-tuples).

## 3. Rules needed alongside the grammar

### Binding and execution order

`Π`, `λ`, and `struct` use left-to-right telescope scope. A binder enters scope
after its annotation; all function parameters are in scope in the result type
and body. Both function groups are mandatory: the first is implicit and the
second explicit. Every lambda also requires its capture list, which may be empty.
Implicit parameters are solved only from explicit arguments, not expected call
results. Duplicate binders and forward references within telescopes are rejected.

Every `λ` has a mandatory capture list `(Name*)` before its parameter groups;
the empty list explicitly captures nothing. Capture names resolve to distinct
enclosing bindings before parameter scope begins, and cannot collide with a
parameter name. `Π` has no capture list. Listed captures are in scope throughout
the lambda's annotations and body. The capture list must cover free outer values
in those positions, nested capture lists, and dependencies in captured types.

Closure construction moves listed affine values immediately and may copy listed
unrestricted values. Primitive bindings and verified closed static top-level
definitions need no capture field; other outer values, including runtime globals,
must be listed. The closure grade follows its captured runtime fields. Type-only
dependencies follow the separate phase rules. These are the [capture rules](core-ir.md#explicit-consuming-captures)
for both source lambdas and lambdas produced by later macros.

Every `begin` creates a fresh lexical scope. Its items execute in source order.
Each `def` evaluates one initializer in the preceding scope, then introduces
its bindings together using the same `Pattern` grammar as `match`. A name binds
the whole result; tuple and struct patterns consume and unpack it. Pattern
checking derives the bound types, including dependent field relationships.
Separate `def` statements do not create nested scopes or admit forward references.
Local bindings infer a monotype initially; polymorphism is expressed by a `λ`
over type parameters. Recursive function groups have the rules below.

Require a definition's pattern to be irrefutable for the initializer's checked
type and refinements. All pattern forms are available, including literals and
`is`, but reject a definition when coverage cannot be proved. Use `match` for
cases requiring an alternative branch. No runtime pattern-failure effect is
introduced by `def`. Evaluate the initializer once and transfer ownership using
the same consuming elimination as `match`.

The empty tuple pattern `(tuple)` requires `(tuple-of)`. `(tuple x)` requires a
one-element tuple, while the pattern `x` binds the whole result. Struct patterns
must name all fields in declaration order. Patterns remain shallow, names must
be distinct, and `_` has ordinary binding semantics in definitions too.

A block requires a final expression and returns its value in tail position.
Nonfinal expression results are discarded before the next item. Unused affine
bindings are cleaned up at scope exit. The [block example](core-ir.md#local-bindings-and-sequencing)
shows sequential dependencies while keeping a lambda body a single expression.
Reject a block result type that exposes an unavailable local index; substitute
admitted pure definitions or package the index with its payload in a dependent
record. File scope admits any item sequence without requiring a final expression.

Evaluate a runtime call's operator and explicit arguments left to right. Static
arguments are elaborated and erased where appropriate, without evaluating
runtime effects during checking. Calls have exactly the explicit arity declared
by their signatures. `match` evaluates only its selected branch. Ownership uses
accumulate sequentially and are checked per branch.

Branching is expressed with `match`. A higher-level Boolean conditional
`(if Test Yes No)` lowers to `(match (ann Test boolean) (#t Yes) (#f No))`:
evaluate the test once, require its Boolean type, check both branch bodies, and
execute only the selected body. Scheme's broader truthiness can instead lower
to a `#f` clause followed by a named catch-all clause for the true branch.

For `new`, require every field exactly once, in declaration order. Check and
evaluate fields in that order, substituting earlier values into later types.
This avoids giving field-label reordering an implicit effect on evaluation.
The type expression itself must meet the existing type-formation restrictions.

Evaluate `tuple` elements left to right and transfer their values into the
resulting tuple. The checker infers its element types, or checks each element
against the corresponding expected tuple type. A tuple's grade is the minimum
of its element grades, with grade `omega` for the empty tuple; there is no grade
argument. The ordinary cleanup rules apply if construction is abandoned.

### Elimination and dependent scope

`match` evaluates its scrutinee once. Initially patterns are shallow: nested
destructuring is another `match`. A name binds the entire selected value.
`new` patterns open a known nominal struct's fields in declaration order and
must bind every field, including unused ones. In `match`, pattern binders are
in scope only in their branch body; in `def`, they belong to the containing
scope. Unused affine bindings receive ordinary cleanup at scope
exit. A higher-level wildcard lowers to a fresh unused binder for each occurrence;
the core gives `_` normal binding, reference, and duplicate-name semantics.

A `(tuple Name*)` pattern consumes a tuple with a statically known `tuple-of`
type and binds every element in order. The number of names must match the
tuple's arity. The pattern is irrefutable for that type and does not add dynamic
dependent type tests to `is`. Patterns remain shallow; use another match to
destructure a nested element.

```scheme
(def package-length
  (λ () [] ((value sized-array))
    → i64
    = (match value
        ((new sized-array ((length n) (items unused-items))) n))))
```

Variant tests do not duplicate ownership. Select a branch using safe observations
before moving the selected payload or fields. Matching an affine value consumes
its owner, including when only part of the payload is retained.

`is` patterns support only types with a known runtime discriminator: primitive
tags, supported singletons, and nominal structs. They cannot test arbitrary
dependent type equality at runtime. Clauses are tried in source order. Check
coverage for the supported cases, requiring a catch-all where coverage cannot
be established. Failure to discriminate or establish coverage is a static error.

Check branch bodies against an available expected type. Otherwise synthesize a
common type, using a supported union join where necessary. A branch-local field
index cannot escape in the result type; package it in an existing dependent
record if it must escape with its payload. This does not yet specify arbitrary
dependent elimination motives.

### Definitions, recursion, and phases

One `def` has one initializer, whether it binds one result or several tuple
components. Process separate definitions in source order. Reject recursive
value/type initializers and forward reads of values; lexical name availability
does not initialize storage.

Initially allow recursive references only for `(def Name Lambda)` or
`(def (tuple Name+) (tuple Lambda+))`, where the elaborated result is a direct lambda
or a direct tuple of lambdas with matching arity. Require unrestricted external
captures. Check every header and capture list in the preceding environment,
then check bodies with the corresponding functions available as recursive code
references. Group names are available only in those bodies, not in the headers
or capture lists. Construct environments in element order and bind the names
only after the initializer completes; no body executes during construction.
Retain concrete function identities and their known environment grades through
the tuple. This rule does not make arbitrary environment-erased callables reusable.

An arbitrary expression, including a call or `begin`, may produce a tuple of
functions, but it cannot refer recursively to the names being defined. A tuple
mixing recursive functions with ordinary computed values is also rejected by
this initial recursion rule. Use earlier definitions for prerequisites, or
compute them inside an initializer's `begin` before defining a local recursive
group and returning its functions.

Self and peer references within that group do not create captured copies of the
functions. Each reference uses the established group environment. All other
runtime outer bindings require explicit captures, including runtime globals.
Nonrecursive definitions can capture affine values under the ordinary rules;
recursive calls cannot recapture an affine environment on each call. Owned
arguments can still be threaded through recursive calls. The interpreter can
store code references and a shared immutable external environment instead of a
cyclic graph of closures. No user-visible `fix` form is needed for these groups.

Normalizing types may reduce trusted pure operations and admitted nonrecursive
pure definitions. Initially, recursive helpers can execute as programs or
compile-time transformer code, but are not admitted into type normalization.
Being immutable does not imply termination. Arbitrary higher-order calls need
an established normalization contract before conversion can execute them.

The checked representation retains blocks, ordered bindings, recursive function
groups, and ownership-aware `match`. Elaboration makes inferred
arguments, union injections/refinements, and static information explicit. The
interpreter receives checked terms and uses explicit control frames with a
trampoline; a later C backend can consume the same checked representation.

## 4. Immutable data sufficient to implement the macro engine

Avoid adding recursive datatype syntax just to bootstrap the matcher. Provide
trusted immutable `list-of` and, in the expansion layer, abstract `syntax`.
User-defined structs and unions can hold those values without defining a new
recursive type themselves.

The small list interface needs `list-empty` with an explicit element type,
`list-cons` with an inferred element type, and a consuming `list-view`. The last
returns `(option (pair A (list-of A)))`: empty or a head/tail pair. Inspection
must respect the list's effective grade. Syntax values and the macro engine's
immutable metadata have grade `omega`.

Add primitive immutable strings, scalar comparison, and diagnostic construction.
An abstract syntax view distinguishes identifiers, literal atoms, lists with
optional improper tails, and later vectors. Identifier inspection must preserve
lexical information; a string spelling is not a binding identity. Syntax views
and reconstruction expose no mutable reference.

The rule interpreter can use named recursive function groups and immutable
association lists. It does not need a mutable dictionary, user-defined recursive
types, or higher-order iteration. In particular, repeatedly invoking a callback
stored with an erased `Π` type would conflict with the current conservative
affine callable rule. Reusable top-level helper functions avoid that issue.
Their reuse is justified by unrestricted dependencies and captures, not merely
by their placement at top level.

These are runtime/data capabilities, not additional expression productions.
The parser, elaborator, checker, and interpreter can first exercise lists and
records without installing any macro binding.

## 5. A small, separate macro-definition grammar

The working proposal keeps the expansion phase explicit while retaining `def`:

```scheme
(def choose
  (macro
    (syntax-rules ()
      ((_ test yes no)
       (match (ann test boolean)
         (#t yes)
         (#f no))))))

(def answer
  (choose #t 41 42))
```

`macro` is an expansion-only marker in a definition's RHS. The bootstrap marker
binds one transformer by name; its output may introduce several ordinary bindings.
For the first macro extension, restrict its operand to a `syntax-rules` specification:

```text
Macro-Definition ::= (def Name (macro Rules-Spec))
Rules-Spec       ::= (syntax-rules (Identifier*) Rule*)
                   | (syntax-rules Identifier (Identifier*) Rule*)
Rule             ::= (Macro-Pattern Template)
Macro-Use        ::= (Identifier Reader-Syntax*)
                   | (Identifier Reader-Syntax* . Reader-Syntax)
```

`Reader-Syntax` is a whole reader node, without an expression constraint.
`Macro-Use` applies only when the head resolves to an installed macro. At each
expression or item position, expand such uses before applying the core
`Expr` or `Item` productions. The same list shape may otherwise denote
an ordinary application; a dotted ordinary application is rejected.

The second `Rules-Spec` form supplies a custom ellipsis identifier. Rule bodies
are opaque reader syntax, not ordinary application arguments. This extension is recognized
before falling back to the macro-free `Definition` grammar, using the resolved
built-in bindings of `macro` and `syntax-rules`, not their spellings alone.
It does not add a runtime `macro` operation or classify ordinary runtime results
as macros.

A macro can introduce several bindings from one initializer:

```scheme
(def define-two
  (macro
    (syntax-rules ()
      ((_ (first-name second-name) initializer)
       (def (tuple first-name second-name) initializer)))))

(begin
  (define-two (left right) (tuple 20 22))
  (i64-add left right))
```

The invocation occupies an item position and expands to one `def`. Its
use-site names `left` and `right` become available to following items in this
block. The template emits the initializer once, so a call or block producing
the tuple can share work. A macro returning `begin` would instead introduce a
nested scope.

The bootstrap handler passes the specification as a syntax value, together with
its definition environment, to an already-checked core function. This requires
compiler-supplied syntax constants, not a general source quotation form. A later
procedural-transformer facility may add `(quote-syntax Reader-Syntax)` and a
general compile-time RHS, but neither is necessary for this first extension.
In particular, ordinary Scheme `quote` would lose the lexical information the
handler needs.

Register `syntax-rules` using a small built-in adapter initially. The actual
rule validator, matcher, and template interpreter are ordinary core programs.
The adapter does not need to implement the pattern language or run unchecked
source. This breaks the bootstrap cycle: the macro-free interpreter can execute
the engine before any user macro has been installed.

### Pattern and template grammar

Use the R7RS-small pattern language, keeping its grammar separate from `Expr`.
Its wildcard rules belong to macro matching; core `match` uses ordinary binders.
Here `Ellipsis` is the selected identifier in its active role. `Pattern-Id`
includes captures, literal identifiers, and the wildcard after classification;
`Template-Id` includes substitutions and introduced identifiers. `Constant`
means a supported non-identifier datum constant. `#(...)` denotes vector syntax,
not an alternate list delimiter.

```text
Macro-Pattern ::= (Identifier Pattern*)
                | (Identifier Pattern* . Pattern)
                | (Identifier Pattern* Pattern Ellipsis Pattern*)
                | (Identifier Pattern* Pattern Ellipsis Pattern* . Pattern)

Pattern       ::= Pattern-Id | Constant
                | (Pattern*)
                | (Pattern+ . Pattern)
                | (Pattern* Pattern Ellipsis Pattern*)
                | (Pattern* Pattern Ellipsis Pattern* . Pattern)
                | #(Pattern*)
                | #(Pattern* Pattern Ellipsis Pattern*)

Template      ::= Template-Id | Constant
                | (Element*)
                | (Element+ . Template)
                | (Ellipsis Template)
                | #(Element*)
Element       ::= Template | Template Ellipsis
```

There is at most one repeated segment at each list/vector pattern level; nesting
creates further repetition dimensions. The leading macro-pattern identifier
is ignored. Pattern variables are unique; `_` discards, unless declared literal.
Literal identifiers compare bindings, with equal unbound names matching. A
literal entry also overrides the ellipsis marker's special role. Constants use
datum equality. Select the first matching rule; no match is an expansion error.
Template substitutions preserve use-site context; other identifiers preserve
definition-site context. `(Ellipsis Template)` disables ellipsis interpretation
inside its operand. These rules follow [R7RS §4.3.2](https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-6.html#TAG:__tex2page_sec_4.3.2)
and its [formal grammar](https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-9.html#TAG:__tex2page_sec_7.1.5).

Exclude an active ellipsis from ordinary `Pattern-Id` and `Template-Id` roles.
In an escaped template its occurrences are ordinary identifiers, while pattern
variables still substitute. Thus `(... ...)` emits one ellipsis, and
`(... (x ...))` substitutes a depth-zero capture `x` beside a literal ellipsis.

Validate repetition depth before installing a rule. A variable captured under
positive depth must be substituted at that same template depth; a depth-zero
variable may broadcast inside a repetition driven by another variable. Each
template repetition needs a driver, and drivers at that level must have equal
lengths. Diagnose incompatible lengths instead of truncating a zip. Consecutive
template ellipses and additional depths for positive-rank variables are outside
this baseline; [SRFI 149](https://srfi.schemers.org/srfi-149/srfi-149.html) specifies
extensions and explains their distinction from R7RS.

The full grammar is the compatibility target. A first matcher may support only
the reader's available atom/list forms, but must reject unsupported forms and
describe itself as a subset until vectors and the remaining datum forms exist.
Source quote abbreviations are reader notation, not an instruction for the
matcher to stop traversing a pattern or template.

## 6. Representing the engine in the immutable core

Use an unrestricted `rules-transformer` descriptor containing checked rule data,
not a stored function whose grade is unknown. It contains a definition binding
view, literal identifiers, the selected ellipsis identifier, and ordered rules.
The binding view is an immutable lexical snapshot, not a captured compiler
capability or mutable runtime environment.

A compact representation can keep patterns/templates as abstract syntax and
use flat metadata tables rather than introducing recursive pattern datatypes:

```scheme
(def variable-plan
  (struct ((slot i64)
           (identifier syntax)
           (repetition-sites (list-of i64))) omega))

(def repetition-plan
  (struct ((site i64)
           (pattern-path (list-of i64))
           (parent-sites (list-of i64))) omega))

(def rule-plan
  (struct ((pattern syntax)
           (template syntax)
           (variables (list-of variable-plan))
           (repetitions (list-of repetition-plan))) omega))

(def rules-transformer
  (struct ((definition-view binding-view)
           (ellipsis syntax)
           (literals (list-of syntax))
           (rules (list-of rule-plan))) omega))

(def capture-entry
  (struct ((slot i64)
           (indices (list-of i64))
           (form syntax)) omega))

(def repetition-extent
  (struct ((site i64)
           (parent-indices (list-of i64))
           (count i64)) omega))

(def captures
  (struct ((entries (list-of capture-entry))
           (extents (list-of repetition-extent))) omega))

(def selected-rule
  (struct ((rule rule-plan)
           (captures captures)) omega))
```

Assign stable per-rule slots and repetition-site IDs while validating a pattern.
Each variable's `repetition-sites` records its outer-to-inner ancestry. These
identifiers are metadata, not addresses or user-visible type identities.
Repetition plans identify pattern occurrence paths even for variable-free
repetitions; IDs do not depend on how many input elements happen to match.
Store a count for every repetition instance, including count zero. Capture
entries alone cannot distinguish an absent match from an empty inner repetition.
Parent paths preserve ragged nesting: two outer elements can have different
inner lengths. Independent template drivers are zipped only after validating
their extents at the current parent path.

This interface sketch uses ordinary dependent function types. The routines
themselves are to be implemented; these definitions describe their signatures:

```scheme
(def compile-syntax-rules-type
  (Π [] ((definition-view binding-view) (spec syntax))
    → (result rules-transformer diagnostic)))

(def match-rule-type
  (Π [] ((definition-view binding-view)
      (use-view binding-view)
      (rule rule-plan)
      (form syntax))
    → (option captures)))

(def instantiate-template-type
  (Π [] ((introduction introduction-context)
      (rule rule-plan)
      (matched captures))
    → (result syntax diagnostic)))
```

`binding-view` and `introduction-context` are opaque expansion-library types.
Views and the nominal `rules-transformer` descriptors above are unrestricted.
An introduction context is also unrestricted immutable data, scoped to one
expansion. The affine driver allocates its unique invocation identity and
introduction scope once. Pure template helpers reuse it together with distinct
output-position paths, including paths for each copy of substituted syntax.
The driver supplies subsequent lexical binding scopes during elaboration.
This gives the expander hygiene/provenance information without allowing a
template helper to manufacture checked terms or allocate arbitrary fresh scopes.

The engine can execute these steps with immutable accumulators:

1. **Compile the specification.** Validate rule shapes, literal/marker roles,
   unique variables, and repetition depths. Produce rule metadata and preserve
   definition syntax. Do not expand template forms or interpret their identifiers
   as runtime variable references during this step.
2. **Match a rule.** Walk the input and pattern together, accumulating captures
   and extents. For a repeated sequence, account for its fixed prefix/suffix and
   match each repetition at a distinct index path. Dotted patterns use syntax
   pair/tail operations, including a tail represented by another list node;
   an explicit dot followed by a proper list does not make the datum improper.
   For `(_ x ... . tail)`, `(m a b)` captures `a`, `b` and an empty tail;
   `(m a b . c)` captures `a`, `b` and tail `c`. Do not backtrack to give the
   dotted-tail variable an arbitrary suffix of the proper list.
3. **Select a rule.** Try rules in order. Failure discards an immutable candidate
   capture table and proceeds with the next rule; it does not consume the
   affine expansion context. Once a rule matches, a template error is a
   diagnostic, not a reason to try a later rule.
4. **Instantiate.** Follow the template with the capture paths and recorded
   extents. Substitute matched syntax, reconstruct literal structure, and use
   the introduction context for template-origin identifiers and provenance.
   Construct the output before asking the elaborator to interpret it.

Use recursive helper groups or a driver with an explicit work list for the tree
walk. Its task records, capture tables, and work list are ordinary immutable
data. The macro engine needs no shared mutable cells.

The affine `expand-context` stays with the expansion driver. Matching only reads
immutable binding views. After a match succeeds, obtain the fresh introduction
context, build the result, and return the successor expansion context. Fatal
errors may abort expansion; any recoverable API must return the context on its
failure path as well. A failed pattern match is not such an effectful failure.

The generic transformer signature in the core sketch describes one invocation.
It does not by itself make a stored closure reusable. The descriptor plus a
known reusable top-level runner supplies reuse for `syntax-rules`; general
procedural transformer registration awaits an explicit callable-reuse contract.

## 7. Definition processing and macro application

The expansion driver resolves bindings with a phase and a syntactic context.
Bindings identify a core form, an ordinary value, or an installed macro descriptor.
A bare macro identifier is not an ordinary runtime value. A local value binder
can shadow a macro, so the same printed head may denote an ordinary call in a
different scope. Macro dispatch never depends on a runtime type test.

Process definitions in source order. For a macro definition, reserve its binding
identity before capturing the definition environment. Invoke the already-checked
rule compiler at expansion phase and install the descriptor on success. The
binding is usable by subsequent items in the scope. A template may refer to its
own binding, but invoking an uninstalled descriptor is an expansion error.
Ordinary definitions expand and check one initializer, with binding visibility
and the recursive-function exception described in section 3. An initializer's
own nested `begin` scope does not export its local names with the tuple result.

The immutable definition view retains binding identities, including the reserved
self identity. Descriptor availability lives separately in the
driver's current phase registry, which associates an installed descriptor with
its identity.
The captured view must not freeze the self descriptor in its unfinished state.
The driver can thread successive immutable registries through its affine context.

Do not use the type normalizer as the transformer evaluator. Checked recursive
helpers may run during expansion even though conversion does not reduce them.
Only phase-available dependencies may execute: no reading program runtime locals,
sharing runtime continuations across phases, or running runtime initializers
speculatively. Expansion limits yield diagnostics, never proofs of type equality.

At an item or expression position:

1. If its head resolves to a macro, give the descriptor and the **entire original
   syntax form** to the runner. Do not evaluate, typecheck, or recursively expand
   the operands first. An operand may be a binder, a pattern, or arbitrary data.
2. Expand the returned syntax again in the same lexical and syntactic context.
   It can begin with another macro or contain macros in expression positions.
3. If the head resolves to a core form, interpret only that form's designated
   expression positions, introducing scopes before processing their bodies.
   Field labels, binders, and macro specifications are not ordinary operands.
   Enter a new scope for every `begin` and expand its items in order. A `def`
   adds its bindings to the current item scope without introducing another one.
4. Otherwise elaborate an ordinary application, including a computed operator,
   or an atomic expression. Check the resulting core types and ownership.

For `choose`, the second definition above expands to
`(def answer (match (ann #t boolean) (#t 41) (#f 42)))`.
An unused macro operand may disappear without ever being checked as an expression.
By contrast, both branches of the resulting core `match` must typecheck even though
only one executes. A transformer cannot manufacture a checked node or bypass
the affine-use checker by duplicating input syntax.

An item-position invocation, at top level or inside `begin`, produces one item:
an expression or a definition consuming its result with an irrefutable pattern. An
expression-position invocation must produce one expression; a bare `def` is
invalid there, while `begin` can provide local bindings and a result. The final
item of a `begin` must expand to an expression. The protocol does not splice
sequences or erase a `begin` scope. Tuple binding evaluates one ordinary core
value and distributes its components to names. The eventual Scheme front end also needs
`define-syntax`, `let-syntax`, `letrec-syntax`, and `syntax-error`; those bindings
can lower to this phase protocol without adding runtime evaluator forms.

## 8. Hygiene and nominal identity

Extend located syntax with lexical scope information and expansion provenance.
The existing source locations alone do not distinguish bindings. Supply binding
comparison and syntax reconstruction through the expander's trusted interface;
do not implement hygiene by comparing identifier strings or renaming every
identifier with the same printed name.

Substituted syntax retains its use-site context. Template-origin free identifiers
retain definition context, while introduced binders and their references share
fresh introduction information for the invocation. The binder-aware expansion
traversal then establishes their lexical scopes. Freshness alone is insufficient:
it must also preserve the intended references. Use a complete hygiene algorithm,
such as [binding as sets of scopes](https://users.cs.utah.edu/plt/scope-sets/),
for the trusted binding layer; the immutable rule interpreter uses its interface.

Each expanded struct occurrence receives a stable nominal key that includes its
expansion occurrence, as well as the type-family arguments described in the
core design. Two separate macro invocations must not accidentally share a type
identity because they copied the same template. Rechecking or normalizing the
same expanded occurrence must preserve its identity. Assign occurrence identities
during expansion/elaboration, rather than generating them during evaluation.

## 9. Implementation checkpoints

The current `syntax.sld` already separates atoms and located lists with optional
dotted tails. It is still a reader, not this core-form parser. It currently accepts
only parenthesis fenders; matching square/curly fenders and `→` need
lexical work. Vectors and binding scopes also remain unimplemented. This proposal
does not claim that the examples already run.

Implement and exercise the layers in this order:

1. Reader/token additions, then the macro-free grammar and binding rules.
2. Elaboration, checking, and immutable interpretation, including scoped blocks,
   single-initializer definitions, tuples, lists, and consuming matches. Exercise
   mutual recursion and reject uninitialized reads independently of normalization.
3. Abstract syntax inspection and binding-aware hygiene infrastructure.
4. Compile, match, and instantiate rule descriptors as core functions. Test
   these by calling them directly with supplied syntax values before registering
   user macros.
5. Add the macro-definition adapter and head-dispatch expansion loop. Recheck
   every expansion through the same core elaborator/checker.

The following cases should become implementation tests, not merely examples
that happen to expand successfully:

| Case | Required observation |
| --- | --- |
| `choose` above | Expands to core `match`, then checks as `i64` |
| `define-two` in a block | Both names are available to following items in that block |
| A tuple initializer performs shared work | It executes once before any of its output names become available |
| Tuple binding has the wrong number of names | Static arity error |
| Tuple binding consumes an affine tuple | Components receive ownership; the old aggregate cannot be reused |
| A macro returns `begin` containing definitions | Bindings remain inside the new scope |
| A macro returns `def` in an expression position | Expansion is rejected in that context |
| A macro shadows an outer value; a local value shadows that macro | Dispatch follows the binding in scope |
| A macro discards a syntactically non-core operand | Discarded operand is not parsed as `Expr` |
| A macro repeats an affine argument in its output | The core checker rejects the duplicate ownership use |
| A generated lambda omits an outer value from its capture list | Capture checking rejects the expansion |
| Template introduces `temp` beside a use-site `temp` | No accidental capture |
| Template uses `match` beneath a use-site binding named `match` | Definition-site syntax binding is preserved |
| Literal identifier has the same spelling but a different binding | Literal match fails |
| Pattern `(_ head middle ... last)` | Fixed suffix survives zero or several repetitions |
| Pattern `(_ ((x ...) ...))` with input `(m (() (a b) ()))` | Outer extent is three; inner extents are zero, two, zero |
| Template `(pair-up x y) ...` driven by unequal capture lengths | Expansion reports a shape mismatch |
| Repeated wildcard matches zero inputs | An explicit zero extent remains, despite having no capture entries |
| Custom ellipsis, literal `_`, or escaped ellipsis | Marker roles follow the specification |
| Improper-list and vector patterns | The syntax view preserves their distinct structure |
| Two invocations generate identical-looking `struct` forms | Distinct occurrence identities, stable under normalization |
| One invocation duplicates a captured `struct` into two output positions | Distinct occurrence keys even if both positions share a syntax node |
| Template expands into another macro call | Expansion resumes before core-form parsing |
| No matching rule, invalid template, or runaway expansion | Located expansion diagnostic; no partially checked program |

The initial interpreter remains usable without this expansion layer. The macro
engine adds checked programs over syntax data and a small compiler protocol;
it does not make user macro execution part of runtime application semantics.
