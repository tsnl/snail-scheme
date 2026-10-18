# Lofi benchmark corpus

Lofi was previously named SFIR. The rename preserves all 57 workloads, canonical
inputs and external controls. Each `migration.json` retains its historical
`sfir_sha256` and records the renamed source in `lofi_sha256` and
`language_rename`. The subsequent `source_layout` records the `.sld` path move
with before/after hashes; all 57 main source contents are unchanged by that move.
Preparation checks `lofi_sha256`. Frozen reports, raw records
and their `sfir-*` route labels retain the names used by the measured revision;
the rename does not establish new validation or performance results.

Current runs use Lofi/Wasm, original/adapted Chez, Rust/Wasm and Rust/native.
The LLVM backend and Lofi/native route are removed. Historical six-route records
below retain their original compiler, results and meaning; no current full-suite
performance measurement is claimed by the removal.

The corpus keeps all 57 workloads from R7RS benchmarks revision
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Each directory contains the
canonical input, an external original Chez program, source provenance, and a
complete bare `main.sld`. Adapted Chez controls expose
representation changes separately. Rust implementations remain in
[`../wasm-reference`](../wasm-reference).

All 57 workloads now have complete static Lofi sources and registered execution
routes. Forty-nine were serialized once
from the resolved IR of reviewed complete ports, including Peval, Pi and
Chudnovsky. Cat and WC have complete direct Lofi character loops and file
lifecycles and matching adapted Chez controls. CTak and Fibc preserve call/cc behavior with explicit immutable continuation
variants and matching original call/cc traces. Dynamic and Scheme retain complete
benchmark-local typed implementations with separate original/adapted Chez controls.
SLaTeX now passes its complete 500-iteration workload, all 28,500 output files and
resource checks on the current source. Compiler retains all 1,343 kernel forms,
its 2,000-compilation canonical input and complete 497-line assembly predicate;
all six canonical routes pass on the recorded compiler snapshot. The runner
registers all 57 sources. Recorded Dynamic and Scheme campaigns passed their
canonical workloads on both then-supported Lofi targets and all four controls.
Their workload-local verifiers preserve the source lifecycles. The
[manifest](corpus.json) retains source presence, historical target validation and
measurement separately. Source presence establishes neither current correctness
nor measured performance.

The [completed full57 report](evidence/20261015-full57.md) freezes compiler
`8e547bfb`, validates all 57 native routes and 56 Wasm routes, and measures 326
eligible target/control routes with 1,956 successful scheduled attempts. Both
Ack Wasm failures, 12 absent adapted controls and two Mperm Chez timer-name
rejections remain in its primary matrix. A distinct corrected Mperm campaign
passes six routes and 36 attempts. Every case has native optimized-guest parity.
Lofi is slower on every reported geometric-mean control comparison; the report
keeps matching counts, per-case ranges and representation differences visible.
The later [packet-input measurements](evidence/20261015-input-packets.md) cover
Cat/WC separately and do not replace this frozen baseline.

`lambda` has one body expression, `let` is a sequential statement, `if` has both
branches, and sequencing uses lexical `begin`. No target macro or derived Scheme form runs
during preparation. The one-off conversion expanded macros with the old
frontend outside the product, then retained resolved binding identities with
unique local names. Administrative lambda applications from that expansion
remain visible. Literal constants retain their original representation.
Each `migration.json` identifies the pinned source and input, reviewed port
hash, conversion utility hash and authored Lofi hash. This is provenance, not
a claim of behavioral equivalence before target execution.

The published surface migration uses `def`, static formers, `Any`,
`define-library`, `(lofi base)` and the ordinary `empty-list` operation. The
[source manifest](../../tests/lofi/surface-migration.json) records the old,
mechanically migrated and formatted hashes. Each active `migration.json` keeps
its old hashes in `surface_migration`; `language_rename` connects the last SFIR
source to the current `lofi_sha256`, so preparation still requires an exact hash
match. Parallel let
initializers retain their original outer scope and left-to-right effects through
fresh temporaries before aliases bind the original names. Numeric spellings,
algorithms, canonical inputs, counts, predicates and external controls are unchanged.

Historical executed checkpoints below retain their older surfaces and compilers.
The manifest's current status comes from the full57 freeze; per-case
`historical_evidence` preserves earlier links and measured routes. Current
surface-validation checkpoint is complete with Ack's Wasm failure retained,
rather than inferred from historical Ack success. Older records remain verbatim.
The later named-declaration syntax reserves `data`; the preserved FFT source
currently fails to compile because it uses that name for a value binding. The
full57 checkpoint does not establish correctness on this newer compiler. The
native-package reorganization rechecked Ack: native, Chez and Rust native pass,
while both Wasm routes retain their default-stack exhaustion. Benchmark sources,
inputs and published evidence remain unchanged. The standard formatter covers
libraries, tests and examples. Benchmark layout remains token-preserving because
the formatter also fails on the pre-migration Parsing source.

## Preparation and validation

```sh
chibi-scheme -I bootstrap -I benchmarks benchmarks/lofi/runner.scm inventory
chibi-scheme -I bootstrap -I benchmarks benchmarks/lofi/runner.scm prepare --output /tmp/lofi-check --benchmarks ack \
  --compile-timeout 1800
chibi-scheme -I bootstrap -I benchmarks benchmarks/lofi/runner.scm verify --output /tmp/lofi-check
chibi-scheme -I bootstrap -I benchmarks benchmarks/lofi/runner.scm validate --output /tmp/lofi-check
```

Preparation copies static source files, compiler/runtime/build support, Rust
sources and pinned runtime inputs into a new directory. Both correctness and
timing preparation copy the selected Rust sysroot and vendor the exact locked
crates for the runtime and Rust controls. Builds invoke that copied Cargo and
Rust compiler with the frozen vendor configuration. Preparation records content
digests and explicit positive finite build/run timeouts. The default compile
timeout is 1800 seconds. Mutable checkout files are never referenced by
the frozen driver; immutable Nix tools are identified by invocation path and
digest. The manifest also retains the original Rustup dispatcher identities and
selected installation path as provenance; subsequent builds use the copied
installation and dependency sources.

Custom `RUSTC_WRAPPER` and `RUSTC_WORKSPACE_WRAPPER` commands must be unset for a
campaign; their unrecorded dependencies would defeat the freeze.

Validation invokes the Lofi compiler, whose build contract always runs Binaryen,
and retains both raw and optimized Wasm. Every process has a terminal record,
including stdout, stderr, duration, failure and timeout. Timeout cleanup kills
and drains the process group. A successful compile does not establish successful
execution. The integrated routes handle scalar/typed-container kernels and Datum/I/O
programs with their complete predicates. Native builds require the retained raw
Lofi Wasm. The helper's mandatory Binaryen pass must produce byte-identical
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

Dynamic and Scheme use local `verify.mjs` and `native-entry.rs` files with the
shared frozen build and artifact-parity protocol. Their explicit `execution_files`
lists copy only declared case fixtures into fresh target working directories;
escaping paths are rejected. The [current-source checkpoint](evidence/20261015-dynamic-scheme.md)
records all six canonical routes passing for each workload, all 26 supported
interpreter probes, and the precise Wasm/native resource evidence. Those runs
added correctness coverage while both workloads were unmeasured at that checkpoint.

## Clean timing protocol

```sh
chibi-scheme -I bootstrap -I benchmarks benchmarks/lofi/timing.scm prepare --output /tmp/lofi-full57 \
  --benchmarks all --compile-timeout 1800 --run-timeout 1800 --cpu 2
chibi-scheme -I bootstrap -I benchmarks benchmarks/lofi/timing.scm verify --output /tmp/lofi-full57
# Run only after coordinating a quiet machine with every active worker.
SNAIL_NATIVE_SUPERVISOR=/tmp/lofi-full57/toolchain/snail-native-supervisor \
chibi-scheme -I bootstrap -I benchmarks benchmarks/lofi/timing.scm measure --output /tmp/lofi-full57 \
  --quiet-window 'Coordinator, confirmation time, and scope of the quiet interval'
```

Set the frozen supervisor path before starting the measurement driver; the
supervisor setting in each child environment does not initialize the parent
Chibi process launcher.

The harness supports all 57 registered workloads and all six target/control
routes; a named subset can still be selected explicitly. The plan retains
unavailable adapted Chez controls and every failed preparation or execution.
Support establishes no new correctness or measurement result: each frozen
campaign earns its own route statuses. Preparation rebuilds all available
routes, then builds a separate native entry/provider with observation counters
disabled. Each actual clean
executable/provider must pass its complete canonical predicate before it earns
a place in the frozen schedule. Its native build also consumes the copied raw
sidecar and independently verifies optimized-program parity; the plan preserves
that proof and checks its artifacts before execution. All original validation
outcomes remain visible. Preparation and clean-artifact validation are never
timing samples.

Native providers pass their scalar inputs, expected values, counts and hide
returns through Rust's `black_box`, including generated pathname accessors.
This preserves value opacity with the tested Rust/LLVM toolchain when shared
LTO can see both provider and guest. Observation counters remain disabled in
clean builds. Correctness predicates and hook counts are separate from evidence
that repeated work survives optimization; timing claims must check the actual
clean executable's work too. Existing frozen campaigns retain their copied
providers; this change applies to newly prepared native artifacts.

Clean Wasm hosts preserve the scalar, typed sequence, decimal Integer,
Datum/runtime, Nucleic, Tail and Ray interfaces explicitly. Compiler, Dynamic,
Scheme and SLaTeX use the uninstrumented runtime host and scalar native entry;
their validation-only diagnostic probes remain outside clean execution. FFT
retains its separate Rust sine provider on both targets. Every clean attempt
copies declared execution fixtures and starts in a fresh working directory.
New native builds use the collector's fixed production policy; historical
`native_heap_bytes` fields no longer configure them. Frozen campaigns retain
their original executables and recorded environments. The plan hashes implicit math providers
as well as files named directly on the command line.

Sequence workers compare every existing expected element inside `bench` and
return a success flag. Pi and Chudnovsky compare every expected decimal
character there, then serialize the complete observed result after the clock;
all six routes must emit the exact canonical decimal bytes. Their original
and adapted Chez controls have untimed drivers, so preparation retains derived
timing artifacts that replace only that driver with a monotonic clock around
the same worker loop and complete predicate. Frozen control sources remain
unchanged. Array1, Equal and Mperm record the actual Chez and Rust timer names in
`spec.json`. Array1/Equal's canonical inner counts differ from Lofi's outer count
of one; Mperm's Chez name places count before its three parameters. The primary
full57 freeze predates that Mperm metadata fix and preserves its two rejections.

Every route gets one fresh-process warmup and five fresh-process measured runs.
Cases and route positions rotate deterministically, all processes inherit the
same pinned CPU, and the schedule never retries or drops failures. The guest
clock encloses the repeated workload and its full final predicate. Benchmark parameter setup,
result formatting and final resource cleanup lie outside it. Canonical file
reads and writes remain inside the repeated worker. Fresh-process
warmups warm shared machine state; module loading and instantiation precede the clock in each V8 process, while
any tiering during its canonical workload remains measured. Cat, Tail and Ray
output bytes and SLaTeX's complete numbered output manifest are additionally
checked outside the guest clock, matching the original benchmark's predicate
boundary. Every command retains exact stdout/stderr bytes beside decoded
diagnostics; newline conversion cannot weaken decimal checks.

The plan records Node/V8, Chez, Rust, compiler/source/input, executable/provider
and immutable shared-library identities. Full preparation verification precedes
and follows the campaign; each trial checks its executed files and inputs. The
fixed protocol rejects nonempty `NODE_OPTIONS`, coverage and preload settings.
It also rejects legacy GC observation settings when replaying older frozen
executables: `SNAIL_GC_STATS` enabled statistics even with an empty value. The
current runtime has no GC environment configuration. Missing/null settings and inert empty
values such as `NODE_OPTIONS=""` or `LD_PRELOAD=""` remain accepted; rejected
values remain in the manifest and error. The frozen tree must have no writers.
The quiet-window text is an operational attestation, not an automatic proof that
the machine has no competing work.
Interrupt the command if the coordinated interval is lost: partial attempts and
unattempted schedule entries remain recorded, and comparisons are withheld.
Only complete routes with a successful warmup and all five valid measurements
receive median/minimum/maximum statistics and ratios. Ratios are Lofi seconds
divided by control seconds, so values below one favor Lofi.

CPU 2 is the default for this campaign. Older reports used CPU 5; compare their
absolute times only with that difference disclosed. Historical Scheme results
under `benchmarks/results` remain unchanged and do not count as Lofi validation
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

The full-corpus timing extension used a fresh no-files explainer and informed
critique to retain one scalar native entry and one decimal entry. Run the
bounded harness checks with
`chibi-scheme -D snail-tests -I bootstrap -I tests -I tests -I benchmarks tests/lofi-benchmarks.scm`. Besides frozen
dependency and scheduling tests, reduced synthetic Wasm/Rust/Chez probes execute
every host category, typed sequence/decimal/math interfaces, failed predicates,
declared fixture copies and explicit environment propagation. Their command records and
artifacts remain in `build/lofi-timing-probes`; these probes establish harness
behavior and are neither canonical corpus correctness nor timing samples.
Pass `--execute` to that command to run the actual Wasm, Cargo-native and Chez
harness probes. The short invocation runs the pure contract and fixture checks.
The [full-corpus harness checkpoint](evidence/20261015-full57-timing-harness.md)
records all six canonical and clean-artifact routes passing for FFT, Pi, Tail
and Equal, plus the exact frozen revision. It adds no measurements.

## Historical executed checkpoints

Canonical Ack and Fibfp pass Lofi optimized V8, native64, and original Chez.
Fibfp passes both Rust targets; Ack passes Rust native while its default Rust
Wasm stack overflows. Canonical Cat and WC pass both Lofi targets, original
and adapted Chez, and both Rust targets. Cat additionally checks the complete
output bytes; the Wasm host observes every input/output cycle, deletion and
close. The first Cat/WC adapted-control compilation failures remain retained;
excluding the two Chez copy-operation imports fixes that control boundary
without changing any benchmark or library body.

[Checkpoint evidence](evidence/20261015-canonical.json) identifies these exact
source hashes, frozen attempts, artifacts, outcomes and diagnostic records. All
53 authored main programs have also passed the direct Lofi frontend's source
resolution. Resolution alone does not establish inference or target correctness.
The first [clean timing report](evidence/20261015-clean-six.md) covers six
workloads and 33 eligible routes; the remaining workloads are not measured.

A later [Ack stack diagnostic](evidence/20261015-ack-stack.md) preserves the
checked-arithmetic snapshot's default V8 failure. Its private-worker experiment
keeps all arithmetic checks and passes one default-tier probe, while forced cold
tiers still fail. This supplies no replacement route result or timing sample;
the earlier checkpoint and measurements retain their frozen provenance.

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
symbols without changing the provider source or optimized Lofi program.
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
this checkpoint to 53 canonical Lofi Wasm passes and 52 native passes. The
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
canonical Lofi routes pass, including GCBench's separately preserved earlier
timeout. This brings authored-program correctness coverage to 53 on both Lofi
targets; nine cases also have the new parity proof. The six-case plan has 33
ready routes, retaining Rust Wasm Ack's failure and unavailable controls, but
no new performance samples have been collected.
