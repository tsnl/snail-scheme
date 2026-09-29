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
`λ`, `Π`, `→`, `=`, `#:captures`, and `#:grade` as complete tokens. Binder casing follows the
core design; the reader must also preserve arbitrary Scheme identifier spelling
in syntax data instead of applying the core naming convention to it.

For the initial core, literals are booleans, signed integer literals, characters,
and immutable strings. An integer literal checks against `i32` or `i64`, or
defaults to `i64` when synthesized; an out-of-range literal is rejected. A reader
may recognize more numeric forms without admitting them as core expressions.
There is no implicit conversion from quoted Scheme data to a core value.

## 2. Macro-free surface grammar

In this grammar, `*`, `+`, `?`, and `|` are metanotation. Parentheses are literal
list delimiters. `Name` and `Field` are identifiers, and `Literal` is an admitted
core literal. `Type-Expr` is the same grammatical category as `Expr`, checked to
denote a type. The two alternatives for `Groups` encode the optional implicit
group; delimiter shape is irrelevant.

```text
Program       ::= Definition*
Definition    ::= (def Name Expr)

Expr          ::= Name
                | Literal
                | (Π Groups → Type-Expr)
                | (λ #:captures (Name*) Groups → Type-Expr = Expr)
                | (Expr Expr*)
                | (ann Expr Type-Expr)
                | (let (Binding*) Expr)
                | (if Expr Expr Expr)
                | (struct Telescope Grade-Option)
                | (union Type-Expr*)
                | (new Type-Expr (Field-Value*))
                | (match Expr Clause+)

Groups        ::= Telescope
                | Telescope Telescope
Telescope     ::= (Binder*)
Binder        ::= (Name Type-Expr)
Binding       ::= (Name Expr)
Grade-Option  ::= empty | #:grade Grade
Grade         ::= 1 | omega
Field-Value   ::= (Field Expr)
Clause        ::= (Pattern Expr)

Pattern       ::= _
                | Name
                | Literal
                | (is Type-Expr Name-Or-Wildcard)
                | (new Type-Expr (Field-Binding*))
Field-Binding ::= (Field Name-Or-Wildcard)
Name-Or-Wildcard ::= Name | _
Type-Expr     ::= Expr
```

The spelling `empty` means absence, not a source token. `_` is the distinguished
discard pattern, rather than a variable binder. Duplicate names within a binder
group, simultaneous `let`, or match pattern are errors; telescope binders are
also distinct across the implicit and explicit groups. Field labels are unique
within a struct.

Grades describe affine or unrestricted ownership. Phase availability and
erasure use separate rules for the same types.

Special forms take precedence over the application production when the head
resolves to their built-in syntax binding. Their names are not first-class
runtime functions. Ordinary lexical bindings may shadow syntax bindings; the
resolver, rather than a parser keyed only by spelling, selects the form.
The structural markers `→`, `=`, `#:captures`, and `#:grade` are recognized in their designated
positions. Empty `()` is not an expression; `(f)` is a zero-argument call.

There are no separate declaration forms for types or functions. There is no
general `quote`, `begin`, `letrec`, local `def`, rest parameter, `set!`, or
user-defined recursive datatype form in this initial grammar. Use nested `let`
for sequencing. Ordinary applications cover arithmetic, array operations,
`singleton`, and the immutable data primitives described below. An expression
can be checked or run through the interpreter API; a source file contains
definitions, with an entry function selected by the driver.

`union` has an intrinsic n-ary typing rule and a checked union node. A fixed-arity
`Π` cannot describe that arity, so it is not initially a first-class callable.
It remains an expression producing a type value. `(union)` denotes `nothing`.
`singleton` can be a unary intrinsic, initially restricted to supported pure
scalar values. Neither adds a top-level introduction form.

## 3. Rules needed alongside the grammar

### Binding and execution order

`Π`, `λ`, and `struct` use left-to-right telescope scope. A binder enters scope
after its annotation; all function parameters are in scope in the result type
and body. A single function group is explicit; with two, the first is implicit.
Implicit parameters are solved only from explicit arguments, not expected call
results. Duplicate binders and forward references are rejected.

Every `λ` has a mandatory `#:captures (Name*)` clause before its parameter groups;
the empty clause explicitly captures nothing. Capture names resolve to distinct
enclosing bindings before parameter scope begins, and cannot collide with a
parameter name. `Π` has no capture clause. Listed captures are in scope throughout
the lambda's annotations and body. The capture list must cover free outer values
in those positions, nested capture clauses, and dependencies in captured types.

Closure construction moves listed affine values immediately and may copy listed
unrestricted values. Primitive bindings and verified closed static top-level
definitions need no capture field; other outer values, including runtime globals,
must be listed. The closure grade follows its captured runtime fields. Type-only
dependencies follow the separate phase rules. These are the [capture rules](core-ir.md#explicit-consuming-captures)
for both source lambdas and lambdas produced by later macros.

`let` has simultaneous binding scope: all initializers see the outer environment,
and the body sees every new binder. Evaluate initializers left to right. For a
sequential dependency, nest another `let`; do not silently give `let` the scope
of Scheme's `let*`. Local bindings infer a monotype initially; polymorphism is
expressed by a `λ` over type parameters.

A `let` returns its body's value, and the body retains tail position. An unused
affine binding is cleaned up at scope exit, not implicitly before the body.
The [nested-let example](core-ir.md#local-bindings-and-sequencing) shows sequential
dependencies while keeping every body a single expression.

Evaluate a runtime call's operator and explicit arguments left to right. Static
arguments are elaborated and erased where appropriate, without evaluating
runtime effects during checking. Calls have exactly the explicit arity declared
by their signatures. `if` requires a `boolean` test and evaluates only its chosen
branch. Ownership uses accumulate sequentially and are checked per branch.

For `new`, require every field exactly once, in declaration order. Check and
evaluate fields in that order, substituting earlier values into later types.
This avoids giving field-label reordering an implicit effect on evaluation.
The type expression itself must meet the existing type-formation restrictions.

### Elimination and dependent scope

`match` evaluates its scrutinee once. Initially patterns are shallow: nested
destructuring is another `match`. A name binds the entire selected value; `_`
discards it with any required cleanup. `new` patterns open a known nominal
struct's fields in declaration order and must list all fields, using `_` for
unused ones. Pattern binders are in scope only in their branch body.

```scheme
(def package-length
  (λ #:captures () ((value sized-array))
    → i64
    = (match value
        ((new sized-array ((length n) (items _))) n))))
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

Process definitions in source order and reject duplicate definitions in one
scope. Earlier definitions are available to later ones. For a definition whose
elaborated RHS is a `λ`, first check its header, then make its own binding
available in its body. The header cannot depend on the function being defined.
This supports directly recursive helpers without a `fix` or `letrec` form.
Mutual recursion and arbitrary recursive value/type definitions are deferred.
Runtime top-level values require explicit captures; putting a function at top
level does not exempt it from that rule. The function's own recursive reference
is available only in its body and is not a capture.
Recursive calls must respect the same ownership accounting and cannot recapture
an affine environment on each call. Initially require recursive functions to
have unrestricted runtime environments; owned arguments can still be threaded
through recursive calls.

Normalizing types may reduce trusted pure operations and admitted nonrecursive
pure definitions. Initially, recursive helpers can execute as programs or
compile-time transformer code, but are not admitted into type normalization.
Being immutable does not imply termination. Arbitrary higher-order calls need
an established normalization contract before conversion can execute them.

The checked representation retains `let` and ownership-aware `match`; it need
not encode everything as lambda application. Elaboration makes inferred
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

The rule interpreter can use named, directly recursive functions and immutable
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
       (if test yes no)))))

(def answer
  (choose #t 41 42))
```

`macro` is an expansion-only marker in a definition's RHS. For the first macro
extension, restrict its operand to a `syntax-rules` specification:

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
expression or top-level position, expand such uses before applying the core
`Expr` or `Definition` productions. The same list shape may otherwise denote
an ordinary application; a dotted ordinary application is rejected.

The second `Rules-Spec` form supplies a custom ellipsis identifier. Rule bodies
are opaque reader syntax, not ordinary application arguments. This extension is recognized
before falling back to the macro-free `Definition` grammar, using the resolved
built-in bindings of `macro` and `syntax-rules`, not their spellings alone.
It does not add a runtime `macro` operation or classify ordinary runtime results
as macros.

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
           (repetition-sites (list-of i64)))))

(def repetition-plan
  (struct ((site i64)
           (pattern-path (list-of i64))
           (parent-sites (list-of i64)))))

(def rule-plan
  (struct ((pattern syntax)
           (template syntax)
           (variables (list-of variable-plan))
           (repetitions (list-of repetition-plan)))))

(def rules-transformer
  (struct ((definition-view binding-view)
           (ellipsis syntax)
           (literals (list-of syntax))
           (rules (list-of rule-plan)))))

(def capture-entry
  (struct ((slot i64)
           (indices (list-of i64))
           (form syntax))))

(def repetition-extent
  (struct ((site i64)
           (parent-indices (list-of i64))
           (count i64))))

(def captures
  (struct ((entries (list-of capture-entry))
           (extents (list-of repetition-extent)))))

(def selected-rule
  (struct ((rule rule-plan)
           (captures captures))))
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
  (Π ((definition-view binding-view) (spec syntax))
    → (result rules-transformer diagnostic)))

(def match-rule-type
  (Π ((definition-view binding-view)
      (use-view binding-view)
      (rule rule-plan)
      (form syntax))
    → (option captures)))

(def instantiate-template-type
  (Π ((introduction introduction-context)
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

Use a directly recursive driver with an explicit work list if a straightforward
tree walk would otherwise need mutually recursive functions. Its task records,
capture tables, and work list are all ordinary immutable data. The initial
grammar is therefore sufficient without adding local recursion or mutable cells.

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

For a macro definition, reserve its binding identity before capturing the
definition environment. Invoke the already-checked rule compiler at expansion
phase and install the resulting descriptor on success. A template can then
refer to its own macro. Attempting to invoke it while its descriptor is still
being constructed is an error. Initially definitions remain source-ordered;
mutually recursive macro groups and local macro-binding constructs are later
front-end features.

The immutable definition view retains binding identities, including the reserved
self identity. Descriptor availability lives separately in the driver's current
phase registry, which associates an installed descriptor with that identity.
The captured view must not freeze the self descriptor in its unfinished state.
The driver can thread successive immutable registries through its affine context.

Do not use the type normalizer as the transformer evaluator. Checked recursive
helpers may run during expansion even though conversion does not reduce them.
Only phase-available dependencies may execute: no reading program runtime locals,
sharing runtime continuations across phases, or running runtime initializers
speculatively. Expansion limits yield diagnostics, never proofs of type equality.

For a candidate expression:

1. If its head resolves to a macro, give the descriptor and the **entire original
   syntax form** to the runner. Do not evaluate, typecheck, or recursively expand
   the operands first. An operand may be a binder, a pattern, or arbitrary data.
2. Expand the returned syntax again in the same lexical and syntactic context.
   It can begin with another macro or contain macros in expression positions.
3. If the head resolves to a core form, interpret only that form's designated
   expression positions, introducing scopes before processing their bodies.
   Field labels, binders, and macro specifications are not ordinary operands.
4. Otherwise elaborate an ordinary application, including a computed operator,
   or an atomic expression. Check the resulting core types and ownership.

For `choose`, the second definition above expands to `(def answer (if #t 41 42))`.
An unused macro operand may disappear without ever being checked as an expression.
By contrast, both branches of the resulting core `if` must typecheck even though
only one executes. A transformer cannot manufacture a checked node or bypass
the affine-use checker by duplicating input syntax.

Initially allow macro uses in expression positions and at top level. A top-level
use must produce exactly one definition, ordinary or macro; an expression use
must produce exactly one expression. Supporting a definition splice, a sequence
of forms, or Scheme internal definitions needs an explicit contextual protocol.
It is not implicit in the `syntax-rules` pattern language. The eventual Scheme
front end also needs `define-syntax`, `let-syntax`, `letrec-syntax`, and
`syntax-error`; these are separate bindings/adapters, not additions to the
macro-free evaluator.

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
only parenthesis fenders; matching square/curly fenders, `→`, `#:captures`, and `#:grade` need
lexical work. Vectors and binding scopes also remain unimplemented. This proposal
does not claim that the examples already run.

Implement and exercise the layers in this order:

1. Reader/token additions, then the macro-free grammar and binding rules.
2. Elaboration, checking, and immutable interpretation, including lists and
   consuming matches. Exercise self-recursion independently of normalization.
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
| `choose` above | Expands to core `if`, then checks as `i64` |
| A macro shadows an outer value; a local value shadows that macro | Dispatch follows the binding in scope |
| A macro discards a syntactically non-core operand | Discarded operand is not parsed as `Expr` |
| A macro repeats an affine argument in its output | The core checker rejects the duplicate ownership use |
| A generated lambda omits an outer value from `#:captures` | Capture checking rejects the expansion |
| Template introduces `temp` beside a use-site `temp` | No accidental capture |
| Template uses `if` beneath a use-site binding named `if` | Definition-site syntax binding is preserved |
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
