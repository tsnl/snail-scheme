# FIBC

`main.lofi` ports the complete upstream `succ`, `pred`, `addc` and `fibc` algorithm.
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
has a `black_box` barrier. Lofi uses mutually tail-recursive functions and WasmGC
ownership. All canonical numbers fit `I64`. These representation and barrier
differences remain relevant when comparing performance.

`observe.lofi` adds events for calls, captures, invocations and Peano steps.
`verify.mjs OBSERVE_WASM` compares every event against actual `call/cc` in
`chez-observe.scm`, with the same explicitly chosen left-to-right operand order.
The cases cover both base cases and complete recursive traces. At input 10 the
trace must contain 177 calls, 176 captures, 177 invocations and 130 Peano steps.
These small observations supplement the full canonical run. The measured
`main.lofi` contains no event calls.

The frozen corpus runner passed the complete canonical predicate on Lofi/V8,
Lofi/native64, original/adapted Chez, and Rust Wasm/native. That native preparation
optimized an already optimized module again, so its program bytes differ from
V8's input; it establishes correctness, not module parity. The runner is correcting
that preparation separately. Concurrent validation observations are not clean
timing data.

The focused simplify review used a fresh explanation without repository access
and a critique of the source's exact operations. The first frame retains the
input needed for the second operand, and the second frame retains the first
result needed by `addc`. The zero and predecessor-zero tests stay separate;
the second recursive operand still evaluates `pred(pred(x))`. Each diagnostic
Peano event records one complete addition step, without claiming to count every
standalone predecessor call. The review rejected scalar addition and Fibonacci
memoization because both remove measured work. Immutable frames and tail calls
express the closed continuation uses directly; no general multi-shot machinery
is required for these source programs.
