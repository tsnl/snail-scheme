# Bounded bigint products: faster on V8 and native64

Replacing division and remainder by a power of two in Integer's bounded
multiply/subtract worker reduces complete Pi time by **20.5% on production
V8 and 29.5% on native64**. Chudnovsky takes **13.1% and 16.6% less time**,
respectively. These are fresh builds of the production source change, following
a separate Wasm-instruction ablation. The benchmark programs, full inputs,
iteration counts and complete numerical predicates are unchanged.

The source change is in [PR198](https://github.com/tsnl/snail-scheme/pull/198).
Fresh preparation compares `d685a644207805a3f9e755e00fcbcac12118735f` with
`fdb9eb65bdfcd0e8752a2745350ced26ff9bd0f9`. Integration commit `af5e833`
contains the identical source changes above the later report-only stack entries.
All production paths run Binaryen. The native backend mechanically lowers the
optimized Wasm and uses the existing exact collector; this experiment does not
include the separate automatic heap-growth work.

## Fresh production comparison

Times are workload seconds, including computation and the complete numerical
predicate, excluding input parsing, setup and result serialization. Each row
has twelve retained samples per revision. Ranges retain every observation.

| Workload | Execution | Baseline median [range] | Candidate median [range] | Less time |
| --- | --- | ---: | ---: | ---: |
| Pi | Production V8 | 2.242324534 [2.225715419–2.260680600] | 1.782598224 [1.760417092–1.814866987] | 20.50% |
| Pi | Native-final Wasm on V8 | 2.217098874 [2.200246729–2.247074412] | 1.751301662 [1.736273358–1.785149566] | 21.01% |
| Pi | Native64 | 1.775911575 [1.774602556–1.784088962] | 1.252264644 [1.251065377–1.256956619] | 29.49% |
| Chudnovsky | Production V8 | 0.717095894 [0.711776444–0.722604029] | 0.623202943 [0.619443954–0.632604376] | 13.09% |
| Chudnovsky | Native-final Wasm on V8 | 0.719078746 [0.714246836–0.726920171] | 0.629459445 [0.626131496–0.635649821] | 12.46% |
| Chudnovsky | Native64 | 0.656761135 [0.655624544–0.657565838] | 0.547604734 [0.546079374–0.549940441] | 16.62% |

Native and its native-final V8 control consume the exact same final Scheme Wasm
bytes within each revision, with different scalar service providers/linkage.
On the candidate, native takes 28.50% less time than that V8 control for Pi,
and 13.00% less for Chudnovsky. This is a result for these two workloads,
not a claim that native is faster throughout the suite.

The [independent review](independent-review.json) rechecks all 156 captures,
144 retained clocks, complete output bytes, cleanup records, the frozen
schedule and 361 artifact identities. It independently reproduces all medians,
ranges and twelve paired revision ratios for each mode. All candidate samples
are faster than their matched baseline samples. The actual runner handle
`75613` returned exit zero before other agents' heavy work resumed.

No Chez or Rust comparison was rerun in this experiment. Historical coverage
remains 44 of 57 workloads, 43 paired with Chez; these are accumulated reports
from different compiler revisions, not one current whole-suite run.

## Why the substitution is valid

Integer stores unsigned base-`B` limbs, with production `B = 2^30`. In this
worker the product plus incoming carry is at most `B * (B - 1)`, below `2^60`.
Its low limb is therefore `product & (B - 1)` and its high limb is a logical
right shift by 30. If the high limb reaches `B - 1`, the low limb must be zero,
so the subtraction cannot introduce an additional borrow in that case. The
carry bound is preserved. This proof belongs beside the library operation;
the compiler does not guess that arbitrary signed division has these semantics.

The compiler exposes ordinary I32/I64 bitwise-and and logical-right-shift
primitives through the shared primitive table. Shift counts follow Wasm's
low-five/low-six-bit masking, including negative and oversized counts. The
Integer body differs only in these two operations and explanatory comments.
Public signed integer behavior and all four sign combinations remain intact.

Disassembly confirms one `i64.and` and one `i64.shr_u` replace the worker's
`i64.rem_s` and `i64.div_s`. Its tail call, seven trapping guards and two array
stores remain. The freshly compiled production worker matches the successful
probe worker text, but complete modules differ; production timings above were
measured independently. Native scalar tests retain real indirect calls and
execute the register operations, including the masked-count edge cases.

## Earlier instruction ablation

Before changing production source, a frozen optimized Wasm worker was changed
at just those two operations. The controls include unchanged original bytes,
a disassemble/reassemble round trip, that round trip optimized again, the two
bit operations, and that version optimized again. Ten samples per variant and
workload were retained after one predetermined warmup each: 110 processes,
100 retained measurements, all with complete numerical outputs.

| Workload | Original | Round trip | Round trip + optimizer | Bit operations | Bit operations + optimizer |
| --- | ---: | ---: | ---: | ---: | ---: |
| Pi | 2.238181710 | 2.265546602 | 2.216105453 | 1.798934306 | 1.754128951 |
| Chudnovsky | 0.719917571 | 0.719749980 | 0.719197734 | 0.626423244 | 0.628968077 |

Against the corresponding round-trip controls, Pi takes 20.60% less time
without the additional optimization and 20.85% less with it. Chudnovsky takes
12.97% and 12.55% less. Thus the instruction substitution helps independently
of the extra optimization pass. Separate V8 code captures show the expected
mask and shift in TurboFan output. Code-size differences alone are not used
to explain the speedup. These timings remain separate from the fresh
production comparison.

## Correctness and protocol

Validation includes 307 strict contracts; 64,512 exhaustive small-radix pairs
at each of radix four and radix `2^30`; 2,912 integer oracle cases; 442 Chez
scalar-oracle cases; and direct/first-class scalar operations on raw Wasm,
optimized Wasm and native. Complete Pi and Chudnovsky controls include counts
zero, one and two, full canonical counts, and deliberately wrong first/final
expected values. Fresh baseline/candidate preparation completed 96 controls,
then the frozen measurement runner completed twelve untimed full-output probes.
Repository Scheme, Rust, formatting, linked-backend and build checks pass.

The clean production schedule uses Pi count 100 and Chudnovsky count 1,000,
CPU 5, a fresh process for every invocation and a 60-second timeout. Twelve
untimed warmups precede twelve measured rounds. Two six-row Williams cycles
put each system in every serial position twice and each directed adjacent
pair twice; candidate precedes baseline six times and follows it six times.
Workload order alternates by round. There is no sample trimming or replacement.

Node 24.19.0, Binaryen 132, Rust 1.95.0 and LLVM 22.1.8 tool records, source
identities, exact commands, complete stdout/stderr, process-group cleanup and
host snapshots are preserved. The host is an Intel Core Ultra 7 270K Plus on
x86-64 Linux. Recorded CPU policy is stable; fresh processes do not establish
cold caches or absence of unrelated host activity. Owned build, diagnostic
and archive jobs were held during the clean campaign.

## Retained evidence

The archive preserves production preparation and captures, both independent
reviews, the earlier instruction ablation and its captures, source validation,
Wasm/LLVM/machine-code inspection, tool records and coordination boundaries.
Preparation records that say timing had not started remain historical records;
the completed campaigns and reviews supply the later result.

`package.py` verifies compressed and decompressed byte identities without
executing guests. `--prepare` requires the original evidence locations, takes
one private copy, checks it against the parent's audited hashes, and archives
that copy. Missing selected evidence or changed audited bytes fails. External
tool binaries and regenerable Cargo/Python caches are omitted; tool identities
remain recorded. The manifest maps every retained member to its exact bytes.
Paths inside the archive are relative to `/tmp`, except this report under
`report/`; the frozen runners record their original absolute execution paths.
