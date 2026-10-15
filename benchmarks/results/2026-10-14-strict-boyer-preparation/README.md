# Both complete Boyer provers pass strict correctness preparation

NBoyer and SBoyer each pass the pinned original input: one invocation at size 5,
with a successful theorem result and exactly **51,507,739 rewrites**. The full
programs pass as raw linked Scheme Wasm, mandatory Binaryen-optimized Wasm,
mechanically lowered native64, original Chez and exactly adapted Chez. The
unchanged Rust references pass their native, raw Wasm and optimized Wasm
controls. **Clean timing remains pending; this preparation does not increase
historical measured coverage.**

Preparation uses compiler/library commit `6fd5ca453cc58903cdb64f13abc3cdc656b06226`
and adapter/driver commit `6f4a30e3f342bac06d01be3e5228abe783a0bfab`. The source
stack begins with `cf43239`. Upstream is the unchanged r7rs-benchmarks commit
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Node is 24.19.0, Binaryen is 132,
Chez is 10.4.1 and the compiler remains hosted by Chibi 0.12. Tool identities,
compiler source snapshots, original source and complete input bytes are retained.

## Source behavior and explicit representation boundaries

The adapter retains all kernel definitions, including those after the upstream
harness, all 106 installed lemmas, association-list lookup, recursive
substitution, directional unification, rewriting and tautology search. Setup
runs inside each worker invocation, as the original executable harness does.
The original comment describing setup as untimed does not match that harness.
Quoted constant construction runs once before worker entry. The input port
closes before the worker; each invocation makes its one scalar opacity call.

The existing closed `Datum` type represents terms and constructor-record
vectors. Existing typed `Ref` cells represent every mutated value and procedure
binding. Constructor records retain their cycles, and SBoyer retains an old
pair exactly when both newly computed fields are identical to its old fields.
Equal but separately stored children require a new pair. No compiler pass,
collector, frontend structure or reusable library implementation changed for
these ports.

Every source edit is recorded and reversed to the exact original kernel bytes;
the complete adapted Chez program also reverses to the complete original
control. Three explicit `let*` expressions preserve the observed original
compiled Chez order: translate a lemma before looking up its prior lemmas,
translate a constructor before its arguments, and translate an argument head
before its tail. General Scheme leaves operand evaluation order unspecified.
Wrapping primitive `cons` in a Datum constructor changed Chez's observed order
without these edits. The failed exact comparisons remain evidence; equal trace
lengths and equal work counts were insufficient to detect that change.

The compatibility boundary is the pinned workload, not arbitrary Scheme:
canonical integer inputs fit I64; source placeholders for later-installed
procedures become typed traps; the unreachable invalid-lemma error keeps its
failure but simplifies its payload. Adapted Chez prints its Datum record on the
wrong-result fixture where the original prints an ordinary number, while both
must reject that fixture. Quote translation accepts the symbol, integer and
proper-list forms present in these sources. Trailing unused input datums and
comments remain byte-for-byte intact.

## Complete correctness and separate observations

Each workload has five fixtures. Every fixture runs on all five Scheme paths
and all three unchanged Rust paths:

| Fixture | Repetitions | Size | Expected rewrites | Required outcome |
| --- | ---: | ---: | ---: | --- |
| Original complete input | 1 | 5 | 51,507,739 | Accept |
| Small boundary | 1 | 0 | 95,024 | Accept |
| State reset | 2 | 0 | 95,024 | Accept |
| Wrong rewrite count | 1 | 0 | 95,025 | Reject |
| No worker invocation | 0 | 0 | 95,024 | Reject |

The exact final Scheme Wasm consumed by native lowering also passes the original
input on V8. This gives 41 required correctness executions per workload. Three
Rust library tests additionally check the small rewrite counts, sharing and
numeric/repeated-variable unification. Native C interfaces check positional
scalar signatures. The complete process records include commands, exit status,
stdout, stderr, timeout status and process-group cleanup; a successful clean
correctness record requires its exact output frame and empty stderr.

Five separately labeled observations run on each of the five Scheme paths,
giving 25 diagnostic executions per workload. They compare the complete
ordered lemma table; identity and unification assertions; a narrow constructor
ordering witness; the complete normalized size-0 term; and full size-5 work
counts. Assertions include numeric constants, repeated variables, partial
bindings surviving a failed unification, reset at the next top-level attempt,
constructor cycles/reset, fresh translation/substitution spines and SBoyer's
two-field identity rule. Failed unification is not given transactional rollback.

Structural observations use kernel bodies without work-counter edits. A
procedure-entry logger changed Chez inlining and operand scheduling during
development, so it was removed. The work-counter program is separate, and its
source-cons counter expands as syntax. Both Chez diagnostic programs compile
at optimize level 2, like the complete controls. Exact ordered streams must
match across the five systems; a count or digest of a differently ordered
structure is insufficient.

| Source operation, full original size 5 | NBoyer | SBoyer |
| --- | ---: | ---: |
| rewrite | 51,507,739 | 51,507,739 |
| rewrite-args | 101,900,430 | 101,900,430 |
| rewrite-with-lemmas | 68,699,742 | 68,699,742 |
| apply-subst | 6,590,695 | 6,590,695 |
| apply-subst-lst | 7,908,889 | 7,908,889 |
| one-way-unify | 18,307,050 | 18,307,050 |
| one-way-unify1 | 40,911,692 | 40,911,692 |
| one-way-unify1-lst | 24,059,434 | 24,059,434 |
| term-equal? | 204,265 | 204,265 |
| tautologyp | 186 | 186 |
| translate-term | 1,262 | 1,262 |
| add-lemma | 106 | 106 |
| explicit source cons | 118,128,901 | 17,982,522 |
| sharing-cons | 0 | 101,900,430 |
| sharing reuse | 0 | 100,146,379 |

These are entries to source operations, not physical allocation totals. Helper
list construction, quoted constants and Ref storage are outside the explicit
source-cons count. Counter programs retain the final rewritten term for
observation, so their live ranges and allocation behavior do not describe clean
execution. The complete size-0 term is serialized; the full size-5 term is
validated by its original theorem/rewrite predicate and the work stream rather
than by serializing that whole tree.

The ordered lemma stream is 41,701 bytes with SHA-256
`ee6fdc409f584469b7a64bd790371fcb7d601ff7c320403745b72d036e76b97a`.
The complete size-0 streams are 719,827 bytes for NBoyer and 719,836 for SBoyer;
their difference includes the sharing counters. All five copies of each
workload's stream match exactly. The parent independently reviewed the adapter
and verified 837 identities, all 190 completed process records, all 50 complete
Scheme fixture frames, all 50 ordered diagnostic streams and the native-final
Wasm identities. The author performed a separate audit of the same artifacts.

## Native capacity and lifetime observations

Clean native correctness uses an explicit 2 GiB reservation for NBoyer and
1 GiB for SBoyer. The preparation selects these reservations directly and never
silently retries a failed run. Both final native executables still fail at the
default 256 MiB reservation with the recorded arena-exhaustion error. Capacity
and collection-statistic invocations are separate diagnostics and cannot satisfy
the clean correctness gate.

The collector is the current nonmoving exact collector with its default 8 MiB
minimum allocation budget. Statistics report marked object payload extents;
they exclude arena slack and do not prove that every marked byte is necessary
to the source semantics. Exact registered roots can retain generated values
beyond their final source use. `peak_live` samples collections, while
`arena_used` is the used-block high-water mark. Reservations are virtual address
space, not a claim that every reserved byte is resident.

The separate lifetime executable inserts collections before and after the
worker. Its worker module is byte-identical to the final clean native module;
the C entry and collection schedule differ. It runs a setup-only baseline and
the complete original workload. These observations distinguish persistent
post-return retention from transient marked storage, but do not isolate line
fragmentation, representation cost or temporary root lifetime as a sole cause.

| Exact native-final Scheme module | SHA-256 |
| --- | --- |
| NBoyer | `8b1e3d29f3abaa976f126c867cd1561122db1eeea84b3400e09501129a7b26e3` |
| SBoyer | `516f1a41d794e724828df9a985a93d00ef220abf2dcf526064a89480b7f7bb0a` |

| Separate native lifetime observation | NBoyer | SBoyer |
| --- | ---: | ---: |
| Selected reservation | 2 GiB | 1 GiB |
| Smaller tested reservations that fail | 256, 512, 1024 MiB | 256, 512 MiB |
| Setup-only marked payload after collection | 192,560 B | 192,576 B |
| Full workload marked payload after return and collection | 343,992 B | 344,008 B |
| Full workload sampled peak marked payload | 944,883,176 B | 313,025,688 B |
| Full diagnostic object-construction requests | 359,440,532 | 59,001,388 |
| Full diagnostic allocated payload | 8,692,156,392 B | 1,481,616,992 B |

The small post-return footprint bounds persistent retention after the worker;
it does not explain why so much storage was marked during execution. The
[NBoyer](nboyer-lifetime.json) and [SBoyer](sboyer-lifetime.json) records retain
the separate schedules and capacity failures. Their collection-phase times
are diagnostic elapsed times, not clean benchmark comparisons.

## Independent Rust controls and retained evidence

The Rust controls retain their existing implementation: immutable `Rc` cells
for calls, arguments and substitutions; vector constructor records with integer
constructor IDs; tail loops and reference-counted destruction. Integer IDs
avoid constructor-record ownership cycles. Scheme retains its source recursive
procedures and Datum/Ref storage. Rust's scanner reads all input datums before
the worker, while Scheme reads the three used datums. Full original input bytes
are supplied to both. These controls establish useful independent correctness,
not identical generated code, allocation, object layouts or a causal GC-only
comparison.

Preparation and both independent audits are retained alongside original and
adapted programs, reversible ledgers, raw/optimized/native artifacts, native
LLVM, hosts and scalar interfaces, original input bytes, diagnostic programs
and streams, complete command records, Rust sources/binaries/emitted code and
the meaningful rejected development comparisons. External tool binaries and
Cargo target caches are excluded. The offline builds use the default
`/home/nti/.cargo` cache with `CARGO_HOME` and `RUSTUP_HOME` unset.

The [focused simplify review](simplify-review.md) records the fresh independent
behavioral explanation, its debate and the resulting refinements. Incidental
elapsed fields in preparation and diagnostic captures are not clean performance
samples. Generic measurement deliberately rejects these ports pending a
separately frozen timing plan.

The complete preparation command is:

```sh
python3 benchmarks/strict-suite/measure.py prepare \
  --output build/boyer-prepared-combined \
  --benchmarks nboyer sboyer --compiler-basis 6fd5ca4
```

Use a fresh output directory when repeating it. Retained commands contain their
original absolute paths; replay elsewhere requires verified path mapping and
the pinned external tools.

The report records completed preparation and diagnostics. Compressed evidence
packaging is still pending; clean comparative timing has not started.
