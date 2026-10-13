# Five more strict benchmark ports

On the **unmerged interim numeric compiler**, strict Wasm is faster for
nqueens, mbrot and pnpoly, and slower for primes and triangl. These are
original-size runs against both original Chez and Chez with the same kernel
text. The result-context overload and `Default T` layer is not included.

| Workload | Strict median (range), s | Same-kernel Chez median (range), s | Original Chez median (range), s | Strict / same-kernel |
| --- | ---: | ---: | ---: | ---: |
| primes | 0.596629 (0.591274–0.597710) | 0.415163 (0.414582–0.415736) | 0.416653 (0.414733–0.416929) | 1.437098 |
| nqueens | 2.537022 (2.536123–2.548119) | 2.621019 (2.619234–2.633863) | 2.637343 (2.618334–2.644186) | 0.967953 |
| triangl | 1.305392 (1.295807–1.306327) | 0.859839 (0.856649–0.860099) | 0.856087 (0.855843–0.856265) | 1.518182 |
| mbrot | 0.313929 (0.313726–0.321488) | 2.266252 (2.261316–2.266379) | 2.264043 (2.258950–2.265939) | 0.138523 |
| pnpoly | 0.713934 (0.704758–0.748842) | 1.527904 (1.527140–1.528142) | 1.513107 (1.510446–1.515969) | 0.467263 |

[All 60 observations](results.json) pass the original result checks: 15
discarded and 45 retained, with no failures, timeouts, replacement samples or
shortened counts. Each case uses fresh processes on CPU 5, default V8 tiering,
one complete discarded trio and three rotating retained trios. Each system
occupies every retained position once. Other compiler builds/tests were paused.

| Workload | Original repetitions and inputs | Original result validation |
| --- | --- | --- |
| primes | 10,000; limit 1,000 | All 168 primes, order and list ending |
| nqueens | 10; 13 queens | 73,712 solutions |
| triangl | 50; initial move 22, depth 1 | All 13 expected moves, order and list ending |
| mbrot | 1,000; 75 by 75 matrix | Returned element equals 5 |
| pnpoly | 1,000,000; two 20-element F64 vectors | Original 12-point count equals 6 |

The [preparation record](prepared.json) freezes compiler/driver commit
`39d68ff0702d20857a5f42d8ff3170335e67cc8a`. All 50 compiler-source files match
numeric commit `320987e43e705bd81c7058985656c084c99474a3`, cherry-picked locally
as `a23fbdc90a9aacffa44fcdfdef01dc549df69c22`. Upstream remains pinned at
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Tools are Node 24.19.0 /
V8 13.6.233.17-node.51, Chez 10.4.1 and Binaryen 132 on Intel Core Ultra 7
270K Plus; executable paths and hashes are preserved.

The kernel edits are mechanical: primes is unchanged; nqueens removes the
trace body guarded by immutable `#f`; triangl constructs five flat integer
tables, boxes its mutable answer and supplies an omitted identity `do` step;
mbrot supplies explicit vector fills and two I64-to-F64 conversions; pnpoly
boxes its local integer counter. Every adapted Chez kernel matches strict text
exactly. Whole-source reconstruction preserves the original Chez import,
hide, harness, predicate and optimization level 2, with compatibility helpers
outside the shared kernel. Primes' complete original/adapted Chez sources are
byte-identical. The archive includes exact patches and proof records.

Strict inputs are runtime imports constructed before timing. Pnpoly imports
every vector value; primes/triangl import every expected list element. The
timer includes the original repetitions, opacity calls and final full result
predicate. Scalar host assertions are also timed. Raw and optimized Wasm and
both Chez programs pass 48 preparation probes; 12 negative list probes return
checked flag zero and fail the host assertion. Empty-primes and all-zero
pnpoly probes pass, and independent review also rejects swapped prime order.
The first rejected Chez helper build is archived with its diagnostic; it is
preparation evidence, not a timing sample.

Static inspection of the exact optimized Wasm retains primes' allocation and
remainder recursion, both nqueens search branches and append allocation,
triangl's board updates/restoration and move search, mbrot's matrix allocation,
pixel loops and F64 escape recurrence, and both pnpoly vector-to-list-to-vector
copies plus all 12 point tests. Named loops use recursive/native tail calls.
[The retention audit](retention-audit.json) identifies functions and disassembly
lines. This is binary retention evidence, not dynamic instruction counts or a
separate V8 machine-code/tier audit. Imports, helper representations, static type
knowledge and host wrappers still differ; these ratios do not isolate one engine
or collector mechanism.

Cumulative coverage is now **18 passing measured ports/slices**, including
cat/wc, with Ackermann's prior default-stack failure and **38 unported** out of
57. [Coverage](coverage.json) preserves that partition. The
[43-workload capability inventory](../../strict-suite/capabilities.md) is the
historical cut after array1; its five selected cases are measured here. Existing
frozen reports remain unchanged.

Restore and verify the archive from the repository root:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-next-five-replay \
  --report benchmarks/results/2026-10-13-strict-numeric-next-five
```

To repeat timing, use the recorded tools and driver checkout `39d68ff`, then:

```sh
python3 benchmarks/strict-suite/measure.py measure \
  --output /tmp/strict-next-five-replay/strict-next-five-interim-320987e \
  --cpu 5 --rounds 3
```

That command overwrites only the restored `results.json`. The immutable archive
keeps the original observations. [Replay verification](replay-check.json)
records hash-checked restoration and result checks on every restored raw/
optimized Wasm and original/adapted Chez payload.
