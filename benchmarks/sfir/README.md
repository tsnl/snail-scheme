# SFIR benchmark corpus

The corpus keeps all 57 workloads from R7RS benchmarks revision
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Each directory contains the
canonical input, an external original Chez program, source provenance, and a
bare `main.sfir` when its complete port exists. Adapted Chez controls expose
representation changes separately. Rust implementations remain in
[`../wasm-reference`](../wasm-reference).

There are currently 56 committed static SFIR programs. Forty-nine were serialized once
from the resolved IR of reviewed complete ports, including Peval, Pi and
Chudnovsky. Cat and WC have complete direct SFIR character loops and file
lifecycles and matching adapted Chez controls. CTak and Fibc preserve call/cc behavior with explicit immutable continuation
variants and matching original call/cc traces. Dynamic and Scheme retain complete
benchmark-local typed implementations with separate original/adapted Chez controls.
SLaTeX now passes its complete 500-iteration workload, all 28,500 output files and
resource checks on the current source; Compiler remains in a preserved draft.
The runner registers 54 sources; Dynamic and Scheme await its lifecycle integration. The
[manifest](corpus.json) distinguishes source presence, Wasm validation, native
validation and measurement. Source presence proves none of the latter three.

`lambda` has one body expression, `let` is a sequential statement, `if` has both
branches, and sequencing uses lexical `begin`. No target macro or derived Scheme form runs
during preparation. The one-off conversion expanded macros with the old
frontend outside the product, then retained resolved binding identities with
unique local names. Administrative lambda applications from that expansion
remain visible. Literal constants retain their original representation.
Each `migration.json` identifies the pinned source and input, reviewed port
hash, conversion utility hash and authored SFIR hash. This is provenance, not
a claim of behavioral equivalence before target execution.

The published surface migration uses `def`, static formers, `Any`,
`define-library`, `(sfir base)` and the ordinary `empty-list` operation. The
[source manifest](../../tests/sfir/surface-migration.json) records the old,
mechanically migrated and formatted hashes. Each active `migration.json` keeps
its old hashes in `surface_migration` and sets `sfir_sha256` to the current static
source, so preparation still requires an exact hash match. Parallel let
initializers retain their original outer scope and left-to-right effects through
fresh temporaries before aliases bind the original names. Numeric spellings,
algorithms, canonical inputs, counts, predicates and external controls are unchanged.

Historical evidence referenced below predates this surface migration. The corpus
records current-surface validation as pending except the explicit SLaTeX result;
the older successful execution and timing records are retained verbatim and do
not establish results for the migrated sources. The standard formatter covers
libraries, tests and examples. Benchmark layout remains token-preserving because
the formatter also fails on the pre-migration Parsing source.

## Preparation and validation

```sh
python3 benchmarks/sfir/runner.py inventory
python3 benchmarks/sfir/runner.py prepare --output /tmp/sfir-check --benchmarks ack \
  --compile-timeout 1800
python3 benchmarks/sfir/runner.py verify --output /tmp/sfir-check
python3 benchmarks/sfir/runner.py validate --output /tmp/sfir-check
```

Preparation copies static source files, compiler/runtime/build support, Rust
sources and pinned runtime inputs into a new directory. It records content
digests and explicit positive finite build/run timeouts. The default compile
timeout remains 1200 seconds. Mutable checkout files are never referenced by
the frozen driver; immutable Nix tools are identified by invocation path and
digest. Rustup dispatchers are identified explicitly and do not yet establish a
frozen selected Rust toolchain.

Validation invokes the SFIR compiler, whose build contract always runs Binaryen,
and retains both raw and optimized Wasm. Every process has a terminal record,
including stdout, stderr, duration, failure and timeout. Timeout cleanup kills
and drains the process group. A successful compile does not establish successful
execution. The integrated routes handle scalar/typed-container kernels and Datum/I/O
programs with their complete predicates. Native builds require the retained raw
SFIR Wasm. The helper's mandatory Binaryen pass must produce byte-identical
optimized guest Wasm to the V8 program before native execution is accepted.
`native-parity.json` retains raw/program/native-optimized/LLVM/executable hashes,
the actual build command and configuration, including failed build or parity
outcomes. This equality concerns the guest program, with separate target runtime
providers. Earlier freezes supplied already optimized input and ran Binaryen
twice on the native route; their effective optimized modules differ. The
[retrospective audit](evidence/20261015-native-optimization-audit.json) records
this for all six measured workloads. Runtime-backed Wasm supplies concrete scalar
services from a separately pruned Rust provider; the retained provider imports
exclude the legacy Root ABI. Each target and external control runs in a fresh
working directory. Per-stage records preserve successful Wasm evidence if a
later native or comparison step fails. FFT uses a separate scalar Rust sine provider; Tail, Ray and Nucleic use
concrete runtime services. Pi and Chudnovsky check their entire decimal output
after running the unchanged canonical count.

## Clean timing protocol

```sh
python3 benchmarks/sfir/timing.py prepare --output /tmp/sfir-six \
  --benchmarks ack fibfp cat wc ctak fibc --compile-timeout 1800 --cpu 2
python3 benchmarks/sfir/timing.py verify --output /tmp/sfir-six
# Run only after coordinating a quiet machine with every active worker.
python3 benchmarks/sfir/timing.py measure --output /tmp/sfir-six \
  --quiet-window 'Coordinator, confirmation time, and scope of the quiet interval'
```

The first timing cohort contains these six cases. Preparation copies the
selected Rust sysroot and vendors the exact locked crates, invokes the copied
Cargo/Rust compiler, and rebuilds all available routes. It then builds a separate
native entry/provider with observation counters disabled. Each actual clean
executable/provider must pass its complete canonical predicate before it earns
a place in the frozen schedule. Its native build also consumes the copied raw
sidecar and independently verifies optimized-program parity; the plan preserves
that proof and checks its artifacts before execution. All original validation outcomes remain visible,
including default Rust Wasm Ack's stack overflow and unavailable adapted Chez
controls. Preparation and clean-artifact validation are never timing samples.

Every route gets one fresh-process warmup and five fresh-process measured runs.
Cases and route positions rotate deterministically, all processes inherit the
same pinned CPU, and the schedule never retries or drops failures. The guest
clock encloses the repeated workload and its full final predicate. Benchmark parameter setup,
result formatting and final resource cleanup lie outside it. Canonical file
reads and writes remain inside the repeated worker. Fresh-process
warmups warm shared machine state; module loading and instantiation precede the clock in each V8 process, while
any tiering during its canonical workload remains measured. Cat's complete output
bytes are additionally checked outside the guest clock, matching the original
benchmark's predicate boundary.

The plan records Node/V8, Chez, Rust, compiler/source/input, executable/provider
and immutable shared-library identities. Full preparation verification precedes
and follows the campaign; each trial checks its executed files and inputs. The
frozen tree must have no writers. The quiet-window text is an operational
attestation, not an automatic proof that the machine has no competing work.
Interrupt the command if the coordinated interval is lost: partial attempts and
unattempted schedule entries remain recorded, and comparisons are withheld.
Only complete routes with a successful warmup and all five valid measurements
receive median/minimum/maximum statistics and ratios. Ratios are SFIR seconds
divided by control seconds, so values below one favor SFIR.

CPU 2 is the default for this campaign. Older reports used CPU 5; compare their
absolute times only with that difference disclosed. Historical Scheme results
under `benchmarks/results` remain unchanged and do not count as SFIR validation
or measurement.

## Focused clarity review

A fresh independent explainer, without repository access, described the runner
as freezing inputs, establishing target evidence, and only then admitting an
explicit clean protocol. Informed critique retained immutable tool references
instead of copying whole installations, while requiring copied mutable
dependencies and explicit unsupported host routes. Tests exercise source
tampering, checkout independence, escaping/symlinked dependencies, timeout
configuration, and a process with a live child. No generic callback or plugin
framework was introduced.

## Executed checkpoint

Canonical Ack and Fibfp pass SFIR optimized V8, native64, and original Chez.
Fibfp passes both Rust targets; Ack passes Rust native while its default Rust
Wasm stack overflows. Canonical Cat and WC pass both SFIR targets, original
and adapted Chez, and both Rust targets. Cat additionally checks the complete
output bytes; the Wasm host observes every input/output cycle, deletion and
close. The first Cat/WC adapted-control compilation failures remain retained;
excluding the two Chez copy-operation imports fixes that control boundary
without changing any benchmark or library body.

[Checkpoint evidence](evidence/20261015-canonical.json) identifies these exact
source hashes, frozen attempts, artifacts, outcomes and diagnostic records. All
53 authored main programs have also passed the direct SFIR frontend's source
resolution. Resolution alone does not establish inference or target correctness.
The first [clean timing report](evidence/20261015-clean-six.md) covers six
workloads and 33 eligible routes; the remaining workloads are not measured.

The focused review kept process launch, waiting, group termination and terminal
recording together despite that function exceeding the ten-line guideline: one
exception boundary owns the child group. Reversible export selection and staged
build publication likewise keep their complete validation decisions visible.
The remaining helpers separate concrete freeze, build, execution and result
checks. Tests also cover stale outputs, a parent exiting while its child holds
stdout, mandatory adapted controls, and exact provider export selection.

[Specialized-host evidence](evidence/20261015-specialized.json) records canonical
FFT, Tail, Ray, Pi, Chudnovsky and Nucleic passing all six target/control routes.
The first FFT native link failure is retained: linking a single Rust sine object
instead of a second complete Rust standard-library archive fixes duplicate
symbols without changing the provider source or optimized SFIR program.
Verification and validation enter the copied driver, so subsequent checkout
edits cannot change an existing frozen attempt's execution logic.

The timing module received a separate fresh no-files explanation and informed
critique. That review kept eligibility, frozen schedule and process records as
ordinary data. It rejected adaptive retries and repeated full toolchain hashing
between trials; actual executed dependencies are checked each time instead.
The native clock transition and exhaustive route selection remain together even
where they exceed the ten-line guideline, because splitting would hide timer
boundaries or artifact identity. Tests cover failed warmups, missing samples,
malformed/wrong-count timer reports, schedule exclusions and input tampering.

The first CPU-2 campaign completed all 33 warmups and 165 measured processes
successfully, followed by full integrity verification. Its report preserves
original/adapted Chez separately and discloses Rust FIBC's additional opacity
at each Peano step. A completed future schedule exits nonzero if any eligible
route lacks its successful warmup or all five valid measurements.

[Conform host evidence](evidence/20261015-conform-host.json) retains its first
missing-character-import failures and validates the unchanged optimized program
and provider on Wasm and native. Both established character-output spellings
write through the existing UTF-8 operation. Canonical Conform disables progress
printing, so a separate actual ABI probe checks the full ASCII/NUL/BMP/non-BMP
byte stream on both Node hosts and native, followed by normal completion and
exactly one explicit barrier. The empty canonical workload stream agrees with
both Chez controls. No timing sample was collected.

A fresh no-files explanation and informed critique kept this correction to the
existing character writer and its import names. It rejected a generic import
registry and a canonical-only check, which could not distinguish output from a
no-op when progress printing is disabled. Two failed synthetic probe attempts
remain visible alongside the final passing fixture.

Reader-host observations normally scale with the canonical count. Parsing
declares `observation_basis: "whole-run"`: it reads its input once and makes
two opacity calls around 2,500 parses of the resulting string. This changes
only expected observations; the canonical count still reaches the unchanged
worker. Barrier quantities describe one selected observation basis. Setup and
cleanup expectations remain independent. Unknown observation bases fail.
[Parsing evidence](evidence/20261015-parsing-observations.json) retains the old
count-mismatch failures and actual corrected Wasm/native executions. Node also
rejects wrong barrier totals, missing and extra cycles, a wrong result and an
invalid basis. Its byte/EOF/close/live-handle predicates remain intact; native
checks the full result, barriers and exact resource-close totals.

The fresh no-files observation review and informed critique selected this one
basis declaration, preserving the existing complete file-cycle checks. It
rejected a second benchmark count and independently configurable observation
formulas. Canonical artifacts remain separate from the corrected metadata and
host evidence; no performance samples were added.

The [remaining-41 validation report](evidence/20261015-existing41.md) brings
this checkpoint to 53 canonical SFIR Wasm passes and 52 native passes. The
remaining native route, GCBench, retained its 1,800-second build timeout and
partial artifacts. All 53 original Chez and Rust native routes pass, all 41
present adapted controls pass, and Rust Wasm retains Ack's stack failure among
52 successes. Four source ports remain pending. Full original process records,
the frozen manifest and separately corrected outcomes are archived; these
contended executions add no performance measurements and retain the disclosed
second native optimization pass.

The native parity correction received a local behavioral explanation, an
artifact audit and context-informed critique from the coordinating agent. A
fresh independent review was unavailable: both new and existing reviewer calls
hit the tool's conversation limit. The review kept raw input, actual optimized
output and executable identity together, and covered scalar, Integer and clean
build routes. It rejected a skip-optimization flag and fallback to an already
optimized input. Tests cover missing raw input, differing optimized bytes,
replaced executables, ambiguous build attempts and ineligible timing evidence.
The build-evidence checks stay together despite exceeding the ten-line guideline
because they establish one artifact-identity guarantee.

[Native parity validation](evidence/20261015-native-parity.md) records 15 actual
builds with identical optimized guest bytes: the six representative workloads
with correctness and clean native entries, plus Pi, Primes and GCBench. All
canonical SFIR routes pass, including GCBench's separately preserved earlier
timeout. This brings authored-program correctness coverage to 53 on both SFIR
targets; nine cases also have the new parity proof. The six-case plan has 33
ready routes, retaining Rust Wasm Ack's failure and unavailable controls, but
no new performance samples have been collected.
