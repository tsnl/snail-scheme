# Reusing validated application snapshots: 2026-10-18

A growing Siegework colony repeatedly decoded the entire World during Client
commands, state validation and presentation. The bridge now retains three
validated interpretations per owner in each Program's Wasm instance. Its host
assigns immutable snapshot banks unique, nonrecycled identities. A cache entry
is installed only after decoding and application checks return successfully.
The host continues to select current, prior and proposed banks; cache entries
have no authority to publish state.

Every newly encoded replacement still undergoes structural and application
validation before persistence, including byte-identical paused transitions.
External restores receive fresh banks and validation. Decoding caches rely on the
existing library contract: codecs and validators depend only on their inputs,
and handlers leave reachable input storage unchanged. This is not a compiler
proof of immutability or purity.

## Method

The baseline is the native checkpoint's 542,560-byte Wasm, SHA-256
`2a3b5ea33b3801da5d8c90c84a2efafd108276237ee4f87cea4fba56777cb82d`,
packaged as generation `a12a8aa5b43babe899d043f3`. The isolated candidate starts
from `224ab7b8` and changes only the application bridge, host identity support,
and Siegework's current/prior World reader calls. Both game builds use the
default `-O1` profile. Candidate generation `ae733e7b2bcc57d95974ba65` contains
546,626-byte Wasm, SHA-256
`64e4cbd2288679a9bf075f92c6857c26726c9948b6a9423807a2d735091bf9da`.

The mixed colony was constructed through actual reducer commands: twelve
workers, sixteen level-three towers, two mines, four guns, sixteen rails,
thirty-nine surveys and eighty track cells. Fixture setup supplies funds and
resets encounters between construction stages. A bounded encounter then adds
96 enemies, each with a 64-cell route, through the real snapshot validator.
The grown colony has 4,735 snapshot words; the encounter has 25,089. Additional
fixtures cover a fresh world, the paused encounter, and three attack insets.
They represent controlled workloads, not a captured player's save.

Node v24.19.0 runs the actual compiled game with a 390 by 844 logical viewport.
Each fixture/operation resets its inputs, warms five operations, then measures
25 operations. Four rounds alternate baseline/candidate order. Timings are
uninstrumented; separate calls count scalar reads and writes. Each process has
a 180-second timeout and a 2-GiB JavaScript heap limit. These are shared-host
diagnostics, not controlled hardware benchmarks. The raw record retains every
round, including an unusually slow grown-colony candidate round.

## Results

Ranges below are the four round medians, in milliseconds.

| Operation | Baseline | Candidate |
| --- | ---: | ---: |
| Fresh world, tick and view | 0.31–0.36 | 0.16–0.20 |
| Grown colony, tick and view | 12.97–13.63 | 8.41–14.40 |
| Encounter, repeated view | 5.90–6.29 | 0.06–0.09 |
| Encounter, camera command and view | 9.64–9.71 | 0.10–0.12 |
| Encounter, tick and changing view | 26.43–27.52 | 17.27–17.85 |
| Paused encounter, tick and view | 14.44–15.19 | 4.60–5.10 |
| Three attack insets, tick and changing view | 56.90–59.24 | 46.33–47.15 |

In the encounter, one repeated view previously read 25,261 current and 25,089
prior words; both counts are now zero. A camera command falls from 25,439 reads
to 178, consisting of the newly encoded Client and schema probes. An active
tick falls from 50,208 reads to 24,947 while still writing 24,942 scalar calls,
including the length declaration. The paused tick still writes 25,090 calls
and reads its new candidate through the complete validator. Encoding and
durable writes are unchanged.

Five fixtures each execute six tick/view and camera/view pairs in both builds.
All **60 complete presentation outputs and both owner snapshots match**.
The candidate also passes **199 application integration checks**, including nine
new actual-Wasm cache checks, and **21 presentation groups**. The focused async
runner freshly rebuilds six fixtures and passes eleven ordering checks plus the
nine cache checks. Fresh counter, counter-Lofi, state, testing and other relevant
fixtures execute successfully; the raw and optimized snapshot serialization
artifacts both execute with the real linked scalar provider.

The cache checks cover current/prior reuse, fresh validation for equal bytes,
malformed candidates, failed decoding, pending and failed saves, per-instance
isolation, stale preparation, rollback, three-entry eviction and nonaliasing
identity tokens. Identity exhaustion is explicitly rejected in the host; tokens
are never wrapped or reused. Raw snapshot fixture providers admit the additional
identity import while still throwing if an unused application hook is called.

## Remaining work and scope

The baseline investigation also identified geometry construction and collection
costs. Small camera drifts retained every geometry batch, while active ticks
rebuilt terrain and entities; three insets repeated entity construction in four
views. This patch changes neither geometry nor rendering. The independent
removal of product attack thumbnails is outside this measured pair. Generic
inset keys remain scoped per view; automatic sharing based only on equal batch
keys would be incorrect.

These CPU results do not measure IndexedDB latency, physical GPU performance,
phone thermals or frame rate. Native HiDPI, dimetric projection, smoothing and
the existing lack of MSAA remain unchanged. The focused explanation review
stopped after the validated-value cache: reusing handler output as a validation
certificate or giving cache entries commit roles would weaken the boundary or
add unnecessary state.

Raw rounds, artifact identities, baseline diagnostics and scalar counts are in
[`decoded-snapshots-2026-10-18.json`](decoded-snapshots-2026-10-18.json).
