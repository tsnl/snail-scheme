# Character I/O: generated work, GC, and a small ablation

The frozen `b218ce2` program copies 4,460,056 ASCII bytes fifty times,
one character at a time: 223,002,800 characters. It spends about 21 seconds
on this machine, versus 0.70 seconds for the compiled Chez program. The
evidence points to generated per-character work and the generic Rust boundary;
it does not attribute the gap to V8's collector.

This report contains no production compiler or runtime changes. It preserves
three separate diagnostic processes and a clean four-variant timing experiment.
The compiler's later positional calling convention and strict-core rewrite are
outside these measurements.

## What the loop does

Both implementations use buffered files. Snail's diagnostic run makes 27,301
WASI `fd_read` and 27,267 `fd_write` calls, rather than one syscall per character.
The current Rust `write-char` uses a four-byte UTF-8 stack buffer; an earlier
temporary-string implementation is not the code measured here.

The final Wasm loop (`$function172`, Wasm function index 149) constructs three
argument arrays per non-EOF iteration: a one-element EOF-predicate array,
a one-element read array, and a two-element write array. It also requests a
capture-environment struct when recursing. Binaryen names that two-reference
struct `$complex`; its role in this loop is an environment, not a number.
The Rust boundary acquires owned roots, checks containers and port resources,
and transfers a rooted Scheme result for each read/write.

Heavy counters record the following over the full invocation, including
initialization and result checking:

| Reached operation | Count |
| --- | ---: |
| Constructor requests, all types | 1,115,017,326 |
| Argument-array requests in the hot loop | 669,008,450 |
| Capture-environment requests in the hot loop | 223,002,800 |
| Character-atom requests, whole program | 223,002,801 |
| `abi_root` entries | 1,561,020,760 |
| ABI length-helper entries | 1,561,023,927 |
| `abi_take` entries | 446,005,982 |

These are reached instructions and helper entries in instrumented Wasm,
not counts of heap objects materialized by uninstrumented V8. Instrumentation
changes optimization. Approximately seven root registrations per character
describe generated work; they are not seven collections.

## Independent CPU sampling and GC tracing

A fresh default-tier Node 24.19.0 process sampled at one millisecond produced
19,859 samples. Self-attribution included the loop (33.18%), Rust `read-char`
(12.73%), Rust `write-char` (9.49%), the ABI length helper (7.46%), port and
root helpers, and the garbage collector (2.51%). These are whole-process sample
fractions, not exact causal cost fractions. Inlining can attribute work to a
surprising function: `call-with-values` has 7.05% of samples despite only 200
entries in the separate instrumented run.

The GC-only process recorded 19,037 scavenges and 35,688,298,824 allocated bytes
reported at GC events. That is whole-process V8 allocation, excluding the last
uncollected interval and Rust allocations within Wasm linear memory. The live
object size after the final observed collection was about 5.1 MB.

**The printed pause sum is not an exact GC duration.** Individual pauses are
rounded to 0.1 ms, so their printed 4.4 ms sum admits a 2.55–956.25 ms rounding
interval. The included scavenge phase, printed with finer precision, sums to
500.98 ms (rounding interval 405.795–596.165 ms). Do not add these overlapping
durations or treat either as all concurrent/background GC CPU time. The raw
trace and parsing definitions are retained in the archive.

All three diagnostic runs passed a complete output-size and SHA-256 check.
Their durations are excluded from the clean comparison below. Compiler/test
jobs were allowed during diagnostics; clean timings used a coordinated quiet
host and CPU affinity 5.

## Removing only the EOF argument array

The ablation edits final WAT to replace the inlined EOF predicate's one-element
array length with `1` and its element extraction with the original value.
It keeps the existing arity branch and all other code. No further optimization
pass runs. An unchanged WAT round trip changed binary encoding, so a separate
round-trip control is essential.

Each variant ran in a fresh process, with one discarded full run and three
retained full runs. Variant order rotates each round. Compilation and process
startup are outside the program's workload timer. Every invocation deletes the
previous output first, then verifies all 4,460,056 output bytes by hash; all
sixteen invocations passed.

| Variant | Retained median (s) | Retained range (s) |
| --- | ---: | ---: |
| Original frozen Snail binary | 20.822369 | 20.698988–21.337163 |
| Unchanged WAT round trip | 20.664498 | 20.615954–20.996885 |
| EOF argument array removed | 20.933658 | 20.750830–21.026706 |
| Chez | 0.700398 | 0.695606–0.701455 |

Removing that single carrier shows **no demonstrated speedup**. Its median is
1.30% above the matched control, with overlapping ranges. This does not show
that all argument arrays, boxing, or root ownership are cheap; it bounds what
this particular one-change experiment established.

The next useful experiment separates native scalar Rust imports from a loop
that also retains characters in registers and roots ports once around copying.
Those are separate mechanisms and should be measured separately.

## Evidence and replay

`clean.json` contains every timing and output check. `diagnostics.json` contains
the derived counters, profile fractions and GC definitions. `manifest.json`
hashes the archived files and `artifacts.tar.gz`. The archive includes frozen
Wasm/Chez programs, input, host code, raw profiles/traces/counters, WAT, and the
exact experiment scripts. Duplicate copied output payloads are omitted; their
size and hash remain in each run record.

Restore and verify the frozen experiment without running benchmarks:

```sh
python3 benchmarks/results/2026-10-13-cat-abi/replay.py /tmp/cat-abi-restored
```

After arranging a quiet host, add `--measure` to run a fresh clean comparison.
The original pinned Node and Chez executables must still be available; the
replay verifies their hashes instead of silently substituting another version.
Use the stored raw data to inspect prior results without rerunning anything.
