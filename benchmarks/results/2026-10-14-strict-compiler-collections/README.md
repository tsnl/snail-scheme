# Compiler collections and adapted Chez output

Source commit `2f4a57f7e6a656cc00cd7ff8f93fcd2f846c9508` adapts 41 complete
upstream collection functions and three diagnostic functions. It depends on the
writer prerequisite `43c8929`, locally cherry-picked as `52e8d01`. The complete
typed compiler workload remains pending. These are correctness diagnostics,
with no clean timing samples or speedup claim.

The original corpus is pinned to `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`.
Every generated partial adaptation retains the entire 459,221-byte compiler
source, including all definitions outside the adapted forms. The unchanged
8,377-byte input requests 2,000 complete compilations and compares the ordered
497-line assembly result. Reversing each counted source-edit ledger restores
every original source byte. The unadapted forms are present, but are not yet
typed or executed by the typed collection fixture.

## Checked behavior

| Check | Result |
| --- | --- |
| Unchanged original collection bodies | 14 contracts and three independent ordinary-host-failure controls pass under Chez |
| Identical typed collection bodies | 22 contracts pass under Chez, raw linked Wasm, mandatory-Binaryen linked Wasm, and actual native64 |
| Terminal host failures | Short right zip input, absent graph target, and negative list index escape the installed compiler handler on all four targets; preceding stdout remains and later work does not execute |
| Compiler queue abort | Exact original diagnostic appears once on stdout; earlier mutation remains; the typed handler consumes the explicit abort |
| Complete compiler ordering experiment | Original, chosen left-to-right map, and chosen map/set head sequencing each pass the full unchanged 2,000-compilation / 497-line predicate under Chez |
| Exact shared writer under the new Chez boundary | All 68 readable/displayed rows and round trips, eight graph rows, depth 8,192, stdout ownership/defaults, and six terminal failure cases pass |
| Scalar I/O boundary | Lookahead, path/ID transitions, cleanup order, exhausted-ID non-truncation, failed-close descriptor release, and 18 fresh-process malformed UTF-8 cases pass |
| Existing reader controls | Generated text remains byte-identical for the existing reader interface |

Collection cases cover zero versus absence, dotted zip rows, alternating sort
comparison order, equal-key decisions, suffix sharing, copied removal prefixes,
duplicate occurrence-set semantics, fold orientation, association aliases,
Unicode string/vector conversions, graph convergence and wrapper identity,
queue sharing and detached stored tails, counter failure, and callback abort
after mutation. The extra result constructors and propagation branches remain
in the identical adapted Chez bodies. Pure callbacks retain pure signatures.

The map experiment changes all 72 executable `map` calls in the complete original
compiler, then separately sequences the `set-map` and `set-keep` heads before
recursion. It retains native pairs to isolate order from typed representation.
Scheme does not prescribe the original callback order; passing these controls
supports the chosen order on the canonical workload, without claiming it is a
language rule or that the complete compiler is already typed.

The list-to-vector mapping adds concrete initial storage: a nonempty vector is
allocated with its first list item as a default before executing the original
full fill loop. This adds an initial read and initialization work. No source
sort, set, graph, queue, numeric, reader, or compilation algorithm is replaced.

The lexical operation audit accounts for all 1,345 source forms and records
108 external names / 4,580 references, each with its containing definition,
source line, ASCII byte offset, and call/value role. The complete inventory and
its small source-specific audit script are retained in the archive. The
[port contract](../../strict-suite/compiler-port.md) groups those operations
and identifies the exact library and source-adaptation boundaries.

## I/O scope and failure ownership

The new Chez invocation scope executes the unchanged I/O, Integer, Rational,
Number, Datum, reader, and writer bodies in private library scopes. Static
default/explicit output overloads call the same named Scheme functions. The
only new host work is the scalar file ABI; native Chez does not print Datum.
The earlier reader generator retains its previous native input boundary and
unchanged generated text.

Binary input preserves NUL, BOM and separate CR/LF scalars. Scalar lookahead
distinguishes absence, zero and EOF. File IDs never repeat; failed open consumes
an ID, pathname consumption occurs on failure too, and exhaustion precedes
creation/truncation. Borrowed stdout is never closed and flushes each scalar.
Owned cleanup follows issue order, releases every remaining owner, and retains
the first failure. Ordinary host failures stay outside the compiler's typed
abort channel.

The concrete `/dev/full` probe found that Chez leaves the descriptor open after
a failed buffered close. The bridge retries pending bytes once, then discards
the failed buffer and closes before propagating the first condition. The second
probe verifies both `port-closed?` and disappearance of the descriptor in
`/proc/self/fd`, including cleanup of another pending file. Chez documents
binary standard ports and explicit buffer discard in its
[I/O reference](https://cisco.github.io/ChezScheme/csug10.3.0/io.html).
The bridge follows the Rust provider's explicit close followed by buffered-port
drop; platform diagnostic spelling and host buffer/allocation costs remain
implementation properties.

Locally caught provider conditions allow inspecting ownership transitions and
exhausted-ID state. They are host-only diagnostics, not guest recovery. All
malformed guest input and writer failures instead use fresh terminal processes
and check prior output and pending-file cleanup. The writer cases are the
existing independent fixture and oracle; this bridge check adds no replacement
formatter or reduced input.

## Retained attempts and actual completion

[checks.json](checks.json) contains 120 terminal command records, source hashes,
artifact provenance and actual outer-tool completion records.
[diagnostics.tar.gz](diagnostics.tar.gz), indexed by [archive.json](archive.json),
retains 485 files including every failed attempt, original/adapted source,
unchanged input, expected output data, commands, raw output streams, source
ledgers, compiler traces, link records and native build metadata. Executables
and LLVM IR remain in the isolated build tree; their byte counts and SHA-256
identities are recorded. The archive was read back and every member verified.

| Attempt | Retained failure and correction |
| --- | --- |
| `compiler-map-order-v1` | The `--script` harness bound forward calls to Chez's host `compile-program`. The complete source now uses the benchmark suite's existing compile-then-program driver. |
| `compiler-collections-chez-v1` | The new scalar provider used an unavailable Chez `exact-integer?` name. The equivalent integer/exactness conjunction fixes the boundary. |
| `compiler-collections-v2` | Three exported negative fixture entries lacked explicit concrete declarations. Inference completed; export validation rejected the fixture. Added the three `(-> I64)` signatures without changing shared collection bodies. |
| `compiler-io-boundary-v1` | The descriptor fixture used the wrong Chez accessor name. Corrected it to `port-file-descriptor`. |
| `compiler-io-boundary-v3` | Surrogate input was rejected through the raw scalar diagnostic. The decoder now reports invalid UTF-8 for surrogate/out-of-range encoded input; raw invalid-character writes retain their distinct scalar error. |

The unsuccessful collection build ended normally with child exit 70; its
900-second supervisor did not expire and retained no executing descendants.
Its incomplete trace JSON is preserved verbatim. The successful retry completed
as actual session **4126**, terminal **0**, chunk `80dc12`; its unclean diagnostic
trace records inference 699.433 s, specialization 6.105 s and emission 15.052 s.
These durations are not performance samples. Target checking then completed in
session **1327**, terminal **0**, chunk `bf2dfe`. The final full Chez output/
boundary checker completed in session **94505**, terminal **0**, chunk `7961ec`.
All build and guest handles owned by these checks drained to terminal.

The linked writer runtime is
`3a04334f3a37fd7ddbf5ab28c9c24abc4550c0424210dcfb1a10c88742c5c6d4`.
Its Rust/Cargo source tree matches prerequisite `43c8929` exactly. These checks
do not use the separate Unicode-only runtime. Future full-compiler builds
importing both writer and Unicode helpers must build their combined runtime.
`make check`, explicit formatting of benchmark support and Scheme fixtures,
Python compilation, and whitespace checks passed.

## Parent review and integration

The parent inspected the collection storage and source substitutions, scalar
I/O ownership, UTF-8 decoder, output boundary and actual-target checker. No
implementation change was justified. Independent archive replay verified all
485 members, 120 raw command records, 38 source identities and 17 omitted
artifacts. The 85 nonzero records include expected terminal controls and the
retained unsuccessful attempts above; none timed out or retained executing
descendants.

Integration as source commit `28d3d09` preserved all 11 feature files exactly;
only the module tour needed an automatic merge with the Unicode layer. This
review reran no guests and makes no new timing claim.
[parent-review.json](parent-review.json) records the verification. The preceding
[combined writer/Unicode checks](../2026-10-14-strict-output-integration/README.md)
cover the shared runtime that future full-compiler builds will need.

## Focused review and reproduction

The pinned simplify pass used fresh Astra/max explainers with no files or
conversation history, followed by informed critique. The collection review
retained old-graph closure rounds, fresh wrappers on convergence, literal fold
orientation, copied removal misses, asymmetric zip termination and queue
stored-tail alias effects. It rejected repairing detached queue tails or
deduplicating occurrence sets. The I/O review retained owned IDs, one lookahead,
binary ports, explicit pathname transfer and invocation cleanup, and rejected
native Datum printing and text-transcoder normalization. The concrete close
probe settled its final host-specific question.

The fixed source-edit table, closed data declarations, UTF-8 decoder, scalar ABI
dispatch and integration checks exceed the ten-line target where keeping the
whole operation together explains its contract. Original algorithm bodies keep
their structure; no frontend/backend refactoring is part of this change.

```sh
python3 tests/strict-compiler/check.py --collections \
  --runtime build/wasm-runtime/wasm32-wasip1/release/snail_runtime.wasm \
  --output build/compiler-collections-check
python3 tests/strict-compiler/check.py --chez-output \
  --output build/compiler-chez-output-check
python3 tests/strict-compiler/check.py --map-order \
  --output build/compiler-map-order-check
```

The checker reuses the existing process-group supervisor and rejects an existing
output directory. It starts no clean measurement. The next VM-data review is
retained separately in [next-gvm-review.md](next-gvm-review.md); it is a source
audit and implementation brief, not executed compiler coverage.
