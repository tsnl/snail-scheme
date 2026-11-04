# Proposed source syntax

**Draft for approval; none of the new notation in this chapter is implemented.**
The recommendation is a Python-like surface over Snail-Core, with a small
structural reader inspired by shrubbery. Each source file selects its reader.
The surface keeps Snail's types, effects, ownership, and library model.
Implementation waits for approval of this draft.

## The proposed everyday language

```text
#lang snail
from snail.core.base import *
from snail.core.io import write_line

def fibonacci(n: I64) -> I64:
    if n < 2:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

def main() -> Unit ! console:
    answer = fibonacci(30)
    write_line(show(answer))

main()
```

The intended feel is ordinary: `f(x, y)`, `value.field`, `Type[T]`, `#`
comments, four-space indentation, and familiar operator precedence.
`def`, `return`, `if`, `elif`, `else`, `match`, and `case` spell common
operations. Parentheses group expressions and delimit arguments. They do
not introduce prefix calls in this reader.

Python's spelling is useful without adopting its object model or dynamic
semantics. Conditions remain `Bool`; records remain immutable values;
bindings have lexical scope; calls have fixed arity; effects and ownership
remain checked. Optional values use `Some(x)` and `None()`, the ordinary
constructors of `Option[T]`. Python's implicit `self`, truthiness, and
dynamically extensible object dictionaries are outside this surface.

The first implementation should make this complete example and the examples
using current semantics work through existing compiler passes. It should not convert the
compiler's own sources as its first step.

## Definitions, results, and scope

```text
limit: I64 = 100

def square(n: I64) -> I64:
    return n * n

def absolute(n: I64) -> I64:
    if n < 0:
        return -n
    else:
        return n

def report(n: I64) -> Unit ! console:
    message = show(square(n))
    write_line(message)
```

`name = expression` defines an immutable binding. `name: Type = expression`
also supplies its signature. A second definition of the same name in the
same scope is an error; an inner scope may shadow it. Assignment never
silently decides between defining a name and mutating storage. This is the
largest deliberate difference from Python.

Every indented suite introduces lexical scope. Top-level definitions may
refer to later top-level definitions, as today. Local definitions become
visible in sequence; a local function can refer to itself. A name defined
inside an `if` branch does not become available after the `if`.

`return expression` returns from the enclosing function. A value-returning
function must return on every terminating path. Falling through returns
`Unit`, and `return` alone does the same. A discarded expression is subject
to the existing ownership and cleanup checks. A final expression is not an
implicit return. Early return lowers to structured branches before checking;
it is not a continuation operation or an exception. For example:

```text
def f(n: I64) -> I64 ! console:
    if n < 0:
        return 0
    write_line("nonnegative")
    return n + 1
```

has the control structure
`(if (< n 0) 0 (begin (write-line "nonnegative") (+ n 1)))`.
Unreachable statements after an unconditional return are rejected.

Use `lambda x: x * x` for a short expression callback and a local `def`
for a callback needing statements:

```text
def odd_squares(numbers: List[I64]) -> List[I64]:
    return map(lambda n: n * n, filter(lambda n: remainder(n, 2) == 1, numbers))
```

This draft keeps `def` and `lambda` as the surface spelling of callables.
The existing core can represent them with `define` and `lambda`. The
separately proposed [callable contracts](types.md#proposed-callable-typeclass)
can later represent the same definitions with `fun` and `impl Fun`.
`-> I64` in a definition header states its result; it does not require
callables to have a universal runtime representation.

Generic parameters use brackets; constraints follow `where`:

```text
def twice[T](x: T) -> T where Num[Pure, T], Copy[T]:
    return x + x
```

`Pure` in a row position spells the empty effect row. `! console, fs`
spells a closed row; `! console, ..e` adds a quantified tail `e`.
Function type notation is `Fn(A, B) -> R ! ..e`, initially spelling today's
function arrow, with `FnOnce` and `FnStatic` spelling today's one-shot and
environment-free callable types. Argument-position `impl Fun(...) -> R`
belongs to the separate callable-capability proposal; the reader must be
able to represent it without declaring that proposal implemented.

## Data and ordinary expressions

```text
struct Point:
    x: I64
    y: I64

enum Shape:
    Circle(center: Point, radius: I64)
    Rectangle(corner: Point, width: I64, height: I64)

def area(shape: Shape) -> I64:
    match shape:
        case Circle(_, radius):
            return 3 * radius * radius
        case Rectangle(_, width, height):
            return width * height

origin = Point(0, 0)
shapes = [Circle(origin, 2), Rectangle(origin, 3, 4)]
areas = map(area, shapes)
```

Constructors remain positional, including zero-argument `Nil()`.
`Unit`'s value is `()`. Patterns retain existing constructor matching,
wildcards, literals, and bindings, with the current exhaustiveness checks.
`True` and `False` are boolean literals. Both `'text'` and `"text"` are
strings; neither denotes syntax quotation. Character literals use `c'x'`.

`[a, b, c]` constructs a `List`. Other collections use their existing
library constructors, with explicit aliases where names need changing;
the reader does not give them Python's variadic constructor protocol.
There is no tuple or dictionary literal in the first surface. A single
parenthesized expression is grouping; an empty one is `Unit`; a standalone
comma-separated parenthesized sequence is an error. Braces are reserved.

`a.b.c` is a chain of field projections. A label is not a variable lookup.
The type checker resolves each field, as it does the existing `::field`
operations. A computed field does not become writable. `f(x).b` evaluates
`f(x)` once. `object.method(x)` calls the value selected by `method`; it
does not insert `object` as an extra argument.

The initial reader may parse `a[i]` structurally, but the surface should
reject value indexing until its collection operations, bounds behavior,
and place behavior have an explicit contract. Type application `List[I64]`
is unambiguous in a type context. Use existing named collection operations
for executable indexing in the first implementation.

Operators have a fixed precedence table, from tightest to loosest:

| Level | Operators | Rule |
| --- | --- | --- |
| Postfix | `f(...)`, `.field` | Left to right. |
| Unary arithmetic | `+`, `-` | Prefix. |
| Multiplication | `*`, `/` | Left associative; existing numeric operations. |
| Addition | `+`, `-` | Left associative. |
| Comparison | `==`, `!=`, `<`, `<=`, `>`, `>=` | One comparison; chains initially rejected. |
| Boolean negation | `not` | Prefix; lower precedence than comparison. |
| Boolean conjunction | `and` | Short-circuiting, `Bool` operands. |
| Boolean disjunction | `or` | Short-circuiting, `Bool` operands. |

Thus `a + b * c` means `a + (b * c)` and `not a == b` means
`not (a == b)`. `==` lowers to Snail's equality operation and `!=` to its
negation, with each operand evaluated once. `/` keeps Snail's existing
numeric semantics; Python's automatic conversion to floating point is not
implied. Keep named `quotient` and `remainder` until division conventions
are separately chosen. No custom operator declarations, comparison-chain
rewrite, exponentiation, implicit application, or implicit concatenation
are included in the first grammar.

Ordinary call operands evaluate once, left to right. Short-circuit forms
evaluate only the required branch. These are surface contracts to verify
against lowering, including calls through macros, not assumptions inferred
from how the example looks.

## State, with mutation visible

The initial surface can express the counter using today's concrete `Ref`:

```text
struct Counter:
    count: I64

def bump!(counter: Ref[Counter]) -> Unit ! mut:
    set ref_get(counter).count = ref_get(counter).count + 1

clicks = ref(Counter(0))
bump!(clicks)
bump!(clicks)
display(ref_get(clicks).count)
newline()
```

The definition corresponds to today's code:

```scheme
(: bump! (-> (Ref Counter) Unit ! mut))
(define (bump! counter)
  (set! (::count (ref-get counter)) (+ (::count (ref-get counter)) 1)))
```

`set target = expression` is explicit mutation. Its left side must denote
writable storage; assigning to an ordinary immutable binding or a computed
getter fails. The target's root is evaluated before the right side, once
per target occurrence; the right side is evaluated once. Repeating a read
in the source, as above, still performs that read separately. Initially
there is no `+=` or other read-modify-write shorthand.

With the separate [places proposal](types.md#proposed-places-and-locators),
the intended spelling becomes:

```text
def bump!(counter: impl Ref[Counter]) -> Unit ! mut:
    set counter.count = get(counter.count) + 1

def shift!(state: impl Ref[World], dx: I64) -> Unit ! mut:
    set state.player.position.x = get(state.player.position.x) + dx
```

These last two definitions require the proposed place capability and its
`get` operation. Dot on a place composes a place; dot on an ordinary value
reads a field. Reading a place stays explicit as `get(place)`, so a call
does not guess whether to pass a place or read its contents. This draft
selects explicit reads for review. It does not change the static path,
GC-root, or array restrictions in the places chapter.

For comparison, a nested update using current storage and field paths is:

```scheme
(: shift! (-> (Ref World) I64 Unit ! mut))
(define (shift! state dx)
  (set! (::player::position::x (ref-get state))
        (+ (::player::position::x (ref-get state)) dx)))
```

## Effects remain ordinary calls

The notation for the current handler model is:

```text
effect Ask:
    def ask() -> String

def greet() -> String ! Ask:
    return string_append("hello, ", ask())

def main() -> Unit ! console:
    with Ask(ask=lambda: "world"):
        write_line(greet())

main()
```

`with Effect(operation=implementation, ...):` installs the supplied
operations for its suite. The `name=value` syntax here names handler
operations; it does not introduce general keyword arguments. This example
has the same behavior as:

```scheme
(effect Ask ((ask (-> String))))
(: greet (-> String ! Ask))
(define (greet) (string-append "hello, " (ask)))
(write-line (handle Ask ((ask (lambda () "world"))) (greet)))
```

For a control operation, use `ctl def` in the effect declaration; its
implementation receives the existing one-shot `resume` as its final
parameter. `resume(())` is a call, with the current ownership obligations.
No `async`/`await` layer is introduced by the reader. The separately
proposed provider and callable model may change handler declarations;
this syntax draft does not settle that semantic design.

## Libraries and names

```text
#lang snail
library sample.geometry
from snail.core.base import *
export Point, square

struct Point:
    x: I64
    y: I64

def square(n: I64) -> I64:
    return n * n
```

This is a `.sld` file at `sample/geometry.sld`. `library` and `export`
are top-level declarations and the file's definitions form its body.
Programs omit `library` and `export`. `from path import name, other as alias`
spells the existing `only` and `rename` import sets; `from path import *`
imports the library's public interface. A library path's dots separate
name segments and do not denote runtime projections. Module objects and
package resolution are outside this syntax change.

Use snake_case identifiers, with an optional final `!` for mutating
operations and `?` for predicates. A suffix `!` is part of an identifier;
the `!` after a result type introduces an effect row. `!=` is always one
operator. Hyphens are subtraction, so `read-file` means `read - file`.
Backticks quote an exact existing identifier: `` `read-file`(path) ``.
They are identifier escapes, not interpolation or syntax quotation.

The examples assume explicit snake_case export aliases such as `write_line`
for `write-line` and `ref_get` for `ref-get`. These aliases are proposed
library changes. Do not globally replace underscores with hyphens during
reading: distinct identifiers must stay distinct, including in macros.
Until an alias is supplied, use a backtick name or an explicit import rename.
An alias must denote the same binding, including for macro literal matching.

## The reader boundary

Use an explicit header: `#lang snail` selects the new surface and
`#lang snail/sexp` selects the traditional reader. The earlier
`#lang snail/sweet` proposal is superseded by this recommendation; it need
not become a third supported mode. Reader selection belongs to each file
and never propagates through imports. Keep `.sld` paths independent of mode.

There are three steps before the existing typed pipeline:

```text
file header
    -> selected reader: located groups, delimiters, blocks
    -> surface parser: located Snail syntax
    -> hygienic expansion and structured-return normalization
    -> existing resolved IR, checking, specialization, and lowering
```

The traditional reader already produces located Snail syntax and bypasses
surface parsing. Generated binary syntax also bypasses the textual layers.
Neither path acquires indentation rules. Source syntax selection does not
change Scheme `read` or any program's data protocol.

The structural layer is intentionally smaller than Rhombus. Shrubbery
separates groups and blocks from later language parsing; Rhombus then
interleaves macro expansion with extensible operator parsing. We adopt
the structural separation and use a fixed expression grammar initially.
This is not a claim of shrubbery conformance or of implementing Rhombus's
macro system. See the primary descriptions of
[groups and blocks](https://docs.racket-lang.org/shrubbery/group-and-block.html)
and [Rhombus parsing](https://docs.racket-lang.org/rhombus-model/syntax-model.html).

For example, the structural reader represents:

```text
unless(ready):
    write_line("waiting")
```

schematically as:

```scheme
(group unless
  (parens (group ready))
  (block (group write_line (parens (group "waiting")))))
```

This is an internal representation, not additional user syntax. Nodes
retain the distinction between a group, an argument list, and a block.
They retain source ranges and spelling; the compiler's current `Loc`
records only a starting position, so lossless formatting requires richer
reader data. The IDE's error-recovering tree is separate from successfully
parsed compiler input. Structural tags and punctuation-generated forms
must have private identities that user identifiers cannot capture.

The surface parser handles operator precedence and declaration shape;
it does not resolve types, field layouts, imports, or ownership. Those
decisions remain with the existing passes. Public syntax construction
continues to use the established located syntax protocol rather than
printing text and reparsing it.

## Layout rules

- A newline ends a group outside delimiters. A trailing colon followed by
  a newline opens an indented suite. The first nonblank line establishes
  its column; sibling lines align, and dedents return to an enclosing column.
- Indentation uses spaces; tabs in indentation are an error. The formatter
  emits four spaces. Blank and comment-only lines do not open or close suites.
- Inside parentheses and brackets, newlines are whitespace and commas
  separate items. Trailing commas are allowed. Continue a long expression
  by surrounding it with parentheses. No backslash continuation is needed.
- A colon inside `x: T` or `lambda x: expression` stays in the group. Only
  the final significant colon at a logical line's end can open a suite.
  An inline empty-body lambda such as `lambda x:` is an error.
- `if`, `elif`, and `else` are separate groups associated by the surface
  parser at one indentation level. `case` groups belong to the `match`
  suite. No `|` alternatives or same-line statement separator is required.
- An empty suite is written `pass`, which produces `Unit`. An indented
  line without an opener is an error. The first version has no inline
  statement suites, block lambdas inside call parentheses, or multiline
  string literals; a local `def` handles a long callback.

The structural reader can preserve a colon inside a group without knowing
whether it annotates a parameter or separates a lambda body. A bare
`x: Type` outside a declaration context is then a surface parse error.
This deliberate colon rule differs from full shrubbery and accommodates
Python-style parameter annotations.

## Macros with a bounded grammar

Keep the existing hygienic `syntax-rules` engine. Initially, macros receive
fully grouped Snail forms after fixed expression parsing. A macro invocation
uses the same `name(arguments)` shape as a function. A following suite is
one additional argument represented as a body form:

```text
unless(ready):
    write_line("waiting")
    retry()
```

becomes `(unless ready (begin (write_line "waiting") (retry)))`.
A function receiving that argument evaluates the block normally; only a
macro can change evaluation through expansion. The colon does not
implicitly create a callback. Use `lambda` or a named function to pass work.

A small proposed macro-definition surface is:

```text
macro unless:
    rule ($test, $body):
        if not $test:
            $body
```

This generates the equivalent of:

```scheme
(define-syntax unless
  (syntax-rules ()
    ((_ test body) (if (not test) body (unit)))))
```

`$name` denotes a pattern variable in a rule and substitution in its
template. Repetition uses `...` over argument or body elements. Repeated
variables and nested repetitions retain the existing matcher's constraints.
Literal identifiers use an explicit `literals(...)` clause on `macro`;
the definition adapter must preserve binding-aware matching and template
definition scope. Existing S-expression macros remain definable and
importable. The new notation promises interoperability for the normalized
call/body shape, not arbitrary textual equivalence with old macro calls.

The first macro surface supports expression arguments and explicit blocks.
It does not support user-defined precedence, arbitrary unparsed infix
fragments, or grammar extensions that require new reader rules. More
specialized declarations can continue to be authored in traditional mode.
The structural tree leaves room for a later pattern system over groups,
but that is a distinct extension, not a hidden requirement of this draft.

`return` must retain the identity of its enclosing source function while
macros expand. Normalize returns after expansion and before type checking;
a macro may inline an early return in that same function. If expansion
moves it under a different callable, report a source error rather than
silently creating a nonlocal return. Handler scopes and affine cleanup
must survive this normalization. Returning from an effect-handler suite
requires dedicated tests; syntax substitution alone is insufficient.

## Implementation after approval

1. Establish source-mode selection at all source-file loading boundaries,
   with exact traditional parsing as a compatibility case. Reader
   implementations are libraries; adding a reader is a deliberate registry
   change. Arbitrary runtime-loaded reader plugins are not a prerequisite.
2. Implement the located structural reader and fixed surface parser,
   returning the syntax expansion already consumes. Add the private
   identities needed for punctuation, function boundaries, and returns.
   Keep the implementation readable as one subject per module.
3. Implement structured-return normalization, ordinary definitions, calls,
   types, operators, declarations, imports, handlers, and macro adapters.
   Add explicit standard-library aliases for the documented snake_case API.
   Give unsupported notation targeted diagnostics.
4. Use the same lexical/layout rules in the formatter, highlighter, and
   editor. Formatting must preserve parsed meaning, and diagnostics must
   point into the original source after macro expansion.
5. Convert the tour and representative applications only after equivalent
   programs execute correctly. Implement a tested stage-0 adapter before
   migrating compiler sources or making headers mandatory across the tree.

During rollout, headerless existing files remain explicitly classified as
legacy S-expression sources by the loader's migration policy. New templates
write a header. The final state requires a header on source files; the
transition must never guess from whether a file happens to start with `(`.
Embedded fragments and data streams take a reader explicitly at their API.

Chibi currently loads the compiler's source directly. The stage-0 adapter
must itself run on Chibi through the deliberate bootstrap include closure,
translate new notation to forms Chibi can consume, preserve source mapping,
and require no already-compiled Snail compiler. Even a traditional source
with a new header needs header handling at this boundary. Keep bootstrap
sources in their current mode until that path works from a clean checkout.

Acceptance requires paired traditional/new-surface programs whose normalized
syntax and execution agree, allowing intentional source-location differences.
Cover imports between modes, macro hygiene and repetition, precedence,
calls and mutation evaluation order, returns through branches and handlers,
affine captures and cleanup, layout errors, comments and strings, and
formatter round trips. Test complete examples, not only expression snippets.
Run linked Wasm on the supported hosts, `make test`, `make check`,
`make test-chibi`, and `make bootstrap`; use the browser test driver for
editor changes. Run the repository's Rust checks if Rust code changes.

The reader/parser work can ship independently of the proposed callable
and place semantics. The first implementation should diagnose their
unsupported forms rather than pretend that parsing establishes support.

## Decisions requested

The recommended approval is for `def` with explicit `return`, immutable
`name = value` bindings, explicit `set` mutation, explicit place reads,
Python-style blocks/calls/operators, and a fixed grammar preserving
`syntax-rules` macros through normalized forms. `#lang snail` and
`#lang snail/sexp` select the two source modes.

The main alternatives worth deciding now are `def` versus the earlier
`fun` spelling, explicit `return` versus a final-expression result, and
`name = value` versus `let name = value` for immutable bindings. The draft
recommends the first of each to make ordinary code look familiar to a
Python programmer. Approving the surface does not approve unrelated
changes to callable capabilities, effect providers, place representation,
or package resolution.
