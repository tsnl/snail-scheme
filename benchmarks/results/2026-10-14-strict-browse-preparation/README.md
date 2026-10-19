# Complete Browse preparation

The complete canonical Browse workload passes raw linked Wasm, mandatory
Binaryen-optimized linked Wasm, actual native64, original Chez and the exact
adapted Scheme body on Chez. All five execute counts 1, 2 and the original
2,000, including the complete final 100-integer result predicate. Seven timing
controls are prepared. **No clean measurement is claimed.** This preparation
adds no measured coverage to the historical 37 of 57 workloads.

Sources remain pinned to upstream
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. The compiler and library basis is
`15d2c64` in the isolated `/tmp/snail-strict-browse-20261014` worktree, above
`6a8e476` and the reader-preparation dependency. The archive retains the actual
compiler, library, linker and native-runtime sources. Later integration changes
are not substituted into these artifacts.

| Input | SHA-256 |
| --- | --- |
| Complete 203-line `src/browse.scm` | `6d40dd2f2276926c656e2575c95e2844f4558925c97e7797d4b9c5ad04940776` |
| Original `inputs/browse.input` | `c9382e4142ae4a3b78bc80a0dd299355ca917eb204b190b82298fe76c3dc702f` |

## Source and representations

[`browse_port.py`](https://github.com/tsnl/snail-scheme/blob/2db2216b32254bbaf9b49ebed30e0bca495ec6c2/benchmarks/strict-suite/browse_port.py) makes counted reversible
edits to the complete source kernel. The source lookup/put association lists,
generated interned names, copied three-tree cyclic pattern ring, tree-copy
sharing rules, destructive list shuffle, nested investigation loops and both
result maps remain. Setup creates 100 units with ten additional properties and
four shared pattern references per unit. The original final unused gensym step
also remains. There is no reduced worker or precomputed result service.

Mixed source values become the shared closed `Datum` variant. Every mutable
datum pair contains two explicit Ref cells; mutable source bindings use Ref
as well. Symbols retain interned identities. Generated decimal names use the
Scheme `i64->string` helper, including its complete signed-I64 contract. The
source's `symbol->string` calls remain inside the matcher. Source pair/list
operations use the reusable datum library. `datum-list` accepts a typed Rest
list and builds the datum spine; its intermediate homogeneous spine and the
explicit pair field cells are representation costs, not equal-allocation claims.

`my-match` has three result classes: False, True and Empty. False is the only
false condition. In particular, the source's nonempty-pattern/empty-data arm
returns the truthy empty list. Short-circuit helpers preserve the selected
result class, evaluation order and skipped recursive branches; they do not
turn every truthy result into True. The matcher remains one source-shaped
exhaustive dispatch so its exact terminal, named-variable and star cases can
be read beside the original.

The [datum contract](https://github.com/tsnl/snail-scheme/blob/2db2216b32254bbaf9b49ebed30e0bca495ec6c2/doc/strict-reader.md) deliberately bounds proper
list operations to finite spines and structural equality to finite acyclic
data. Pair identity means both field storages are identical. Two public raw
`datum-pair` views over the same two Refs are aliases; sharing just one field is
not pair identity. Fresh `datum-cons` creates fresh storage. Numeric atom
equivalence follows the existing Number policy and is not a claim about every
R7RS implementation's numeric `eq?`. Browse's identity comparisons use symbols,
pairs and null, so no numeric equality substitution affects its matcher.

Adapted Chez executes the exact edited workload and library Scheme bodies.
Its local compatibility boundary erases annotations and represents variants
and Refs with Chez vectors; scalar services use Chez facilities. Original Chez
executes the unchanged source body and upstream harness. Reversible source
edits and these differential executions support the tested input domain; they
do not prove equivalence for every possible Scheme value or error.

## Correctness and retained work

`build/browse-attempt2` contains the successful artifacts and command records.
Its parts were prepared incrementally during development. The final freeze
regenerates every clean and observed workload source and requires exact byte
identity with the built sources. Module-test regeneration permits whitespace
formatting only. Re-running the compiler with a source-map recorder reproduces
the clean WAT byte for byte, tying its function names to the current library.
Earlier failed attempts and their logs are retained separately in the archive.

The three canonical counts pass on all five Scheme paths. Four negative
expectations—wrong value, short list, extra value and reordered values—fail
the original complete predicate on each path. Empty patterns, changed patterns,
zero count and negative count also agree. Zero and negative counts return the
source's initial false result. Input parsing and file close occur once during
setup; no file I/O occurs in the timed workers.

Separate observation programs serialize all recursive matcher arguments
immediately at entry and each selected result class immediately at return.
They include the full ordered worker results and the copied ring's contents
and cycle identity. Snapshots are not deferred references to mutable operands.
The five executors produce byte-identical observations:

| Canonical count | Recursive entries | False / True / Empty returns | Top-level matches | Trace bytes |
| ---: | ---: | --- | ---: | ---: |
| 1 | 49,000 | 38,000 / 3,300 / 7,700 | 1,200 | 19,607,537 |
| 2 | 98,000 | 76,000 / 6,600 / 15,400 | 2,400 | 39,214,356 |

The internal-trace claim is bounded to these counts. Full 2,000-invocation
executions are unobserved internally. The trace decoder independently checks
event framing, nesting, result classes, worker indices and the 100 × 3 × 4
top-level matches per worker. Seventeen targeted matcher cases distinguish
literal failures, named single and sequence bindings, repeated bindings,+nested trees, short-circuit cases and Empty returns. Changed and empty pattern
inputs also have complete matching five-path traces.

Separate setup probes test copied versus shared tree nodes, destructive append
with a shared suffix, property-entry mutation, ring sharing and the destructive
shuffle. Datum module tests cover raw pair views, each partial-sharing
counterexample, cyclic rest mutation, list sharing/lookup/map, string/vector/
bytevector storage identity, symbol interning, truthy null and decimal I64
limits. They return 42 on raw Wasm, optimized Wasm and native64. `make test` and
`make check` pass. No compiler or Rust runtime implementation changed here.

The final database does not by itself show that the discarded matcher results
were computed. The separate [retained-work inspection](retained-work.md)
therefore follows clean raw, optimized and native-final Wasm call paths through
all three investigation loops to the recursive matcher. The actual native
executable still has `main → f.105 → f.102`, with recursive matcher calls and
allocation calls present. No production observer was added to retain this work.
Static retention evidence is separate from the instrumented traces and does
not establish equal allocation counts across executors.

## Distinct Rust controls

The existing Rust reference is unchanged. Its native, raw-Wasm and optimized-
Wasm artifacts pass counts 1, 2 and 2,000 with the complete printed result; all
four wrong expectations trigger its full assertion. Its focused unit tests
also pass. Clean measurement selects optimized Wasm and native only.

Rust uses Vec database/property tables, Rc lists, string symbol comparisons
and copied star-prefix spines where the Scheme source mutates a fresh tail.
It collapses Empty and True into one Boolean truth category and applies
`black_box` to each match result. Its initialization shares parsed pattern
trees through vectors instead of constructing a cyclic list ring. These are
algorithm, ownership and layout controls, with different allocation and
reclamation behavior; they are not an identical representation port.

## Frozen timing plan

[`timing-plan.json`](timing-plan.json) selects original Chez, adapted Chez,
production optimized linked Wasm on V8, actual native64, V8 executing that
exact native-final Scheme Wasm with its scalar provider, Rust native and Rust
optimized Wasm. The exact-module control isolates the Scheme module; its Rust
provider compilation target and linkage still differ from native.

All seven clocks start after database initialization and input parsing, then
include all 2,000 complete worker invocations and the final predicate.
Serialization, output and terminal cleanup follow the clock. The Scheme timing
hosts use an opaque constant barrier without observational counting. Rust
retains its existing black boxes. There is one predetermined discarded round,
then seven retained rounds with every system occupying every order position:
56 fresh, serial processes pinned to CPU 5, each with a 120-second timeout.

The supervisor freezes executable modules, providers, inputs, hosts, its Python
helpers, compiler/runtime sources, tool identities, Chez boot files and resolved
dynamic-library identities. Dry verification imports the frozen `matrix_port`
and `data_ports` modules and checks their exact paths and hashes. Seven retained
protocol records validate output framing; their incidental durations are
correctness diagnostics and are excluded from future clean summaries.

Each sample owns a process group from Popen through capture, timeout handling,
leader reap and bounded cleanup. Logs retain stdout, stderr, status and live
group checks. SIGTERM unwinds through cleanup. Namespace-local PIDs are checked
by the owning supervisor, never inferred from an unrelated tool namespace.

```sh
python benchmarks/results/2026-10-14-strict-browse-preparation/measure-seven.py
```

That command verifies the frozen plan and starts no benchmark. The `--run`
campaign is reserved for the root-coordinated quiet window after review.
The [archive manifest](manifest.json) records every packaged file and the
compressed artifact hash; all regular archive members are read back and hashed.
