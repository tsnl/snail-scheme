# Functional tree composition in Scheme

This is an initial React-inspired prototype running under Chibi. It implements
a functional tree composition API that can be used for document markup, GUI
composition, and other structured output. The API is experimental.

The implemented core is [react.sld](../src/snail-scheme/react.sld). It describes
elements, resolves ordinary Scheme components, and returns tree data. State,
reconciliation, effects, scheduling, and host integrations are future work.
There is no dependency on a browser, HTML, a custom reader, or `generate-library`.

## Try it

From the repository root:

```sh
chibi-scheme -I src examples/react.scm
make test
```

The [example](../examples/react.scm) prints a document tree followed by a GUI
tree. The latter is a description of a window and buttons; it does not open a
window. Tests run under the existing Chibi test command. Running this library
through the Snail native or WASI backend has not been validated.

## Elements describe calls

```scheme
(import (scheme base) (snail-scheme react))

(define (greeting props children)
  (create-element 'paragraph '()
                  "Hello, " (cdr (assq 'name props)) children))

(define page
  (create-element 'document '((title . "Guide"))
                  (create-element greeting '((name . "Scheme")) "!")))

(render page)
;; => ((document ((title . "Guide"))
;;               (paragraph () "Hello, " "Scheme" "!")))
```

`create-element` takes a type, properties, and zero or more children. A symbol
names a host node, such as `paragraph`, `window`, or an application-defined tag.
A procedure names a component. Construction records that procedure without
calling it. `element?`, `element-type`, `element-props`, and `element-children`
inspect descriptions.

This follows React's distinction between an
[element description](https://react.dev/reference/react/createElement) and
[rendering components](https://react.dev/learn/render-and-commit). This prototype
uses Scheme procedures and data conventions rather than reproducing React's
JavaScript API.

Components take two arguments: a property association list and an unrendered
child list. This keeps children separate from named properties. A component can
choose which children to return, forward them, wrap them, or compute new ones.
A discarded child component never runs. Ordinary Scheme functions, closures,
`map`, conditionals, and recursion supply the composition language.

Scheme evaluates arguments before calling `create-element`, so code that
computes those arguments runs immediately. Only component calls represented by
elements are deferred. Calling `greeting` directly is an ordinary immediate
procedure call.

## Properties and children

Properties are a proper association list with unique symbol names, such as
`((title . "Guide") (enabled . #f))`. Values are arbitrary Scheme values; a host
can interpret a procedure-valued property as an event handler. Rendering passes
properties through without calling or converting their values. `key` and `ref`
have no special meaning in this prototype.

Descriptions, lists, strings, and property values must be treated as immutable.
Element records have no setters, but Scheme accessors expose the underlying
values; the API does not freeze or deep-copy mutable data. Descriptions must be
finite and acyclic, and component expansion must terminate.

| Child description | Rendered result |
| --- | --- |
| Element with a symbol type | A host node with recursively rendered children. |
| Element with a procedure type | The recursively rendered result of calling the component. |
| String or number | The same value, including `""` and `0`. |
| `#f` or the empty list | No nodes. |
| Proper list | Its children in order, recursively flattening nested fragments. |
| Anything else | An error when that description is visited. |

For example, dynamic children need only `map`:

```scheme
(render
 (create-element 'list '()
                 (map (lambda (n) (create-element 'item '() (* n n)))
                      '(1 2 3))))
;; => ((list () (item () 1) (item () 4) (item () 9)))
```

Unlike React's empty boolean nodes, `#t` is an error here. `#f` supports the
ordinary Scheme idiom `(and condition child)`. Bare symbols are also errors;
literal text must be a string. These rules make accidental non-content values
visible rather than silently coercing them.

Construction validates an element's type and properties. Rendering checks only
selected descriptions. A selected improper fragment fails before visiting its
own prefix; earlier valid siblings may already have executed.

## Rendering produces ordinary data

`render` always returns a forest, including when its input describes one root
or no roots. Each host node is a list shaped `(tag props child ...)`, where
`tag` is a symbol and each child is a string, number, or host node. There are no
remaining component calls in child positions. Properties remain opaque and can
still contain procedures.

The forest is output data for a consumer. It is not a list of element
descriptions to pass back to `render`: host-node lists contain literal tag
symbols, whereas lists in the input mean fragments. The distinction is visible
in the input element records and the output ordinary lists.

A renderer for documents could translate these nodes to HTML; a GUI host could
create widgets from them. Such hosts would supply their own tag vocabulary,
property interpretation, validation, escaping, and lifecycle. The core preserves
text and numeric values, and has no output-format serialization policy.

Each render resolves selected components depth-first, left-to-right. The
implementation accumulates siblings in reverse order and reverses each completed
forest, avoiding repeated concatenation of fragment prefixes. Reusing a component
description twice calls it twice; rendering again calls it again. There is no
memoization. Component failures propagate to the caller without replacement.
Pure components are the intended usage; traversal order does not define an
effects or workbook execution system.

## Next questions

Use real document and GUI examples to judge whether the separate `props` and
`children` arguments and the plain output shape are pleasant. Add a concrete
consumer when its vocabulary is understood. A custom markup reader could later
generate these ordinary Scheme expressions.

Reconciliation would need a deliberate identity and key policy; hooks would
need component instances and an update model. Neither follows from retaining a
procedure in an element record, and neither is claimed by this initial API.
