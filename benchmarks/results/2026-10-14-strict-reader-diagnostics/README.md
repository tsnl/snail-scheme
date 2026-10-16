# Strict reader diagnostics

Character input, repeated token staging and the delimiter scan are concrete
reader costs. Read1 performs **256,280,000 scalar service calls**, including
**61,022,500 token-character transfers**. Reusing each ordinary symbol's
already staged text could remove **40,395,000 repeated character transfers**
and **9,550,000 extra text handles**, while keeping the parser in Scheme.
This is an attribution candidate, not a measured optimization or speedup.

The completed [clean comparison](../2026-10-14-strict-reader-comparison/README.md)
remains the timing evidence: production V8/original Chez is 2.621× for Sum1
and 8.450× for Read1; V8/adapted Chez is 1.074× and 1.850×. **All observations
here are instrumented. No elapsed time here is a clean benchmark sample.**

## Exact artifacts and observation boundaries

The compiler/library basis remains `4176e304a0d329af62787f2cfaabb1f72816c3e8`,
including its earlier native allocator. No production module was rebuilt or
changed. Before and after each of eight diagnostic processes, the driver
verified all **111** identities in the corrected timing plan, SHA-256
`f23d33d0620bc56698f4519aa4b2e03e9e11e5440d1c9fd4e1417e6a5eaf90f3`.
Every process passes its full result predicate at Sum1 count 25 or Read1
count 2,500. Normal V8 tiering and normal collector policies remain enabled.

| Workload | Production linked Wasm SHA-256 | Common native-final Scheme Wasm SHA-256 |
| --- | --- | --- |
| Sum1 | `9a57746e747678c1ff85b8b8d63f8ddf8e832ccd9f8e761edf526a46303b1b5f` | `2fc8bd4337237ee9af6c3af7a4b16d32a615309cfe8133acaf5897196328ff3b` |
| Read1 | `2f80eb5611d557a4364aa1d911176dfeb943d539cfd36a24bc3fd32cef188639` | `e7ead840c0be14fa89ce28a10f4e9a313e40256e6ece630f27e72b45b5b9da8d` |

The Inspector profiler starts after `main` completes setup and before `bench`
begins, at a requested 1,000 µs interval. It stops immediately after the
synchronous full-count `bench` returns. Raw profiles and markers retain start
submission, start acknowledgement, workload clock boundaries, stop submission
and stop completion. Host additions erase exactly to the frozen timing host.
The full profiler window includes its start/stop boundary work; no clock-domain
alignment is assumed to clip samples to the workload clock.

CPU affinity is the frozen CPU 5. Other agents could build or probe concurrently;
the root also checked Ackermann correctness. Counter and native/GC diagnostic
processes overlapped within this agent. This is deliberately separate from the
coordinated quiet timing campaign. The owned process handles were reaped and
their process groups received bounded cleanup. No guest or host process remains
owned by this diagnostic run.

## Sampled production Wasm

There is one complete production V8 profile per workload: **985** Sum1 and
**2,602** Read1 samples. The following shares are exclusive leaf interval
weights over the whole profiler window. They are approximate sampled elapsed
interval shares, not continuous CPU-time measurements. Inlining assigns its
work to the surviving function. Inclusive ancestors are retained separately
in [findings.json](findings.json) and must not be added to exclusive shares.

| Surviving operation | Sum1 exclusive | Read1 exclusive | Read1 inclusive |
| --- | ---: | ---: | ---: |
| `snail:io/read-character` | 18.51% | 22.03% | 27.23% |
| `read_utf8_char` | 5.95% | 5.31% | 7.87% |
| `function137`: next-token/dispatch and inlined atom handling | 9.54% | 10.66% | 91.96% |
| `function170`: word loop and final substring | 12.39% | 6.57% | 21.58% |
| `function168`: delimiter-string membership scan | 10.86% | 6.05% | 6.05% |
| `snail:datum/token-character` | 4.45% | 5.24% | 9.66% |
| `BTreeMap::remove_leaf_kv` | 5.04% | 5.07% | 5.07% |
| `Tokens::take` | 2.77% | 5.01% | 10.01% |
| `BTreeMap::insert` | 2.47% | 3.74% | 3.74% |
| `snail:datum/token-intern` | — | 3.07% | 5.84% |
| `(garbage collector)` | 4.63% | 3.29% | 3.29% |

Function labels are compiler names, not numeric Wasm function indices. The
disassembly maps Read1 `function137` to index 33, `function168` to 44,
`function170` to 45, and `function181` (container construction) to 49.
Their Sum1 indices are 29, 40, 41 and 45. Read1 read/peek/token-character
services are indices 158/157/145; Sum1 uses 155/154/142. The archive retains
complete disassemblies, index/name maps and focused Read1 excerpts.
Inclusive weights count a complete frame at most once per sample, including
recursion. Unmapped Wasm frame names retain an unresolved index.

The fixed delimiter string is a module constant. Its surviving scan repeatedly
loads String length, checks the index, addresses character storage, compares
a scalar and tail-calls itself. It does **not** allocate a delimiter string per
character. The word loop retains character-result `struct.new` sites for peek
and read, followed by tag checks and extraction. This establishes their presence
in final Binaryen output; it does not prove V8 heap allocation, because V8 may
perform further elimination. Buffer creation, growth and substring copying also
survive. Source files copied from the frozen commit establish these mappings;
the reader and Rust scalar sources match this diagnostic checkout exactly.

## Exact common-module counters

This separate heavy run wraps imports of the exact native-final Scheme module
in JavaScript and forwards them to its unchanged Wasm Rust provider. It also
counts the provider's WASI imports. Those wrappers change the provider boundary
and prevent cross-module inlining: their times are not used for comparison or
as estimates of production linked-call overhead. Initialization, setup, worker
and cleanup phases remain distinct in the raw records.

| Workload-only count | Sum1, 25 workers | Read1, 2,500 workers |
| --- | ---: | ---: |
| All scalar service calls | 104,450,400 | 256,280,000 |
| `read-character` calls, including EOF | 27,500,025 | 70,752,500 |
| `peek-character` calls | 18,474,950 | 20,437,500 |
| Scalar whitespace checks | 30,000,000 | 65,297,500 |
| Temporary token opens | 2,500,000 | 14,477,500 |
| Token-character transfers | 18,474,950 | 61,022,500 |
| Characters staged for number parsing | 18,474,950 | 20,390,000 |
| Characters staged for identifier checking | 0 | 20,197,500 |
| Characters staged for symbol interning | 0 | 20,435,000 |
| Identifier checks | 0 | 4,775,000 |
| Symbol interning operations | 0 | 4,822,500 |
| Buffered WASI `fd_read` calls | 3,400 | 12,500 |

Every Sum1 worker records exactly 1,100,001 reads, 738,998 peeks, one read EOF
and close. Every Read1 worker records exactly 28,301 reads, 8,175 peeks, one
read EOF and close. Each setup file is recorded separately. No staged token
handle remains at normal completion. Rust uses `BufReader`; the counters show
136 underlying reads per Sum1 file and five per Read1 file, including EOF.

For ordinary symbols, the 20,197,500 identifier characters were already staged
once for unsuccessful number parsing and are staged again for interning.
Removing those two repeats accounts for 40,395,000 character transfers and
twice 4,775,000 token handles. Additional interning includes quoted/escaped
symbols and prefix names, so its entire count must not be treated as ordinary
three-stage symbols.

## Managed allocations and collection

Unchanged native binaries with `SNAIL_GC_STATS=1` supply independent managed
allocation counts. They include the whole process, including initialization and
setup. The bytes are requested native managed payload bytes, excluding collector
alignment/header overhead; they are neither RSS nor Rust allocation bytes.
These counts do not assert equal V8 allocations.

| Whole-process native statistic | Sum1 | Read1 |
| --- | ---: | ---: |
| Managed objects | 75,975,227 | 178,337,762 |
| Requested managed bytes | 1,849,503,844 | 4,164,064,940 |
| Collections | 346 | 797 |
| Mark phase seconds | 0.000949 | 0.088533 |
| Sweep phase seconds | 0.143878 | 0.412687 |

Separate production V8 GC observers retain 2,311 Sum1 and 281 Read1 events
overlapping the workload clock, all reported as minor collections. Their summed
whole-event durations are 139.874 ms and 78.331 ms. Boundary events remain
whole. GC observations and phase clocks are instrumentation; they are not clean
timing samples. Collection time and the profiler's GC leaf share exclude
mutator allocation, barriers, rooting, Rust text allocation and allocator work.
They cannot establish total allocation overhead. The Read1 profile separately
samples Rust `dlmalloc`/`dlfree` at 2.53%/1.47% exclusive shares.

## Ranked bottlenecks and independent next ablations

1. **Character service and decoding path.** Read1 makes 91,190,000 checked
   read/peek calls. Read alone has 27.23% inclusive sampled weight. A later
   internal scalar-code read/peek path could test the CharacterResult wrappers;
   preserve public EOF behavior, validation, ownership and error ordering.
   This needs an ablation before attributing allocation or promising a gain.
2. **Repeated token staging and owned handle churn.** Counts directly establish
   the repeated transfers; Rust tree take/remove/insert and token appending are
   visible hot functions. The smallest useful experiment stages each ordinary
   atom once, then keeps number parsing, identifier checking and interning in
   their current order. It must preserve malformed-number errors, numeric
   field extraction and close-or-consume ownership on every branch. Interning
   currently rejects Parsed handles: explicitly permit only a parsed
   `Ok(None)` nonnumber transition, while rejecting successful numbers and
   parse errors, with direct transition tests. Keep handles private to the
   datum service wrapper and reuse existing reader/result representations where
   possible. Quoted symbols, sharp words and the public reader contract retain
   their behavior. Do not introduce a second public numeric/symbol type family
   merely to organize this experiment.
3. **Fixed delimiter-string scan.** It contributes 10.86% Sum1 and 6.05% Read1
   exclusive sampled weight with no callees. First run an independent Scheme
   ablation replacing membership in the twelve constant scalars
   `40 41 34 59 124 39 96 44 91 93 123 125` with direct scalar checks. Keep EOF
   and Unicode-whitespace short circuit order unchanged. Check all twelve
   members, representative nonmembers, whitespace, comments, strings, quoted
   symbols, dotted lists, vectors, bytevectors and malformed boundaries, then
   inspect optimized Wasm to ensure the string loop disappeared.
4. **Buffer, result and container allocation.** Native object totals establish
   a large managed allocation workload, and final Wasm retains buffers,
   substring copies, result variants, reversed temporary List nodes and Datum
   pairs with two mutable Ref fields. Collection alone is a small sampled V8
   leaf share. Allocation/representation changes need scoped dynamic evidence
   and semantic tests rather than inference from static constructor counts.

Run the delimiter and single-staging ablations independently against the same
basis, with raw and optimized linked Wasm execution and complete stream,
full-count, error-boundary and resource-cleanup validation. Check Scheme and
Rust tests where their modules change. Collect clean comparisons only after a
new frozen plan and coordinated quiet release; none has been collected here.

## Retained evidence and reproduction

[findings.json](findings.json) contains complete exclusive/inclusive rows,
counts, GC scopes and boundary summaries. [manifest.json](manifest.json) checks
every member of [artifacts.tar.xz](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-strict-reader-diagnostics/artifacts.tar.xz): full raw profiles, raw
outputs, per-process commands/environment/frozen checks, markers, phase/file
counters, GC events, exact host-erasure proofs, disassemblies, source snapshots
and the used frozen guest modules/native binaries/input files. Nix tool binaries
are identified by the original plan and are not duplicated.

Restore the archive into `build/strict-reader-diagnostics/` in this checkout.
The original frozen owner tree and its complete comparison artifacts are needed
for the 111-identity verification and replay. `analyze.py` reproduces the summary
and archive. To make a new instrumented record, use a fresh output directory
and invoke `diagnose.py profile sum1` (or `gc`, `counters`, `native-stats`, and
`read1`). Existing run directories deliberately fail rather than overwrite
evidence. These commands never produce clean samples.
