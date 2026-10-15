# Retained Wasm list-node footprint in two V8 builds

The same tiny Wasm module retains approximately 32 bytes per list node in the
installed Node build, versus 20 or 16 bytes in the installed Chromium build.
Fresh processes with reversed shape/count order reproduce the result.

| Immutable node fields | Node 24.19.0 | Chromium 152.0.7977.82 |
| --- | ---: | ---: |
| I64 value and nullable next reference | 32 bytes/node | 20 bytes/node |
| Nullable inner-list reference and nullable next reference | 32 bytes/node | 16 bytes/node |

These are slopes of reported retained heap usage, not physical resident memory
or independently decoded object-header sizes. They apply to this probe in
these two installed engines. The two shapes correspond to the inner and outer
lists in `mperm`; this probe does not execute the permutation algorithm.

## What is measured

The module privately roots an array of N references, then creates N immutable
linked nodes of one shape. Each array entry points to its corresponding node;
each node links to the preceding node, with a null tail on the first node.
Inner nodes also contain their index as an I64 payload. Wasm checks every
payload and link. The immutable null-terminated chain establishes distinct
nodes. No GC reference is returned to JavaScript.

For each N, the host measures the same root array while empty and populated.
Subtracting those readings controls root-array storage. It then releases the
array and records the return toward the earlier heap baseline. Each reading
contains three explicit collections, each followed by a 110 ms event-loop
turn and a heap-counter sample; medians produce the retained differences.
Constructors, verification, collection, and the getter are warmed beforehand.

The initial process visits 25,000, 100,000, 200,000, 200,000, 100,000 and 25,000
nodes for each shape. A fresh process reverses both the shape order and the
count order. An affine fit of retained bytes against node count yields:

| Engine and run | I64/reference slope | Reference/reference slope |
| --- | ---: | ---: |
| Node, initial | 31.99586 | 32.00010 |
| Node, reversed | 32.00010 | 32.00507 |
| Chromium, initial | 19.99998 | 15.99999 |
| Chromium, reversed | 20.00000 | 16.00011 |

All 48 graph checks pass. The small intercepts and within-reading variation
are retained in [summary.json](summary.json) and the archived raw observations.
Node uses `v8.getHeapStatistics().used_heap_size`; Chromium uses
`performance.memory.usedJSHeapSize` with precise memory information enabled.
Their accounting APIs differ. This experiment is stronger evidence of an
amortized retained-footprint difference than of exact individual object size.

Node reports V8 `13.6.233.17-node.51` and a disabled pointer-compression build
setting. Chromium is a different V8 build, and this experiment did not query
its pointer-compression build setting. It changes engine version, build,
configuration and host together. It does not isolate pointer compression or
prove that footprint explains the benchmark gap. A matched V8 build experiment
or independently decoded allocation layout would be needed for that claim.

## Original workload browser check

The exact frozen optimized `mperm` artifact from the previous comparison also
passes in Chromium with its original count 20, inputs 10/2/1, result 1, four
setup opacity calls and no timed opacity calls. A bounded 2:5:2:1 check passes
as well. The local page invokes `main` before timing `bench`, and performs its
result and opacity-count checks afterward.

The full browser observation was 14.499 seconds. It was collected while other
build work was allowed, uses a validation host, and has no repeated clean
Node/Chromium comparison. It must not replace the earlier clean Node median
or be described as a browser speedup. The heap probes are also diagnostics;
their collection and verification work is deliberately intrusive.

Attempts to obtain native Wasm disassembly from this Chromium build produced
no code output. Those attempts and the initial sandbox launch failure remain
in the archive. They supply no native-layout evidence. No compiler source or
default runtime setting changes follow from this report.

## Reproduction

The regular-file archive contains both process orders, all four raw heap
results, the unchanged 461-byte module and WAT, embedded local pages, driver
code, tool identities, browser workload outputs, and failed diagnostic attempts.
The WAT was independently reassembled with Binaryen 132 and matched the frozen
Wasm byte for byte. Browser profiles and caches are excluded.
Both restored drivers were then executed from new directories: all 37 archived
hashes and 24 additional graph checks passed, reproducing the rounded footprint
estimates. Their raw results are in [replay-check.json](replay-check.json).

Restore and verify the archive:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/list-footprint-replay \
  --report benchmarks/results/2026-10-14-wasm-list-footprint
```

Run either heap diagnostic in a new output directory, using the exact recorded
tools. The `--reversed` option selects the second observation order:

```sh
python3 benchmarks/results/2026-10-14-wasm-list-footprint/reproduce.py \
  /tmp/list-footprint-replay node /tmp/list-footprint-node
python3 benchmarks/results/2026-10-14-wasm-list-footprint/reproduce.py \
  /tmp/list-footprint-replay chromium /tmp/list-footprint-chromium --reversed
```

Chromium requires permission to start its normal browser sandbox and listen on
loopback for the local debugging connection. The driver creates a disposable
profile beneath the output directory and terminates only its own process
group. It does not use an existing browser profile or remote page.
