# Heap preparation and collector controls, 2026-10-11

These are isolated experiments, not changes to the production collector default.
The compiler workload runs an already-built Snail compiler from source to WAT;
building that compiler and translating its WAT to LLVM are outside measurement.

Making the never-reclaiming bump arena resident before timing changes its median
from **6.680 s to 3.506 s**. V8 takes **3.717 s** in the same confirmation series,
about 6% longer while also reclaiming memory. This compares whole programs with
different code generators and rooting protocols; the difference is not a direct
measurement of GC overhead.

## Heap preparation control

| Compiler executor | Median internal time | Heap preparation |
| --- | ---: | --- |
| Native bump, lazy pages | 6.680386 s | 16 GiB address range; pages faulted during execution |
| Native bump, resident pages | 3.505834 s | All 16 GiB touched before timing |
| V8 | 3.716823 s | Normal engine policy |

The resident bump control spends about **3.39 s** preparing the arena before the
timer. It shifts work out of the measured interval; it does not make that work
free. Post-setup kernel CPU drops from about 2.9 s to 0.01 s, and minor faults from
about four million to 1,600. All three retained resident runs have zero major
faults. The arena must be this large because the compiler allocates approximately
16.34 GB in total and this allocator never reclaims anything. A 300 MiB
never-reclaiming arena cannot complete this workload.

`bump-confirmation.json` contains the three retained samples, the discarded first
sample, commands, outputs, checksums, wall times, setup counters and resource
counters. Resource deltas run from heap setup to process exit and include module
initialization; they are slightly broader than the internal Scheme timer.

## Collectors with a 300 MiB starting heap

| Collector | Compiler median | Tail Fibonacci median |
| --- | ---: | ---: |
| V8 | 3.723508 s | 0.114245 s |
| BDWGC, 300 MiB initially resident | 10.398200 s | 0.259777 s |
| Custom full mark/sweep | 20.471989 s | 0.342039 s |
| Custom nursery, 8 MiB budget | 14.079236 s | 0.366709 s |
| Custom nursery, 32 MiB budget | 14.652036 s | 0.376002 s |
| Nonmoving Immix, initial policy | 26.819184 s | 0.374924 s |
| BDWGC incremental, 300 MiB initially resident | 33.048994 s | 2.090555 s |

The nursery improves this compiler workload by about 31% relative to the same
custom collector with generations disabled, but slightly slows the tail workload.
It allocates young objects through the existing size-class free lists and
promotes every minor-collection survivor in place. It is not a copying nursery
with a contiguous bump allocation path. Both custom full-heap collectors initially
use an allocation budget of `max(8 MiB, 2 * live payload bytes)`; the arena size
alone does not make them collect less often.

The Immix prototype uses 32 KiB blocks and 128-byte lines, bump allocation within
reusable holes, and whole-block allocation for large objects. Live objects retain
their addresses. Evacuation is omitted as requested. These initial results do
not characterize a tuned Immix implementation.

BDWGC is allowed to grow beyond its 300 MiB initial heap. Its retained compiler
samples finish with roughly 325–334 MiB reported heap size. The custom collectors
use a fixed 300 MiB arena. Native runs use no parallel marking helpers.

### Incremental dirty-page tracking

The diagnostic log confirms this BDWGC build uses Linux soft-dirty tracking.
Its retained incremental compiler runs record 17.1–18.1 million minor faults and
6.57–6.81 s of kernel CPU; nonincremental runs record 15.8–18.4 thousand faults
and 0.02–0.03 s of kernel CPU. This is a substantial measured cost, not an
explanation of all incremental-mode overhead.

BDWGC 8.2.12 resets soft-dirty state through `/proc/self/clear_refs`.
Linux clears writable page-table bits during that operation, so subsequent
writes fault even if the pages are already resident. Preparing the heap once
cannot remove these later tracking faults. See the
[pinned BDWGC implementation](https://raw.githubusercontent.com/ivmai/bdwgc/v8.2.12/os_dep.c)
and [Linux soft-dirty documentation](https://docs.kernel.org/admin-guide/mm/soft-dirty.html).

### Collection phase and budget controls

Separate diagnostic runs enable phase counters; they are not added to the timing
medians above. The initial full precise collector spends 5.70 s marking and
2.50 s sweeping over 1,491 major collections. The 8 MiB nursery spends only
0.25 s marking and 0.92 s sweeping over 2,469 minor and 9 major collections,
within a 14.08 s total run. Most of that prototype's time is outside collection.
This does not isolate allocation, root publication, barriers or application work
from each other.

With the existing `SNAIL_GC_MIN_BYTES=134217728` override, the full precise
collector's diagnostic run drops to 15.50 s and 155 collections. Initial Immix
drops from 26.91 s / 1,609 collections to 17.81 s / 168 collections. This supports
collection frequency as one cost, but does not close the gap. The nursery takes
14.56 s with this override; it performs no major collection and reports roughly
127 MiB of retained payload, including old garbage awaiting a major. Increasing
its major budget is not a measured improvement.

`diagnostics.json` retains all seven checked diagnostic runs, their exact phase
counters and settings. These are single-run controls, not repeated medians or a
recommended heap policy.

One validated Immix candidate skips full blocks, continues searches after
reserved holes, and wraps to earlier holes before reporting exhaustion. It also
uses a next-fit search for large contiguous reservations. The single diagnostic
screen takes 25.81 s with the initial budget and 17.66 s with the 128 MiB minimum,
versus 26.91 s and 17.81 s for the initial implementation. This shows no large
gain; without repeated paired measurements it does not establish a speedup.
`tuned-screen.json` retains both checked outputs and counters. The candidate
passed strict C, ASan/UBSan, wrapped-hole tests that forbid intervening collection,
and the full actual-native execution suite. Both implementations are preserved
as experiments; the small screen difference does not justify a production change.

## Measurement and validation

All runs are sequential and pinned to CPU 3, a performance core on an Intel
Core Ultra 7 270K Plus. Compiler results
use three retained fresh-process samples after one discarded sample; tail results
use five after one discard. Variant order rotates each round. Tail Fibonacci
uses 1,048,576 repetitions after its internal warmup. No task-owned build, test or
profile runs alongside a timed process. Each output is validated: compiler SHA-256
`658af1403c7313bef3efde25c7383e8bcf68fec34d758c0fdbed6911a27bdb0a`,
tail checksum `4409231671296`.

Native builds use Clang 21.1.8, `-O3 -flto -fuse-ld=lld`, and the same frozen Rust
archive. V8 uses Node 24.19 and the frozen Binaryen-optimized Wasm artifact.
The custom collectors use explicit native roots. The nursery variants also use
generated mutation barriers; its full-heap control uses the same binary with
generations disabled. The BDWGC and bump controls retain the original generated
LLVM without those explicit-root operations. Build commands and source/artifact
hashes are retained alongside the reports.

Both custom collectors passed `SNAIL_PRECISE_GC=1 scripts/test-native`, including
actual native execution, collection on every allocation, callback roots, resources
and finalizers. Nursery-specific tests cover old-to-young edges, large arrays,
cycles, young finalization and promotion. Immix tests cover reclaimed holes,
stable addresses and allocation-exhaustion collection. Sanitizer and strict C
checks are recorded in their experiment reports.

### Excluded attempts

- Initial CPU 2 runs overlapped an unrelated CPU 2 benchmark and are rejected.
- A first 16 GiB resident-bump screen encountered memory pressure and almost
  100,000 major faults. It is not evidence for a resident-heap comparison. The
  separate completed confirmation series above has no major faults in retained
  samples.
- A hard 300 MiB BDWGC cap failed an allocation despite substantial aggregate
  free space. The successful comparison uses an initial size with normal growth.
  This failure does not establish the program's live-memory requirement.
- The final BDWGC preparation harness populates only verified newly mapped heap
  ranges with `MADV_POPULATE_WRITE`. It does not use a temporary giant allocation
  or infer mapped ranges from heap-address bounds.

The raw rejected attempts are retained separately and are not included in any
median above. The experiment runner uses explicit paths to frozen worktrees;
those paths and manifests identify the exact inputs rather than silently
rebuilding a newer compiler.

## Retained experiments

- Nursery implementation and validation: `f92dde9d0f4a68cc1bb7e6eb4c3d5c711a9ef9af`,
  branch `experiment/generational-gc-20261011`, report
  `benchmarks/results/2026-10-11-generational-gc/README.md`.
- Initial nonmoving Immix implementation and validation: `ac6eab67`, branch
  `experiment/immix-gc-20261011`, report
  `benchmarks/results/2026-10-11-immix-gc/README.md`. Its subsequent tested search
  candidate and screen are retained on that same experiment branch.
- This comparison and its controls: branch `experiment/prefault-heap-20261011`,
  based on the retained explicit-root collector commit `008db97`.

The focused simplification review retained the line maps as the source of truth;
it rejected additional free-run lists and exact largest-hole summaries. Search
boundaries follow reserved space, so free runs cannot cross them until collection.
Collection resets those boundaries and rebuilds counts. Acquired runs remain
reserved until collection, including abandoned tails. These invariants and the
adversarial wrap tests explain the candidate's remaining bookkeeping.
