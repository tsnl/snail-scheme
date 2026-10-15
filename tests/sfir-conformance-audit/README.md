These fixtures check lexical class evidence, concrete declared requirements,
recursive captures and the value restriction. The runner uses the existing SFIR
integration harness and checks every listed source on raw and optimized Wasm:

```sh
python3 tests/sfir-conformance-audit/check.py --output /tmp/sfir-conformance
```

The [2026-10-15 audit index](evidence/20261015-book-contracts.json) records a
separate executable audit against the SFIR book. Its
[source and log bundle](evidence/20261015-book-contracts.tar.gz) preserves
pre-fix failures, final outcomes, commands, source hashes, build provenance and
Wasm guests. The JSON index records the bundle's SHA-256 checksum.

| Contract | Executed evidence |
| --- | --- |
| Class proof scopes and value restriction | 20 focused contracts; host tests, 83 surface cases, 14 existing polymorphism cases and 20 existing class/qualified-overload cases also pass. |
| Recursive groups and captured monotypes | 12 existing inference rejections and four raw/optimized/native cases, plus focused captured-hole and private-`All` cases. |
| Call ordering | Fixed/rest arguments run left to right before the operator; argument/operator traps preserve prior effects. Raw/optimized execution and native order checks pass. |
| Full `Any` identity | Scalar, nominal/phantom, empty/nested container, reference and function domain/result/rest distinctions; shared aliases and reexported identity. Representative rejections and alias mutation also execute natively. |
| Instance coherence | Duplicate tuple rejection, no guessing unknown parameters and one initializer through diamond reexports. The diamond executes on raw/optimized Wasm and native. |
| Proper tail recursion | 1,000,000 iterations on raw/optimized Wasm and native. Optimized code retains alternating two- and twelve-argument indirect tail calls, mixed I64/F64 arguments and managed state. Native also passes 10,000 iterations with collection at every allocation. |

Native checks execute the programs and compare the optimized native guest bytes
with the optimized Wasm guests. These are correctness checks, not timings.
Earlier tail probes were optimized into self-calls; the index identifies the
final retained-arity probe as the evidence for alternating arity.

This is executable coverage of selected contracts, not a proof of all programs
or complete language coverage. Numeric default widths, runtime arithmetic
overflow and the full benchmark corpus were outside this audit. The archive
also distinguishes corrected fixture/harness mistakes from compiler failures.
Large native build products remain in the original evidence directory rather
than in the bundle.
