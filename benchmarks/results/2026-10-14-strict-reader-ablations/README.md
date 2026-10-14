# Independent strict reader ablations

Against the same current baseline, direct delimiter checks reduce Read1's
workload median by **5.917%**, and single atom staging reduces it by **18.317%**.
All **60** predetermined fresh-process executions pass. Each candidate/workload
has one discarded execution and nine retained executions, balanced across all
three within-round positions. These are independent candidates; their gains
must not be added to predict a combined implementation.

Sum1's baseline has a wide, visibly separated timing distribution. The observed
median ratios are retained below, but B's Sum1 result is not a stable-gain claim
or evidence of saved symbol transfers: canonical Sum1 contains numeric atoms,
which were already staged once. No timing sample was replaced or selectively
removed. Ranges are observed minima/maxima, not confidence intervals.

| Workload | Source | Workload median (s) | Nine retained range (s) | / current baseline | Process median (s) |
| --- | --- | ---: | ---: | ---: | ---: |
| Sum1 | Current baseline | 1.129985 | 1.041084–1.149848 | 1.000× | 1.158950 |
| Sum1 | A: direct delimiters | 0.948825 | 0.941313–0.969946 | 0.840× | 0.979183 |
| Sum1 | B: single staging | 1.059443 | 1.052530–1.106682 | 0.938× | 1.086473 |
| Read1 | Current baseline | 2.718491 | 2.696329–2.744687 | 1.000× | 2.750135 |
| Read1 | A: direct delimiters | 2.557647 | 2.553921–2.630585 | 0.941× | 2.589102 |
| Read1 | B: single staging | 2.220534 | 2.197359–2.240320 | 0.817× | 2.252268 |

[audit.json](audit.json) retains full precision, process ranges and independently
recomputed summaries. Source/library basis is
`c0ba036499de55622538fc4c077fb8951b510502`, including Browse's datum helpers and
the current native allocator. These artifacts and medians do not replace the
earlier `4176e30` [seven-system comparison](../2026-10-14-strict-reader-comparison/README.md).

## Separate source changes

Both branches start directly at the common basis; neither includes the other.
The compiler implementation is unchanged byte for byte.

- **A**, `965070112eeb9a2ab63a47f21086d5a11c7f61f7`, replaces the fixed String
  delimiter scan with direct Scheme scalar comparisons. EOF, Unicode whitespace,
  the twelve fixed delimiters and lookahead keep their order/behavior. Token
  staging is unchanged. Only `src/snail/read.sld` differs among compiled sources.
- **B**, `b56d8e322b3bdaef79b33546bc5a981605396f98`, keeps the original delimiter
  scan and the same Scheme word buffer/final String. The datum layer stages an
  ordinary atom once and applies number parsing, numeric errors, identifier
  validation and interning in order. Dot handling remains before staging.
  `ReadResult` moves as data only into datum and the existing reader API is
  re-exported. There is no new public result hierarchy or callback framework.
  Only datum/read and `src/strict_datum.rs` differ among compiled sources.

Every atom path closes or consumes its owned scalar handle once before return.
Rust accepts the existing Text interning path and the additional
`Parsed { result: Ok(None), text }` transition. Parsed numbers/errors are still
rejected and consumed; the historical rejection diagnostic is preserved. Token
handles stay private to the datum wrapper, hold no Scheme roots and invoke no
user callback while owned. Parser construction/collection remains in Scheme.

B also updates the existing Chez scalar mock to retain a parsed token's text
and mirror the consume transition. This is necessary for the exact adapted
Scheme reader to execute; it is outside the timed production V8 path. Browse's
datum identity/list/decimal tests and semantics are preserved.

## Correctness and literal delimiter boundary

Each current baseline/A/B workload preparation passes counts 1, 2 and the
full canonical counts on raw linked Wasm, optimized linked Wasm, actual native,
original Chez and adapted Chez. Sum1 remains **25** complete reads of its
100,000-number file; Read1 remains **2,500** complete reads through all five
datums. Real per-worker opens, full buffered reads through EOF, closes, opacity
calls and final predicates are checked. Negative final predicates, changed
files/repeated calls and immediate malformed-input boundaries are retained.

Baseline and B each pass the original **84** reader corpus cases on raw Wasm,
optimized Wasm and native: 30 complete valid streams, 51 syntax errors and
three UTF-8 traps. A passes those plus eleven focused cases, **95** total:
32 complete streams, 60 syntax errors and three UTF-8 traps. Focused cases cover
all twelve delimiter characters, adjacent atoms/forms, EOF/Unicode whitespace,
representative nonmembers, and a preserved preceding atom before rejected
square/brace delimiters. Complete canonical field streams cover one full input
invocation; they do not claim internal field traces for every outer repetition.

Chez's extended grammar concatenates `a|b|` into symbol `ab`. The strict reader's
existing contract treats `|` as a delimiter and returns `a` then `b`. A's fixture
therefore uses explicit Chez spelling `a |b|`, while the literal strict input
stays unchanged. This difference is recorded as oracle compatibility in the
fixture validation. The first failed oracle comparison is retained; it caused
no production code change or artifact rebuild.

A separate direct comparison bypasses Chez: unchanged literal `a|b|` and the
complete unchanged adjacency input produce byte-identical full field traces on
baseline/A raw Wasm, optimized Wasm and native, all six paths. Thus fixture
spelling does not conceal an A behavior change. The existing corpus runner
reuses the unchanged A compiled artifacts into a new validation directory.

B's exact module-final datum test body, extracted with Browse's established
approach, returns 42 on raw Wasm, optimized Wasm and native. It covers duplicate
ordinary symbols, numeric/complex results, numeric-error priority, invalid/empty
atom errors and the original storage/identity/list/decimal contracts. Its helper
does not produce EOF. Rust tests check Text/nonnumber consumption, rejected
numeric/error consumption, surviving independent handles and duplicate interned
identity. Both A/B pass `make test`, `make check`; B also passes
`cargo fmt --all -- --check` and all 44 `cargo test --offline` tests.

## Actual optimized code

The retained production disassemblies come from the exact measured binaries.
In baseline/A, `function152` retains next-token/atom dispatch; it contains four
static stage-text call sites. B's `function154` contains two: one ordinary atom
stage and the unchanged sharp-numeric stage. Static call-site counts are not
dynamic service-call counts or estimates of linked-machine-call overhead.

A's delimiter `function182` calls Unicode whitespace and directly compares the
twelve constants `40 41 34 59 124 39 96 44 91 93 123 125`. Its call to recursive
String scan `function183` disappears. B preserves the original scan through
`function184` → `function185`. The fixed String was a module constant, not a
per-character String allocation.

**B retains intermediate result constructors in final Binaryen output.** Its
next-token body has two static `read-value` sites (`$type132`, tag 1), for numbers
and symbols, and two `read-error` sites (`$type133`, tag 2), for numeric and
identifier errors. The subsequent conversion constructs private `value-token`
(`$type164`, tag 0). These source-introduced wrappers must remain part of the
ablation's cost model. No assertion is made that V8 allocates or eliminates
each constructor; the Wasm code does not measure that engine behavior. Existing
character-result wrappers, word buffers/substrings and container representations
also remain. The independent result supports this whole small B change, not
separate attribution to transfers, handles or result placement.

## Frozen timing and process ownership

The [plan](timing-plan.json) has SHA-256
`e55ab9ec987cf14371fbcd06850348db4e178a01be4494f84b6df508ef7cee7a`.
The reviewed runner is copied unchanged, SHA-256
`e2ddab6bec989227cf9b639fd98f16ad75dfced6e11b414395a2ca3d0645ccfd`.
All **379** source/tool/input/artifact/runner identities are verified; all **18**
accepted local Python supervisor modules are copied unchanged and their origins
are guarded. The sources' independent difference sets are checked before freeze.

Only production linked Wasm/V8 is timed. The original host finishes setup before
the workload clock and keeps every file cycle and final predicate inside `bench`.
Sum1 precedes Read1; all processes are serial on CPU 5. Default V8 tiering and
normal heap policy remain, without counters, profiling or GC overrides. The
predetermined discard round warms an uncontrolled OS file cache. Immediate host
snapshots retain processor/affinity/frequency-policy/load evidence; frequency is
not pinned. Root coordinated the quiet window and held other heavy work.

The actual owned campaign session **14793** was polled to terminal exit 0 before
claiming completion. The independent audit checks all sixty raw outputs, full
predicates, exact commands/schedule, nine retained rows per case, three retained
appearances per position, empty live cleanup members, unchanged frozen identities
and independently recomputed summaries. Raw records equal the campaign rows.
All preparation/corpus/unit/direct-comparison handles are terminal. Namespace-local
PID numbers are not evidence of unrelated host-process absence.

## Retained evidence and reproduction

[manifest.json](manifest.json) identifies every member of
[artifacts.tar.xz](artifacts.tar.xz); [archive-verification.json](archive-verification.json)
records a complete decompression and member-hash check. The archive retains all
three full workload preparations, source snapshots/build commands, raw and
optimized linked Wasm, native artifacts, full disassemblies, native LLVM,
canonical streams, correctness/ownership/negative probes and input files. It
also retains all three complete corpus runs, the initial A oracle failure,
corrected-oracle validation using the same compiled artifacts, B's public datum
unit execution, direct literal-delimiter comparison and all sixty campaign
records plus immediate host snapshots. Source patches preserve the independent
A/B changes against the common basis.

Restore the archive under a fresh `build/reader-ablation-evidence` directory;
its `baseline`, `A`, `B`, `literal-delimiters`, `campaign` and `source-changes`
scopes are recorded in the manifest. Frozen commands retain their original
isolated-worktree paths. Recreating a run elsewhere requires explicit path
adaptation and a new frozen plan; do not overwrite this successful campaign.
The original [preparation plan](plan.md) is marked historical, and this report
records its completed status. [simplify-review.md](simplify-review.md) documents
the focused behavioral explanation, ownership decisions and verification.

## Follow-up combined candidate

The independent branches and evidence stay separate. The later
[combined comparison](../2026-10-14-strict-reader-combined/README.md) starts from
the same basis, combines only these two changes, and repeats full correctness,
ownership and reference checks before a separately frozen timing campaign.
Its measured result does not add the independent percentages reported here.
