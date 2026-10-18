# Automatic nonmoving native heap growth

The complete original NBoyer and SBoyer inputs now pass with the default native
heap and no GC environment settings. NBoyer grows from 256 MiB to 2 GiB in three
additions; SBoyer grows to 1 GiB in two. Both retain the original size-5 predicate
checking exactly 51,507,739 rewrites, the scalar C provider, and the prepared
Binaryen-optimized Wasm and mechanically lowered LLVM.

This is a runtime change based on `b756cce5217c8d57820a9f20250194f883968991`.
It does not add benchmark coverage or comparative timing to the 57-workload
campaign. The immutable preparation evidence remains in
[`2026-10-14-strict-boyer-preparation`](../2026-10-14-strict-boyer-preparation/README.md).

## Capacity policy and ownership

Each mapping owns stable block, line and exact-start metadata. Small allocations
retain their bump range's region owner even when a large allocation uses another
region. Pointer tracing finds the containing region, checks exact membership,
and only then reads an object header. Objects never move or span mappings.
The region list stays small under geometric growth; it needs no fixed giant
virtual-address reservation or relocation of existing metadata.

After a capacity miss, collection runs once. If at most 75% of managed capacity
is occupied, allocation first reuses reclaimed space. Above that threshold it
tries growth first, leaving room before the next capacity collection. Occupancy
counts retained 128-byte lines, including headers, and full large-object block
reservations, including their unusable tails. Thus the threshold measures
aggregate allocation space; it cannot guarantee a contiguous fit. A miss after
reuse still requests growth. The existing budget remains the larger of the
configured minimum (8 MiB by default) and twice the live payload bytes.

Growth normally doubles total mapped capacity, accepts a larger contiguous
object's requirement, and can consume a smaller final cap remainder. It prepares
descriptor, metadata and mapping before publishing anything. If the preferred
mapping fails, it tries the minimum block-rounded request; failed optional
growth still allows a fitting reclaimed hole. Failed additions free provisional
metadata and preserve existing roots, maps, addresses and capacity.

`SNAIL_GC_HEAP_BYTES` remains a hard total managed-byte cap. Used alone, it also
preserves the fixed initial reservation. Optional `SNAIL_GC_INITIAL_BYTES` allows
a smaller start for tuning and deterministic growth tests. Both round down to
32-KiB blocks; allocation extents round up, including their header and alignment.
Configuration, cap remainders and object sizes are checked before arithmetic or
publication. C metadata and root storage are outside the managed-byte cap.
See [`doc/native.md`](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/doc/native.md) for the complete configuration and
statistics contract.

## Diagnostic comparison

Each row is a separate full canonical process with GC statistics enabled.
Correctness also runs separately without statistics and requires empty stderr.
The first implementation grew only after collection left no fitting hole; its
source and complete results are preserved in
[`failure-only-policy/`](failure-only-policy/README.md).

| Workload and policy | Final mapped capacity | Collections | Traced fields | Used-block high-water |
| --- | ---: | ---: | ---: | ---: |
| NBoyer, failure-only growth | 2 GiB | 134 | 3,198,949,356 | 2,048 MiB |
| NBoyer, 75% headroom growth | 2 GiB | 49 | 644,362,526 | 2,048 MiB |
| NBoyer, explicit fixed cap | 2 GiB | 43 | 583,464,864 | 2,048 MiB |
| SBoyer, failure-only growth | 1 GiB | 91 | 815,738,759 | 624.594 MiB |
| SBoyer, 75% headroom growth | 1 GiB | 36 | 84,149,095 | 949.313 MiB |
| SBoyer, explicit fixed cap | 1 GiB | 34 | 73,217,816 | 786.313 MiB |

The headroom policy avoids repeated tracing near capacity, at the cost of using
mapped space earlier. SBoyer's used-block high-water increases; this counter is
a virtual managed extent, not measured resident memory. The threshold is a
measured candidate policy, not an established optimum. All three policies have
identical workload allocation counts: NBoyer allocates 359,440,532 objects and
8,692,156,392 payload bytes; SBoyer allocates 59,001,388 objects and 1,481,616,992
payload bytes. Collection scheduling changes the final observed live set.

Process durations and mark/sweep phase times are retained in the evidence, but
builds and checks overlapped. They are diagnostics and support no clean timing
or speedup claim.

## Verification and reproduction

[`validation.json`](validation.json) records actual commands, statuses, timeout
state, exact outputs, all GC controls, input hashes, and frozen input identities.
The validator verifies unchanged frozen files before and after linking and
substitutes only the collector source in each original recorded link command.
The native host source and public GC header are byte-identical. The optimized
Wasm SHA-256 identities are:

| Workload | SHA-256 |
| --- | --- |
| NBoyer | `8b1e3d29f3abaa976f126c867cd1561122db1eeea84b3400e09501129a7b26e3` |
| SBoyer | `516f1a41d794e724828df9a985a93d00ef220abf2dcf526064a89480b7f7bb0a` |

The validated collector SHA-256 is
`4bdf53cc0544c00b4b4d8018d44eafa2d063c672fa8cbac828a49f7d24459bfe`.
The new executables remain under `build/gc-growth/boyer-headroom/`; the first
policy's executables remain under `build/gc-growth/boyer/` in the task worktree.
To reproduce with the immutable prepared modules, choose an unused output path:

```sh
python3 benchmarks/results/2026-10-14-native-gc-growth/validate.py \
  --prepared /tmp/snail-strict-boyer-20261014/build/boyer-prepared-combined \
  --output build/gc-growth/boyer-recheck
```

Both workloads pass canonical, small, repeated-reset, wrong-rewrite-count and
zero-repetition fixtures. Separate fixed-cap runs confirm one region and zero
growth. The focused collector tests cover repeated growth, cycles and reference
arrays across regions, spanning objects larger than the previous heap, exact
starts and interior rejection, numeric pointer-shaped fields, weak release and
address reuse, bump ownership, cap rounding/remainders/exhaustion, overflow,
descriptor/metadata/mapping failure, minimal-size fallback, and all headroom
branches. Fault injection also checks provisional metadata frees.

The focused modes pass strict clang warnings and AddressSanitizer plus
UndefinedBehaviorSanitizer; records are in
[`headroom-collector-checks.json`](headroom-collector-checks.json). LeakSanitizer
cannot operate under the sandbox's ptrace environment, so these successful runs
set `ASAN_OPTIONS=detect_leaks=0` and make no leak-scanning claim.

The required Scheme, Rust, formatting, linked Wasm/Node and build checks pass;
[`checks.json`](checks.json) records statuses and
[`check-logs.json`](check-logs.json) retains log hashes and tails. The final
`scripts/test-native` integration run covers actual linked native execution,
forced collection, scalar C signatures, reentrant ABI roots, weak cleanup,
normal/trap/I/O-error/exhaustion cleanup and build ownership. Its complete
process records are in
[`native-integration-results.json`](native-integration-results.json), with the
concise result log in [`native-integration.log`](native-integration.log).

## Focused explanation review

Two fresh independent behavioral explanations and debates preceded the region
implementation and headroom refinement. The review kept region ownership,
exact-start checks, transactional publication and the already-collected flag
explicit. A budget-sized growth reserve was rejected because the 8-MiB minimum
dominates tiny heaps and can grow without capacity pressure. Fixed giant address
reservations were rejected in favor of ordinary independent mappings.

The review stopped once the allocation, tracing, sweep and growth decisions
were visible at their call sites. Cohesive region publication, allocation,
collection and scan operations retain their complete transitions where splitting
would obscure invariants. Longer test and evidence functions retain one full
scenario or subprocess transaction; no forwarding helpers were added merely
to meet the ten-line target.

An independent source and test review found no concrete defects or material
coverage gaps in region publication, bump ownership, tracing, sweep ordering,
size arithmetic or cap/failure behavior. The integrated collector, focused tests,
native runner and native documentation match the reviewed commit byte-for-byte;
[`integration-review.json`](integration-review.json) records those identities,
review scope and actual terminal validation handles. Integration formatting and
diff checks pass. This review adds no performance claim.
