# Numeric VM instructions

Fibonacci previously called the general Scheme procedure protocol for every
`+`, `-`, and `<`: return-frame creation, callable classification, Rust primitive
dispatch, result publication, and frame restoration. Its numbers already fit
unboxed fixnums. Allocation was not the bottleneck.

The lowerer now emits ordinary VM instructions `add`, `subtract`, `numeric-equal`,
`less`, `less-equal`, `greater`, and `greater-equal` for binary calls to the
corresponding core builtins. This extends the existing instruction set; there
is no separate optimizer or type-inference pass.

## Binding and stack contract

Lowering uses resolved binding identity. Before choosing an instruction, it
checks that no expanded program or linked library initializer or assignment
writes that builtin, including writes inside nested procedures. Renamed imports
retain their identity. Shadowed bindings, rebound builtins, procedure aliases,
computed operators, and other arities keep the ordinary call protocol.

Both operands evaluate left to right and pass the existing single-value check.
The instruction reads stack depths `s-1` and `s`, publishes a single result in
`a`, pops two operands, and branches to its known successor. It leaves the
current closure and frame unchanged. Tail position uses the enclosing return
instruction. Continuations captured while evaluating operands retain pending
arguments and the numeric instruction's continuation in their stack snapshot.

Each instruction carries the builtin's global index for runtime fallback;
no Rust enum discriminant or boxed-object layout is exposed to LLVM.

## Checked fast path and runtime fallback

The handler checks both low-bit fixnum tags. Addition and subtraction decode
signed31 operands, compute exactly in signed32, and check the signed31 result
range before tagging. Signed comparisons can compare tagged fixnums directly,
since tagging preserves their order. Boolean words match the runtime ABI.

A non-fixnum operand or result outside the fixnum range calls `snail_rt_numeric`.
This service invokes the existing numeric primitive directly and publishes its
result; it does not create a Scheme call frame or enter general callable
dispatch. Boxed integers, floating-point operations, integer overflow errors,
and invalid operand errors therefore retain the runtime's existing semantics.

Fallback polls before borrowing arguments if the operation may allocate. The
active stack, current closure `c`, and accumulator `a` are already roots.
Allocation inside the Rust callable never collects. The new result is published
before removing operands, with no intervening safepoint.

Rust's `Arguments` is a borrowed view over the unchanged physical slice:
source index `i` maps to `len - 1 - i`; iteration walks the same source order.
There is no argument reversal or per-call argument vector. Allocation effects
are classified once, and diagnostic names are looked up only on error paths.

## Native Fibonacci measurement

The [raw report](../benchmarks/results/2026-10-09-numeric-instructions.json)
contains all samples, order, commands, flags, source/artifact hashes, and tools.
Each participant warms once, then executes five rotating rounds of 64 repetitions
on CPU2. Printed checksums are checked every time. Internal timers exclude
compilation, process startup, and printing. Snail uses native32 release Rust and
LLVM O2 without LTO. Chibi and Chez are native64; Chez uses safe optimization
level 2. Chibi's clock has millisecond resolution; the others are monotonic.

| Configuration | Median seconds |
| --- | ---: |
| Baseline `e570708` | 1.488415 |
| Current Rust runtime, baseline LLVM | 1.426669 |
| Current Rust runtime, numeric VM instructions | 0.449323 |
| Chibi 0.12 | 0.461000 |
| Chez 10.4.1 | 0.028525 |

The combined change is 3.31× faster, taking 0.975× Chibi's time and 15.75×
Chez's. The small lead over Chibi is best treated as parity. A separate
128-repetition hardware-counter probe drops native instructions from 102.57
billion to 29.47 billion; counters include startup. There are no IIFE, heap,
inference, or LTO changes in this comparison.

To reproduce the ablation, emit `benchmarks/cpu.scm` from a worktree at
`e570708` with `snail-compile`. Link that unchanged LLVM against both its original
runtime and the current runtime. Separately emit and link current LLVM. For each
build set `SNAIL_LLVM_IR` to the absolute IR path and run:

```sh
cargo build --offline --release -p snail-runner --target i686-unknown-linux-musl
```

Copy each executable before the next build. Run each with `taskset -c 2` and
argument `64`, rotating order. The existing `benchmarks/chibi` and
`benchmarks/run` adapters supply the Chibi and compiled Chez workloads; the
recorded command arrays identify the exact artifacts used for this run.

## Validation and scope

Scheme unit tests check binding identity, shadowing, arity, and writes nested
inside closures. Native and WASI integration tests compare instructions against
dynamic calls across sign and fixnum boundaries, boxed integers, floats, NaN,
infinities, rebinding, operand effects, and reusable continuations. GC stress
covers fallback while a captured object is reachable only through the current
closure. Rust unit tests check argument order and fallback root/frame invariants.
The existing bootstrap, continuation, error, and CLI suites also pass.

The simplify review kept each numeric handler's checks, result publication,
and fallback visible as one atomic VM transition. That multi-block constructor
and exhaustive tests exceed the ten-line target deliberately. No frontend
structure changed. A separate Rust-handler/shared-LTO experiment is investigating
whether Rust can supply these same instruction bodies; it is not required by
this implementation.
