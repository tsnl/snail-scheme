# Complete exact-integer comparison controls

Pi and Chudnovsky pass complete-output validation on all eight requested
comparison systems. These are prepared artifacts and diagnostic evidence;
no clean timing has been taken and measured suite coverage is unchanged.
The reusable Integer implementation and original source ledgers are documented
in the [arithmetic/adapter report](../2026-10-14-strict-integer/README.md).

| Workload | Original repetitions | Precision | Production Wasm | Native-final Wasm |
| --- | ---: | --- | ---: | ---: |
| pi | 100 | 50 through 500 digits, step 50; all three original algorithms | 19,458 bytes | 35,797 bytes |
| Chudnovsky | 1,000 | 50 through 500 digits, step 50; complete binary splitting | 18,558 bytes | 24,821 bytes |

The controls are production Wasm/V8, the exact native-final Wasm/V8, native64,
compiled original Chez, compiled adapted Chez using native big integers,
compiled Chez executing the same checked limb body, Rust native, and optimized
Rust/Wasm. Raw Scheme and raw Rust/Wasm are additional correctness controls.
Native builds include the two reviewed allocator inlining annotations from
`e2c05ce`. Chez uses optimization level 2. Rust uses the frozen reference source,
`num-bigint` 0.4.8, release optimization/LTO, and the established Binaryen `-O3`
WASI feature set. Exact tools and hashes are in [tools.json](tools.json).

## Full outputs and negative controls

Every system compares the entire numerical result. The visible pi result
contains all ten Borwein2 values and both original difference columns, preserving
every rounding difference. Chudnovsky retains all ten full integers. The outputs
match the independently executed original Chez programs byte-for-byte after
ordinary Scheme decimal serialization.

Each production artifact also ran count 0, 1, and 2. Count 0 performs no numerical
iteration and does not satisfy the nonempty expected result. Scheme exposes a
false result flag and an empty observed list; Chez and Rust reject the empty
result. Counts 1 and 2 produce the complete expected result. Negative controls
add one to the first expected integer and separately to the final table
component. Both are rejected by the production result predicate on every
system. The first mutation changes low-order digits; the final pi mutation
specifically exercises the last difference column.

Separate reversible Scheme probes serialize every iteration's complete result.
At counts 0, 1, 2, and the full original count they pass raw Wasm, optimized Wasm,
native-final Wasm/V8, and native64. Thus the full probes observe all 100 pi tables
and all 1,000 Chudnovsky lists. These probes are never substituted for measured
artifacts. Their extra serialization is diagnostic work.

## Retained production work

The optimized production Wasm retains the count guard, three scalar opacity
imports, their returned digit arguments feeding the full workload, and the
increment/backedge. Pi's `function138` invokes the complete `function139` range
calculation; its three numerical recurrence bodies remain `function142`,
`function144`, and `function146`. Chudnovsky's `function140` invokes
`function141`; each precision reaches `function130`, which calls the recursive
binary split `function126`.

Final native machine code confirms those dependencies. Pi's `f.64` decrements
the repetition count, calls `hide_i64` three times, passes all three returned
values to `f.65`, and returns to the count guard. Chudnovsky's `f.66` likewise
keeps the imported values and the precision traversal inside its repetition
loop; its `f.59` numerical calls remain on the normal path. The empty-range
branch depends on returned first/last precision and is not taken for 50..500.
The completed result reaches the final numerical comparison.

Default-V8 code capture ran the exact production and native-final modules at
their full counts. The observed outer repetitions were Liftoff functions:
index 64 for pi and index 66 for Chudnovsky. Their machine code retains the
imported-return dependencies, numerical call, and recurrence. The complete
capture also preserves inner functions that tier up. No tiering or optimization
flag was changed; the added flags print code. These records establish the
observed tiers and configurations, not an assertion that later runs can never
tier differently. Module hashes, observed tiers, selected bodies, complete code
dumps, and native disassembly are retained in each workload archive.

## Comparison boundaries and source differences

All optional workload clocks exclude input/expected parsing, module setup, and
decimal output. They include the original repetition loop and one final complete
numerical predicate. The original workloads likewise retain and check their last
result. No predicate was inserted into each measured iteration.

| Control | Material differences retained in the comparison |
| --- | --- |
| Strict Scheme targets | Immutable nominal Integers and private I32 GC limb arrays; ordinary Scheme arithmetic. Three imported scalar calls per repetition count barriers and return digit controls. Their cost remains inside the clock. |
| Original/adapted native-bigint Chez | Chez's native exact arithmetic and original `hide` behavior. The adapted source is a source-equivalence control with explicit constant lifting. |
| Same-limb Chez | Identical arithmetic body with record/declaration/vector-copy translation and checked scalar operations. Expected values become Integers before the clock and compare numerically. General Chez vectors/scalars and explicit I64/I32 checks differ from native I32 arrays and proved fixed-width arithmetic. |
| Rust native/Wasm | Frozen independent implementation using `num-bigint` arithmetic and `black_box`. Bounded canonical precision/term controls are `u32`; the complete Chudnovsky constant cube remains `u64`. Allocation, arithmetic implementation, layout, and opacity differ. |

Rust's only new source edits make its existing reporting clock optional during
preparation. The reversible ledger restores its original source exactly.
Canonical inputs satisfy the Rust scalar bounds; full results validate on both
architectures. These controls do not isolate integer representation alone.

## Frozen evidence and later execution

The [manifest](manifest.json) identifies all archives and the explicit attempt
lineage. They retain original/adapted/strict/compiled-Chez sources, complete
inputs and outputs, raw/optimized Wasm, native binaries and LLVM, Rust binaries,
emitted LLVM/assembly, source ledgers, every command record, and all diagnostics.
Build caches are omitted. The initial compiled-Chez attempt rejected an imported
`expt` redefinition; excluding that import fixed the limb control. Its failed
source/logs remain separate, all Chez controls were regenerated/revalidated,
and unchanged independent Scheme artifacts retained their identities. A failed
Chibi version-option query is also retained; the corrected query uses `-V`.

The [timing plan](timing-plan.json) lists sixteen concrete system/workload
commands, exact artifact hashes, input paths, and runtime environment guards.
It has not been executed. The complete local preparation import set
(`integer_controls.py`, `integer_ports.py`, `data_ports.py`) is frozen and passed
an isolated, clean-directory import check. Timed commands depend only on frozen
hosts/programs and the pinned runtimes. Reproduction of compiler preparation
uses the repository sources and tool identities recorded in the bundle.

Before timing, verify all hashes/environment guards and obtain the coordinated
quiet-window release. Run fresh processes serially using the frozen plan.
The retained verification establishes that every command path exists and every
artifact hash matches; optional timer branches await that later invocation.
There are no live preparation descendants or outstanding process handles.

The focused simplify explanation used a fresh Astra/max agent with no history,
files, or tools. It confirmed the final-only predicate boundary and kept
instrumented observations distinct from production retention evidence. We kept
the direct preparation loops and explicit system rows together; their complete
build/validation contracts are the deliberate exceptions to the ten-line target.
