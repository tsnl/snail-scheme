# SFIR benchmark corpus

The corpus keeps all 57 workloads from R7RS benchmarks revision
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Each directory contains the
canonical input, an external original Chez program, source provenance, and a
bare `main.sfir` when its complete port exists. Adapted Chez controls expose
representation changes separately. Rust implementations remain in
[`../wasm-reference`](../wasm-reference).

There are currently 53 static SFIR programs. Forty-nine were serialized once
from the resolved IR of reviewed complete ports, including Peval, Pi and
Chudnovsky. Cat and WC have complete direct SFIR character loops and file
lifecycles and matching adapted Chez controls. CTak and Fibc preserve call/cc behavior with explicit immutable continuation
variants and matching original call/cc traces. Compiler, Dynamic, Scheme and
SLaTeX still need complete SFIR sources. The
[manifest](corpus.json) distinguishes source presence, Wasm validation, native
validation and measurement. Source presence proves none of the latter three.

`lambda` and `let` have one body expression, `if` has both branches, and
sequencing uses lexical `begin`. No target macro or derived Scheme form runs
during preparation. The one-off conversion expanded macros with the old
frontend outside the product, then retained resolved binding identities with
unique local names. Administrative lambda applications from that expansion
remain visible. Literal constants retain their original representation.
Each `migration.json` identifies the pinned source and input, reviewed port
hash, conversion utility hash and authored SFIR hash. This is provenance, not
a claim of behavioral equivalence before target execution.

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
programs with their complete predicates. Native lowering consumes the exact
optimized SFIR Wasm used in V8. Runtime-backed Wasm supplies concrete scalar
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
a place in the frozen schedule. All original validation outcomes remain visible,
including default Rust Wasm Ack's stack overflow and unavailable adapted Chez
controls. Preparation and clean-artifact validation are never timing samples.

Every route gets one fresh-process warmup and five fresh-process measured runs.
Cases and route positions rotate deterministically, all processes inherit the
same pinned CPU, and the schedule never retries or drops failures. The guest
clock encloses the repeated workload and its full final predicate. Input setup,
result formatting and final resource cleanup lie outside it. Fresh-process
warmups warm shared machine state; each V8 process still performs its own
compilation and tiering during the canonical workload. Cat's complete output
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
No SFIR performance coverage is claimed.

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
