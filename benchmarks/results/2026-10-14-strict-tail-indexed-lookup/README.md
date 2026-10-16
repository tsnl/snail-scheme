# Full Tail indexed lookup experiment

Changing the diagnostic file lookup container reduced the sampled full-workload
median by **3.83%**: **4.874577 s** for the unchanged `BTreeMap` baseline versus
**4.687847 s** for indexed `Vec<Option<Port>>`. Four retained pairs improved by
1.18%, 4.20%, 6.71% and 2.78%. This small signal leaves most of the measured Tail
gap unresolved. It supports a bounded observation about these artifacts and
this workload; it neither isolates a universal lookup cost nor authorizes a
production Vec replacement.

| Variant | Workload median | Workload range | Separate process median |
| --- | ---: | ---: | ---: |
| Original lookup | 4.874577 s | 4.754660–5.002979 s | 4.909873 s |
| Indexed lookup | 4.687847 s | 4.667305–4.731803 s | 4.722170 s |

[summary.json](summary.json) retains every sample and paired reduction;
`matched-measurements/tail-indexed-lookup.json` retains all ten raw outcomes and
their complete actual file identities. One excluded AB pair precedes retained
AB, BA, AB, BA cycles. There are four retained observations per variant, no
replacement trials, and no statistical confidence claim. All outcomes passed
and **408 frozen identities remained unchanged**. Every owned process group was
empty at completion.

## Precisely bounded source change

This isolated task starts from first-pass diagnostics commit
`0038492d894cf18dd833e7ba4a532555e58887e5`. Production sources, Scheme libraries,
compiler and historical artifacts remain unchanged. The
[first-pass report](../2026-10-14-strict-tail-diagnostics/README.md) found 73.14% of weighted profile
intervals in combined Rust scalar/UTF-8 frames and confirmed 446,005,650 scalar
requests plus substantial Scheme line construction. Those frames combine
borrowing, lookup, direction/error checks, codec and buffering; this experiment
tests one representation component of that combined work.

[provider-change.patch](provider-change.patch) shows the entire baseline/candidate
difference. Both snapshots come from the frozen 76-file Tail runtime/compiler
source closure. A common `cfg(test)` sparse-history check compiles out of both
release providers. Only `src/strict_io.rs` differs between snapshots:

- `BTreeMap<u32, Port>` becomes `Vec<Option<Port>>`, indexed by the same ID.
- Successful publication grows through that ID with `None` holes while the
  opened Port remains locally owned, then moves it into its issued slot.
- Lookup/removal use checked indexed Option access; final cleanup takes the
  Vec and flattens it in ascending issued-ID order.

ID reservation, `RefCell` scope, scalar ABI, pathname transfer, Unicode codec,
buffering, error messages/precedence, flush/drop, cleanup order and Scheme
storage/operations stay the same. Negative I32 bit patterns reach the existing
`u32` unknown/closed error. The erasure ledger recovers the baseline source
exactly. A failed open consumes an ID before the filesystem attempt; it need
not grow the Vec until a later successful publication.

Holes make capacity proportional to historical issued IDs, rather than current
live ports. Canonical Tail has at most two live file ports and issues only 100
IDs in each fresh instance. Inserting
at `I32_MAX` would require 2,147,483,648 slots; only reservation/exhaustion
arithmetic is tested at that boundary. Memory exhaustion and arbitrary host
traps can interrupt disposal. Trapped instances remain terminal. These limits
make the candidate unsuitable as an unrestricted production representation.

## Matched build and correctness evidence

Both providers compile through the same source path, with separate frozen
snapshots and target directories, verified Rust 1.95 compiler/target libraries,
offline locked release commands, LTO and one codegen unit. Build overrides are
unset. Both links use exactly the same pre-link Scheme Wasm, SHA-256
`097a7eab1e03b7a8905d6487bb622d70aa2e55a7e5da89ae1fa5e827e89b6594`,
the same frozen linker/adapter, and mandatory Binaryen 132 `-O3`, closed-world,
inlining and convergence passes. Raw/intermediate forms remain diagnostics.

The rebuilt baseline reproduces the historical final guest **byte-for-byte**:
`23de40d54791743841fe3e9e93336872bd34ef6a8858607b136eb4cb92d2e33d`.
The indexed final guest is
`1e21bb03a5b47c398197b3dff04f72daf54be3b6a14cecaf7576a3f147dd3b2a`.
Provider differences can change whole-module Binaryen optimization and layout;
final Scheme instruction bytes are not claimed identical. The paired baseline
is newly measured, rather than substituting an earlier median.

Each configuration passed six focused Rust unit checks and ten actual optimized
Rust/WASI scalar cases: Unicode/EOF/lookahead, monotonically issued IDs, failed
open consumption through private helpers, holes/stale/negative/unknown IDs,
ordered release after returned WASI EIO and primary-error precedence. Descriptors
were disposed before fatal diagnostics. The runtime-only probes retain unused
legacy ABI imports with explicit throwing stubs; successful probes cannot call
those services. Full linked strict artifacts retain their normal import contract.

Both linked guests then completed count 50 on the entire 4,460,056-byte input.
A common diagnostic observer compared every byte of all **50** materialized
outputs after output close, verified the final actual file and unchanged input,
100 opens/closes, 49 deletions, release order, and 223,002,800 transferred bytes
in each direction. Every iteration reads the same original bibliography and
writes the same reversed oracle. The observer's extra host reads/hashes are
absent from the timed host. These preparation durations are not clean samples.

## Clean protocol and limits

[freeze.json](freeze.json) gives exact commands, tools, sources, artifacts,
original input bytes and host. CPU 5, Node 24.19/default V8 tiering, cleared
Node injection variables and fresh process/cwd apply to every trial. The full
bibliography is seeded before either clock and output starts absent. Workload
timing starts after initialization/pathname setup and ends after all repeated
file work and the original always-true predicate. Process timing covers launch
through completion; subsequent process-group inspection and complete output/
input validation are outside that clock. Only the canonical frozen host runs
in timing trials; profiling, counters, trace callbacks and fault injection do
not enter them.

The parent granted this window after Nucleic's campaign was terminal and all
agents acknowledged holding CPU work. [quiet-window.json](quiet-window.json)
records the acknowledgment. Conversation/source editing/tool metadata and
uncontrolled desktop/kernel/filesystem activity remain possible. Sample spread,
four observations and this host limit generalization. Process durations are
reported separately from workload durations.

The [original four-system comparison](../2026-10-14-strict-tail-comparison/README.md)
remains historical context: original Chez uses native line/string operations;
adapted Chez uses the Scheme character loops; Rust uses UTF-8 `Vec<String>`
storage and closes input earlier; strict Scheme uses Unicode I32 buffers and
persistent list nodes. Nonnegative Rust count parsing and CR/LF semantics differ
outside the canonical input. Those controls were not rerun in this provider
pair and their medians do not isolate a mechanism. No new storage, codec,
Scheme/compiler or production optimization is included here.

## Closed archive and reproduction

[prepare.py](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-strict-tail-indexed-lookup/prepare.py), [probe.mjs](probe.mjs) and [measure-matched.py](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-strict-tail-indexed-lookup/measure-matched.py)
retain actual commands, started attempts, raw streams and complete files before
interpretation. New subprocess groups are killed on timeout and checked for
executing descendants; a synthetic owned parent/child timeout passed. The first
preparation attempt is preserved with its original source and path relocation
map: its probe rejected unused legacy imports before instantiation. No clean
trial was retried. [measurement-review.md](measurement-review.md) records the
fresh independent explanation, single critique and parent review.

`artifacts.tar.xz`/`manifest.json` close sources, builds, erasure records, focused
checks, failed attempt, all ten raw trial/file trees and prior diagnostic/control
evidence. Every regular archive file is restored and hash-verified. Two actual
relocated executions use the full count and all input/output bytes; they are
correctness replays, excluded from clean samples. `replay-check.json` and its
separate `replay-evidence.tar.xz`/`replay-manifest.json` retain their raw outcomes
and actual files without an archive self-reference. External tools/toolchain
libraries are identified by path/hash rather than vendored; complete inherited
environment and machine activity are not archived. No coverage count changes.
