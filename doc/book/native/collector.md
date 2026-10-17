# Immix collector

The in-house collector is synchronous, single-threaded, full-heap Immix with
opportunistic evacuation, 32-KiB blocks and 128-byte lines. It has no nursery
or generational write barrier. It traces only declared reference fields and
explicit roots; I64 words that resemble addresses are never roots.

Small allocations (at most one line including their header) mark their starting
line; reclamation also reserves the following line because an object can straddle
the boundary. Medium and large objects mark their full extent. This conservative
line reservation does not scan pointer-shaped numeric fields. After weak cleanup,
a block with no retained lines
can clear its exact-start map without inspecting dead object headers. Candidate
roots must pass exact-start membership before a header is read, so stale header
bits cannot revive an object. Allocation clears the payload before reusing that
storage. Blocks containing live lines retain the ordinary per-object sweep.

The allocation policy follows [Immix, sections 3.1–3.3](https://www.mmtk.io/assets/pubs/immix-pldi-2008.pdf):

- Recycle holes in address order before consuming empty blocks.
- Preserve useful small holes by sending medium objects to a separate bump
  cursor in empty blocks. Allocations of at least 8 KiB, including their header,
  bypass both cursors and reserve whole blocks.
- Reserve 2.5% of mapped blocks, rounded down, for evacuation. This reserve is
  inside the heap cap; heaps smaller than forty blocks have no reserved block.
- Select fragmented source blocks using hole-count histograms, previously marked
  lines and currently available target space. During tracing,
  copy movable survivors once, leave forwarding headers, and repair every edge.
  If target space runs out, retain the remaining objects in place.

The histogram follows the [original MMTk block sweep](https://github.com/JikesRVM/JikesRVM/blob/f10ba059ebdb801cc66e2cb6552a6f4a3a0f193d/MMTk/src/org/mmtk/policy/immix/Block.java#L139):
count transitions from marked to unmarked lines before reserving the conservative
following line. Estimate copy volume from marked lines,
separately from retained allocation capacity. Otherwise alternating live/dead
lines would look unfragmented after guard lines consume every available hole.
Prior marks predict copy cost; current allocation state bounds target capacity.
New allocations reduce available target space without being presumed live in the
previous mark histogram. Each copy checks actual capacity, so underestimated
survival causes in-place marking rather than overwriting occupied storage.

At the cutoff, follow the [2008 implementation](https://github.com/JikesRVM/JikesRVM/blob/f10ba059ebdb801cc66e2cb6552a6f4a3a0f193d/MMTk/src/org/mmtk/policy/immix/Defrag.java#L171):
include the first histogram bucket that reaches or exceeds estimated target
capacity, then rely on allocation failure to stop copying. Section 3.2.1's prose
instead excludes the crossing bucket. That interpretation can repeatedly skip a
large group of equally fragmented blocks and eventually exhaust the heap; a
regression test exercises partial evacuation of exactly this case.
Partial evacuation need not free a whole block, and aggregate free bytes do not
guarantee that a sufficiently large contiguous allocation is available.

Allocation occupancy and current collection marks are separate maps. Evacuation
uses only previously free storage and never allocates into selected source blocks.
An unmarked line during tracing is not necessarily free: its objects may simply
be unvisited. Weak resource records follow forwarding pointers without retaining
their wrappers; unreachable wrappers still receive exactly one cleanup.

This implements the paper's full-heap collector, without a generational nursery
or write barriers. Deliberate platform differences are a single mutator/collector,
Rust-owned out-of-heap metadata, exact-start membership and payload-size headers,
and whole-block large-object allocation. Object-header sweeping preserves exact
membership checks. These differ from MMTk's compact embedded metadata and LOS;
we do not claim identical metadata overhead or performance.

The heap initially reserves 256 MiB of virtual address space. An allocation
that cannot fit collects, then normally reuses reclaimed space. If more than
75% of capacity remains occupied, it first tries to add a region, normally
doubling total capacity, to avoid repeated tracing for tiny reclaimed holes.
Occupancy counts retained 128-byte lines and entire large-object block
reservations, including headers and unusable tails. At or below 75%, at least
one quarter of total allocation space is reusable, though fragmentation can
still prevent a particular contiguous fit. Such a miss also requests growth.
A larger object can request a larger region. This headroom rule is a simple
capacity policy, not a measured optimum. Each region owns its block, line and
exact-start maps. Survivors may move between regions during evacuation; each
individual allocation stays entirely inside one region.
Growth publishes a region only after its mapping and metadata both succeed.
If the preferred addition fails, the collector tries the minimum complete
block-rounded extent. Failed growth still permits allocation in any fitting
reclaimed hole. Mappings are
retained for reuse, and startup does not prefault their pages.


## Fixed production policy

Production starts with 256 MiB of virtual address space, collects on allocation
space exhaustion, and grows subject to checked size bounds and OS availability.
There are no environment variables for heap sizing, allocation budgets,
evacuation policy or statistics output. Explicit collection remains available
at the runtime ABI. Collector unit tests construct private bounded heaps.

The nondefault Cargo `gc-stress` feature starts with 1 MiB, collects before every
allocation and attempts evacuation at every collection. This is a separately
built testing runtime; ordinary executables have no per-allocation configuration
check. See [stress execution](failures.md).
