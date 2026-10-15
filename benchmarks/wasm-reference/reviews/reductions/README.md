# Rust summation review

The integer and floating workers directly implement descending summation with
two scalar variables. Each invocation includes zero and resets its accumulator.
The canonical inputs therefore require 2,000,200,000 integer additions and
500,000,500 floating additions at the algorithm level.

The fresh independent explanation and subsequent informed critique found no
required source change. [review.json](review.json) records the model, source
comparison, exact identities, limits and existing execution evidence. This
closes the bounded review of `sum.rs` and `sumfp.rs`; the other workload cohorts
and general suite driver still need their own reviews before landing PR105.

Hash-verified emitted Wasm retains both repetition and descending reduction
loops. The [integer excerpt](sum.wat.txt) also shows the cost of its per-step
optimizer barrier: accumulator loads and stores on every iteration. The
[floating excerpt](sumfp.wat.txt) keeps the accumulator in a local and preserves
the ordered addition/decrement loop. Both drivers also obscure each invocation's
input and result. These are artifact observations, not an isolated measurement
of barrier overhead or an inspection of V8's final machine code.

The supported comparisons use the pinned positive repetition counts and finite
numeric inputs. Zero repetitions differ between the Rust and original Scheme
harnesses. NaN, floating counters too large to decrement, signed64 overflow and
Scheme's wider numeric tower are outside the claimed equivalence. Input parsing
precedes timing; repetition, opacity and the final predicate are timed.

Existing canonical and small positive/negative records remain valid because no
implementation changed. This review ran no benchmark guests and adds no timing
samples. It leaves stronger claims about V8 machine-code retention unproved.
