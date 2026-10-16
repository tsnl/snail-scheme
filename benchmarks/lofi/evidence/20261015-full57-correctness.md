# Checked full57 correctness, 15 October 2026

**Local package; hold for the completed campaign before landing.** The first
validation phase is terminal: 57 cases, 328 passed route outcomes, two original
Ack Wasm failures and 12 unavailable adapted Chez controls. Clean preparation is
still running; neither a complete timing plan nor measurement samples existed at
this capture. No performance claim follows from these validation records.

The [machine-readable capture](20261015-full57-correctness.json) and
[original record archive](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/sfir/evidence/20261015-full57-correctness-records.tar.gz) preserve this
phase independently of the earlier [44-case capture](20261015-full57-pending.md),
whose Markdown and JSON remain byte-identical. Every result here belongs to
compiler `8e547bfb353fa5c5aa7c17bc805db13af0d2bca1` in
`/tmp/sfir-checked-full57-20261015-v1`. Later library, service and I/O commits,
historical measurements and paired input-buffer experiments supply no results
for this freeze.

| Route | Passed | Failed | Unavailable |
| --- | ---: | ---: | ---: |
| SFIR Wasm | 56 | 1 | 0 |
| SFIR native | 57 | 0 | 0 |
| Chez original | 57 | 0 | 0 |
| Chez adapted | 45 | 0 | 12 |
| Rust Wasm | 56 | 1 | 0 |
| Rust native | 57 | 0 | 0 |

Unavailable means there is no adapted source for that control. All 57 original
Chez controls remain visible. Ack's SFIR and Rust Wasm commands each terminate
with `Maximum call stack size exceeded`; neither the
[private-worker experiment](20261015-ack-stack.md) nor altered engine tiers
replace those failures. Native Ack passed.

## All 57 canonical validations

W and N denote Wasm and native. Counts come from the frozen corpus; complete
inputs and predicates remain in the archived specifications and verifier sources.
Array1 performs one outer invocation with its 500-iteration input. Equal performs
one outer invocation with all six canonical parameters. Their saved harness count
is one; the JSON retains both counts rather than treating them as reduced runs.

| Case | Canonical count | SFIR W | SFIR N | Chez original | Chez adapted | Rust W | Rust N |
| --- | ---: | --- | --- | --- | --- | --- | --- |
| browse | 2000 | Pass | Pass | Pass | Pass | Pass | Pass |
| deriv | 10000000 | Pass | Pass | Pass | Pass | Pass | Pass |
| destruc | 4000 | Pass | Pass | Pass | Pass | Pass | Pass |
| diviter | 1000000 | Pass | Pass | Pass | Unavailable | Pass | Pass |
| divrec | 1000000 | Pass | Pass | Pass | Unavailable | Pass | Pass |
| puzzle | 1000 | Pass | Pass | Pass | Pass | Pass | Pass |
| triangl | 50 | Pass | Pass | Pass | Pass | Pass | Pass |
| tak | 1 | Pass | Pass | Pass | Unavailable | Pass | Pass |
| takl | 1 | Pass | Pass | Pass | Unavailable | Pass | Pass |
| ntakl | 1 | Pass | Pass | Pass | Unavailable | Pass | Pass |
| cpstak | 1 | Pass | Pass | Pass | Unavailable | Pass | Pass |
| ctak | 1 | Pass | Pass | Pass | Pass | Pass | Pass |
| fib | 5 | Pass | Pass | Pass | Unavailable | Pass | Pass |
| fibc | 10 | Pass | Pass | Pass | Pass | Pass | Pass |
| fibfp | 10 | Pass | Pass | Pass | Unavailable | Pass | Pass |
| sum | 200000 | Pass | Pass | Pass | Unavailable | Pass | Pass |
| sumfp | 500 | Pass | Pass | Pass | Unavailable | Pass | Pass |
| fft | 100 | Pass | Pass | Pass | Pass | Pass | Pass |
| mbrot | 1000 | Pass | Pass | Pass | Pass | Pass | Pass |
| mbrotZ | 1000 | Pass | Pass | Pass | Pass | Pass | Pass |
| nucleic | 50 | Pass | Pass | Pass | Pass | Pass | Pass |
| pi | 100 | Pass | Pass | Pass | Pass | Pass | Pass |
| pnpoly | 1000000 | Pass | Pass | Pass | Pass | Pass | Pass |
| ray | 50 | Pass | Pass | Pass | Pass | Pass | Pass |
| simplex | 1000000 | Pass | Pass | Pass | Pass | Pass | Pass |
| ack | 2 | **Fail** | Pass | Pass | Unavailable | **Fail** | Pass |
| array1 | 500 | Pass | Pass | Pass | Unavailable | Pass | Pass |
| string | 100 | Pass | Pass | Pass | Pass | Pass | Pass |
| sum1 | 25 | Pass | Pass | Pass | Pass | Pass | Pass |
| cat | 50 | Pass | Pass | Pass | Pass | Pass | Pass |
| tail | 50 | Pass | Pass | Pass | Pass | Pass | Pass |
| wc | 50 | Pass | Pass | Pass | Pass | Pass | Pass |
| read1 | 2500 | Pass | Pass | Pass | Pass | Pass | Pass |
| compiler | 2000 | Pass | Pass | Pass | Pass | Pass | Pass |
| conform | 500 | Pass | Pass | Pass | Pass | Pass | Pass |
| dynamic | 500 | Pass | Pass | Pass | Pass | Pass | Pass |
| earley | 1 | Pass | Pass | Pass | Pass | Pass | Pass |
| graphs | 3 | Pass | Pass | Pass | Pass | Pass | Pass |
| lattice | 10 | Pass | Pass | Pass | Pass | Pass | Pass |
| matrix | 2500 | Pass | Pass | Pass | Pass | Pass | Pass |
| maze | 10000 | Pass | Pass | Pass | Pass | Pass | Pass |
| mazefun | 10000 | Pass | Pass | Pass | Pass | Pass | Pass |
| nqueens | 10 | Pass | Pass | Pass | Pass | Pass | Pass |
| paraffins | 10 | Pass | Pass | Pass | Pass | Pass | Pass |
| parsing | 2500 | Pass | Pass | Pass | Pass | Pass | Pass |
| peval | 2000 | Pass | Pass | Pass | Pass | Pass | Pass |
| primes | 10000 | Pass | Pass | Pass | Pass | Pass | Pass |
| quicksort | 2500 | Pass | Pass | Pass | Pass | Pass | Pass |
| scheme | 100000 | Pass | Pass | Pass | Pass | Pass | Pass |
| slatex | 500 | Pass | Pass | Pass | Pass | Pass | Pass |
| chudnovsky | 1000 | Pass | Pass | Pass | Pass | Pass | Pass |
| nboyer | 1 | Pass | Pass | Pass | Pass | Pass | Pass |
| sboyer | 1 | Pass | Pass | Pass | Pass | Pass | Pass |
| gcbench | 1 | Pass | Pass | Pass | Pass | Pass | Pass |
| mperm | 20 | Pass | Pass | Pass | Pass | Pass | Pass |
| equal | 100 | Pass | Pass | Pass | Pass | Pass | Pass |
| bv2string | 100 | Pass | Pass | Pass | Pass | Pass | Pass |

## What the archive establishes

All 57 saved case statuses agree with terminal `validation.json`. Its outcomes
are authoritative; status fields inherited in `corpus.json` or manifest cases
describe older evidence. Source presence alone does not establish correctness.

The existing runner's hash and source-provenance helpers checked all 647 frozen
source files, all 64 frozen data files, all 57 SFIR sources and case inputs, all
102 present original/adapted Chez sources, and all 57 Rust source identities.
Each saved validation specification matches its frozen source byte for byte.
The upstream revision and per-source hashes are retained as provenance; this
report does not turn a source migration record into an equivalence proof.

All 57 native parity records report the same optimized guest hash as the Wasm
validation artifact. Their raw, optimized, LLVM and executable identities agree
with the retained native build manifests; build-configuration hashes also match.
This capture rechecks metadata and small record bytes. It does not rehash large
artifacts or rerun native execution. Separate target providers remain distinct.

The bundle retains 797 original terminal validation command records and all
1,594 raw stdout/stderr captures. There were no recorded timeouts or surviving
descendants. Of four nonzero process exits, two are the Ack failures and two are
Compiler's expected fatal-handler probes. The latter satisfy the frozen runner's
exact diagnostic/exit predicate and are successful negative checks. Another 11
tool/preparation records, their raw captures and 57 native build manifests retain
exact commands, selected environment, tool/source/artifact hashes and build flags.

Original process and harness clocks remain in the archive for byte integrity.
They are neither clean execution samples nor a compilation benchmark. No durations,
medians or ratios are derived here. The separate clean artifacts, completed plan,
measurement protocol and samples will need their own terminal evidence.

## Integrity and provenance

The archive includes the exact captured manifest, machine context, corpus,
validation records, source-fidelity metadata, selected static sources and controls,
canonical data, predicates, provider/output checks and frozen runner/timing helpers.
It excludes binaries, Wasm/WAT, LLVM IR, sysroot/vendor copies and generated output
trees; existing identities remain in the manifest, parity, build and provider
records. Large artifacts, tool executables and dependency trees were not rehashed
for this report. The archive is evidence for audit, not a self-contained toolchain.

Its `index.json` gives SHA-256 and byte length for every other member. After
extracting into a fresh directory, `python3 audit/verify.py /path/to/archive.tar.gz`
checks the indexed bytes without executing a retained campaign command. The
machine-readable capture records the outer archive and index hashes.

The manifest hash identifies captured bytes. Preparation may legitimately add
`timing_plan_sha256` later; a changed manifest hash alone does not imply changed
frozen source, artifact or original validation files. Their separately retained
identities remain authoritative. No campaign file was changed and no build or
workload was executed to prepare this package.
