# Lofi: 57-workload correctness check, 18 October 2026

Compiler `a2818640e3d6b681bbe5e07e4ecf018c473dd401` was frozen with a clean
source tree after the fixed-arity migration, Wasm-only backend reconciliation
and checked type evidence changes. All 57 canonical workloads were attempted
on Lofi/Wasm and the four control routes. Twelve workloads have no adapted
Chez source; those controls remain unavailable.

Across this primary attempt and the separately recorded follow-ups below,
56 distinct Lofi/Wasm workloads execute successfully. Ack retains its known
stack failure. The primary matrix remains unchanged, including its failed builds.

The [exact results](20261018-checked-types-full57.json) retain every route status.
The [indexed raw archive](20261018-checked-types-full57-records.tar.gz) contains the frozen manifest,
command receipts, exact stdout/stderr, per-case results, build traces and
compiled artifact identities. It excludes generated binaries and toolchain
contents; the manifest records their source/tool identities.

| Route | Passed | Failed | Unavailable |
| --- | ---: | ---: | ---: |
| Lofi Wasm | 54 | 3 | 0 |
| Chez original | 57 | 0 | 0 |
| Chez adapted | 45 | 0 | 12 |
| Rust Wasm | 56 | 1 | 0 |
| Rust native | 57 | 0 | 0 |

## Retained failures

- **simplex** — Lofi Wasm: build-failed.
- **ack** — Lofi Wasm: failed; Rust Wasm: failed.
- **compiler** — Lofi Wasm: build-failed.

Simplex's local two-element `list` function conflicts with the packing macro
imported from `(lofi base)`. The same source fails on baseline compiler `601a6962`;
This missed fixed-arity migration predates the checked-type change.
The correction removes that redundant definition and records its new source hash.

Compiler exhausted its 600-second compilation allowance before producing Wasm.
That establishes no execution result. The original runner leaves
`wasm_validation` as `pending` after a failed build; the table labels these two
routes `build-failed`, and the JSON preserves the original fields unchanged.

Ack retains `Maximum call stack size exceeded` on both Lofi/Wasm and Rust/Wasm.
Its original Chez and Rust/native controls pass. This matches the
[historical Ack failure](20261015-ack-stack.md); no input or stack limit was changed
to replace the result.

All five SLaTeX routes pass their complete 28,500-file output checks, with zero
mismatches or extra files. All 57 source and canonical-input hashes match their
provenance, and post-run frozen-input verification passes. The archive index and
732 terminal command records were checked against their exact stdout/stderr bytes;
successful Lofi builds' raw and optimized artifact hashes also match.

## Separate follow-up

Revision `81bf1e152ea46f25a847518b3f2d0090cd5f5764` changes only Simplex's
redundant constructor and migration provenance. The compiler and other 56
workload sources are unchanged. Simplex passes all five canonical routes in this
fresh snapshot. Its source hash changes from `b3287759…` to `79bc76a5…`;
the archive retains the exact source diff and baseline failure reproduction.

The same follow-up allowed Chibi `-h64M/4G`, an 8 GiB process-group limit, no swap,
a two-CPU quota and 1,800 seconds per compilation. Compiler completed checking
and specialization but exceeded the memory limit during emission. The supervisor
killed the process group after 215.777 seconds. Compiler produced no executable
and its controls were not attempted in this follow-up.

The [follow-up results](20261018-checked-types-followup.json) and
[indexed raw records](20261018-checked-types-followup-records.tar.gz) preserve that
interruption. Child command records left at `started` and the uncompleted
Compiler row remain unchanged; the separate interruption record identifies the
memory-limit failure. Simplex's completed results remain valid. No timing from
this differently constrained run replaces a primary result.

### Compiler with a larger process-group budget

A third, Compiler-only snapshot uses the same revision, inputs, Chibi flags,
CPU quota and per-command timeouts, with a 16 GiB process-group memory limit.
All five canonical routes pass. The Lofi build takes 501.995 seconds and its
validation execution takes 80.898 seconds; these are diagnostic durations,
not clean timing samples or a comparison against the earlier limits.
The supervisor records a 10.9 GiB memory peak and no swap.

The [exact Compiler result](20261018-compiler-memory-check.json) and
[indexed raw archive](20261018-compiler-memory-check-records.tar.gz) retain this
separate success. The original timeout and subsequent 8 GiB memory failure are
not replaced. Reducing host memory for this large static source remains an
explicit [follow-up task](../../../TODO.md#compiler-memory-use).

## Reproduction and scope

The pinned R7RS benchmark inputs are revision
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Preparation freezes the compiler,
benchmark sources, providers, Rust toolchain and locked crate dependencies.
Both Rust wrapper environment variables were unset. Chibi ran with
`-h16M/1G`; Binaryen used one core. The campaign had a two-CPU quota, 4 GiB
memory limit, no swap and a six-hour overall limit. Each compilation had a
600-second limit and each execution a 1,200-second limit.

```sh
env -u RUSTC_WRAPPER -u RUSTC_WORKSPACE_WRAPPER CHIBI=/path/to/chibi-wrapper BINARYEN_CORES=1 \
  /path/to/chibi-wrapper -I bootstrap -I benchmarks benchmarks/lofi/runner.scm prepare \
  --output /tmp/lofi-full57-check --compile-timeout 600 --run-timeout 1200
env -u RUSTC_WRAPPER -u RUSTC_WORKSPACE_WRAPPER CHIBI=/path/to/chibi-wrapper BINARYEN_CORES=1 \
  /path/to/chibi-wrapper -I bootstrap -I benchmarks benchmarks/lofi/runner.scm validate \
  --output /tmp/lofi-full57-check
```

The wrapper and supervisor output are included in the archive. Apply the
stated resource limits externally when reproducing this bounded run.
Passing requires the complete canonical predicate. Rust/native
executes native machine code; there is no Lofi/native backend in this snapshot.

This is correctness evidence. Retained command durations are diagnostic and
provide no new runtime ranking or speedup. The earlier clean full57 timing
campaign remains historical evidence for its own compiler and sources.
The [fresh Siegework build measurements](../../../doc/compilation-performance.md#checked-expression-evidence-18-october-2026)
measure compilation separately.

## Complete matrix

| Case | Lofi Wasm | Chez original | Chez adapted | Rust Wasm | Rust native |
| --- | --- | --- | --- | --- | --- |
| browse | passed | passed | passed | passed | passed |
| deriv | passed | passed | passed | passed | passed |
| destruc | passed | passed | passed | passed | passed |
| diviter | passed | passed | unavailable | passed | passed |
| divrec | passed | passed | unavailable | passed | passed |
| puzzle | passed | passed | passed | passed | passed |
| triangl | passed | passed | passed | passed | passed |
| tak | passed | passed | unavailable | passed | passed |
| takl | passed | passed | unavailable | passed | passed |
| ntakl | passed | passed | unavailable | passed | passed |
| cpstak | passed | passed | unavailable | passed | passed |
| ctak | passed | passed | passed | passed | passed |
| fib | passed | passed | unavailable | passed | passed |
| fibc | passed | passed | passed | passed | passed |
| fibfp | passed | passed | unavailable | passed | passed |
| sum | passed | passed | unavailable | passed | passed |
| sumfp | passed | passed | unavailable | passed | passed |
| fft | passed | passed | passed | passed | passed |
| mbrot | passed | passed | passed | passed | passed |
| mbrotZ | passed | passed | passed | passed | passed |
| nucleic | passed | passed | passed | passed | passed |
| pi | passed | passed | passed | passed | passed |
| pnpoly | passed | passed | passed | passed | passed |
| ray | passed | passed | passed | passed | passed |
| simplex | build-failed | passed | passed | passed | passed |
| ack | failed | passed | unavailable | failed | passed |
| array1 | passed | passed | unavailable | passed | passed |
| string | passed | passed | passed | passed | passed |
| sum1 | passed | passed | passed | passed | passed |
| cat | passed | passed | passed | passed | passed |
| tail | passed | passed | passed | passed | passed |
| wc | passed | passed | passed | passed | passed |
| read1 | passed | passed | passed | passed | passed |
| compiler | build-failed | passed | passed | passed | passed |
| conform | passed | passed | passed | passed | passed |
| dynamic | passed | passed | passed | passed | passed |
| earley | passed | passed | passed | passed | passed |
| graphs | passed | passed | passed | passed | passed |
| lattice | passed | passed | passed | passed | passed |
| matrix | passed | passed | passed | passed | passed |
| maze | passed | passed | passed | passed | passed |
| mazefun | passed | passed | passed | passed | passed |
| nqueens | passed | passed | passed | passed | passed |
| paraffins | passed | passed | passed | passed | passed |
| parsing | passed | passed | passed | passed | passed |
| peval | passed | passed | passed | passed | passed |
| primes | passed | passed | passed | passed | passed |
| quicksort | passed | passed | passed | passed | passed |
| scheme | passed | passed | passed | passed | passed |
| slatex | passed | passed | passed | passed | passed |
| chudnovsky | passed | passed | passed | passed | passed |
| nboyer | passed | passed | passed | passed | passed |
| sboyer | passed | passed | passed | passed | passed |
| gcbench | passed | passed | passed | passed | passed |
| mperm | passed | passed | passed | passed | passed |
| equal | passed | passed | passed | passed | passed |
| bv2string | passed | passed | passed | passed | passed |
