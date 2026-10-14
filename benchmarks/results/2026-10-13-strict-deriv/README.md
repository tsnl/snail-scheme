# Complete deriv preparation

The original ten-million-invocation derivative workload passes in raw Wasm,
optimized Wasm, original Chez and source-matched adapted Chez. **No clean timing
observations have been collected.** Source checkpoint `fe14121` adds the port;
all 52 frozen compiler/build files match combined compiler
`7ff18c01f4fc5407826e4815b30394ed437b2440`. Preparation ran from checkout
`a92cf79` with the exact adapter/driver/host bytes subsequently committed as
`fe14121`; the original preparation metadata is retained unchanged.

Every invocation differentiates `(+ (* 3 x x) (* a x x) (* b x) 5)`. The full
input and expected expression stay intact. The derivative body is preserved
through exact operation renaming. Its deliberately incorrect quotient rule
remains incorrect, and operands after a quotient's denominator remain ignored,
including improper tails. No compiler or frontend capability was added.

The closed datum contains the seven source symbols, I64 integers, booleans,
empty and a two-edge pair. Each source pair has one corresponding nominal pair
node; an operation-only AST would erase list spines and change the allocation
work. Fixed three/four-argument list helpers allocate those spines directly.
Operators and derivative zero/one are shared constants initialized before
timing. Product results embed the original product and operands; quotient
results reuse the original numerator and denominator. The supported datum
domain excludes arbitrary symbols, strings, vectors and non-I64 numbers.

The input and expected datum arrive as runtime scalar prefix streams and are
constructed before timing. The repeat loop starts with false, retains only its
current result, and compares the entire final expression once inside the timer.
The untouched original Chez program remains one control. The adapted control
contains the exact strict derivative kernel, with tagged-vector counterparts
for its closed nodes. Input/expected conversion occurs before timing. Its false
initializer and structural predicate use the corresponding representation.
The whole-source restoration proof accounts for these four harness edits and
all helpers. Native Chez pairs, tagged vectors and WasmGC structs have different
physical layouts and allocation costs.

[Correctness records](correctness-summary.json) include twelve canonical runs
at counts 1, 2 and 10,000,000 across the four systems. Separate programs execute
164 checks: nineteen complete literal derivative cases, seven altered expected
trees, ten original failures and five repeat-loop boundaries, each across four
systems. Thirty-eight original/adapted Chez extractions compare actual complete
expressions with the literal oracles. Two further Chez programs each pass nine
identity assertions for original product/operand/denominator sharing and fresh
result spines. Negative and zero repeats retain false and skip even a malformed
derivative input. The host's expected hiding-call calculation handles those
nonpositive counts without JavaScript's `0` versus `-0` distinction.

The [retention audit](retention-audit.json) inspects the exact 5,759-byte
optimized canonical module, whose only exports are `bench` and `main`.
`function47` calls the Boolean import and `deriv` inside every positive loop
iteration, then tail-calls itself with the replacement result. Complete equality
runs after that loop. The pair subtype retains both reference fields, and
product/term constructors store existing input references directly.

Separate observer runs complete 49, 98 and 490,000,000 pair constructor
instructions at counts 1, 2 and 10,000,000 after subtracting setup. The full run
enters the derivative 130,000,000 times and the repeat function 10,000,001 times.
Complete equality enters 121 times regardless of repeat count. Erasing the
allocation-free counter observers recovers every original Wasm function.
These counts describe completed instructions in the diagnostic module, not
unmodified-engine allocator events or performance.

Default-tier V8 dumps from the unchanged canonical binary independently retain
the per-iteration import, derivative call and tail jump. TurboFan's product-term
code has three 40-byte bump-allocation paths and stores both pair edges.
Those surviving native paths support the retained-work conclusion; the audit
does not infer an exact physical allocation total from them.

Managed references are still rejected by the concrete extern contract. The
Boolean import preserves the original number of hiding sites, but it does not
hide the actual datum identity. Runtime input construction and inspected code
are the evidence for this preparation. Another optimizer may legally discard
earlier unobserved derivatives. A nominal value-returning identity import is a
separate proposed capability, not an implemented part of the port.

The [compiler identity](compiler-identity.json) and [prior-port comparison](prior-port-regression.json)
confirm that production compiler files and all 24 previous specifications and
generated strict sources are unchanged. `make test` and `make check` pass.
[Preparation history](preparation-history.json) retains the first compile's
unsupported wildcard-pattern rejection. The adapter was corrected to emit the
language's required exhaustive constructor arms; that failure was not omitted
or converted into a benchmark observation.

The [independent simplify review](simplify-review.md) records a fresh no-history
Sol 6.1 max behavioral explanation without file access, followed by debate and
parent-owned source inspection. The complete parser, exhaustive source/schema
dispatch and integration checks remain coherent operations where they exceed
the ten-line target. No broader backend or frontend refactoring was needed.

The regular-file archive includes all sources, commands, raw/optimized binaries,
Chez controls, complete probes, the failed attempt, observers, native dumps and
diagnostic drivers. Restore and verify it without executing workloads:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-deriv-replay \
  --report benchmarks/results/2026-10-13-strict-deriv
```

The [restore check](replay-check.json) verifies all 393 archived files and runs
the four restored programs at count two, with all result checks passing.

Rebuild the full preparation with the pinned tools:

```sh
python3 benchmarks/strict-suite/measure.py prepare --output build/strict-deriv \
  --benchmarks deriv --compiler-basis 7ff18c0
```

Durations embedded in validation and diagnostic records are not clean
performance samples. Measurement remains a separate coordinated step.
