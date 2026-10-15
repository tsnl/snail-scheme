# Strict scalar visibility and completed global initialization

Two general compiler changes expose facts already established by the strict
language. The first forwards a binding's direct scalar literal while retaining
its readiness check. The second removes a global readiness check only when the
global's complete initialization precedes the function's owned creation site.
Neither change depends on benchmark names, source constants, argument values,
or a convention that workers run after `main`.

The unchanged full `bv2string` workload demonstrates their distinct generated
code effects. Scalar forwarding lets V8 replace the RNG's constant-modulus
division with signed bias/mask arithmetic. Completed-global facts remove four
readiness loads from each decoder loop. This report contains correctness and
code diagnostics; it contains **no clean timing results**. Durations embedded
in diagnostic records must not be used as performance samples.

## Separate changes and exact inputs

| Variant | Compiler commit | Optimized Wasm SHA-256 |
| --- | --- | --- |
| Baseline | `f32024bf6be9ab434b1581d04624b32d5b43c31f` | `c9ba1e18d65ead5db6cc005d9486e7275c14f9e8c91875edaa68e2ae59d7b1d6` |
| Scalar literals | `eb0f8544cd48bf22417fbb287c6f4d2a6042db70` | `bc2f5942886883a5f4c0c5398304de896db90ad6059ee29dd73ee6b1d3357742` |
| Scalar literals and global readiness | `d8ee1f4d91fe1eebabea5eb983d47ad8ed4bb0e6` | `632f53687dca8d70668832e76e13ac3d0ab2933ecdcfb1a6331b7f8723801178` |

All three use the same complete source, 100 iterations, 1,000 stress roundtrips,
maximum size 1,000 and expected failure count zero. The successful exported
predicate is `1`. RNG resets, sanity cases, conversions, comparison and failure
handling are unchanged. The source SHA-256 is
`f67ffdc685fed6a7c33e1519376b0f5eb56590ce7c1d7f84552af1f755f9618c`;
the input specification is
`1ebfaf3ba6cbe8ab5622bdcc12fa699a6c4e9e0ec078ba290d93ad4e50da1efa`;
the clean host is
`7a966858ab02cc531bb55dd93c213c8405e517d9608fb8adc506b7dc90e44c7a`.
They are copied from the frozen preparation used by the
[original diagnostics](../2026-10-14-strict-bv2string-diagnostics/README.md).
The baseline rebuild reproduces that report's exact once-optimized V8 module.
All production builds retain mandatory Binaryen. These artifacts do not use
the distinct, twice-optimized native input from that earlier experiment.

## Observed code effects

| Static optimized-WAT observation | Baseline | Scalar literals | Plus readiness |
| --- | ---: | ---: | ---: |
| Whole-module readiness `global.get` | 63 | 63 | 1 |
| Decoder function59 readiness `global.get` | 4 | 4 | 0 |
| Decoder function67 readiness `global.get` | 4 | 4 | 0 |
| Whole RNG function89 readiness `global.get` | 10 | 10 | 0 |
| Whole RNG function89 `struct.get` | 79 | 44 | 44 |
| Whole RNG function89 `i64.const 524288` | 0 | 11 | 11 |

The one remaining module readiness load is in the exported entry. Decoder
payload globals, nullable-reference checks, input byte checks, and the mutable
RNG seed remain. These are static instruction-site counts, not executed request
totals or hardware counters. In particular, the canonical small-bound branch
of function89 already had **zero global readiness checks** in the baseline.
Its whole-function reduction must not be assigned to that hot branch.

Default-tiering V8 code dumps separately establish the arithmetic effect:

| Variant | Binary index for function89 | TurboFan canonical branch | `idivq` offsets |
| --- | ---: | --- | --- |
| Baseline | 21 | 0x777–0x806 | 0x7cb, 0x7fc |
| Scalar literals | 21 | 0x7c7–0x83d | 0x837 |
| Plus readiness | 20 | 0x7ae–0x824 | 0x81e |

Each index is resolved independently from its module's name section. The
scalar variants use a signed remainder sequence with mask `0x7ffff` for
modulus 524288. The general bound `n` still requires a division. Division by
eight was already signed shift/bias arithmetic in the baseline. The source
caller's common byte bound 128 is still hidden across its first-class closure
call; this change adds no bound-specific specialization.

The baseline machine dump is retained from the exact original diagnostic
module; the scalar and combined dumps are fresh full-count diagnostic runs.
All three also have separate full-count validation records: result `1`, 200
opacity calls, zero setup opacity calls, and no diagnostic output. Code dumps
and opacity counters affect execution and supply no clean timing evidence.

## Correctness and review

The [review notes](review.md) record the entry proof and an independent focused
`simplify` explanation/debate. The implementation reuses literal emission and
source-site identity. It adds no arithmetic evaluator, alias solver, call-graph
analysis, flow-merge machinery, or source-language transformation. Typeclass
and overload resolution remain in their existing passes. Explicit `Ref`
contents remain mutable storage.

Validation passed:

- `make test` and `make check`, including the global-prefix unit test.
- 48 focused strict contracts on raw and production-optimized Wasm, then the
  additional creation-owner regression on both forms. These cover forward
  reads, recursion, direct and escaping closures, captured aliases, mutations,
  multiple activations, specialization, overloads and typeclasses.
- All 22 strict external-boundary contracts, including actual separately
  compiled Wasm provider linking and Node execution. An early callback retains
  its effect-before-trap order; exports before/during `main`, failed `main`,
  repeated `main`, and reentrant `main` remain guarded.
- All 1,112,064 Unicode scalars through encode/decode on raw Wasm, optimized
  Wasm and native; the 10,000-byte literal and located 10,001-byte rejection;
  the native literal check with collection on every allocation.
- Eight actual Rust-linked Node text-I/O executions, covering four fixtures
  on raw and optimized Wasm.
- The exact full-count workload on each of the three frozen optimized modules.
  Rebuilding the final committed compiler reproduces the combined module
  byte for byte.

The archive retains source/input/host snapshots, all three Wasm modules and
their raw/optimized WAT, machine output and excerpts, compiler changes,
test records and tool identities. `manifest.json` identifies every archived
file. All 334 file hashes passed after extraction, followed by three successful
relocated full-count checks using the same bounded process supervision.
`replay-check.json` retains those results and process-group cleanup records.
To repeat the functional check, extract `artifacts.tar.xz` into a fresh directory
and run `python3 replay.py --root EXTRACTED --output NEW-OUTPUT`. The archived
Node path is pinned; `tools.json` records its identity.

The planned [three-way V8 comparison](timing-plan.md) uses these exact snapshots
and remains gated on the coordinated quiet-window release. Plan verification
checks all identities, all six permutations, sample counts, and the adapted
result labels without starting a benchmark process.
