# Complete hexagonal Maze correctness preparation

The original **10,000 constructions of a 20 × 7 hexagonal maze** pass on
original Chez, exactly adapted Chez, raw linked Wasm, Binaryen-optimized Wasm,
and mechanically lowered native64. Every run checks the complete supplied
**668-character list**, including 42 newlines. The unchanged Rust reference
passes native, raw Wasm, and optimized Wasm controls. The exact final Scheme
Wasm consumed by native lowering also passes directly on V8.

**No clean comparative timing has been performed. This preparation does not
increase historical measured coverage.** Elapsed fields in process captures
are correctness or diagnostic observations only.

Compiler/library basis is 27604d44652f74169104d25c3a3edc8a0bb653ca; the adapter
commit is af0d3a68ea4e85fc63d8380fee756f5e02962a22. No compiler, frontend,
collector, or reusable library changed. The upstream corpus remains clean at
85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1. The source SHA-256 is
b5b6307faab776b66f59b602c1327a79b925c64fa08bc421f931abe73bbd0c6e; the full
input SHA-256 is 90874004ae477b9a77164e83459454490a6da66a29cca6cb5d1f71e2b04bb1a9.

## Source operations and explicit representation changes

The [adapter](../../strict-suite/maze_port.py) applies 68 counted reversible
ledger entries. They restore the complete original kernel byte for byte.
Original and adapted Chez retain their complete corresponding benchmark bodies,
and the adapted kernel is identical to the one compiled by Snail. A fresh
source regeneration independently reproduces all six retained production
source files exactly.

The original recursive bitwise-and, div and mod algorithms remain. The port
does not substitute the new integer bit primitives. It preserves the RNG
constants and seed 20, wall construction order, shuffle bounds, reverse scan,
union-by-size tie direction, both root walks, DFS callbacks, rerooting, candidate
order, strict-greater path choice, marking, character prepends and reversal.
Two-pass compression stops before rewriting the final already-root link.

Mutable pair and vector fields become concrete records with typed Ref fields.
Set and cell identity use a fresh field Ref; aliases share those same fields.
Coordinates and result records expose the original fields. Parents and
entrance/exit choices retain explicit absent states. Array slots begin as an
unfinished Cell variant and are filled in the original descending-row,
ascending-column order before use.

The continuation in dig-maze is an immediate lexical escape. Its only call
occurs after union, the owner-wall write, and the resulting set-size check; it
is never stored, returned, or resumed. The adapted callback returns completion
to a reverse traversal that stops before another lookup or index update.
The ignored result becomes Unit. This adds no general continuation support.

The output accumulator's initial false value becomes an empty typed list:
every benchmark invocation resets it before any reachable access. Directly
calling write-ch before the first run would therefore have a different
precondition; that is outside this benchmark's entry contract. The benchmark's
separate initial false result remains observable for zero and negative counts.
The adapted final predicate distinguishes false, character lists and other
datums, compares every character and both list endings, and preserves Chez's
wrong-result printing. Ref fields and typed variants have different allocation
costs from the source vectors and pairs.

## Complete validation and separate observations

Seventeen fixtures execute on each of the five Scheme paths: the original
count, once, twice, altered Unicode character, missing character, extra
character, reversed order, non-character element, zero count with false, zero
count with the normal list, negative count with false, and six positive grids:
1 × 1, 1 × 2, 2 × 1, 2 × 2, 3 × 3 and 4 × 4. Their complete expectations come
from the original Chez source. All 85 required fixture executions pass.

The separate [observation program](../../../tests/strict-maze/probe.scm)
executes signed integer helper cases, ten RNG values, set identity and
compression checks, mutable cell/wall alias checks, complete constructed and
shuffled wall vectors, the exact visited reverse prefix, all cell/parent/set
fields after digging and after marking, and every output character. It then
counts the full original number of constructions. Original and adapted Chez
observers compile at optimize level 2.

Both the once and full-count streams match across all five Scheme systems.
The full stream has 8,567 fields and SHA-256
9d484738b6f58cc95b86ba0e35a67700f0d0a617fa16cdde495142209b8239a6.
The validated visited sequence is exactly the reversed shuffled-vector prefix:
286 walls are examined, 139 walls are removed, and the remaining 81 walls are
skipped. Entrance column 6 and exit column 2 produce 55 marked path cells.

| Source operation | One maze | Original 10,000 mazes |
| --- | ---: | ---: |
| Cell construction | 140 | 1,400,000 |
| Wall construction | 367 | 3,670,000 |
| RNG call | 365 | 3,650,000 |
| Recursive bitwise-and entry | 3,213 | 32,130,000 |
| div entry | 5,827 | 58,270,000 |
| mod entry | 736 | 7,360,000 |
| Set-root lookup | 1,267 | 12,670,000 |
| Union | 139 | 1,390,000 |
| Visited wall | 286 | 2,860,000 |
| Reroot | 8 | 80,000 |
| Path-length query | 49 | 490,000 |
| Character emission | 668 | 6,680,000 |
| Parent write | 224 | 2,240,000 |
| Mark write | 55 | 550,000 |
| Compression write | 130 | 1,300,000 |

These are source-operation observations, not allocation totals. All counters
and detailed trace calls are absent from production kernels. The clean native
timing provider also disables opacity-call counting; the ordinary correctness
provider checks all 20,000 calls. The earlier counting native control is retained
separately as a diagnostic.

## Independent Rust control and retained evidence

The unchanged Rust implementation uses indexed Vec cells and walls, native
integer bit operations, temporary child vectors, owned Box character lists and
iterative destruction. Its row-major cell allocation also differs from the
source's descending-row construction. These are independent algorithm/storage
and lifetime choices, not an equal-allocation or isolated-collector control.
All 21 required Rust executions pass: once, twice, canonical and four complete
wrong-list fixtures on three targets. Its input boundary requires an unsigned
count and character-list expectation; the false/non-character expected cases
are checked on the five Scheme paths.

[The archive](artifacts.tar.gz) retains compiler and supervisor sources,
complete original inputs and programs, ledgers and diffs, raw/optimized Wasm,
native executables and generated LLVM, exact native-final module and scalar
provider, Rust sources/binaries/LLVM, every ordered stream, and full command,
stdout, stderr, return-status and process-cleanup records. External tool
identities are hashed; Cargo target caches are excluded. Its SHA-256 is
3ec10ed96a6a033ae97d284f11e48f83a27423b325f9887f03d7484491de44bb.

The [author audit](author-audit.json) checked 161 terminal process records and
648 retained file identities. Four development failures remain explicit:
an unavailable reader predicate name, a missing R7RS shim in a dimension oracle,
a polymorphic diagnostic shuffle receiving a Wall-specific logger, and an
overbroad Chez import in the compiled observer. They required adapter or
diagnostic corrections only. The first failed strict source is reconstructed
by reversing its sole documented API-name correction; other failed sources
remain directly retained. No failed attempt supplies a passing result.

The [focused simplify review](simplify-review.md) records the independent
explanation and debate. Reproduce preparation with a fresh output directory:

    python3 benchmarks/strict-suite/measure.py prepare \
      --benchmarks maze --output build/maze-prepared \
      --compiler-basis af0d3a68ea4e85fc63d8380fee756f5e02962a22

The preparation basis includes the new Maze probe; its compiler and library
sources are identical to 27604d44652f74169104d25c3a3edc8a0bb653ca.

Retained commands contain their actual absolute paths. Replaying an extracted
archive elsewhere requires verified path mapping. Seven clean comparison
commands are frozen in maze/controls/commands.json; their execution remains
the coordinator's next step.

## Integration review

The root independently replayed all 68 source edits in both directions and
checked the complete retained observation streams against original Chez. All
five Scheme paths agree on the ordered walls, mutations, full character output,
and complete 10,000-invocation work counts. The [review record](integration-review.json)
retains the source and trace identities.

After integration above the Conform reports and growing native collector, the
current adapter regenerates the exact same production Scheme source. A fresh
build passes the complete canonical input on raw linked Wasm, Binaryen optimized
linked Wasm, and native64, with the expected result, 20,000 opacity calls, and
input lifetime markers. The actual build-and-execution tool session reached
exit zero; `make check` also passes. These are correctness checks, with no new
performance samples or increase in historical measured coverage.
