# Complete simplex preparation

The full original million-invocation simplex workload passes on raw Wasm,
optimized Wasm, original Chez and source-matched adapted Chez. **This checkpoint
has no clean timing observations.** Compiler source remains
`a4030ce190058db3e9d64f6942401b5fa38dbd58`; the final preparation driver is
`d92e8be` above source checkpoint `f417571`. The parent subsequently completed
independent simplify review and repeated preparation on stack compiler `efbb151`;
the original freeze remains intact.

Every invocation constructs the original 6-by-5 F64 tableau and executes the
two-phase simplex algorithm with constraint counts 2:1:1. The complete input file
is retained: 1,000,000, 740.0, and `(#(4 1 3 2) #(0 5 7 6))`. Upstream `test`
ignores 740.0, but the original hiding call still executes each time; raw and
optimized canonical validation each confirm 1,000,000 calls. The final predicate
checks both entire index vectors once after all repetitions. It does not inspect
intermediate results or all tableau elements.

The [preparation record](prepared.json) freezes sources, inputs, binaries, tools
and commands. Each case contains the untouched upstream source, original kernel,
adapted kernel, exact kernel/complete-program patches and a restoration proof.
The strict and adapted Chez programs contain identical adapted kernel text.
Their wrapper preserves the original result meaning and final predicate.

The original result is false for infeasible, true for unbounded, or a two-element
list of mutable I64 vectors for solved. A closed nominal type expresses these
three cases. The solved variant preserves the two list nodes and adds a wrapper;
the adapted Chez control uses allocated tagged vectors and unwraps the result
only for the original `equal?` predicate. Strict loads the full expected value
before its workload clock and returns a scalar acceptance flag to the host.

Ten mutable binding sites become explicit Ref cells: six per simplex invocation,
two on every ratio-selection call, and two whenever its tie branch is entered.
All original reads, writes and scopes remain after renaming one shadowing
parameter. This is a source representation count, not a dynamic allocation
measurement: original Chez may itself box captured mutable bindings, and the
optimizers may eliminate storage. Typed source overloads provide unary F64
negation/reciprocal, three/four-argument I64 addition and sign predicates. Strict
negation preserves signed zero. Empty effect branches produce Unit, and the
original explicit complaint becomes a trap. No compiler capability was added.

[Correctness evidence](correctness-summary.json) records canonical checks at
counts 1, 2 and 1,000,000 on all four systems, plus 176 separate probe outcomes:
12 complete outputs, 16 changed complete expectations, 11 final-predicate cases
and five original guard failures, each across four systems. Twelve original-Chez
extractions establish the complete expected outputs. Every final F64 cell and
ordered row/column/value store is compared exactly, including the sign of zero;
replaying the stores reconstructs the final tableau. The canonical diagnostic
invocation performs 104 matrix stores. Diagnostic observations have separate
modules and scalar exports; they do not alter canonical module liveness or work.

The small cases cover tied and duplicate constraints, both phases, infeasibility,
unboundedness before/after a pivot and a non-improving objective. The independent
rational oracle enumerates boundary intersections in the nonnegative orthant
and normalized recession directions. Returned solved bases must partition all
variables, yield feasible original variables and attain the independent optimum.
The canonical optimum is 681/40 (17.025).

There is one preserved upstream discrepancy. The tableau
`#(#(0.0 1.0) #(2.0 -1.0) #(0.0 0.0))` with counts 0:0:1 represents maximizing x
subject to x = 2 and x >= 0, whose bounded optimum is 2. The unmodified original
Chez kernel returns true, its unbounded marker. The exact counterexample source,
compiled program and execution are archived under `supplementary/focused-history/
unmodified-equality/`. The source guards permit it: all counts are nonnegative,
rows equal their sum plus two, and the RHS is nonnegative. Constraints are ordered
less-equal, greater-equal, equality; negated constraint coefficients and the
positive objective convention agree with the source pivot tests and other cases.
No stated dimension restriction excludes this one-variable/one-constraint case.
Phase one removes the sole candidate, but the next selection still reads l1[0]
when the active length is zero. Eleven cases agree mathematically; all twelve
match original source behavior. The report does not label this discrepancy a
mathematical correctness pass or repair it in the adapted kernel.

[Retention inspection](retention-audit.json) records the exact canonical optimized
layouts and instruction sites. It retains fresh F64 tableau arrays, mutable
index/flag work arrays, Ref mutation, coefficient selection, ratio/tie traversal,
both pivot phases, matrix arithmetic/stores, basis exchange, both result list
nodes and vector fields, repetition and complete final comparison. Canonical
exports are only `bench` and `main`; there are no trace observers. The typed
variadic vector constructor also retains temporary F64 lists and copying work,
which native Chez vector construction need not perform. Binding/closure layout
simplifications are legal; these observations are not equal-allocation or
machine-code collector claims.

All 52 compiler files match the frozen base, and all 23 earlier specifications
and generated strict sources remain byte-identical. See [compiler identity](compiler-identity.json), [prior-port regression](prior-port-regression.json),
[environment](environment.json) and [final verification](freeze-verification.json).
The pinned toolchain is Chibi 0.12, Node 24.19.0, Binaryen 132 and Chez 10.4.1.
Validation is sequential with default V8; durations embedded in correctness
records are not clean performance samples.

[Preparation history](preparation-history.json) retains the original unexpected
LP disagreement and a corrected probe-host path omission. The latter occurred
after all canonical runs had passed; the final driver repeats complete
preparation with the proper copied host. The history also notes minor corrected
read-only inspection/command errors. No failure has been converted into a speedup
or omitted from claimed coverage.

[Archive replay](replay-check.json) verifies the regular-file payload and executes
four bounded checks using its restored canonical modules and Chez programs.
Restore without executing a workload:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-simplex-replay \
  --report benchmarks/results/2026-10-13-strict-simplex
```

The cohesive module is `simplex_port.py`, which owns the exact source adaptation
and its complete-output/rational-oracle diagnostic contract. `measure.py`
coordinates preparation in the existing harness. A fresh Sol 6.1 explainer
received the [behavioral brief](simplify-behavioral-brief.md) without file access;
the parent compared its model with the implementation and challenged the read,
arithmetic, hiding-call and restoration boundaries. The review retained the
module: elimination, decoding and complete basis validation are useful complete
operations even where they exceed the usual ten-line target.

The [parent review](parent-review/review.json) records the findings. The parent
restored and verified all 704 original archive files and executed four bounded
artifact checks, then rebuilt the complete preparation on compiler `efbb151`.
All canonical and supplemental checks passed again. Benchmark sources, input,
both Chez sources and complete expected outputs remain byte-identical. This
[new preparation](parent-review/prepared.json) has its own archive and manifest
under `parent-review/`; the same replay command accepts that directory as its
report argument. Neither preparation contains clean timing samples.

The optimized repeat function retains the opaque `hide_f64` call inside every
iteration, before fresh tableau construction; canonical validation observes
one million calls. The arithmetic evidence covers these fixed inputs and
fixtures. Their rational input coefficients are integers or dyadic fractions;
the algorithm's original F64 epsilon is still `0.000001`. Signed-zero checks
cover the observed stores and final tableau. This is not an arbitrary-input
equivalence proof or a claim about native allocations.
