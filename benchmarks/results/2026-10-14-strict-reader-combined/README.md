# Combined strict reader candidate

The combined candidate reduces Read1's workload median by **22.604%** against
the same current baseline in a separate coordinated campaign. All **44**
predetermined fresh-process executions pass, with ten retained executions and
one discard per system/workload. The independent A/B results remain in their
[separate report](../2026-10-14-strict-reader-ablations/README.md); their percentages
are not added to obtain this result.

| Workload | Source | Workload median (s) | Ten retained range (s) | / current baseline | Process median (s) |
| --- | --- | ---: | ---: | ---: | ---: |
| Sum1 | Current baseline | 1.053711 | 1.033194–1.154992 | 1.000× | 1.082961 |
| Sum1 | Combined A+B | 0.956942 | 0.946697–0.969493 | 0.908× | 0.985133 |
| Read1 | Current baseline | 2.718722 | 2.682634–2.742350 | 1.000× | 2.750387 |
| Read1 | Combined A+B | 2.104174 | 2.093586–2.126961 | 0.774× | 2.134935 |

[audit.json](audit.json) retains full precision and process ranges. Sum1's
baseline remains broad with separated timing groups; its observed median
reduction is **9.184%**, without a stable-gain or confidence-interval claim.
Canonical Sum1 contains numeric atoms, already staged once before B. No sample
is excluded or replaced. The ranges are observed minima/maxima. This campaign
measures the complete combined change, including its intermediate result
constructors; it does not separately attribute transfer or handle costs.

Source commit `20b4d2100c3640c50fb535a70956d0b4128a9554` starts at
`c0ba036499de55622538fc4c077fb8951b510502` and combines only
`965070112eeb9a2ab63a47f21086d5a11c7f61f7` (direct delimiter checks) and
`b56d8e322b3bdaef79b33546bc5a981605396f98` (single atom staging). Static file
and section checks confirm the unchanged A delimiter body and B atom ownership
body, Rust transition, datum result placement, Chez mock and responsibility docs.
Compiler files are identical to baseline; only read/datum/strict_datum differ
among compiled sources. The existing data-only ReadResult is shared and
re-exported through the unchanged reader API; Token remains private to read.

The pre-timing [preparation audit](preparation-audit.json) verifies 95 reader corpus cases
on raw linked Wasm, optimized linked Wasm and native: 32 complete streams,
60 syntax errors and three UTF-8 traps. Exact module-final datum tests return
42 on all three paths, preserving Browse's identity/list/decimal tests and the
new numeric/error/nonnumber and duplicate-symbol cases. All 44 offline Rust
tests, Rust formatting, Scheme tests and Scheme formatting pass. Direct literal
`a|b|` and complete unchanged adjacency traces match baseline on all six paths;
the fixture's explicit Chez spelling `a |b|` does not conceal a grammar change.

Sum1 preparation passes counts 1, 2 and full 25; Read1 passes 1, 2 and full
2,500, on raw Wasm, optimized Wasm, actual native, original Chez and adapted
Chez. Every raw/optimized worker's exact buffered cycle is independently
checked: Sum1 reads 1,100,000 bytes in 136 buffered WASI reads, Read1 reads 28,300
bytes in five, each including one EOF followed by close. Native close totals,
barriers and full predicates pass. Complete canonical field streams cover one
full invocation, while every outer file cycle is checked at all tested counts.
Existing changed-input/repeated-call, final-predicate and malformed/error-boundary
probes remain in the completed preparations. Cleanup checks cover all 546
recorded commands; 35 expected negative exits remain distinct from failures.

The exact optimized AB Read1 binary has SHA-256
`b10be422cd323188121d1f0aede79a2df9371a1f18df65b1f2267a1dd7abe3ca`.
[retained-code.json](retained-code.json) maps actual Wasm indices and construction
sites to its retained disassembly. Next-token `function154` (Wasm index 33)
contains two stage-text call sites and retains two read-value sites (`type132`,
tag 1) and two read-error sites (`type133`, tag 2), before private token conversion.
These intermediate result constructors remain part of the cost model. Static
sites establish neither dynamic counts nor V8 allocation/elimination behavior.
Delimiter `function184` (index 43) directly compares twelve fixed scalars and
calls only Unicode whitespace; the former recursive String scan is absent.
[delimiter-function184.wat](delimiter-function184.wat) preserves that body.

The historical [predeclared plan](plan.md) describes preparation and the measurement
contract. Correctness and the campaign are now complete. The frozen [timing-plan.json](timing-plan.json)
has SHA-256 `c9f573cacaf32c3af39d5c0f7e66cb86fe6ec207a80fab90882b8158ca2808bc`,
with **265** verified source/tool/input/artifact/dependency identities. It reuses
the exact baseline production binaries and the independent report's unchanged
runner (`e2ddab6bec989227cf9b639fd98f16ad75dfced6e11b414395a2ca3d0645ccfd`)
with its accepted eighteen-module closure and guarded module origins. Each of
two systems/workloads has one predetermined discard and ten retained executions,
balanced five times per within-round position. Full counts, serial CPU 5,
normal V8 tiering/heap policy, original setup-before-clock host and complete
results remain fixed. Root explicitly released the coordinated quiet window
after other owned handles were terminal and held other heavy work through this
campaign. OS cache and CPU frequency are uncontrolled. Immediate host snapshots
are retained with the raw records; PID numbers within an observer's namespace
do not establish unrelated host-process absence.

Actual owned preparation/check/corpus/unit handles 85922, 10933, 50333 and
62224 are terminal exit 0. Campaign handle **1398** was polled to terminal exit 0
before the independent audit checked every raw output, full predicate, exact
schedule/command/environment, balanced positions, cleanup state, recomputed
summary and all 265 frozen identities. No live owned process remains. The focused
behavioral review is shared with the independent changes; this branch adds no
production redesign or new observer machinery.

Root separately reviewed every campaign row, exact raw record, full result
framing, command/environment, cleanup state, balanced schedule, summary and
frozen identity, plus host affinity/frequency policy. Its
`campaign/parent-independent-review.json` is retained with the campaign evidence.

## Retained evidence and reproduction

[manifest.json](manifest.json) checks every member of
[artifacts.tar.xz](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-strict-reader-combined/artifacts.tar.xz). The archive retains the complete combined
preparation with source snapshots, build commands, raw/optimized linked Wasm,
native artifacts, full disassemblies, native LLVM, input files, canonical streams
and all correctness/negative/ownership probes. It also retains the 95-case corpus,
public datum unit execution, direct literal comparison, Scheme/Rust check
captures, the exact combined source patch, all 44 campaign records, immediate
host snapshots and root's independent review.

The exact timed baseline binaries/configuration/input files and unchanged
runner/host/full supervisor closure are included. The complete earlier baseline
preparation and its source snapshots remain in the independent report's archive;
the manifest pins that archive and its member manifest by hash. Both reports
preserve the same baseline artifact identities. This avoids rebuilding or
silently substituting a baseline for the combined comparison.

Restore this archive under a fresh `build/reader-combined-evidence` directory.
Its `prepared`, `corpus`, `datum-units`, `literal-delimiters`, `checks`,
`campaign`, `source-changes`, `timed-baseline` and `shared-runner` scopes retain
the evidence. [archive-verification.json](archive-verification.json) records full
decompression and member-hash verification. Frozen commands keep their original
isolated-worktree paths; adapting paths elsewhere requires a new frozen plan.
Keep the successful records unchanged and coordinate any new timing separately.
