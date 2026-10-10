# Snail-Scheme HIR

HIR is fully expanded Scheme with resolved lexical references and source
locations. `expand.sld` consumes the reader's syntax objects and constructs the
immutable expression records in `hir.sld`, organized in the independent library
containers from `library.sld`. The elaboration pass in `lower.sld` transforms each
library body into structured MIR. Expansion does not choose machine
representations, infer types, or build closure environments.

The implementation currently covers a Scheme core, library declarations, and
`syntax-rules` transformers. Derived syntax can be supplied by libraries. This is
not yet a complete R7RS implementation or an evaluator.

## Expansion model

Expansion resolves names and replaces macro uses until only Scheme core forms
remain. It follows each form's meaning: lambda parameters introduce bindings,
quoted data stays data, and ordinary calls contain expressions to expand.

The work has three main stages:

1. Resolve imports, giving every imported name its original definition identity.
2. Discover a body's definitions and install its macros in source order. Delay
   expression construction until the body's value identities are known, so
   functions can refer to themselves and each other.
3. Expand those expressions under their lexical environments. Replace a macro
   invocation, continue expanding its replacement, and construct HIR for the
   remaining core forms.

A macro transformer has a smaller lifecycle of its own: parse its rules once,
match an invocation against the rules in order, and instantiate the selected
template with the captured syntax. Parsing determines what each template element
means; instantiation substitutes syntax and preserves identifier context and
locations. The sections below describe the binding and repetition rules that
these stages must preserve.

The following pseudocode separates discovery from construction. A saved recipe
retains the macro bindings visible at its source position; construction supplies
the completed value bindings and transformer registry. Bodies introduced by
macros participate in the same discovery process.

```text
expand_body(forms):
    bindings, definitions = parse_and_reserve_direct_definitions(forms)
    recipes, bindings = discover_items_in_order(forms, bindings, definitions)
    return build_recipes(recipes, completed_value_bindings(bindings))

discover_item(form):
    form = expand_macro_head(form)
    begin:          discover its items in the surrounding body
    define:         reserve or reuse its identity; save an initializer recipe
    define-syntax:  install its transformer; retain a compile-time marker
    expression:     save an expression recipe

expand_expression(form):
    form = expand_macro_head(form)
    identifier:     resolve its value definition
    datum or quote: preserve its datum and location
    lambda:         introduce parameters; expand its body into a block
    other core form or call: expand its expression positions; construct HIR

finish_block(items):
    require a final item that is an expression
    return Block(remove_compile_time_markers(items))
```

Blocks store one nonempty, ordered sequence; its last item provides the result.
Consumers walk that sequence directly rather than reconstructing it from a
prefix and a separate result field. Only expression-producing sequences need a
final result. Library bodies, including unnamed script bodies, retain their ordered items
without this requirement. `build-block` applies the rule for lambda bodies, local macro-binding
bodies, and expression-level
`begin`. It checks the final item before removing macro-definition markers, so a
trailing definition cannot silently turn an earlier expression into the result.

Reservation retains each pending definition's binding and unexpanded initializer,
keyed by the original syntax occurrence. This lets discovery reuse the parsed
definition, including normalized function shorthand. A macro-produced definition
uses the same parser when discovered. Macro visibility is attached at discovery;
the reservation itself contains no environment.

## Grammar

`*`, `+`, `?`, and `|` below are grammar notation. `Name` is an identifier; `Datum`
is reader data, including symbols, lists, vectors, and bytevectors.

```text
Program        ::= Import-Decl* Item*
Library        ::= (define-library Library-Name Library-Decl*)
Library-Decl   ::= Import-Decl | (export Export-Spec*) | (begin Item*)
                 | (cond-expand Feature-Clause* (else Library-Decl*)?)
Feature-Clause ::= (Feature-Req Library-Decl*)
Feature-Req    ::= Name | (and Feature-Req*) | (or Feature-Req*) | (not Feature-Req)
Import-Decl    ::= (import Import-Set*)
Import-Set     ::= Library-Name
                 | (only Import-Set Name*)
                 | (except Import-Set Name*)
                 | (prefix Import-Set Name)
                 | (rename Import-Set (Name Name)*)
Export-Spec    ::= Name | (rename Name Name)
Library-Name   ::= (Library-Part+)
Library-Part   ::= Name | Nonnegative-Integer

Item           ::= Definition | Expr | (begin Item*)
Definition     ::= (define Name Expr)
                 | (define (Name . Formals) Body)
                 | (define-syntax Name Rules-Spec)
Body           ::= Item* Expr
Formals        ::= (Name*) | (Name+ . Name) | Name

Expr           ::= Name
                 | Self-Evaluating
                 | (quote Datum)
                 | (lambda Formals Body)
                 | (if Expr Expr)
                 | (if Expr Expr Expr)
                 | (set! Name Expr)
                 | (begin Expr+)
                 | (Expr Expr*)
                 | (let-syntax (Syntax-Binding*) Body)
                 | (letrec-syntax (Syntax-Binding*) Body)

Syntax-Binding ::= (Name Rules-Spec)
Rules-Spec     ::= (syntax-rules (Name*) Rule*)
                 | (syntax-rules Name (Name*) Rule*)
Rule           ::= (Macro-Pattern Template)
```

Library-level `cond-expand` selects the first matching clause and recursively
splices its declarations before imports, exports, or bodies are expanded. Only
`snail-scheme` is an available feature; host features such as `chibi` and
`snail-tests` are deliberately absent. Empty `and` is true and empty `or` is false.
An optional `else` clause must be last; no match contributes no declarations.
Inactive clauses are read but never expanded or loaded. Library-availability
requirements and expression-level `cond-expand` are not implemented.

Self-evaluating input includes booleans, numbers, characters, strings, vectors,
and bytevectors. Quotation preserves a datum rather than resolving its symbols
or expanding its lists. Reader abbreviations such as `'x` are already represented
as lists headed by `quote`. Empty `()` is data, not an expression; `(f)` is a
zero-argument call.

Expression syntax is selected by the head's binding, so an ordinary parameter
can shadow `if`, `lambda`, or another keyword. The outer `define-library`,
`import`, `export`, and library-body `begin` grammar is recognized before
expression dispatch. It is the bootstrap boundary for loading a language.

For now, expansion supplies a small `(scheme base)` interface containing the
syntax above and primitive value identities for arithmetic, lists, predicates,
vectors, `values`, `call-with-values`, and `apply`. It supplies no runtime
implementations. The remaining standard bindings and derived forms require
library implementations. A program must explicitly import the bindings it uses.

A macro receives the whole input form before its operands are treated as
expressions. It can therefore consume binders, quoted data, vectors, or improper
lists, and can discard input that would be invalid as an expression. Only an
ordinary application requires a proper list of operator and operand expressions.

## HIR records

Executable records are defined in [`hir.sld`](../src/snail-scheme/hir.sld). Every
located node carries its own `loc`; compiler-provided definitions use `#f`. A
definition and a reference to it have separate locations. Locations and spellings
do not establish lexical identity.

| Record | Contents |
| --- | --- |
| `value-definition` | One binding identity, its source name, and definition location |
| `value-binding` | A value definition, its initializer, and the definition form's location |
| `name` | A reference to a value definition and the reference location |
| `literal` | A quoted or self-evaluating datum and location |
| `application` | Operator, operands, location |
| `lambda` | Required parameters, optional rest parameter, body block, location |
| `conditional` | Test, consequent, optional alternate, location |
| `assignment` | Target name, value expression, location |
| `block` | Nonempty ordered items ending in a result expression, location |

Compilation containers belong to [`library.sld`](../src/snail-scheme/library.sld),
which imports neither HIR nor MIR. Its body payload belongs to the current pass;
its interface bindings retain opaque identities, including macro identities.

| Record | Contents |
| --- | --- |
| `library` | Name or `#f`, resolved imports, exported bindings, dependency names, body, location |
| `import-declaration` | Resolved libraries, local bindings, original located import syntax, location |
| `named-binding` | Visible name and original definition identity |

A script is an unnamed library (`name = #f`), selected as the executable's root.
There is no separate program record. Expansion supplies an ordered HIR item list
as the body; lowering replaces it with a MIR body while retaining the library's
organization. `library-dependency-order` visits each resolved library once by
identity, placing dependencies before their importer and the root last.

A `lambda` contains one `value-definition` per parameter. Its optional rest
parameter is `#f` when absent. A `conditional` with no alternate likewise stores
`#f` in that field; a literal false alternate is a `literal` record, so the two
cases remain distinct. If the absent branch is taken, the result is unspecified.

`value-definition` is an immutable identity, not an initializer container. A
`value-binding` associates that identity with its initializer. Reserving identities
before constructing bodies lets recursive functions reference each other without
mutating a definition or creating producer back-links. Later passes can build
identity-indexed tables by walking the binding nodes.

For example, the initializer and final reference in this body share one object:

```scheme
(import (scheme base) (snail-scheme hir))

(define definition (make-value-definition 'identity #f))
(define parameter (make-value-definition 'x #f))
(define initializer
  (make-lambda (list parameter) #f
    (make-block (list (make-name parameter #f)) #f) #f))
(define body
  (make-block
    (list (make-value-binding definition initializer #f)
          (make-name definition #f))
    #f))
```

The executable core has eight forms: names, literals, applications, lambdas,
blocks, conditionals, assignments, and value bindings. Initialization remains
distinct from assignment: a definition introduces a binding and its initializer,
whereas `set!` makes an existing location mutable. Encoding both with an extra
mode flag would move that distinction into every analysis. Blocks likewise
express sequencing without introducing a procedure call or forcing intermediate results to be
single values. Library containers and resolved interfaces belong to their own
module; they are not additional executable forms.

Scope environments are transient association lists passed through recursive
descent. They are never fields of HIR records. Imported names and re-exports
refer directly to the original definitions; renaming an import creates a new
visible name, not a new identity. Each import declaration retains the resolved libraries directly, making their
bodies reachable by later passes even if an import exposes no value bindings.
`only`, `except`, `prefix`, and `rename` are resolved during expansion and have
no HIR node variants. The original located declaration remains available for
diagnostics; lowering does not reinterpret its syntax.

Macro definitions are immutable identities private to the expander. A separate
transient alist maps those identities to compiled transformers. Import and export
interfaces may reference either macro or value definitions, but every `name`
in an expanded expression refers to a `value-definition`. Runtime expressions
contain no macro invocations or transformer specifications.

## Functions, definitions, and sequencing

Lambdas use ordinary Scheme formals and bodies:

```scheme
(import (scheme base))

(define identity (lambda (x) x))
(define (make-adder offset)
  (lambda (x) (+ offset x)))
(define (collect first . rest)
  (cons first rest))
(define all-arguments (lambda args args))
```

All parameters are explicit. Free references in a lambda retain their enclosing
binding identities; a later closure analysis determines what needs to be stored.
The function-definition abbreviation expands using the builtin lambda binding,
even if a local variable is spelled `lambda`.

Parameter names are distinct within one formal list, and internal definition
names are distinct within the body. Internal definitions may shadow parameters;
nested scopes may shadow outer names. Value identities are collected before expanding delayed
bodies, supporting self and mutual references:

```scheme
(define (even n)
  (if (= n 0) #t (odd (- n 1))))
(define (odd n)
  (if (= n 0) #f (even (- n 1))))
```

Binding visibility is separate from initialization. HIR retains source order;
expansion neither executes initializers nor proves that a forward read is safe.
A later pass or runtime must enforce initialization semantics. An initializer is
represented once, without duplication or reordering.

In item position, `begin` splices its items into the surrounding body, including
when a macro produces it. In expression position, `begin` sequences expressions
and cannot introduce definitions. Lambda bodies and local syntax-binding bodies
become blocks. A block retains its internal definitions and nonfinal expressions,
then a mandatory final expression in tail position. Nonfinal expression results
are discarded. Library-level `begin` declarations share one library environment;
their expanded items are concatenated in source order into the library body.

`if` tests Scheme truthiness: only `#f` is false. `set!` retains the target's
resolved identity. Constructing an assignment record does not mutate the expander's
environment or any HIR node. Applications retain operator and operand order;
Scheme evaluation and any permitted choice of argument evaluation order belong
to execution/lowering, not expansion.

## Expansion API and libraries

[`expand.sld`](../src/snail-scheme/expand.sld) exports:

```scheme
(syntax-list->hir-library syntax-forms library-loader)     ; => unnamed library
(syntax->hir-library define-library-syntax library-loader) ; => named library
(macroexpand-1 syntax environment transformers)            ; => syntax
```

The loader receives a library-name datum, such as `(helpers)`, and returns a
located `define-library` syntax object or `#f`. Expanded libraries are cached
within one expansion call. The implementation passes the loader, cache,
transformer alist, and current import path as ordinary parameters and returns
updated alists; there is no loader wrapper or mutable global expansion state.
Each library header is parsed once. A loaded library's name must match the
requested name before its declarations are expanded. The active import path
detects cycles, and only completed libraries enter the cache.

`macroexpand-1` is a low-level hook using the expander's transient environment
and transformer alists. It performs one head transformation and otherwise returns
the input unchanged. Its result can contain private identifier metadata and must
remain syntax until contextual expansion resolves binding positions and references.

Imports support `only`, `except`, `prefix`, and `rename`. Repeated imports of the
same identity are allowed. Conflicting imports, duplicate local definitions,
missing requested names, unresolved exports, missing libraries, and import cycles
are errors. Local definitions cannot replace imports in the same scope; nested
scopes can shadow them.

All library imports are resolved before expanding the library's bodies, regardless
of declaration placement. Bodies are then processed in source order in a shared
environment, and exports are resolved against the completed environment. Private
helpers referenced by an exported macro keep their original binding identities;
callers need not import those private names. Transitive dependency names and
resolved import records retain the corresponding library relationships.
Body expansion keeps one chunk per declaration while resolving macros and
bindings. Construction concatenates the runtime items in source order; source
`begin` and export declaration wrappers have completed their work and do not
survive as records. Imports retain their located syntax for diagnostics, and
exports retain only external names and resolved identities.

## Macro expansion

`define-syntax` binds a name to a `syntax-rules` specification and disappears
from runtime HIR. `let-syntax` compiles each specification in the outer environment;
`letrec-syntax` reserves all local macro identities first, so every specification
can refer to the group. Both expand their bodies under the new bindings. Compiled
transformers live in the separate alist, so recursive macro identities never need
mutable transformer fields.

A parsed transformer is an ordered list of rules. Each macro expansion step
resolves the head to that list once, then tries the rules in source order.

Named macro definitions are processed in source order. Reserving a scope's value
identities does not make later macros visible earlier. Item expansion discovers
definitions, installs transformers, and prepares builders. Those builders retain
the macro environment at their source position; the second pass gives them the
completed value environment and transformer registry.

Full expansion repeatedly transforms a macro head, then descends into expression
positions of the resulting builtin or ordinary application. This continues until
no macro uses remain in those positions, rather than comparing whole forms for
structural equality. The current guard permits 1,000 macro steps per recursive
expansion path, including descent into generated lambdas or other builtin forms.
Sibling expressions receive their parent's remaining budget.

The implementation never evaluates arbitrary transformer expressions or runtime
initializers. It supports declarative `syntax-rules`; procedural transformers,
`syntax-error`, and additional standard library declarations remain future work.

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

### Template construction

Rule construction parses a template into records for variable substitutions,
introduced identifiers, constants, lists, vectors, and repeated elements. It
checks variable depths and interprets ellipsis escapes at this point. Each
repeated element retains the names of its driving pattern variables.

The template parser carries one optional active ellipsis symbol. Declaring that
symbol literal, or entering an escaped subtree, disables ellipsis interpretation
by passing `#f`; variable substitution still follows the recorded capture depths.

Instantiation walks these records with the matched captures. It assigns fresh
keys to introduced identifiers, substitutes captured syntax, and rebuilds lists
and vectors. A repetition checks that its drivers have equal lengths at the
current nesting position, then builds one item per capture group. Nested
repetitions extend that position; depth-zero substitutions always use their
original capture. The template grammar does not need to be interpreted again
for each invocation.

```text
apply_transformer(rules, input):
    arguments = located_argument_tail(input)
    for each rule in source order:
        captures = match(rule.pattern, arguments)
        if captures matched:
            keys = fresh_keys_for_introduced_identifiers(rule.template)
            return instantiate(rule.template, captures, keys, root_position)
    fail: no rule matched

instantiate(template, captures, keys, position):
    variable:    select captured syntax at its repetition position
    identifier:  use its invocation key and definition-site binding
    constant:    retain its value and template location
    list/vector: instantiate children, including any improper list tail
    repetition:  require equal driver lengths; instantiate at each child position
```

All occurrences of an introduced identifier share its invocation key. A
depth-zero variable selects its root capture even within a repetition. These
rules keep substitutions and introductions distinct while the recursive walk
follows the parsed template structure.

### Literal binding identity

A `syntax-rules` literal imposes an identifier-matching condition; it does not
capture input or evaluate the identifier's value. Match the binding visible at
the macro definition with the binding visible at its invocation. Equal binding
identities match, including renamed imports of the same binding. Different
bindings do not match, even when their spellings and runtime values agree.
If both identifiers are unbound, match equal symbol names; if only one is bound,
they do not match. This is the rule in
[R7RS §4.3.2](https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-6.html#TAG:__tex2page_sec_4.3.2).

This R7RS example was verified in Chibi Scheme 0.12.0:

```scheme
(define-syntax recognize
  (syntax-rules (marker)
    ((_ marker) 'literal)
    ((_ anything) 'other)))

(recognize marker)                 ; => literal
(let ((marker 42))
  (recognize marker))              ; => other
```

The definition-site `marker` is unbound. The first invocation also supplies an
unbound `marker`; the second supplies the identifier bound by `let`, so it selects
the fallback rule. Binding lookup establishes identity without evaluating `42`.
If the macro were defined inside that `let`, its literal would refer to the same
binding and would match. An inner `let` would introduce another identity.

Libraries normally bind and export auxiliary keywords alongside their macros.
Clients import the keywords and macro together, preserving shared identities
through import renaming. Shadowing still introduces a distinct identity, and
exporting a macro does not require exporting its private implementation helpers.
See [SRFI 206: Auxiliary Syntax Keywords](https://srfi.schemers.org/srfi-206/srfi-206.html).

### Matching located syntax without changing the datum matcher

Transformer selection uses the invocation's head binding. Rule parsing requires
an identifier head and then discards it; matching compares only the pattern tail
with the invocation's located argument tail. The ignored identifier needs no
capture or cleanup step. In particular, `(h ...)` has an orphan active ellipsis
after the ignored head is removed and is rejected, unless `...` is declared literal.

`pattern.sld` remains a generic datum matcher with the `pattern-dispatch` API.
The adapter is entirely inside `expand.sld`. It projects a syntax node to a pair
of its datum view and the original syntax object. Adapted patterns inspect the
view for lists, vectors, and constants, while variable patterns capture the
original object. Cdr provenance restores dotted-tail captures as located syntax.

Literal identifiers become private capture constraints in the adapter. Those
constraints compare definition identities with `eqv?`, or compare symbols when
both identifiers are unbound. This also handles repeated literal occurrences.
The raw pattern tail is parsed before adaptation, preserving the datum
matcher's grammar checks and duplicate-variable diagnostics.

The matcher still constructs structured matches and flattens them to capture
alists. The adapter restores syntax objects at each variable's repetition depth.
Empty and ragged repetitions remain nested lists; all captures retain their
identifier metadata. Constants and structural markers never become runtime
identifier lookups.

### Hygiene and source locations

The expander's private identifier records contain a spelling, an identity key,
and an optional definition binding. Source identifiers initially use their symbol
as a key. Instantiation first builds one immutable mapping from original template
keys to fresh keys, then reuses it throughout the selected template, including all
repetitions. Each invocation gets a new mapping. Substituted syntax keeps its
existing keys. Lookup checks the current environment before the definition-site
fallback, so introduced binders can bind their corresponding template references.

Template fallbacks are fixed when the transformer is installed, after direct value
definitions have been reserved. A definition exposed later by macro expansion does
not retroactively change an installed transformer's fallbacks.

Macro matching and substitution do not erase locations. Captured syntax retains
its source; introduced template syntax retains the template's location. Synthesized
list tails carry a containing form's location. A future diagnostic trace can add
invocation history without changing binding identity.

This implementation is an initial declarative hygiene mechanism. Broader conformance
work should exercise interacting macro-generated binders and nested transformer
specifications before claiming full R7RS hygiene support. Fresh spellings alone
are never the identity test.

The planned diagnostic policy for free literals and missing auxiliary-keyword
imports remains separate from matching semantics: consider errors by default for
unbound literals or for importing a macro without its bound auxiliary keywords,
with a compatibility option that allows standard fallthrough. These diagnostics
are not implemented yet.

## Later passes

[`lower.sld`](../src/snail-scheme/lower.sld) consumes this untyped HIR, analyzes
captures and mutation, assigns storage, and elaborates it to structured
[MIR](mir.md). Binding identities survive import renaming and source shadowing;
representation choices belong beyond this boundary. Type inference and
information-driven check elimination remain future work.

The executable backend preserves proper tail calls, assignment, quoted data,
recursive initialization, multiple values, and snapshot continuations. `values`
and `call-with-values` remain ordinary calls in HIR. The command-line compiler
runs this pipeline under Chibi and asks Cargo to link LLVM with the Rust runtime
for native or WASI execution. See [backend.md](backend.md) for the implemented
boundary and remaining limitations.
