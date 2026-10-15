# Bounded Tail gap investigation

This task is diagnostics/report only, based on comparison commit
`916ce7a7c2ca4d39a832275acbf1812b5390a1ab`. Production sources and artifacts
stay unchanged. Initial work consisted of isolated checkout and static source/
optimized-WAT inspection. All execution/build/profile/compression handles were
terminal during the parent's subsequent 36-process Ray timing hold. The parent
explicitly released that hold before diagnostic execution was authorized.

## Fixed evidence and static findings

Use the exact optimized strict Wasm
`23de40d54791743841fe3e9e93336872bd34ef6a8858607b136eb4cb92d2e33d`,
its archived `strict.wasm.wat`, count 50, complete 4,460,056-byte bibliography
and complete reversed-byte oracle. Reuse the frozen original/adapted Chez and
optimized Rust controls and their established semantics/lifecycle evidence.
No reduced input, changed algorithm, production rebuild or clean timing campaign
is part of this first pass.

The frozen source already identifies materially different work:

- Original Chez maps `read-line` to native `get-line` and `write-string` to
  native `put-string`. The adapted control builds lines and writes characters
  through the shared Scheme loops; it takes 1.908× original Chez time.
- Strict Scheme constructs Unicode-scalar owned buffers. Each line begins with
  an empty String, grows from 64 by doubling and is trimmed once unless exact.
  Each character receives capacity/bounds/block-index checks and a store.
- Strict reads/writes call linked Rust scalar functions directly within Wasm.
  These are **Wasm-to-Wasm calls**, rather than one JavaScript crossing per
  character. The Rust provider borrows a `RefCell`, finds the resource through
  a `BTreeMap`, validates/directions dispatches, decodes or encodes UTF-8 and
  accesses buffered I/O on each call. Buffering prevents a syscall per character.
- Rust's reference collects UTF-8 `String`s in `Vec<String>` through standard
  line/byte operations and emits buffered strings. It drops input before writing;
  Scheme closes input after output. Count domains and CR handling differ outside
  the canonical LF/count-50 workload.

In the exact final WAT, `$function52` contains the line-building loop,
`$function57` the output character loop, `$function61` the retained reversed
list construction, `$string-new` owned allocation, and `$string-copy-forward`
block copies. `$snail:io/read-character` and `$snail:io/write-character` retain
the Rust provider dispatch. These mappings will be checked against actual
profile names/indices; source presence alone is not a cost attribution.

## First diagnostic pass after release

1. Derive independent canonical input statistics: Unicode scalar count, line
   lengths/distribution, capacities, exact-fit/trim cases and geometric growth/
   trim copy totals. State which counts are source-derived predictions.
2. Sample one full execution of the exact optimized guest on CPU 5 with Node's
   inspector CPU profiler. A diagnostic host will bracket sampling around the
   benchmark call after setup and before terminal cleanup. Preserve exact host
   additions and an erasure proof. Attribute exclusive samples to Scheme line
   building, output, retained-list handling, copies/allocation, Rust scalar
   services, buffered/WASI I/O, GC, and unresolved frames. Inclusive call-tree
   totals will remain separate and will not be added as independent costs.
3. Run a separate full-count counter execution built by textual insertion into
   the exact final optimized WAT, with no reoptimization. Count scalar reads/
   writes, line/list/variant sites, String capacity requests, actual array
   allocations/default-initialized lengths and copied I32 cells. Reset after
   setup. Erasing additions must recover the original WAT exactly. Counts are
   executed sites/operands, not physical engine allocation counts or clean costs.

Every process uses fresh real input/output files and all 50 repetitions.
Preserve started attempts, commands, flags, artifact/source/tool identities,
raw stdout/stderr, profiles/counters and failure records before interpretation.
Verify all 4,460,056 output bytes and unchanged input afterward. Diagnostic
hosts also check 100 successful opens/closes, 49 deletions, ordered input/output
release and 223,002,800 transferred bytes in each direction, excluding stdin/
stdout. Extra host observation and sampling overhead are disclosed; diagnostic
durations never join the clean samples.

If Node cannot resolve Wasm samples sufficiently, retain that failure and report
its limit before selecting another profiler. The initial pass reports actual
findings and unresolved attribution to the parent before any ablation. A GC
trace, provider simplification, altered buffering, changed line storage, or
source/compiler optimization requires a separate decision; none is silently
introduced here. The investigation remains independent of shared-empty
constructor optimization and does not infer GC cost from the 22.658× Rust gap.
