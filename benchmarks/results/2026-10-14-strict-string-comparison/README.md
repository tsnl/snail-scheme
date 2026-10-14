# String copying exposes an allocation cost

The full String workload takes **5.024 seconds in strict Snail**, versus
**0.058 seconds in Rust/Wasm**. Both Chez controls are also faster. The result
adds one measured workload; it does not establish a whole-suite comparison.

Each median contains four fresh-process samples after one discarded round.
All entries are workload seconds, excluding process startup and preparation.

| Implementation | Median | Retained range | Snail time / implementation time |
| --- | ---: | ---: | ---: |
| Strict Snail | 5.024121 | 4.734789–5.113165 | 1.000× |
| Original Chez | 1.615278 | 0.945305–2.535696 | 3.110× |
| Adapted source on Chez | 1.446895 | 0.997757–1.988950 | 3.472× |
| Rust/Wasm | 0.057975 | 0.057711–0.063116 | 86.661× |

Chez varies substantially in this batch. Its two ranges overlap, so their
median ordering is not evidence that the adaptation improves Chez. The large
Snail/Rust difference remains across every retained sample.

## Work and representation

The original input remains `100`, `500000`, `524278`: one hundred invocations,
each running ten trials that grow a string past 500,000 characters. Each
growth concatenates five segments, copies two overlapping halves, then
concatenates those halves. The original literals, reset, growth sequence,
unused trial counter and final length predicate remain.

The [preparation report](../2026-10-14-strict-string/README.md) records the
reversible source adaptation, complete-payload and alias checks, boundary
cases, and optimized Wasm/native inspection. Strict source makes the global
mutable binding an explicit `Ref String`. Its typed harness reconstructs the
original Boolean-or-integer result at the final predicate. Original Chez
retains its original source; adapted Chez runs the explicit-ref source and
corresponding harness representation. These source changes are disclosed;
this is not a claim that all implementations compile identical source text.

Strict strings use mutable WasmGC arrays of four-byte Unicode scalars, with
one permission cell. Rust uses UTF-8 `String`; the canonical data is ASCII,
so each payload character occupies one byte. Rust's final append can grow
and reuse its owned back-half buffer, whereas strict `string-append` creates
a fresh buffer. Their reclamation and lifetimes also differ. The frozen Rust
source and its source-to-Wasm retention audit are in
[the handoff](rust-handoff.json). The comparison measures these complete
programs; it does not isolate GC, storage width, or equal allocation work.

The preparation's separate instrumented module records 60,000 completed
string constructors, 135,000 `array.copy` spans, 3,145,167,000 copied Unicode
scalars, and 31,000 global stores. Variadic argument-list spines are additional
work. Constructor completions are not physical allocation counts. The
unchanged native code retains allocation, zero initialization, both substring
copies, final concatenation and global stores.

## Diagnostic evidence points toward memory allocation

The following runs occur after the clean timing window, with background build
jobs permitted. Their hosts are instrumented; their elapsed times are not
additional clean samples.

A V8 CPU profile of the unchanged canonical Wasm attributes 59.3% of weighted
samples to append sizing/allocation, 21.0% to substring construction, 9.8% to
the trial and stores, and 4.1% to append copying. Samples classified as GC
account for 5.7%. The 197 young and five major collection events between the
benchmark markers report 262.7 ms of pauses. Neither sample classification
nor printed pauses measures all collector work. Native and kernel execution
can be attributed to the enclosing Wasm caller by this sampler.

An independent resource bracket immediately around the full benchmark call
records **0.833 seconds of user CPU, 3.857 seconds of system CPU, 2,896,048
minor page faults, and no major page faults**. This confirms that the kernel
CPU and faults occur during the workload, rather than only during startup or
CPU profiling. Resource counters cover all process threads; they are not a
breakdown of individual Wasm operations.

A syscall trace with only the outer count reduced to one retains ten complete
trials. Between the synchronous benchmark marker writes it records 288
successful `mmap`, 422 `munmap`, 289 `madvise`, and one `mprotect` calls. Of
the advice calls, 288 use `MADV_DONTFORK` and one uses `MADV_DONTNEED`.
The parser pairs all unfinished/resumed calls before counting; no call crosses
the marker boundaries and none inside fails. Summed requested address ranges
can overlap or be reused and are not resident or physical byte counts.
The trace is instrumented and its elapsed time is not comparable with the
clean measurements. An initial sandbox ptrace failure is preserved separately.

The evidence supports allocation and OS memory work as a major remaining
cost. It does not yet separate fresh large-object mappings, initialization,
payload width, and reuse. A bounded page-policy diagnostic changes only
Node's `--no-decommit-pooled-pages` flag. Both default observations and both
alternate observations still incur about 2.896 million minor faults and
3.89–3.94 seconds of system CPU. That flag does not remove the observed
problem. It is not a clean timing experiment and does not change the default
runtime configuration. Matched Rust width/fresh-buffer controls remain
follow-up work.

## Measurement and reproduction

Runs use logical CPU 5 of the same Intel Core Ultra 7 270K Plus, Node 24.19.0,
Chez 10.4.1, default V8 tiering and no inherited `NODE_OPTIONS`. Other agents
held their build/test jobs during the clean window. Four retained cyclic
rotations place each system in every ordinal position once; this balances
position but not all drift or predecessor effects. Fresh-process runs include
JIT tiering even after the discarded round.

All twenty executions pass. The original count and final predicate remain
inside the workload clock; source loading, compilation, instantiation and
setup remain outside. Rust uses the frozen `wasm32-wasip1` release artifact;
its build settings and historical provenance limitations are recorded in
[rust-build-provenance.json](rust-build-provenance.json). All 110 recorded
source, artifact and tool hashes match before and after measurement.

The strict compiler source is `2def994`, published as unmerged `fbb3972`.
The adapter is `3238d82` and preparation evidence is `689ae90`. Historical
strict measurement coverage now reaches 27 of 57 workloads, with 26 paired
Chez comparisons. Earlier entries retain their own compiler checkpoints.

[clean-string.json](clean-string.json) preserves every command, output,
process duration and sample. [summary.json](summary.json) contains ratios and
diagnostic summaries; [resource-summary.json](resource-summary.json) retains
the resource brackets. The regular-file archive includes exact source and
program bundles, raw profiles, traces, policy observations, and diagnostic
scripts. External tool binaries retain their paths and hashes.

Restore and verify the archive:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/string-comparison-replay \
  --report benchmarks/results/2026-10-14-strict-string-comparison
```

After arranging a quiet window, repeat the complete comparison:

```sh
python3 benchmarks/results/2026-10-14-strict-string-comparison/reproduce.py \
  /tmp/string-comparison-replay string /tmp/repeated-string.json
```

The replay driver preserves the recorded schedule and checks relocated files
and exact external tools. The parent also executed one bounded count-one
probe per system from the restored archive, checking the original threshold
and result. Those four executions validate relocation and correctness, not
performance; their commands and outputs are in `replay-check.json`.
