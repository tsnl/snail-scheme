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

The frozen corpus runner passed the complete canonical predicate on SFIR/V8,
SFIR/native64, original/adapted Chez, and Rust Wasm/native. That native preparation
optimized an already optimized module again, so its program bytes differ from
V8's input; it establishes correctness, not module parity. The runner is correcting
that preparation separately. These validation runs are not clean timing data.

The focused simplify review used a fresh explanation without repository access,
followed by a critique of the closed-program invariant. Each incoming continuation
is the active return context because every receiver calls `ctak-aux` in tail
position. The recursive branch shadows its incoming handle with another capture
of that same context; diagnostics retain the capture event, while the measured
code shares the immutable context. Some shadowed handles are never invoked.
Neither source nor diagnostics compares handle identities. The review retained
the exhaustive `resume` dispatch as one atomic transition, despite exceeding the
ten-line target. Replacing it with direct TAK would remove the required control
operations. A caller with non-tail work, mutable frames, escaping continuations,
or observable handle identities would require a new proof.
