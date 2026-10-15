Replacing the ordered-pair visited table's hash reduces complete Equal time by
**20.42% on production V8 and 22.37% on native64**. The native-final Wasm V8
control takes **20.53% less time**. These are clean matched timings of the
unchanged workload. Preparation clocks and instrumented runs remain separate
diagnostic evidence.

Each row retains twelve samples per revision. Times are workload seconds;
ranges include every observation.

| Execution | Baseline median [range] | Candidate median [range] | Less time |
| --- | ---: | ---: | ---: |
| Production V8 | 2.407796387 [2.395139371–2.423135005] | 1.916144544 [1.900747618–1.925821927] | 20.42% |
| Native-final Wasm on V8 | 2.407543313 [2.397128475–2.422049894] | 1.913311304 [1.902610720–1.921986852] | 20.53% |
| Native64 | 2.131489824 [2.126920892–2.149926297] | 1.654610151 [1.635240675–1.672358821] | 22.37% |

All 78 processes passed. The actual clean runner session `25799` returned exit
zero before the quiet window was released. Independent raw-byte replay
reproduces every median, range and all 36 same-round candidate/baseline ratios;
every candidate sample is faster than its matched baseline sample. The
ratio-of-medians values are 0.795808381, 0.794715216 and 0.776269317; their
paired-ratio medians are 0.795260046, 0.793443731 and 0.773793891. These are
measurements for Equal on this host, with no whole-suite performance claim.
The parent's separate raw-data audit independently agrees with every result.
On the candidate, native64 takes 13.52% less time than its exact-native-final
Wasm V8 control, with their respective scalar providers and default collectors.

The full canonical input is `100 100 8 1000 2000 5000 #t`. All five enabled
Clinger phases and the original exact-`#t` predicate run inside the workload
clock. The cyclic phase disabled by the canonical program is covered separately
for correctness. Parsing and setup precede the clock; output serialization and
resource cleanup follow it. Neither revision changes the kernel, input, host,
runtime provider, traversal, visited-table layout, growth or collision equality.

Three execution modes are matched within each revision: production V8,
native-final Scheme Wasm on V8, and native64. Production paths run Binaryen.
Native mechanically lowers optimized Wasm to LLVM and retains the existing
precise collector and its default settings. Native and its V8 control consume
the same final Scheme Wasm bytes with their respective scalar providers. The
separate native heap-growth work is absent from both revisions. No Chez or
Rust comparison is rerun for this ablation.

The baseline compiler/library snapshot comes from
`27604d44652f74169104d25c3a3edc8a0bb653ca`. The candidate was frozen from
uncommitted bytes, with its exact patch, status and source hashes. Its final
`i64-mul`/`i64-add` spelling produces identical Wasm bytes to the initial
candidate at all four recorded stages. Both native builds use that same
initial candidate lowering compiler. Its original library spelling is
reconstructed from final bytes and checked against every recorded source hash;
the native backend reads the already-built Wasm. Commit provenance at freeze
is kept distinct from a later source commit.
Post-freeze source commit `86fcb33` matches every one of the 466 retained
candidate source files and every compiled-source hash. This is a source-identity
check; the timing still describes the frozen uncommitted artifacts.

The schedule has one discarded full-workload warmup per system and twelve
retained samples per system: 78 fresh, serial process invocations. Two six-row
Williams cycles place every system in every position twice, every directed
within-round adjacent pair twice, and candidate before baseline six times and
after it six times in each mode. CPU affinity is fixed to CPU 5. Runtime and
GC behavior keep their reviewed defaults; `BINARYEN_CORES=1` is recorded. No
samples are trimmed or replaced. Fresh processes do not establish cold caches
or the absence of unrelated host activity.

`freeze.py` copies compiler/library/FFI and benchmark artifacts, captures the
dirty source provenance and import/dynamic-library closure, replays complete
existing correctness frames, and writes the immutable plan. It starts no
benchmark guest. The original candidate/native commands, actual providers,
runtime archive, optimized Wasm and LLVM are retained. The first source-status
capture failed because Git followed a permitted read-only submodule symlink;
that attempt is preserved. Source-scoped status inspection resolved it. The
root's later environment-metadata correction and its earlier plan are also
retained explicitly.

`measure.py` verifies all frozen identities before and after the campaign and
the command/module/input/provider identities before every invocation. It owns
each process group through actual termination, bounded cleanup and raw byte
capture. Nonzero exit, stderr, timeout, interruption, unexpected descendants,
changed identities/settings, or an invalid complete frame aborts the campaign.
Native requires result 1 and the original lifetime fields: barriers 0,
setup_closed 1, worker_closed 0 and closed 1. V8 requires result 1. Both require
one complete JSON object with exactly one final newline and a finite positive
clock; duplicate fields, extra output and Boolean substitutes for integers fail.

`review.py` independently consumes the raw bytes without importing runner
validation or analysis. It checks every command, terminal/cleanup record,
capture identity and schedule row, then recomputes all six medians/ranges and
twelve same-round candidate/baseline ratios per mode. Ratio of medians and
median of paired ratios are reported separately. Synthetic capture fixtures
retain malformed bytes, actual exit/signal statuses and process-group cleanup;
their clocks are excluded from the benchmark population.

Separate instrumentation confirms equal work except for probing: both
revisions create 8,108 histories, hash 81,715,848 keys, perform 34,905,800
lookups and 30,412,800 inserts, and grow 60,004 times. Array slots allocated
remain 374,999,296 and rehashed keys remain 46,810,048. Probe steps decrease
from 112,284,044 to 109,840,096. These counters explain work and carry no clean
timing claim. A frozen diagnostic report preserves all individual counters.
The counters do not isolate how much improvement comes from hash dispersion
and how much comes from cheaper arithmetic.

The replacement mixes both identity words with wrapping 64-bit multiply/add,
XOR and logical shifts, then masks to the table's power-of-two capacity. Its
overflow semantics are explicit in Scheme and preserve the full I64 domain.
Hash equality still only chooses candidate slots; the table compares both
ordered identity words to establish a visited pair. Cycles, shared structures,
growth, duplicate detection and collision resolution keep their prior behavior.

The native-final optimized Wasm hash worker changes from four signed divisions
and nine signed remainders to zero div/rem, seven XORs and six logical shifts.
This is a static Wasm worker comparison. The baseline LLVM uses native division
and remainder helper calls, so searching only for LLVM `sdiv`/`srem` instructions
would misdescribe it. A baseline native symbol was inlined away; symbol presence
is not used as an instruction-level performance comparison. The measured full
aggregate and separate work counters supply the performance evidence.

The host is an Intel Core Ultra 7 270K Plus on x86-64 Linux. Node 24.19.0,
Binaryen 132, LLVM 22.1.8 and Rust 1.95.0 build/tool records are retained with
exact bytes, commands and identities. Host snapshots preserve CPU policy and
affinity. Root strict validation completes all 307 contracts; separate native
scalar-word validation retains all 32 indirect calls through optimized Wasm,
LLVM and the actual executable and returns the expected result 42.

`package.py` takes one private evidence copy, checks it against the completed
independent audit, and archives that copy. Its manifest records every regular
member's hash, bytes and mode. Verification checks one complete XZ stream,
safe exact tar inventory and zero trailing padding; unsafe names, duplicates,
file/parent conflicts, missing members and changed bytes fail. It performs no
guest execution. Failed/superseded preparation and instrumentation attempts,
synthetic tests and terminal evidence are retained. External immutable tools
and unfrozen regenerable caches are omitted while their identity records remain.
Explicitly audited local dependencies are retained even when they are bytecode.
The first archive preparation stopped before compression because its cache
exclusion omitted one such dependency; that terminal failure is preserved.
Member paths are relative to `/tmp`; execution records retain original absolute paths.

## Integration and focused source review

The hash source commit was integrated above the growing native collector and
completed Maze/Conform preparation. Fresh builds pass the complete original
Equal input and all Datum tests on raw linked Wasm, optimized linked Wasm, and
native64. The optimized production Wasm is byte-identical to the measured
candidate. The [integration record](integration-review.json) preserves actual
tool completion and artifact identities; these correctness runs supply no
additional performance samples.

A fresh Astra explanation without repository access separated bucket selection
from exact ordered-pair membership. Informed review retained the asymmetric
full-word mixer, the local mask-range invariant, independently computed golden
words, and deliberate collision/growth tests. Changing which key is mixed first
or adding a statistical distribution threshold had no demonstrated benefit.
No further source refactor was warranted within this pure hash operation.
