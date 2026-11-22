# Capabilities

`examples/capabilities.sld`:

```scheme
{{#include ../../../../examples/capabilities.sld}}
```

It prints:

```text
{{#include ../../../../examples/capabilities.out}}
```

`total-cost` writes to the port it is given and to no other, so its caller
decides where the lines go: `main` hands it its own port, from the target,
or one of the program's making that keeps nothing.

A callback can perform less than its caller is allowed to. This function
adds output around an action while preserving the action's row:

```scheme
(define (announce (out OutputPort) (action (Fn → A ! e))) (→ A) (! mut e) (∀ (A e))
  (write-line out "calling")
  (action))
```

The call to `action` uses `e`, which fits the surrounding `mut e` for any
substitution of `e`. Unrelated quantified tails are not interchangeable.
Function-type equality still compares complete rows; this inclusion rule
applies when calling.
[Capabilities and rows](../effects.md) covers both in full, and
[suspension](../suspension.md) how a computation stops and resumes.
