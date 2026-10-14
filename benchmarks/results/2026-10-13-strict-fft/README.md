# FFT with the canonical kernel and native Wasm sine

Strict Wasm takes 74.3% less time than Chez for the original zero-input FFT
workload on the **c39c268 + cf22413 compiler**, before the shared-IR changes.
Chez uses canonical generic arithmetic; no explicit-flonum FFT control was
measured.

| System | Retained median (range), s | Strict / Chez |
| --- | ---: | ---: |
| Strict Wasm | 0.202581 (0.202572–0.206983) | 0.256884 |
| Same-kernel Chez | 0.788609 (0.786080–0.790070) | |

[All eight observations](results.json) passed: one discarded pair and three
retained alternating pairs, with fresh processes, CPU 5 and default V8.
No failed, timed-out, replacement or shortened samples occurred. Other agent
builds/tests were paused for the coordinated quiet window. The discarded pair
does not warm the retained processes.

Each run preserves **100 repetitions**, allocating a fresh **65,536-element
F64 vector filled with 0.0 inside each iteration**. The original predicate
checks only the first returned element against 0.0. Kernel text is unchanged;
the complete original/matched Chez sources and binaries are identical. Strict
supplies `inexact` and a scalar sine import outside the kernel. Its Rust 1.95
provider links sine inside Wasm, has zero imports and receives only F64 scalars;
Scheme vectors stay in the consumer's WasmGC heap. Native math libraries,
representations, static type knowledge and host support still differ.

Explicit setup, instantiation and program initialization precede timing.
Repeated allocation, opacity calls, FFT work, native sine support and final
result checks are timed on both systems. Lazy V8 compilation or tiering during
execution is included. The barrier receives no Scheme vector and does not
establish dynamic work retention.

The weak zero-input predicate is supplemented by **23 preparation checks**:
original-size counts 1/2 in raw/optimized Wasm and Chez; nonzero and impulse
transforms comparing every real/imaginary component with an independent
positive-phase DFT; and wrong, short and long expected-vector rejection by
both implementations. Tolerance is `1e-12 * max(1, abs(expected))`. Static
[retention inspection](retention-audit.json) of the exact optimized Wasm finds
timed allocation, bit-reversal swaps, stage/twiddle/butterfly loops, eight
butterfly loads and four stores, and two sine call sites per stage body.
These are static instruction sites, not dynamic counts or a V8 machine-code
audit. Correct zero output alone cannot establish execution of all that work.

FFT initially exceeded the default stack because Unit sequencing obscured a
tail call. The archive preserves that failed preparation. Parent fix
`cf22413567baa5e39db9cf88f41e53a6be93d4f8`, cherry-picked as `96ce088`, passes
with byte-identical program source and no stack flags. [Preparation](prepared.json)
freezes driver checkout `87855830eb8d216def3ab71bda1757d867be4ca0`; all 51
compiler files match that fix on `c39c268`. Upstream remains pinned at
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Node 24.19.0 /
V8 13.6.233.17-node.51, Chez 10.4.1 and Binaryen 132 are recorded alongside
provider source, binary and 60 Rust compiler/linker/library hashes.
[Independent review](independent-review.json) accepted the source/protocol;
[replay](replay-check.json) verifies all 298 archived files and passes all 23
bounded checks again.

[Coverage](coverage.json) reconciles the prior 18 passing measured ports/slices
plus FFT: **19 passing**, Ackermann's prior default-stack failure and **37
unported** out of 57. Existing reports remain unchanged.

Restore from the repository root:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-fft-replay \
  --report benchmarks/results/2026-10-13-strict-fft
```

To repeat timing, use the recorded tools and driver files matching the hashes
in restored `prepared.json`, as checked in with this report:

```sh
env -u NODE_OPTIONS python3 benchmarks/strict-suite/measure.py measure \
  --output /tmp/strict-fft-replay/strict-fft-final-cf22413 --cpu 5 --rounds 3
```

This overwrites only restored `results.json`; the archive retains the original
observations and all earlier preparation evidence.
