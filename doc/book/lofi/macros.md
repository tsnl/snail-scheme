# Macros and Scheme libraries

Languages are libraries. Lofi has a small typed kernel and hygienic declarative
macros. `(scheme base)` uses those macros to provide initial Scheme binding and
control forms. Both surfaces use `.sld`, share imports and exports, and compile
to the same checked Lofi representation. The public `(lofi compiler)` can be
imported from either; its current Chibi implementation is a separate bootstrap
library, not a different meaning of that public name.

## Defining and using transformers

```scheme
(import
 (lofi core)
 (lofi base))
(def twice
     (syntax-rules ()
       ((_ expression)
        (begin (let value expression) (+ value value)))))
(let value 100)
(twice 21) ; 42
```

`(def name (syntax-rules (literal ...) (pattern template) ...))` creates a static
transformer binding. `(define-syntax name (syntax-rules ...))` is an alias.
A transformer can be exported, imported with `only` or `rename`, and re-exported.
It cannot be passed as a runtime value. Expansion happens after imported binding
identities are resolved, before ordinary type checking and code generation.
Expanded code obeys all ordinary type and initialization rules.

Rules are tried in order. A pattern's first identifier stands for the macro
keyword; `_` matches without binding. Other identifiers bind pattern variables,
unless listed as literals. Literal identifiers compare binding identity (or the
same unbound name), not just printed spelling. Literal data, proper and dotted
lists, vectors, and repeated subpatterns followed by `...` are supported.
Repetition may be nested or empty and may precede a fixed suffix. Each pattern
variable occurs once in a pattern. A template must use it at least as deeply
inside repetition as its pattern occurrence; a shallower capture can be reused
inside a deeper repetition. Repeated variables that drive one template segment
must have equal lengths. Malformed depths and mismatched lengths are errors.

Arguments keep their use-site lexical context. Template identifiers receive a
fresh introduction context for each application and retain their definition-site
environment. Thus `value` above cannot capture a caller's `value`, and a caller's
`+` cannot replace the macro's imported addition. An unbound definition-site
identifier remains unbound even when a caller has that spelling. Private helper
macros, runtime functions, nominal types and literal bindings keep their identity
through rename and re-export. Generated internal names are inaccessible to raw
source. Numeric spelling and locations survive expansion and transfer; errors
use the location of the offending argument or template syntax.

## Scope and expansion order

Direct `def`, `define-syntax` and library declaration bindings are scope-wide.
Sequential kernel `let` binds only following statements, and a macro captures the sequential scope
at its definition site. Value and quantified type variables occupy separate
scopes. Library `begin` clauses concatenate; expression `begin` creates a block.

Macros may produce definitions, including other macros. A block discovers those
bindings before expanding its expressions. A generated binding that would change
an earlier macro-head or literal-identity decision is rejected with a request to
use a direct definition. This restriction prevents retroactive expansion choices;
ordinary forward generated definitions are supported when no earlier decision
changes. One library expansion has a 10,000-application limit, so runaway macro
recursion produces a located diagnostic.

## Producing several library declarations

At library scope, `(begin form ...)` splices its forms into the surrounding body.
It creates no lexical scope or runtime value. An imported macro can use it to
define a nominal type, its operations, and an application registry together:

```scheme
(import
 (lofi core)
 (lofi base))
(def define-counter
     (syntax-rules ()
       ((_ State make-state state-value advance)
        (begin
          (data State ()
            (make-state
             (value I32 state-value)))
          (def advance (-> State State)
               (lambda (state) (make-state (+ (state-value state) 1))))))))

(define-counter Counter make-counter counter-value advance)
(counter-value (advance (make-counter 41))) ; 42
```

The caller supplies the public names. Template-introduced helper names remain
hygienically private. Nested splices preserve source order, block-wide definition
visibility, sequential bindings and definition-site macro capture. The expander
reserves each newly exposed group of sibling definitions before interpreting its
heads. Rebinding a core splice already consumed is rejected by the same recorded
decision rule as other retroactive expansion changes.

This splicing behavior applies in a library body, including a script's implicit
library. Inside `define-library`, write an application macro in a body clause, such as
`(begin (application ...))`; the macro can return another `begin`. The structural
library header parser does not accept arbitrary macro clauses. An ordinary
expression `begin` keeps its lexical scope. `library-begin` is a compatibility
alias for the splice and is an error inside a lambda or expression block.

Imports, exports and `define-library` remain explicit source headers. Producing
one during body expansion, directly or inside a splice, is a located error;
expansion cannot silently add a dependency after resolution. Errors in an
imported macro template retain that template's source location.

The current declarative subset uses `...` only. Custom ellipsis identifiers,
escaped ellipses, `let-syntax`, `letrec-syntax`, procedural transformers and
arbitrary compile-time evaluation are not implemented. Custom type-operator
macros remain outside the supported surface. Kernel syntax remains
intrinsic for existing direct and constructed-library APIs; `(lofi core)` also
exports named syntax bindings so libraries can explicitly import or rename it.

## Deriving typeclass instances

A `data` declaration can end with one `deriving` clause naming macro
transformers. `(lofi serialization)` exports two independent transformers:
`derive-serialize` generates a `Serialize` instance, and `derive-deserialize`
generates a `Deserialize` instance.

```scheme
(import
 (lofi core)
 (lofi serialization))

(data Stock ()
  (stock
   (ore I32 stock-ore))
  (deriving derive-serialize derive-deserialize))
```

The expander removes the clause and passes the complete remaining declaration
to each transformer as its single argument. For example, `derive-serialize`
receives `(data Stock () (stock (ore I32 stock-ore)))`. It can inspect the type
name, parameters, constructors and fields through ordinary `syntax-rules`
patterns. The type declaration is retained once; each transformer's output is
spliced alongside it in the same library scope. A transformer produces only its
additional declarations, without repeating the original type.

Targets are macro bindings, so ordinary import, rename, definition-site capture
and hygiene rules apply. They may be defined later in the same library when
normal definition discovery permits it. An empty `(deriving)` is a no-op.
Duplicate clauses, a clause before a constructor, nonidentifier targets, and
targets that are runtime values or unbound names are errors. Deriving requires a
library-level `data` declaration; it does not give expression blocks local types.

Derived methods are ordinary checked code. They call field operations with one
shared traversal context, so nested fields participate in the same object graph.
A missing field capability is a class requirement error; there is no fallback
through `Any`. Deriving either class does not require deriving the other.

The protocol accepts parameterized declarations, and a user transformer can
inspect their parameters. The two serialization derives currently match an empty
type-parameter list: they generate concrete instances. Their field macros handle
`List`, `Ref` and `Vector` recursively without inventing generic instances.
Deserializing reference or vector storage also requires `Default` evidence for
its element type, to allocate valid storage before decoding a cycle. Constrained
generic instances and derivation for parameterized transport types remain future
work.

### Literal declaration metadata

Three bounded core forms supply literal strings during expansion:

- `(identifier-name identifier)` returns that syntax identifier's source name,
  before generated binder names replace it.
- `(library-name)` returns the printed name of the library being expanded.
  Anonymous scripts use the marker `"#f"`.
- `(type-name identifier)` resolves a datatype declared in the current library
  and returns its library-qualified source name. Distinct local datatype
  bindings cannot claim the same portable name.

The derives use `type-name` for their portable tag and retain constructor and
field names in the wire value.
Renaming an imported type does not regenerate its instance or change its tag.
Use named libraries for stable transport schemas; unrelated anonymous scripts
with the same type spelling share a tag. Within a library, two hygienically
private types with the same spelling cannot both claim that portable name;
serialization derivation reports a collision instead of conflating their types.

These forms do not provide general compile-time evaluation or lookup of an
already-defined type's schema. The full declaration reaches the transformer
because the deriving protocol supplies it explicitly. See
[Data graph serialization](types.md#data-graph-serialization) for the value and
encoding contracts.

## Initial Scheme base

```scheme
(import
 (scheme base))
(define (fib n)
  (let loop ((n n) (previous 0) (current 1))
    (if (= n 0) previous
        (loop (- n 1) current (+ previous current)))))
(fib 10) ; 55
```

[`src/scheme/base.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/scheme/base.sld)
implements `define` (variable and function shorthand), `lambda`, simultaneous
`let`, named `let`, sequential `let*`, recursive `letrec`/`letrec*`, `begin`, `if`,
`and`, `or`, `when`, `unless`, and a basic `cond`. It re-exports selected scalar,
list, vector, string and character operations from `(lofi base)`, along with
`syntax-rules` and `define-syntax`. Mixing these forms with explicitly imported
Lofi annotations and datatypes is supported.

This is a **typed Scheme subset**, not an R7RS implementation:

- Tests require `Bool`; branches must have compatible types. `or` evaluates each
  tested operand once, and `and`/`or` short circuit. The two-operand `if`, `when`
  and `unless` return `Unit`.
- `letrec` and `letrec*` both use Lofi's source-order recursive initialization;
  premature reads trap. Expression `begin` is a lexical block; library-level
  `begin` splices into its surrounding scope, including in macro expansion.
- `cond` supports clauses with body expressions and an optional final `else`.
  It does not implement test-only or `=>` clauses.
- Functions have fixed arity; `define` and `lambda` require proper parameter
  lists. General first-class Scheme variadic procedures remain deferred.
- Lists and vectors are homogeneous and numeric representations follow Lofi.
  There is no automatic dynamic Scheme representation or general numeric tower
  behind these forms.
- Quote/quasiquote, `set!`, multiple values, continuations, Scheme ports and the
  rest of R7RS are future work. Existing `(lofi ...)` libraries expose additional
  runtime services explicitly.

### Packing macros and first-class workers

`(list a b)`, `(vector a b)` and `(string a b)` are hygienic syntax from
`(lofi base)`, also re-exported by `(scheme base)`. They construct a homogeneous
list with `cons`/`empty-list`; the vector and string forms then call the ordinary
`list->vector` and `list->string` functions. Arguments run once, left-to-right.
No runtime function has an optional argument or a rest parameter.

The same distinction applies to these libraries:

| Packing macro | Fixed-arity worker | Library |
| --- | --- | --- |
| `vector` | `list->vector` | `(lofi base)` |
| `vector-append` | `vector-concatenate` | `(lofi base)` |
| `string` | `list->string` | `(lofi base)` |
| `string-append` | `string-concatenate` | `(lofi base)` |
| `bytevector` | `list->bytevector` | `(lofi bytes)` |
| `bytevector-append` | `bytevector-concatenate` | `(lofi bytes)` |
| `datum-list` | `list->datum` | `(lofi datum)` |

Each worker takes one list argument and can be passed as a function value.
The macros cannot be used as runtime values; replace a former first-class
constructor with its worker, or write a lambda with an explicit parameter list.
An empty packing macro still needs enough type context to determine its element
representation. General Scheme variadic calling needs a separately specified
lowering convention; these macros do not implement that convention.

## Library values and bootstrap

Parsing retains located source without obtaining dependencies. Resolution gets
transformers from the explicit library map and expands afresh for that map;
compilation never discovers missing files. Source transfer retains original
syntax and reestablishes lexical identities in the receiver. Kernel declaration
inspection of a library awaiting expansion can be empty; see the
[builder protocol](https://github.com/tsnl/snail-scheme/blob/main/doc/lofi-builder.md).

Chibi reads compiler implementation sources through `bootstrap/`, a loader view
of `src/lofi` that leaves Chibi's own `(scheme base)` unshadowed. Product source
uses `src/scheme/base.sld`. All these libraries use `.sld`; executable Chibi
orchestration remains `.scm`. The compiler's Scheme implementation is retained
for future compilation through its own pipeline. The initial surface does not
yet supply the semantics required to self-host it.
