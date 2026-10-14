# Strict quicksort construction diagnostics

The frozen quicksort module requests ten WasmGC objects whenever it enters a
nontrivial partition. Instrumented execution of the unchanged canonical workload
records **16,705,000 nontrivial partitions and 167,050,000 construction requests**.
Captured V8 TurboFan code retains all ten allocation paths. Passing the private
partition data directly in a diagnostic fixture preserves the sort work and
reduces the whole-process GC trace's summed `allocated` fields from
**6,334,710,400 bytes to 223,455,856 bytes**. These observations identify substantial
closure scaffolding and heap traffic; they do not assign a fraction of the
[previously measured quicksort overhead](../2026-10-13-strict-quicksort/README.md)
to allocation or establish a comparative speed result.

This investigation starts from `dcad7138637cf4a5dc163c768e7c54cbf1e61a28` in a
separate worktree. The original source, compiler, driver, host, canonical input and
measured binaries remain unchanged. Preparation still belongs to compiler
`5894df771cace27507e0f1ab15f6dd320d2a6ad4`, and the driver to
`86d49d4d7f36b00f48724f3fe63854a2afe2413d`. The optimized measured module has SHA-256
`e947322337325a79d278ffb0d7f3cb95340d54ab50e8b98a95a49868d8ece282`.
The probe archive contains a separate copy of that payload and every diagnostic
patch, command, retained binary, raw output and profile. It introduces no production
profiling module or compiler fix.

The primary CPU/GC observation runs the original source and binary using Node
24.19.0, CPU 5, unset `NODE_OPTIONS`, and default V8 tiering, with only
`--cpu-prof` and `--trace-gc-nvp` added. Other workers could perform correctness
work; this was not a coordinated performance window. There is no timer anchor in
either profile. Startup, input generation and other observed process work remain
in scope. Profiling and tracing overhead were not independently measured.

| Primary original whole-process self samples | Count | Share |
| --- | ---: | ---: |
| Upward scan, `function56` | 744 | 35.13% |
| Partition swap/loop, `function58` | 654 | 30.88% |
| Recursive sort helper, `function54` | 305 | 14.40% |
| Downward scan, `function57` | 294 | 13.88% |
| Per-element map loop, `function52` | 68 | 3.21% |
| GC-labelled samples | 30 | 1.42% |

The denominator is 2,118 self samples. The sort helper includes allocation,
readiness checks, captured-data access, inlined partition work and recursion;
its sample share is not an allocation-cost share. Inlining and sampling affect
function attribution. The first profile, which overlapped this worker's code
printing run on CPU 5, is preserved separately and excluded from the primary
interpretation.

| Whole-process trace observation | Original | Direct-parameter fixture |
| --- | ---: | ---: |
| Scavenge events | 450 | 70 |
| Sum of reported `allocated` fields, bytes | 6,334,710,400 | 223,455,856 |
| GC-labelled self samples | 30 / 2,118 | 3 / 1,183 |

V8 defines `allocated` as a difference between heap object sizes at successive
collection boundaries. The sum includes startup objects and other process work,
omits allocation after the last GC, and has no construction-site attribution.
`pause` is printed to 0.1 ms; many events display zero, so summing the printed
fields does not give a precise total pause duration. The separately rounded
`scavenge` phase field is also not total collector CPU. These definitions are
checked against the pinned [Node 24.19.0 V8 GC tracer source](https://github.com/nodejs/node/blob/v24.19.0/deps/v8/src/heap/gc-tracer.cc#L759).
The raw logs and derived rounded sums remain archived, while the table makes
only the observed event and field comparisons.

The ten original construction sites are inside the `left < right` branch of
optimized WAT `function54`, lines 3330–3383. Each runs once before the partition
call. Wasm index 27 corresponds to this function in the frozen binary.

| WAT site ordinal | Purpose | Type | TurboFan bytes |
| ---: | --- | --- | ---: |
| 0 | Upward scan readiness cell | `type52` | 32 |
| 1 | Upward scan closure | `type21` | 32 |
| 2 | Upward scan environment | `environment56` | 48 |
| 3 | Captured immutable pivot cell | `type37` | 32 |
| 4 | Downward scan readiness cell | `type52` | 32 |
| 5 | Downward scan closure | `type21` | 32 |
| 6 | Downward scan environment | `environment57` | 48 |
| 7 | Partition readiness cell | `type53` | 32 |
| 8 | Partition closure | `type29` | 24 |
| 9 | Partition environment | `environment58` | 56 |

The generated optimized code contains ten bump-pointer limit checks, top updates,
object initialization paths, and corresponding allocation slow paths, totaling
368 bytes per nontrivial partition in that captured code. V8 reorders operand
construction: pivot and environments precede their enclosing closures. The
machine audit records exact offsets, sizes and excerpts. Multiplying those
static sizes by the separate instrumented path counts gives a 6,147,440,000-byte
size model. It is not a measured physical-allocation total: the original run's
tier transitions and dynamic machine paths were not counted, and engine work
such as function-reference materialization is outside the ten-site inventory.
No construction at these ten sites was eliminated in the captured TurboFan code.

Counters wrap each struct/array instruction with a numeric global increment
before its original operands. Function entries are counted too. New globals
contain no Scheme references, and the hot path invokes no JavaScript counter
callback. The adapter snapshots initialization counts after `main`, resets the
numeric globals, and snapshots workload counts afterward. Those counts describe
entered Wasm requests in the instrumented binary, including requests whose
operands could later trap. All retained canonical executions complete normally.
Instrumentation affects optimization and register pressure, and its elapsed
times are diagnostic only.

| Canonical workload count | Original counters | Fixture counters |
| --- | ---: | ---: |
| Partition scaffolding requests | 167,050,000 | 0 |
| Recursive helper entries | 33,412,500 | 33,412,500 |
| Upward scan entries | 206,467,500 | 206,467,500 |
| Downward scan entries | 205,685,000 | 205,685,000 |
| Partition loop entries | 79,207,500 | 79,207,500 |
| Mapper construction requests | 15,000 | 15,000 |
| Outer sort-context requests | 7,500 | 7,500 |
| Repeat/final-check context requests | 6 | 6 |

Every remaining construction-site count and every function-entry count agrees
between the two instrumented variants at counts 1, 2 and 2500. All ten original
partition sites record 16,705,000 entries; each sort has 6,682 nontrivial partitions.
The mapper still performs all 25,000,000 per-element visits, including its original
first-element fill and later stores. The final predicate still traverses the last
result once after the 2500 repetitions.

The fixture's sole intervention is in WAT functions 54, 56, 57 and 58: partition
data that was carried by private, nonescaping closures is passed as direct
parameters. It removes the ten construction sites and their readiness/field
loads and changes private helper signatures and calls. It also removes repeated
unsigned-index checks in the partition loop and checks `j`'s width before reading
`i`, whereas the original reads `i` first. These changes preserve results for the
valid initialized input domain; their simplification and ordering are part of
the combined intervention. The pivot remains the last element, both scans and
the crossing swap/restoration remain equivalent,
and the smaller partition is visited first. Pivot restoration reads the current
vector after the crossing swap. The unchanged RNG generates the base vector
before the workload; copying, outer sort context and final predicate remain
byte-for-byte the same in WAT. These simultaneous representation and call changes
prevent attributing any diagnostic elapsed difference solely to allocation.

An unmodified WAT reassembly control is retained for future comparison. It has
SHA-256 `517a373f06c492fafbc89603fc4eac70d8c2b312d3d530414b51a24d39d33f35`,
and differs from the measured binary in code section 10 and custom `name` section.
Neither binary contains a `target_features` section; explicit feature flags are
recorded in the build commands. Encoded bodies 37, 48, 66, 67 and 70 gain scratch
locals and instructions, including the canonical repeat helper 70. The text
disassembly diff shows changes in only functions 48 and 66, so text equality
alone does not prove binary equality. Function 54 and 33 other bodies are
byte-identical. The exact section hashes, local encodings, instruction hashes,
binary control and disassembly diff are archived. This is a real code-encoding
control; a future clean comparison must include it alongside the original frozen
module and changed reassembled fixture.

Actual Node checks cover 14 expected outcomes for each of three variants,
including deliberate wrong-value, short-result and long-result rejection. The
two counter variants also pass full canonical counts 1, 2 and 2500. A supplemental
independent expected vector checks all 10000 canonical values, exact length,
duplicates, input preservation and fresh nonempty result identity for both
fixture variants. The scope and result of every check are archived.

The parent independently exercised constructor operands that branch out by name
or trap after an observable effect. Raw and instrumented Node execution agree;
both entered-request counters record one even though construction does not
complete. Those source, binary and adapter witnesses are archived separately.
The unmodified reassembly control has only static verification at this checkpoint;
it still needs actual Node correctness checks before a future clean comparison.

Failed and superseded attempts remain visible. Initial assembly with
`--all-features` emitted compact imports unsupported by the pinned Node, producing
`CompileError: unknown import kind 0x7f`; that binary and failure are retained.
The final fixtures use the frozen compiler's explicit Binaryen feature flags.
An intermediate build that additionally enabled multivalue was superseded before
Node validation; its command is retained, while its overwritten output was not
separately saved. The original overlapping profile and global code-printing capture
are retained with their diagnostic limitations; the latter printed all functions,
and the function 54 blocks were extracted afterward.

Three failed static metadata assumptions are also retained: the canonical-count
specification was already in the frozen payload, binary body differences extended
beyond the textual disassembly diff, and the optional feature section was absent.
Correcting those audit expectations changed no fixture, profile, construction
count or correctness result.

The archive manifest verifies exact files and hashes. Restore the archive to a
fresh directory, verify every manifest entry, and run its `analyze-evidence.py`
with that directory as its argument to reproduce the derived data without
executing a workload. The original canonical report's source and archive are
unchanged. The diagnostic fixtures and one-off generators are frozen for the
parent's focused explanation review before any separately coordinated clean
comparison.

The compact findings are in [summary.json](summary.json), with exact hashes in
[evidence-manifest.json](evidence-manifest.json), the
[probe archive](probe.tar.xz), and its
[restoration verification](archive-verification.json). The
[neutral review brief](review-brief.md) identifies requirements and limits for the
parent's fresh explanation and critical debate.
