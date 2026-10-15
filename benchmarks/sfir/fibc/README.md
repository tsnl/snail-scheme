# FIBC

`main.sfir` ports the complete upstream `succ`, `pred`, `addc` and `fibc` algorithm.
The canonical input remains ten evaluations of `fibc(30)`, with final result
`832040`. The driver separately hides the input and identity continuation. The
original Chez source, count, input and numeric correctness predicate are unchanged.

`Continuation` records the active return context for the first or second recursive
operand. Capturing shares an immutable frame; invoking it tail calls the saved
computation. After the second operand returns, `addc` still performs one successor
and predecessor transition for each unit of its second argument. No arithmetic
sum replaces that loop. The frames describe the complete workload's continuation
uses, rather than implementing general Scheme `call/cc`.

The adapted Chez control uses the same immutable records. The Rust reference uses
the same operand contexts behind `Rc` with a transition loop; its Peano successor
has a `black_box` barrier. SFIR uses mutually tail-recursive functions and WasmGC
ownership. All canonical numbers fit `I64`. These representation and barrier
differences remain relevant when comparing performance.

`observe.sfir` adds events for calls, captures, invocations and Peano steps.
`verify.mjs OBSERVE_WASM` compares every event against actual `call/cc` in
`chez-observe.scm`, with the same explicitly chosen left-to-right operand order.
The cases cover both base cases and complete recursive traces. At input 10 the
trace must contain 177 calls, 176 captures, 177 invocations and 130 Peano steps.
These small observations supplement the full canonical run. The measured
`main.sfir` contains no event calls.

Optimized SFIR on V8 and both original/adapted Chez controls have passed the full
canonical predicate. Native execution remains to be checked by the frozen corpus
runner. Concurrent validation observations are not clean timing data.

The simplify review so far is local because the independent explainer slot was
unavailable. The saved input in the first frame is necessary to evaluate the
second operand, and the saved first result in the second frame is necessary for
Peano addition. Replacing `addc` with scalar addition would change the benchmark's
work and was rejected. An independent explanation remains required before landing.
