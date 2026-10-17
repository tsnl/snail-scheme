# Terms and definitions

## Expressions and values

An expression describes a computation. A value is its result: `42`, `"hello"`,
`#t` and `#f` are values that can be written directly. A function is also a value.
The examples assume that standard operations such as `+` are in scope; the
[library chapter](libraries.md) explains how they become available.

To call a function, put it first inside parentheses, followed by its arguments.
`(+ 40 2)` produces `42`. Nesting expressions describes a larger calculation:
`(+ (* 6 7) 1)` produces `43`. Whitespace separates parts; parentheses determine
how they fit together. A semicolon starts a comment extending to the line's end.

The grammar below describes this notation. `…` means zero or more repetitions of
an item; square brackets make an item optional. Each quoted string is a separate
source token: `"(" "if"` means an opening parenthesis followed by the keyword
`if`. Names such as `expression` are grammar categories, not source words.

A call's first expression produces the function; the remaining expressions
produce its arguments. The three expressions after `if` are its condition,
true branch and false branch. Using the same `expression` category for each
position means each can contain an arbitrary expression.

<!-- ANCHOR: expressions -->
```text
expression ::= literal
             | name
             | call
             | conditional
             | function
             | block
             | match
             | annotation
             | instantiation

literal ::= integer_literal
          | float_literal
          | boolean_literal
          | character_literal
          | string_literal
          | bytevector_literal

call ::= "(" expression expression … ")"

conditional ::= "(" "if" expression expression expression ")"

function ::= "(" "lambda" "(" name … ")" expression ")"
           | "(" "lambda" "(" name name … "." name ")" expression ")"
           | "(" "lambda" name expression ")"

block ::= "(" "begin" statement … expression ")"

statement ::= value_definition
            | local_binding
            | expression

value_definition ::= "(" "def" name [signature] expression ")"

local_binding ::= "(" "let" name [signature] expression ")"

match ::= "(" "match" expression match_arm match_arm … ")"

match_arm ::= "(" "(" name name … ")" expression ")"

annotation ::= "(" "ann" expression type ")"

instantiation ::= "(" "inst" name type type … ")"
```
<!-- ANCHOR_END: expressions -->

`name` is an identifier. The reader recognizes literal tokens: integers such as
`42`, floating-point numbers such as `1.5`, Booleans `#t` and `#f`, characters
such as `#\a`, quoted strings and bytevectors such as `#u8(1 2 3)`. Reserved
form keywords identify syntax, so `(if …)` is a conditional rather than a call
to a function named `if`. The [type grammar](types.md) defines `signature` and
`type`. Library-level static definitions extend this grammar with
[`data`, `typeclass` and `instance`](types.md#kinds-and-static-definitions).

`if` selects a value. `(if (< 1 2) 40 0)` produces `40`. Its condition must be a
Boolean; only the selected branch runs. Both branches are required and must have
compatible types. `ann` checks an explicit type annotation, and `inst` supplies
type arguments to a generic binding; both are explained in [Types](types.md).

## Strings and bytes

`String` stores well-formed UTF-8. `string-length`, `string-ref`, `substring`
and the positions in `string-copy!` count Unicode scalar values. They do not
count bytes or grapheme clusters: `"Aé😀"` has three characters and seven bytes.
Character replacement preserves the string's character count and identity,
even when the replacement needs a different number of bytes. Random character
access may scan UTF-8; it has no constant-time guarantee.

String literals are readonly. `make-string`, `string-copy`, `substring` and
`utf8->string` produce independent mutable strings. Mutating a readonly string
traps, including an empty `string-copy!`. Copies validate complete ranges before
changing contents and preserve the original source characters when ranges overlap.

`(lofi bytes)` provides `utf8->string` and `string->utf8`. The former validates
the selected byte range and rejects malformed encodings; the latter selects a
range of characters. Both allocate independent mutable results. Empty byte ranges
are valid, and bytes outside the selected range are not validated. Neither operation
normalizes text or changes Unicode scalar values. The current representation
limits a string's encoded contents to `2^32 - 2` bytes; allocation can fail sooner.

## Functions and local names

`(lambda (x) (+ x 1))` constructs a function with one parameter, `x`. Creating it
does not run its body. Calling it with `41` binds `x` to `41`, evaluates the body,
and returns `42`. The body is one expression, which can be a block.

The first lambda form has a fixed parameter list. The dotted form binds its
last name to an immutable list of remaining arguments. A single name in place
of the parameter list binds all arguments as a list. Parameter names are distinct.

A reference uses the binding visible where that reference is written. This is
*lexical scope*. When a function uses a surrounding binding, it keeps access to
that binding even after the surrounding call has returned. The function and its
captured bindings form a *closure*. Captures are inferred from the body; a source
lambda has no explicit capture list.

```scheme
(def make-adder (-> I32 (-> I32 I32))
  (lambda (amount) (lambda (value) (+ amount value))))
(let add-two (make-adder 2))
(add-two 40) ; 42; the returned function still has amount = 2
```

Parameters are immutable bindings. Calling a function creates a new set of
parameter bindings; it does not change the bindings belonging to an earlier call.

## Definitions and blocks

`def` creates a new variable with an initial value. The binding is immutable:
reading it returns that value. This does not require the implementation to
allocate a separate memory cell for every variable.

In expression position, `begin` groups statements and returns a final expression.
At library scope, `begin` splices its contents into that same scope; it does not
create a block. This also applies when a macro produces the `begin`.
`def` introduces a binding in the whole block, which permits recursion.
`let` introduces a binding
only for subsequent statements. Either form may carry a signature:
`(def answer 42)` infers I32, while `(def answer I64 42)` explicitly selects I64
for that literal. A supplied signature is checked; omitting it requests inference.
The [type chapter](types.md) explains the separate static declaration forms.

All `def` names in a block are in scope throughout that block, including their
own initializers. A `def` initializer sees the `let` bindings preceding its
declaration, never later ones. A `let` initializer sees preceding `let` bindings
and every
`def` in the block, but not the binding it is about to create. Its new binding is
visible only afterward. A later `let` may shadow an earlier `let`; the two
bindings remain distinct. Duplicate `def` names and a `let` sharing a `def` name
in the same block are errors. Nested blocks may shadow enclosing bindings.

```scheme
(begin
  (let value 40)
  (def read-value (-> I32) (lambda () value))
  (let value (+ value 2))
  (+ (read-value) value)) ; 82: the closure captured the earlier binding
```

### References to later definitions

A forward reference is simply an ordinary name whose `def` appears later in the
same block. There is no forward-declaration syntax. The shared scope of `def`
allows these references so functions can be mutually recursive. `let` does not
make its name available to earlier statements.

A reference can occur in an earlier function body because the body runs only
when called. What is prohibited is *reading the value* before its initializer
finishes. A block reserves its value bindings on entry and evaluates statements
in source order; it does not evaluate a later initializer on demand.

```scheme
(begin
  (def first (lambda () (second)))
  (def second (lambda () 42))
  (first)) ; 42: both functions are initialized before first reads second

(begin
  (def first second)
  (def second 42)
  first)   ; error: first's initializer reads second before initialization
```

The second program has a resolvable name and compatible types but an invalid
execution. A compiler may diagnose a provably premature read; any remaining
case must trap at execution. Calling `first` before the second definition in
the first example would fail for the same reason. This preserves source order
for effects, including initializers whose results are never used.

### Closure captures and initialization cells

Closures capture values by copy. A scalar capture copies the scalar; capturing
a `Ref`, vector, string or other object copies its reference, preserving the
object's identity. Capture does not deep-copy the object, so mutations through
another reference remain visible.

The block-wide scope of `def` requires an initialization exception. A closure
may capture a binding whose value does not exist yet:

```scheme
(begin
  (def read-value (lambda () value))
  (def value 42)
  (read-value)) ; 42
```

The implementation can reserve a hidden, single-initialization cell for `value`
and copy the cell's reference into the closure. Completing the `def` initializer
fills that cell. Creating the closure does not read the uninitialized payload;
calling it does. Calling `read-value` before `value` is initialized must trap.
Recursive definitions use the same mechanism. These hidden cells implement
initialization, not assignment: they are not user-visible `Ref` values, and the
binding remains immutable after initialization.

`let` introduces its binding only after its initializer completes, so capturing
that binding needs no deferred-initialization cell. Its initialized value can be
copied directly. The current compiler conservatively uses cells for captured
local definitions, including `let`; this is an implementation cost, not a
semantic requirement for `let`. Neither form guarantees a heap allocation:
the compiler or downstream optimizer may remove cells, readiness checks or
closure allocations when doing so preserves these rules.

## Mutation

An immutable binding can refer to a mutable object. `(ref 0)` creates a cell;
`ref-get` reads its contents and `ref-set!` changes them. The binding still
denotes the same cell after an update.

```scheme
(begin
  (let counter (ref 0))
  (ref-set! counter 1)
  (ref-get counter)) ; 1
```

Aliases share the object, so a closure that captures `counter` observes updates
to that cell. Cells and mutable containers keep their element type through
updates. There is no assignment operation on bindings themselves.

## Proper tail recursion

A call is in *tail position* when its result is returned directly, with no work
left for the caller. Lofi must execute arbitrarily long chains of tail calls
without accumulating return frames. This applies to mutual recursion and calls
through function values as well as direct self-calls. It is a language guarantee,
not an optional optimization.

A lambda's body is in tail position. When a block is in tail position, so is its
final expression. The selected branch of a tail `if` or `match` is also in tail
position. Arguments, conditions and initializers are not. An annotation that
still requires a result conversion or check leaves work after the call.

`fast-fibonacci` in the [overview](index.md#a-first-look) uses recursive calls to
carry the next state instead of updating variables. Proper tail recursion makes
this style practical. It does not promise bounded heap use when the program
retains new data on each iteration.

## Evaluation order

Execution is eager. For a call, evaluate arguments left to right, then evaluate
the operator, then invoke the resulting function. In `((choose-function) (read-a)
(read-b))`, the order is `read-a`, `read-b`, `choose-function`, invocation.
Type checking may examine the operator first; that does not change execution.

Creating a lambda captures bindings without evaluating the body. `if` evaluates
its condition and one branch; `match` evaluates its subject and one arm. Blocks
evaluate statements in order and return their final expression. A trap ends
that execution; it does not undo earlier effects.
