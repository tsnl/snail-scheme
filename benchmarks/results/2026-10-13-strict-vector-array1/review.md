# Array1 measurement review

A fresh explainer received only the workload's behavioral contract and did not
inspect repository files, implementation, or diffs. One explanation and debate
pass established the model before the driver extension was written.

The outer harness invokes `go` once. `go` repeats the original increasing fill
and decreasing copy 500 times on vectors of 1,000,000 elements. The two inputs
come from runtime imports before timing; the two scalar identity calls at the
original hide sites remain timed. The port supplies explicit zero fills and an
I64 initial result. Its equivalence claim covers the original positive repeat
count; zero or negative repeat counts return typed zero instead of upstream's
empty list.

Small raw and optimized behavior probes precede timing. The complete discarded
pair validates the original full workload on both systems before retained
samples, so an additional full correctness run is unnecessary. Three retained
pairs alternate order: the retained set has a 2:1 first-system balance, and all
four pairs including the discarded one have a 2:2 balance. Diagnostic V8 code
printing stays outside the clean batch.

The final length alone cannot show whether either allocation or element loop
survived. The report must inspect the exact compiled artifacts and qualify its
execution claims by the available Wasm and V8 evidence. Source-level allocation
counts are not dynamic allocation measurements. Elimination must be reported
without changing the source algorithm to add observability.

The implementation extends the existing driver with one explicit input case,
one checked source adaptation, and a short list of validation inputs. A new
generic harness would obscure the two distinct repeat counts. All eleven older
kernel sources and specifications remain byte-for-byte unchanged. Both new
helpers stay below the project's ten-line logic target; the pre-existing driver
operations retain their cohesive structure.
