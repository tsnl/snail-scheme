# Strict native Scheme core

The new core keeps Scheme syntax and hygienic macros while inferring ML-style
types and emitting concrete Wasm values. It is currently an independent compiler
entry, hosted by Chibi. The existing gradual command-line compiler remains the
comparison implementation.

```sh
scripts/build-strict program.scm build/program.wasm
scripts/test-strict
scripts/test-strict-extern
```

Source imports `(snail strict)`. Compilation retains `.wasm.wat` and
`.wasm.raw.wasm`, then applies the shared Binaryen `-O3` optimization pipeline.
The module exports zero-argument `main`, whose native result is the final source
expression; Unit produces no Wasm result. It executes once per module instance;
a second call traps, including after a failed first call. The guard is set before
any source initializer.
Pure programs have no runtime imports. The API is
`strict-source-file->core`, `strict-source-file->wasm`, and
`strict-source-file->wat-file` in `(snail-scheme strict-compiler)`; callers supply
the repository root and source path inside a trace scope.

## Types, inference and immutable bindings

Concrete scalars are `I32`, `I64`, `F32`, `F64`, `Bool`, `Char` and `Unit`.
Integer literals default to I64, floating literals to F64. A compatible expected
I32 or F32 type selects that literal's narrower representation. An annotation
or a checked function parameter can supply the expectation. Already typed values
retain their width; there is no automatic numeric coercion. Integer literals must fit their width.
Native fixed-width arithmetic uses Wasm wraparound and division traps.
`(unit)` constructs Unit. `when` and `unless` evaluate their selected bodies and
produce Unit, including when their bodies are empty. In tail position, an already
Unit-valued body can supply that result directly, so recursive Unit-returning
calls through these forms use constant stack space. Only trailing inert Unit
constructors are removed; later effects, checked conversions and readiness
checks still execute, and bodies of other types still have their results discarded.

```scheme
(import (snail strict))
(define (identity x) x)
(if (identity #t) (+ (identity 40) (identity 2)) 0)
```

Each lambda parameter gets its own inference variable. Unification checks
occurrence and links flexible variables by their canonical lower ID. Recursive
definition groups are solved together. Nonexpansive values generalize variables
absent from their environment; allocations and other applications obey the
value restriction. All source bodies are checked, including unused definitions.
An explicit `(: identity (All (T) (-> T T)))` checks the body with rigid T.
`(inst identity I32)` selects an explicit view. Unused quantified variables need
not acquire a machine representation. Declaration-bound type names are currently
scoped to the signature, not to annotations or `inst` syntax in the body.

Polymorphism is rank one: a binding scheme is monomorphic or has one outermost
`All`. Nested `All` in function results, parameters, or stored element types is
rejected. An outer `All` may quantify the types used by a returned closure; each
concrete copy still returns a monomorphic function. Unknown semantic types or
operations never acquire a generic runtime representation or JIT fallback.

The existing `let` macro expands to a directly applied lambda. The strict checker
elaborates that exact fixed-arity syntactic form as a typed let: actuals are
checked in the caller environment, then eligible bindings generalize. This also
applies to directly written lambda applications. Named and opaque function
parameters remain monomorphic within their bodies.

Bindings cannot be assigned with `set!`. `(ref value)`, `ref-get`, `ref-set!`,
and `ref-eq?` provide explicit invariant cells. Each concrete `Ref T` has a
mutable native T field. Aliases retain one cell, including aliases captured by
different concrete copies of a generic function. Immutable `List T` supports
`cons`, `car`, `cdr`, `null?`, and typed empty lists.
`String` is a distinct concrete managed type; string literals have that type.

## Nominal records and closed recursive variants

`define-data` declares a closed sum of immutable products. A single constructor
is a nominal record. Each field gives its name and type, followed by an optional
accessor name; constructor arguments follow the declared field order.

```scheme
(define-data Point
  (point (x F64 point-x) (y F64 point-y)))
(define-data (Tree T)
  (leaf (value T))
  (branch (left (Tree T)) (right (Tree T))))
(define (first tree)
  (match tree
    ((leaf value) value)
    ((branch left right) (first left))))
(first (branch (leaf 12) (leaf 19)))
```

The type name, constructors, and accessors have resolved declaration identities.
Renamed imports keep those identities; another local or hygienically introduced
declaration with the same spelling creates a distinct type. Type parameters are
explicit and scope the declaration's field types. Constructors and accessors
have ordinary rank-one schemes and can be passed as fixed-signature functions.
Every runtime instance and stored field is monomorphic. A constructor allocation
obeys the existing value restriction, including when a field contains a `Ref`.
No unresolved field becomes `Top`.

These are static declarations: their constructors and accessors are available
throughout the containing body. A constructed value still evaluates every
argument once, left to right, and reads source bindings at its original runtime
position. A forward read of an uninitialized value still traps. Every constructor
requires all its fields; no implicit field initialization or setters are added.
An ordinary constructor alias still has its own value-binding initialization.
An effectful alias initializer remains monomorphic; an `All` annotation cannot
override the existing value restriction.
Explicit `Default` instances can name these concrete nominal types and use the
same class selection and specialization as scalar and container instances.

`match` evaluates its subject once. Each shallow pattern names a declared
constructor followed by one distinct variable per field. Every constructor must
appear exactly once after name resolution, including constructors with a `Never`
field. Missing, repeated, mixed-type and wrong-arity arms are rejected. Nested
patterns, guards and wildcard arms are outside this slice. Arm bodies use normal
binding and result-type rules; a `Never` arm does not widen another arm's result.
An optional accessor on a multi-constructor type checks its constructor tag and
traps when applied to another case, including one with identical field types.

A record has one WasmGC struct with immutable native fields and no constructor
tag. A sum has a tagged base struct and one subtype per constructor, each holding
only that constructor's concrete payload. A native integer field stays an integer;
a managed field stays a typed GC reference. `Unit` uses an i32 slot; `Never` is an
uninhabited reference type and cannot supply a constructor argument by returning
normally. Wasm may canonicalize structurally identical layouts, so accessor tag
checks and explicit `Top` projection tags preserve nominal and case distinctions.

Zero-field constructors share one immutable value per concrete case, rooted in
a private module global. The existing layout registry supplies its identity;
no runtime cache or alternate representation is involved. Constructor aliases
and effectful operator expressions keep their original initialization checks
and evaluation. Constructors with fields continue to evaluate their arguments
and allocate normally, including wrappers around mutable cells.
Immutable data does not promise fresh reference identity or prompt collection.
Imports and selected worker exports remain scalar-only; the generated `main`
itself enforces one-shot execution, including reentrant calls.

Recursive and mutually recursive declarations may refer through records, sums,
lists, vectors, cells and fixed-signature functions. The registry reserves each
concrete nominal application before following its fields, terminating exact
cycles. Different applications remain distinct; finite graphs that change to a
fixed argument type also work. A declaration is limited to 64 demanded concrete
layout applications, matching the existing per-site value-specialization budget.
This is a resource limit, not a termination proof: a sufficiently large finite
graph is also rejected. Recursive arguments that keep growing eventually reach
this bound instead of consuming unbounded compiler memory.

Fields are immutable. Use a `Ref T` field for a mutable edge, with the usual
invariant element type and shared alias identity. The small `data-gcbench` fixture
preserves the original benchmark's top-down child assignment and bottom-up tree
construction using two explicit child cells. Each node therefore allocates a
tagged node plus two `Ref` objects; one shared `Nil` replaces the numeric zero
sentinel. This changes allocation cost from a mutable record and is not a timing
comparison. The `data-paraffins` fixture preserves the canonical partitions,
loop order and accumulation, replacing H/C and BCP/CCP tagged vectors with closed
variants. It checks the canonical count of 75 for ten carbon atoms without `Top`.
The complete Ray port and its measured empty-constructor optimization are
documented in the [benchmark reports](../benchmarks/README.md). The full Nucleic
port remains in progress.

## Free overloads and numeric operations

`(snail math)` supplies `sin`, `cos` and one-argument `atan` with signatures
`(-> F64 F64)`. These ordinary scalar externs call the same Rust implementations
through linked Wasm or native C linkage. They accept infinities and NaNs according
to Rust's binary64 operations; `sin` and `atan` retain the sign of zero.
Two-argument quadrant selection remains ordinary Scheme code. The library does
not add a complex-number or F32 overload.

`define-overload` gives one name several function signatures. Argument types,
expected result types, and later uses constrain the complete signature. A unique
compatible row supplies the remaining type information. An ambiguous use requires
more context; declaration order never chooses a row. Each family lowers to a
static class over one complete function type and uses the existing member checking
and specialization path. There are no runtime dictionaries or tagged arithmetic.

```scheme
(define-overload convert (-> I64 I64) (lambda (value) value))
(define-overload convert (-> I64 F64) i64->f64)
(ann (convert 42) F64) ; 42.0
```

Families currently require module scope. Each row owns its declared signature or
inference hole and its lambda or stable named implementation. Detached `(: family ...)` declarations
are rejected rather than assigned to a row by source order. Rows may have different
fixed arities and rank-one generic signatures. Rest signatures are unsupported.
All bodies are checked, including unused rows. Declarations may extend an imported
family through its original, renamed, or prefixed binding identity. A family cannot
replace an ordinary value or class method with the same identity.

Exact or alpha-equivalent complete row signatures are duplicates, regardless of
their class prerequisites. Other overlaps may be declared, but a use compatible
with several rows remains ambiguous. There is no specificity ordering. Prerequisites
are proved after row selection and do not rank candidates or guess missing types
from the available class instances. Candidate trials use private type copies;
only committing a unique applicable row constrains the actual use.

A family name also names its generic obligation, with one complete function type:

```scheme
(: combine (All (A B R) (=> ((+ (-> A B R))) (-> A B R))))
(define (combine left right) (+ left right))
(combine 20 22.0) ; F64, value 42.0
(define mixed-add (inst + (-> I64 F64 F64)))

(define-overload choose (All (T) (-> T T T))
  (lambda (left right) left))
```

Without a declaration, inference derives a qualified scheme. A unique compatible
given family obligation can solve a body's remaining holes without weakening rigid
`All` variables. Different result obligations for identical inputs remain distinct.
Selection repeats after unification and before concrete specialization so nested
calls and later uses can settle earlier holes. Ordinary `define-class` contracts
retain exact full-head lookup and never infer a type from an available instance.
Declared obligations remain assumptions throughout checks of an unused generic
body, even if the current rows cannot fulfill that abstract premise. A concrete
use must prove it. Row prerequisites share one fresh instantiation while they
are jointly improved and proved; this lets one prerequisite determine another's
otherwise hidden type. Repeated equal complete obligations are one proof, so
reading a constrained value twice does not duplicate its proof graph.

Numeric families supplied by `(snail strict)` are:

| Family | Same-type signatures | Mixed signatures |
| --- | --- | --- |
| Binary `+`, `-`, `*` | I32, I64, F32, F64; result has the same type | I64/F64 in either order; result F64 |
| Binary `=`, `<`, `<=`, `>`, `>=` | I32, I64, F32, F64; result Bool | I64/F64 in either order; result Bool |
| Binary `quotient`, `remainder` | I32, I64; result has the same type | None |
| Binary `/` | F32, F64; result has the same type | I64/F64 in either order; result F64 |
| Unary `sqrt`, `truncate`, `round` | F32, F64; result has the same type | None |

Mixed rows explicitly convert the integer, then call the float row. For example,
the library defines:

```scheme
(define-overload + (-> I64 F64 F64)
  (lambda (left right) (+ (i64->f64 left) right)))
```

There is no search for a common numeric type. I32/I64 and F32/F64 pairs are absent
unless the program supplies an explicit overload. Bool and Char have no numeric
rows despite sharing the physical i32 layout. Integer-only `/` is rejected;
`quotient` is signed integer division. Floating comparisons retain Wasm's NaN
behavior: all five comparisons are false when either operand is NaN. Integer
arithmetic wraps; division by zero and signed division overflow trap.

Each overload argument is checked without consulting candidates. Literals default
to I64/F64 unless ordinary type context supplies a concrete width. Consequently,
both `(+ (ann 40 I32) 2)` and `(+ 2 (ann 40 I32))` reject their I32/I64 pair.
Annotate both literals, or use a concrete function view such as
`((ann + (-> I32 I32 I32)) 40 2)`. A result annotation alone does not choose operand
widths. Calls still evaluate arguments from left to right, then the operator.

First-class family aliases generalize under the usual value restriction. A
concrete use selects an implementation before emission. Named implementations
retain their original initialization and readiness checks; lambda implementations
initialize at the overload declaration. Specialization copies code and never
reevaluates an effectful initializer.

`truncate`, `f32-truncate`, and `f64-truncate` round toward zero while keeping their floating
representation. They preserve signed zero and infinities, and return NaN for a
NaN input. Unlike a conversion to an integer, they also accept finite values
outside the I64 range. These operations emit native Wasm `f32.trunc` and
`f64.trunc` instructions.

`round`, `f32-round`, and `f64-round` select the nearest integral floating value,
with halfway values going to the even integer. They keep the input width, signed
zero, and infinities; NaN produces NaN without a payload guarantee. Thus `-0.5`
rounds to negative zero, and both `-1.5` and `-2.5` round to `-2.0`. Finite values
outside the I64 range remain valid. The native operations are `f32.nearest` and
`f64.nearest`; integer conversion is a separate operation. A concrete function
view such as `(ann round (-> F32 F32))` uses the same static selection rules as
the other numeric overloads.

Conversions are explicit native unary functions:

| Function | Native behavior |
| --- | --- |
| `i32->i64` | Signed extension. |
| `i64->i32` | Keep the low 32 bits. |
| `i64->f64` | Signed conversion, rounding to the nearest representable F64. |
| `f32->f64` | Exact floating promotion. |
| `f64->f32` | Floating demotion with native rounding and overflow behavior. |
| `f64->i64` | Truncate toward zero; trap on NaN or an out-of-range result. |

The explicitly named `i32-*`, `i64-*`, `f32-*`, and `f64-*` primitives remain
available for code that requires a fixed representation.

## Concrete mutable vectors

`Vector T` has fixed length, mutable identity, and native T element storage.
For example, `Vector I64` stores i64 elements, `Vector F64` stores f64 elements,
and `Vector (Ref I64)` stores managed cell references. Element types are
invariant: aliases see one vector, and a write cannot change its element type.
Heterogeneous storage requires an explicit `Vector Top` with explicit injections.

```scheme
(define values (make-vector 3)) ; later writes determine Vector I64
(vector-set! values 1 42)
(vector-ref (vector-append values (vector 7 8)) 1)
```

The public vector operations are:

| Operation | Contract |
| --- | --- |
| `(empty-vector)` | Fresh empty vector; context must determine T. |
| `(make-vector length fill)` | Fresh vector with every element set to fill; no Default obligation. |
| `(make-vector length)` | Fresh vector; one `default` call per element under Default T. |
| `(vector-length source)` | Length as I64. |
| `(vector-ref source index)` | Element at an I64 index. |
| `(vector-set! target index value)` | Replace one T element; return Unit. |
| `(vector-eq? left right)` | Identity comparison for vectors of the same type. |
| `(vector-copy! target at source start end)` | Copy `[start, end)` to target at `at`; return Unit. |

Indices and lengths reject negative I64 values and values above `2^32 - 1`
before narrowing to native array indices. Native array operations check the
actual bounds. Allocation also remains subject to the engine's resource limits.
Bulk copy supports overlapping ranges and validates both complete ranges before
any write, including zero-length ranges. Operands execute once, left to right,
then the operator, before these checks.

`vector`, `vector-copy`, `vector-append`, `vector->list`, and `list->vector`
are ordinary polymorphic functions in `(snail strict)`. Their concrete copies
use those storage operations without a dynamic element boundary. `vector-copy`
currently copies a whole vector; `vector-copy!` takes exactly five arguments.
`make-vector` has two generic rows. `(make-vector length fill)` uses the fill's
type, requires no `Default` instance, and shares that fill's identity across slots.
`(make-vector length)` requires `(Default T)` and creates each element with the
ordinary zero-argument `default` method. Expected `Vector T` context or later uses
must determine T; available defaults never choose it. The library supplies defaults
for I32, I64, F32, F64, Bool, Char, and Unit. Programs may define exact instances for
other types.

The one-argument constructor validates the length before invoking `default`. Zero
length invokes it zero times; positive length invokes it once per element. Its
private vector does not escape before all slots are initialized. Mutable defaults
therefore retain distinct element identities when the method constructs fresh
values. Both forms create fresh outer storage.
The default and list conversion fill loops use native tail calls, so their stack
use does not grow with the vector length.
Allocations obey the value restriction: one empty vector cannot be reused at
different element types. For an otherwise unconstrained empty vector, write
`(ann (empty-vector) (Vector I64))`.

## Unicode strings and characters

A `String` owns Unicode scalar characters. Lengths and indices count characters,
so NUL, `é`, and `😀` each occupy one position. Strings are distinct from
`Vector Char`, including across explicit `Top` conversions. Character operations
are binary `char=?`, `char<?`, `char<=?`, `char>?`, and `char>=?`.
`char->integer` returns the I64 scalar value; `integer->char` accepts I64 values
from 0 through `#x10ffff`, excluding surrogates `#xd800` through `#xdfff`, and
traps otherwise. Case folding, normalization and grapheme indexing are not
implemented.

String literals are readonly module constants, allocated before `main`.
Evaluating one literal occurrence repeatedly returns its constant; equal
occurrences may share storage. The permission belongs to the string object and
follows every alias. Constructors and copies return fresh mutable strings,
including empty results and one-argument append.

| Operation | Contract |
| --- | --- |
| `(make-string length fill)` | Fresh string filled with the Char value. |
| `(make-string length)` | Fresh string filled with NUL characters. |
| `(string character ...)` | Fresh string containing the supplied characters. |
| `(string-length source)` | Number of characters as I64. |
| `(string-ref source index)` | Char at the I64 index. |
| `(string-set! target index value)` | Replace one character; return Unit. |
| `(string-copy! target at source start end)` | Copy `[start, end)` into target at `at`; return Unit. |
| `(string-copy source)` | Fresh mutable copy of the whole source. |
| `(substring source start end)` | Fresh mutable copy of `[start, end)`. |
| `(string-append source ...)` | Fresh mutable concatenation, including zero sources. |
| `(string=? left right)` | Compare lengths and character values. |
| `(string-eq? left right)` | Compare string identity. |
| `(string->list source)` / `(list->string characters)` | Convert to/from a `List Char`. |

Every mutating operation checks destination writability, even a zero-length
copy. A readonly source is permitted. Empty copies on mutable destinations allow
valid source and destination endpoints; all ranges are checked before any
write. Overlapping copies have memmove behavior. Negative lengths or indices,
reversed ranges, and out-of-bounds positions trap. Operands run exactly once,
left to right before the operator, before any primitive permission/range check.

The native representation is one mutable i32 GC array: cell 0 stores a private
writability flag, and the remaining cells store Unicode scalars. Length subtracts
one from the unsigned native length; indexing checks the I64 value before adding
the metadata offset. The maximum representable string length is `2^32 - 2`,
with lower allocation limits possible in the engine. No operation exposes the
metadata cell or permits a string to be used as a character vector. Wasm owns
all string lifetimes and keeps live references in globals, locals and containers.

Allocation, indexing, mutation, length, identity and bulk copying are native
primitives. Append, substring, fresh copy, content comparison and list conversions
are ordinary Scheme functions in `(snail strict)`. `string-copy` currently takes
one argument and `string-copy!` takes exactly five. String values remain internal
managed references; native scalar imports/exports do not accept them.

## Concrete calls and static classes

Function types are `(-> Fixed ... Result)` or
`(-> Fixed ... (Rest Element) Result)`. Fixed parameters become separate native
Wasm parameters. A rest parameter is one immutable typed list, with a fresh
spine and shared element identities. Ordinary calls evaluate operands left to
right before the operator. A closure contains a typed code reference and a
GC-visible environment. Known code can be called directly; unknown code uses a
typed indirect call. Tail calls use Wasm tail-call instructions.

A local binding initialized by a lambda can omit its closure and environment
when every concrete use is a call operator. Its code receives captured lexical
state as additional native parameters. Aliases, returned function values,
global bindings, and exported workers retain ordinary closures. Named `let`
currently returns its procedure through a wrapper, so that expansion also keeps
the closure representation.

Specialization keys retain concrete body, capture and class-obligation types,
including phantom class parameters. Instances are reserved before their bodies
are expanded, so ordinary recursion reuses one instance. Changing polymorphic
recursion is bounded and rejected with a located diagnostic, never widened to
a universal representation. The current depth limit of 128 and per-binding
limit of 64 concrete instances are implementation limits, not additional type
rules. Reachable expression types must be concrete.

`define-class`, `define-instance`, and qualified `All` retain the static class
contract. Instance heads match exactly. Inferred functions can generalize their
class obligations; explicit declarations must supply every abstract obligation.
Concrete method views and method values resolve to their implementation before
Wasm emission. Named implementations retain their original binding and
initializer site. Instance declarations do not evaluate an early runtime alias.
Lambda implementations initialize at their declaration position.

Code copies and runtime initialization are distinct. An effectful initializer
executes once at its lexical source site. Captured local immutable bindings use
private, once-initialized concrete cells when necessary to tie recursive closure
references. Those cells carry readiness state; capturing the cell does not read
an uninitialized value. They are separate from user-visible Ref cells. Global
bindings likewise check readiness, preserving failure before an early read.
An unused polymorphic name initializer still performs its source read. A lazily
created Unit readiness token preserves that check when no payload copy is needed;
erasing a concrete payload never erases a required early-binding failure.
Ref and Vector allocation identities are exposed by the language. Pure
specialized closures may have separate wrappers while sharing their captured
cells and vectors.

## Reading the specialization pass

Three compiler objects explain this separation. A **site** belongs to a lexical
source binding and records its initialization position. A **value** is one
concrete payload demanded from that site. A **function** is a concrete copy of
lambda code. None of these compiler objects is a runtime polymorphic dispatch
table. Executing an enclosing function creates its local storage anew.

For example, the following program returns 2:

```scheme
(define count (ref 0))
(define (counted x)
  (ref-set! count (+ (ref-get count) 1))
  x)
(counted 42)
(counted #t)
(ref-get count)
```

The `count` initializer allocates one cell. `counted` needs I64 and Bool code
copies, each referring to that existing cell. Cloning the lambda does not run
its body or repeat the allocation. There is no need for another universal
closure object to connect the copies.

Specialization first reserves a requested value, then clones its initializer.
A recursive use can find that pending value without expanding forever. The
source bind node remains responsible for runtime initialization: monomorphic
initializers are demanded even when unused, and generalized names retain any
required source read even when no concrete payload is needed. Consequently,
`(define alias later)` before `later` is initialized still fails if `alias` is
unused. A payload-free readiness token preserves this behavior.

After cloning discovers all demands, specialization identifies direct local
procedures. It follows an immediately invoked result through `let` bodies and
the final expression of blocks. For example, `((let () (define (f x) x) f) 42)`
calls `f` without constructing its closure. Initializers and block prefixes
still use procedure values normally, and conditionals and other operators
retain their ordinary closure behavior. Capture analysis follows value references
and propagates the requirements of both direct calls and nested closures to a
fixed point. It excludes a function's own parameters and local bindings, so
recursive activations retain separate storage. The emitter uses the specializer's
same site-value enumeration to assign storage, then emits source initialization in
order. Code reservation, runtime storage allocation, and successful binding
initialization are distinct events; only the last makes a source read legal.

Parameters and nonrecursive `let` bindings are initialized before their body
can create a closure. Captures of those bindings therefore carry their concrete
values directly; match fields follow the same rule after successful extraction.
Copying a Ref or vector reference preserves the original object's identity.
This guarantee belongs to the source binding: a recursive alias of a ready value
still has its own initialization event, and a let initializer must still check
any recursive binding it reads.

Recursive bindings captured by a surviving closure keep shared initialization
cells, including dependencies carried through direct calls. Other recursive
captures can travel as raw payloads and readiness flags while their synchronous
owner is suspended. Passing that state performs no source read: an unready
reference stays nullable until the original use checks readiness. A direct
procedure's binding also keeps its readiness flag, checked after operand effects
and at the original invocation.

The emitter first saves every operand, from left to right, in typed Wasm locals
that remain GC roots. A structured operator then runs its preparations,
initializers, and prefix expressions before invoking its final result with those
saved operands. This preserves source effect order and lexical scope while
allowing the frontend's existing named-let expansion to use a direct local
procedure. Tail calls remain tail calls through these final result positions.

## Explicit universal values

The bounded lattice is `Never <: T <: Top`. Top means a checked universal value;
an unsolved inference hole is not Top. Different branch types fail unless an
explicit Top expectation requests the conversion. `ann` injects concrete values
into Top and projects them back with a checked tag:

```scheme
(define value (ann (ref 42) Top))
(ref-get (ann value (Ref I64)))
```

Top is an engine-managed `eqref`. Small I64 values use signed i31 immediates;
other scalars use tagged boxes. Managed values use a wrapper containing the
original reference and a complete semantic type witness. Thus Bool and I32,
Ref Bool and Ref I32, Vector Bool and Vector I32, and function signatures
differing only in those types remain distinct even when their physical Wasm
layouts coincide. Projection
returns the original referenced value and preserves identity. Mismatches trap.
Compound witness IDs belong to the module's layout registry. They do not yet
define a shared cross-module Top ABI.
Projection to Never evaluates its operand and traps. Never-returning calls emit
validator-visible unreachable control flow when used in a concrete context.

## Native scalar imports and reusable workers

An extern declaration names a Wasm module, export, and complete function type:

```scheme
(import (snail strict))
(define-extern add-native "arithmetic" "add" (-> I32 I32 I32))
(: increment (-> I32 I32))
(define (increment x) (add-native x (ann 1 I32)))
(unit)
```

It contributes a typed binding without a runtime initializer. Direct calls
pass separate native arguments to the Wasm import. Used as a function value or
static class implementation, the same binding receives an ordinary typed
closure adapter. It does not acquire an argument vector or rooted-object ABI.
Externs can occur in local scopes and hygienic macros as ordinary declarations.

The external signature accepts fixed I32, I64, F32, F64, Bool, or Char parameters
and one of those result types or Unit. Bool and Char use i32. Providers must
return their valid source encodings: 0/1 for Bool and Unicode scalar values for
Char. Callers of exported workers must supply those encodings as well. Wasm linking
checks physical signatures, so it cannot distinguish Bool from I32. Source
checking retains those distinct semantic types. Unit returns no Wasm result;
the compiler supplies its internal Unit value when evaluating such a call as
a Scheme expression. All, rest parameters, Unit parameters, Never, managed
references, and Top are rejected at this boundary.

```sh
scripts/build-strict --export increment program.scm build/program.wasm
```

`--export` selects an unambiguous top-level value binding with an explicit
monomorphic function declaration and the same scalar signature restrictions.
It may be repeated for distinct names; `main` is reserved. The selected worker
keeps the closure produced by its source initializer, including any managed
captures. Calling it before main finishes successfully traps. Calls after
initialization reuse those captures and never repeat the initializer. A worker
failure does not reset initialization. A failed first main leaves the module
unready, and subsequent main calls trap before executing source effects.
Reentrant main calls likewise trap; a provider that catches that trap and
returns normally can allow the original initialization to finish.

The scalar restriction applies to declared imports and selected worker exports.
The diagnostic main export can still return a concrete managed value; this is
an opaque result, not a supported cross-module GC contract. Shared managed
imports need an agreed type graph and ownership contract. Numeric resource IDs
belong to their provider's resource interface and never represent GC addresses.

## Current boundary

This slice supports scalar arithmetic, concrete higher-order closures, recursive
functions, explicit cells, immutable lists, concrete mutable vectors, nominal
records, closed recursive variants, static classes and explicit Top.
It also provides native scalar foreign declarations and reusable exported
workers. It does not yet provide strings, arbitrary integers, rationals,
dynamic `apply`, or universal-value operation dispatch. The
existing parser may recognize forms outside this surface; the strict checker
rejects unsupported expressions. No benchmark speedup is claimed from
correctness tests alone.

## Shared IR and compilation ownership

Expansion, checking and specialization use the same located node and definition
records in `ir.sld`. A definition owns its scheme, optional located declaration
and initializer; each overload row has its own member identity and signature.
Expansion resolves names and attaches syntax without inferring types. Unannotated
expressions and bindings begin with fresh `Hole` identities.

Inference owns one graph copy of all source and primitive roots, including unused
bodies. A temporary identity map preserves sharing and cycles while copying
mutable nodes, schemes, holes and checking data. Cached expanded libraries stay
unchanged. The owned graph is then refined in place: holes are solved, eligible
bindings are generalized, and explicit conversions and direct-let lowering become
visible in the same IR. `strict-core.sld` contains only program and static class
evidence records.

A Hole is missing static information, not a universal value. `Top` has a concrete
runtime representation and explicit checked boundaries. Rigid `All` variables
cannot be solved; generalized uses instantiate fresh holes. Specialization copies
expressions with concrete substitutions while retaining external checked binding
and runtime initialization identities. Its site, value and function objects
separate one initializer event from the storage and code it needs. Generic
templates retain their obligations, and every emitted instance must have fully
concrete types and resolved operations.

## Inferred overload signatures

A row may omit its signature. Expansion still only resolves names and gives the
member a fresh hole. Checking infers a lambda's scheme or uses a stable named
implementation's completed scheme, including its class prerequisites:

```scheme
(define-overload increment (lambda (value) (i64-add value 1)))
(define-overload increment (lambda (value) (f64-add value 1.0)))
(define-overload select (lambda (value) value)) ; All (T), T -> T
(define-overload convert i64->f64)
```

Each scheme is determined before callers select that row. Ordinary recursive
binding groups share provisional monotypes and generalize together. Dependencies
through helpers, named aliases and family prerequisites must settle before an
inferred row's scheme becomes available. An unfinished family row remains a
possible candidate; only a known different fixed arity excludes it. Once the
relevant signatures are complete, ordinary generic wrappers can retain unresolved
family obligations as before. Prerequisites never filter or rank candidates.

A cycle that requires an unfinished family signature reports a located request
for an explicit signature. This includes directly recursive omitted rows; the
checker does not speculate about candidate bodies to break the cycle. An explicit
row signature or a declared helper scheme can break the dependency, but every
body still checks, including unused definitions. An inferred scheme must be a
fixed-arity function and have no free captured type holes. Other independent
binding initializers may settle shared storage types before publication, in either
source order. This scheduler does not use bare executable module expressions to
settle row signatures: a `ref-set!` expression before or after the row cannot fix
an otherwise unresolved captured cell type. Annotate the captured storage or the
row in that case. The signature must settle before executable expressions can use
the family. Inferred and declared rows obey the same duplicate and ambiguity rules.
Changing the declaration order cannot select a different row.

Signature checking does not move runtime initialization. A named row still uses
its original implementation binding, including its effectful initializer and
forward-read guard; it creates no early alias or extra initialization event.
