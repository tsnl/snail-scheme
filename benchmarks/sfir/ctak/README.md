# CTAK

`main.sfir` ports the complete upstream `ctak` and `ctak-aux` algorithm.
The canonical input remains one invocation with `(32, 16, 8)`, with result `9`.
The benchmark driver hides all three arguments separately and checks the final
integer through `spec.json`. The original Chez source and input are unchanged.

The original captures the active return context before evaluating each operand.
`Continuation` makes those contexts explicit: return the result, finish the first
operand, finish the second, or finish the third. Each frame is immutable and keeps
its enclosing context reachable. A capture shares that context. Invoking it tail
calls the saved computation; no discarded caller executes afterward. The outer
capture inside a recursive call has the same return context as the supplied
continuation. This fact is specific to this complete workload, not an
implementation of general Scheme `call/cc`.

The adapted Chez control uses the same immutable records and state transitions.
The Rust reference already uses these contexts behind `Rc`, with an explicit
transition loop. SFIR uses mutually tail-recursive functions and WasmGC ownership.
The numerical domain is `I64`; every canonical intermediate fits that domain.
These representation and control differences must remain visible in comparisons.

`observe.sfir` adds diagnostic event calls for source calls, captures and
invocations. `verify.mjs OBSERVE_WASM` compares every event with
`chez-observe.scm`, which retains actual `call/cc` and explicitly chooses the
same left-to-right operand order permitted by the source. Its four checks cover
the base case and all three recursive operands. They supplement the full canonical
run; they do not replace it. The `(10, 6, 3)` trace contains 497 calls, 497 captures
and 373 invocations, and returns 4. No event calls occur in `main.sfir`.

Both optimized SFIR on V8 and the original/adapted Chez controls have passed the
complete canonical predicate. Native execution remains to be checked by the
frozen corpus runner. These concurrent validation runs are not clean timing data.

The simplify review so far is local because the independent explainer slot was
unavailable. It retained the exhaustive `resume` dispatch as one atomic transition,
despite exceeding the ten-line target. Replacing the contexts with an ordinary
direct TAK call would conceal the source's continuation semantics and was rejected.
An independent explanation remains required before landing.
