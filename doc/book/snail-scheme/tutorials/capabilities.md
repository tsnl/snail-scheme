# Capabilities

`examples/capabilities.scm`:

```scheme
{{#include ../../../../examples/capabilities.scm}}
```

It prints:

```text
{{#include ../../../../examples/capabilities.out}}
```

`total-cost` writes to the port it is given and to no other, so its caller
decides where the lines go: `main` hands it its own port, from the target,
or one of the program's making that keeps nothing.

A callback does what it was made with. This function adds output around
an action:

```scheme
(define (announce (out OutputPort) (action (Fn → A))) (→ A) (∀ (A))
  (write-line out "calling")
  (action))
```

`announce` writes to the port it is given. What the call of `action` does
is not in `announce`'s signature or in `action`'s type: a closure that
captured a port writes to it, and one that captured none reaches nothing
of the host's.
[Capabilities](../capabilities.md) covers this in full, and
[suspension](../suspension.md) how a computation stops and resumes.
