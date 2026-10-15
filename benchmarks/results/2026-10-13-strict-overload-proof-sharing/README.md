# Repeated overload proofs during compilation

A linear chain of local additions caused exponential duplication of concrete
type obligations. Inference stored each initializer's obligations in its binding
scheme, copied them at every read, and appended them at enclosing expressions.
Treating equal complete obligations as one proof removes that duplication.

The probe binds `x0` to 1, then each `xi` to `(+ x(i-1) x(i-1))`, and returns
the final value. These are counts over the final typed entry expression and its
descendants, excluding library declaration templates:

| Additions | Expression nodes | Before: obligation entries | After: obligation entries |
| --- | ---: | ---: | ---: |
| 2 | 18 | 53 | 19 |
| 4 | 30 | 449 | 37 |
| 6 | 42 | 2,673 | 55 |
| 8 | 54 | 13,961 | 73 |

At eight additions, the entry's own obligation list shrinks from 757 to 1.
The same eight-addition source using `i64-add` instead has 54 expression nodes
and no class obligations in either compiler. Deduplication compares class or
family identity and every type in the constraint, including the result type.

The before compiler is `9f875b3`; the corrected compiler is `e4ff3a8`. Sources,
the read-only counting program, commands and raw output are retained here.
The counting program runs after ordinary inference and does not alter it.
[Before counts](results.json) and [after counts](results-after-e4ff3a8.json)
also contain diagnostic times. Other work was running, so these are not clean
performance measurements. The complete eight-addition build took about 21.0
seconds before and 6.2 seconds after in those diagnostic runs.

Both raw and Binaryen-optimized Wasm are **byte-identical** before and after;
both execute successfully in Node and return 256. The
[artifact comparison](artifact-comparison.json) preserves the exact hashes.
This change removes compiler work and makes no claim about application runtime
performance. Two earlier diagnostic-harness setup failures (a missing import
and a missing trace scope) are retained separately and excluded from the table.

Nine independent semantic probes also pass on `e4ff3a8`: declared abstract
evidence, later result context in both declaration orders, permitted and rejected
overlap uses, independent returned captures, intentional Default sharing,
observable effects before a Default trap, and an unused nested body invalidated
by a later vector write. [Cases](cases.json), source fixtures, and
[complete outcomes](independent-contracts.json) preserve these checks.

The checked-in `overload-proof-sharing` contract exercises a longer chain through
actual raw and optimized Wasm execution. Tool paths and versions are those in the
[array1 environment record](../2026-10-13-strict-vector-array1/environment.json).
To repeat the count at either compiler checkout, use its recorded Chibi and run
`inspect.scm` with that checkout's root and one of the retained probe sources.
