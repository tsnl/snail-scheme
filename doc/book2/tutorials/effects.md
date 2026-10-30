# Effects

`examples/effects.sld`:

```scheme
{{#include ../../../examples/effects.sld}}
```

It prints:

```text
{{#include ../../../examples/effects.out}}
```

A callback can use fewer effects than its caller has permission to perform.
This function adds output around an action while preserving the action's row:

```scheme
(: announce (All (A e) (-> (-> A ! e) A ! console e)))
(define (announce action)
  (write-line "calling")
  (action))
```

The call to `action` uses `e`, which fits the surrounding `console e` for any
substitution of `e`. Extra permissions do not authorize effects absent from the
context, and unrelated quantified tails are not interchangeable. Function-type
equality still compares complete rows; this inclusion rule applies when calling.
