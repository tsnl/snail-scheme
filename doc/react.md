# Functional tree composition in Scheme

This Chibi-hosted experiment provides a functional tree composition API for
document markup, GUI composition, and other structured output. The API is
experimental. [react.sld](../src/snail-scheme/react.sld) contains the generic
core; the [reducer and HTML experiment](ui.md) supplies a concrete consumer.
It has no dependency on a custom reader or `generate-library`.

```sh
chibi-scheme -I src examples/react.scm
```

The example prints document and GUI descriptions. It does not open a native
window. The libraries have been exercised under Chibi, not compiled through
Snail's native or WASI backend.

## Elements and components

```scheme
(import (scheme base) (snail-scheme react))

(define (greeting name children)
  (element 'paragraph #f "Hello, " name (apply fragment children)))

(define page
  (element 'document "Guide" (element greeting "Scheme" "!")))

(define roots (resolve page))
(element-type (car roots)) ; => document
(element-data (car roots)) ; => "Guide"
```

`(element type data child ...)` constructs an immutable record. Its type can be
any Scheme value; a procedure type denotes a deferred component call. Its data
is an arbitrary payload, such as a record, a name, or a vector. Components take
`(data children)`, where children are still descriptions. A component can select,
reorder, reuse, or discard them. Discarded component descriptions never run.

Construction does not call the component. Scheme still evaluates the arguments
to `element` normally; only the represented component call is deferred. A direct
call to `greeting` runs immediately. Component reuse performs another call rather
than establishing a stateful instance.

The accessors are `element?`, `element-type`, `element-data`, and
`element-children`. There is no required property list or tag vocabulary in the
core. Payloads and leaves remain untouched, even when they contain procedures.
Only a procedure in an element's type position is invoked.

## Fragments are explicit

`(fragment child ...)` represents zero or more siblings. `(fragment)` omits
content, and `(apply fragment descriptions)` splices an ordinary list of
computed descriptions. `fragment?` and `fragment-children` inspect it.

```scheme
(element 'list #f
         (apply fragment
                (map (lambda (n) (element 'item #f (* n n))) '(1 2 3))))
```

| Description | Resolution |
| --- | --- |
| Element with procedure type | Call `(type data children)` and resolve its result. |
| Element with another type | Preserve type/data and resolve its children. |
| Fragment | Splice its resolved children in order. |
| Any other Scheme value | Preserve it as one opaque leaf. |

Thus `#f`, `()`, booleans, lists, symbols, vectors, and procedures are all data
when used as leaves. Use `(if visible? child (fragment))` for conditional
content. Explicit fragments avoid making Scheme lists or false values unusable
as domain data. An HTML consumer can impose its own narrower leaf vocabulary.

## Resolution preserves the representation

`resolve` returns a forest: a proper list containing zero or more element
records or opaque leaves. Resolved elements have the same accessors as input
elements; component calls and fragments have been eliminated in child positions.
There is no conversion to DOM nodes, HTML, or a new s-expression serialization.

To resolve an existing forest as siblings, use `(resolve (apply fragment roots))`.
Passing `roots` directly preserves that list as one leaf. The example's
`tree->datum` chooses a printable s-expression format outside the core.

Resolution visits components depth-first, left-to-right. Components control
which of their unexpanded children are selected before traversal proceeds.
Sibling results accumulate in reverse order and are reversed once when complete,
avoiding repeated copying through nested fragments. Component exceptions propagate.

Descriptions have no setters, but their payloads and child lists are ordinary
Scheme objects. Treat them as immutable, finite, and acyclic. Component expansion
must terminate. Pure components are the intended usage; traversal order does not
provide a scheduling or effects API.

## State and rendering

State belongs to a model/update/view application, described in [ui.md](ui.md).
There are no hooks, `use-state`, identity keys, reconciliation, or hidden component
state slots. The HTML renderer interprets symbol tags and attribute alists because
HTML needs them; those conventions do not constrain other tree consumers.

A markup reader can eventually generate these ordinary Scheme expressions.
Constructing and resolving the document remains a separate stage from reading it.
