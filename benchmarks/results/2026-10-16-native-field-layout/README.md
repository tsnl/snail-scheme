# Cache immutable record layouts during native tracing

The prototype resolves a record's field-offset storage once before tracing its
edges. The previous loop looked up the same layout after each marking call,
even though marking cannot change it. Diagnostic hardware counters show about
**4.7% fewer instructions with ordinary linkage** and **5.1% fewer with shared
guest/Rust LTO** on the unchanged canonical `gcbench` workload.

The subsequent uninstrumented experiment passed all **24 executions**. Its
medians were about 3.7% lower in both linking modes:

| Linkage | Control median | Candidate median | Control range | Candidate range |
| --- | ---: | ---: | ---: | ---: |
| Ordinary static runtime | 3.764819 s | 3.626569 s | 3.733079–3.795781 s | 3.578315–3.658759 s |
| Shared guest/Rust LTO | 3.506134 s | 3.375937 s | 3.479894–3.601069 s | 3.370300–3.390418 s |

**These are exploratory timings, not a quiet-machine performance result.** All
workers belonging to this task were idle, but the before/after host snapshots
show other busy Chibi compiler processes. No outside process was stopped, and
no outside session was contacted. The instruction reduction and retained
assembly establish less tracing work; this run does not establish the precise
wall-time benefit under uncontended conditions. There is no new V8 comparison.

## What changed

The control runtime is `08f98ad1db244753c48a1739702ca894e50416da`, whose runtime
files match main `0a765e72375a07c521c404e5a95b3688c265956b` after PR #277. It
already includes the zero-fill and wholly-dead-block sweep changes. The complete
prototype release diff is [collector.patch](collector.patch).

For a record, tracing captures the descriptor's offset pointer and length,
then reads each offset and checks it against the actual object extent before
reading the referenced word. Metadata owns its offset storage and remains
immutable during collection. Marking may grow the separate worklist but cannot
move or replace the descriptor; there are no guest callbacks or recursive
collections during marking. The invariant must remain beside the unsafe read.

Exact allocation-start checks, root handling, scalar-field exclusion, traversal
order, finalization and heap policy are unchanged. The baseline and candidate
have identical non-time diagnostic counts: 226,122,908 allocations, 34
collections, 320,561,531 field visits, and 7,994,907 live objects after the last
collection. Eight instrumented canonical executions passed; their times are
kept separate from the uninstrumented schedule above.

Both prototype variants passed 60 Rust tests, including focused cases for an
invalid field offset and worklist growth while tracing nonsequential fields.
Actual optimized native execution with forced collection also passed. These
are prototype checks; later product review and validation are recorded by the
implementation PR.

## Reproduction and evidence

Each linking pair uses identical frozen guest code, Rust entry/provider,
inputs, counts and complete predicates. Ordinary linkage uses the same ELF
guest object; shared LTO uses the same bitcode. The opaque provider boundary
comes from the earlier [LTO experiment](../2026-10-16-native-lto/README.md).
The prototype changes neither benchmark source nor the default link policy.

The uninstrumented driver retains one warmup and five fresh-process samples
per arm, rotates arm order, pins CPU 2, and verifies source/executable hashes
before and after execution. All scheduled attempts remain in
[comparison.json](comparison.json); no failed or slow attempt was replaced.

[evidence.tar.gz](evidence.tar.gz) retains the full schedule, execution records,
standard output/errors, build commands, source snapshots, lifetime argument,
diagnostic counters, disassembly and host snapshots. Binaries and build caches
are excluded but their hashes are retained. Command environments in the public
archive retain only an explicit build/runtime allowlist; the archive records
which files were filtered and their original hashes. Original local records
are unchanged. `evidence-files.sha256` verifies retained archive contents;
[SHA256SUMS](SHA256SUMS) verifies this report, comparison and archive.
