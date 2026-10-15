# Wc compiled from strict Scheme source

The strict Scheme worker reduces the original `wc` workload from **10.261s to
2.021s**, a **5.08×** speedup over the matched old generated character loop.
Same-window Chez takes **0.646s**, so strict Snail takes **3.13×** its workload
time. [`count.scm`](../../strict-wc/count.scm) compiles through the strict
compiler's inference, monomorphization, native Wasm emission, and Binaryen. The
original Scheme harness still opens and closes files, runs fifty repetitions,
and checks `(31102 851820 4460056)`.

## Clean batch

Node 24.19.0 / V8 13.6.233.17, default engine settings, logical CPU 5 on the
recorded Intel Core Ultra 7 270K Plus host. Both Snail variants use the same
frozen Rust scalar provider, Node host, platform, strict-module initialization,
and Binaryen 132 recipe. The untouched Chez 10.4.1 binary uses safe optimization
level 2 and its original character-counting source.

One full fresh-process run per variant is discarded. Three retained rounds
rotate the three variants, putting each in every position once. Other compiler,
test, benchmark, and archive-compression work was paused during timing. The
batch has no instrumentation or forced collection.

| Counting implementation | Retained workload seconds | Median |
| --- | --- | ---: |
| Old generated Scheme loop | 10.363369, 10.189553, 10.260674 | 10.260674 |
| Compiled strict Scheme loop | 2.011033, 2.028453, 2.021339 | 2.021339 |
| Chez, same window | 0.646414, 0.643880, 0.646275 | 0.646275 |

All twelve executions pass the original result predicate against the exact
4,460,056-byte input, SHA-256
`2994b446dfb07d7cf324fb6aa32d519b3f0bd53a582268714adf08df5f45b8d3`.
Each processes 223,002,800 characters across fifty file openings. The corpus
is ASCII; separate Unicode fixtures verify scalar counting rather than byte
or UTF-16 code-unit counting. [clean.json](clean.json) preserves every command,
stdout/stderr, discarded and retained sample, input/artifact hash, and tool
identity. [summary.json](summary.json) contains the derived comparisons.

Workload time includes the original file operations, counting loops, and final
list predicate. Compilation and initialization precede that timer. Median
whole-process times, which include loading and startup, are 10.294064s old,
2.053158s strict, and 0.678019s Chez.

## Native boundary and remaining limits

The source worker receives an I32 resource ID and reads one Unicode scalar at a
time. It keeps newline, word, and character counts in I64 values and word state
in Bool. Only ASCII space and newline delimit words. EOF submits all three
counts through one no-result native scalar call; the legacy adapter constructs
the usual Scheme list. It retains the input wrapper in an owned ABI root
through the reads and result construction, then releases the root. WasmGC
traces list intermediates on the operand stack.

The optimized standalone worker has no successful per-character Scheme boxing,
argument-array allocation, or ABI-root operation. Binding-readiness guards and
non-null closure checks remain in its native counting loop. The archive includes
standalone and linked disassembly. This inspection concerns the worker; the
process still uses legacy AWI startup, current-port roots, file management, and
result allocation.

The scalar result sink contains diagnostic globals. Invocations are synchronous
and do not overlap; the frozen provider makes no Scheme callbacks. A read error
immediately consumes its saved diagnostic and terminates the process, so stale
or partial counts cannot become a successful result. Resource IDs never encode
GC addresses. Fixed I64 counters cover the pinned workload; arbitrary-size
Scheme counters and a public typed character/EOF interface remain separate work.

The old control is rebuilt with the same experiment scaffolding, so its final
binary differs from the historical old benchmark. The old-to-strict comparison
combines representation, foreign-boundary, calling, and generated-control-flow
changes. It does not isolate inference, GC time, or engine overhead. Three
retained runs support this observed workload comparison, not a full-suite claim.
Chez supplies a language/runtime baseline and has a separate monotonic-clock
harness.

## Validation and reproduction

[validation.json](validation.json) records eleven linked process checks: five
modes for each Snail implementation, plus the Chez original-corpus predicate.
Each Snail success check covers seven literal string fixtures, delimiter
transitions, repeated EOF returning zero counts, supplementary characters and
NUL, UTF-8 across a file-buffer boundary, the full corpus result, I64 list
transport up to `2^63-1`, incompatible native import signatures, forced-GC owner
liveness, late resource cleanup, and the final three-current-port root balance.
The four error modes cover closed input, output-port misuse, malformed UTF-8,
and truncated UTF-8. These checks run outside clean timing on the final binaries.

A preliminary checker expected different text for the direction-error
diagnostic. The expectation was corrected and all artifacts rebuilt before
timing; the initial and final binaries are identical. The raw preliminary
failure is retained in [initial-validation.json](initial-validation.json), and
the archive records the initial checker and binary comparison.

The pinned simplify workflow used a fresh behavioral explanation followed by
informed comparison with the implementation. It confirmed the four streaming
state values, successful-EOF-only result transport, root ownership through list
construction, and immediate fatal error handling. No compiler or older frontend
module was changed. [review.md](review.md) records the scope and decisions.

The [archive](artifacts.tar.xz) preserves 163 files: the compiler source snapshot
at `93f34a9`, Scheme worker and build drivers, frozen provider sources/binary,
legacy compilation and capture logs, untouched Chez source/binary, all consumed
inputs, intermediate/optimized/linked Wasm, disassembly, functional fixtures,
and raw timing records. The [manifest](manifest.json) checks every archived file.
Restore and check compiled artifacts without executing a workload:

```sh
python3 benchmarks/strict-wc/replay.py /tmp/strict-wc-replay
```

Add `--validate` to rerun linked behavior. Add `--measure --cpu 5` only during a
quiet CPU window to repeat the clean batch. Execution requires the recorded
Node/Chez binaries; the timing driver also verifies recorded Chibi and Binaryen
tool hashes. [replay-check.json](replay-check.json) records successful restoration
of all 163 files and a fresh pass of every linked behavior check. For a source rebuild, follow the
[experiment instructions](../../strict-wc/README.md).
