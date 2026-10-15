# Complete complex Mandelbrot preparation

The full `mbrotZ` workload passes in raw Wasm, optimized Wasm, original Chez and
adapted Chez: 1,000 repetitions of the original 75-by-75 matrix and result 5.
**This preparation archive contains no clean timing observations.** All 52 compiler/build
files match `7ff18c01f4fc5407826e4815b30394ed437b2440`; this port adds no compiler
capability. The source checkpoint and exact preparation identity are recorded
in [compiler-identity.json](compiler-identity.json).

The original complex escape loop remains visible. It computes radius squared,
scales the rectangular pixel coordinate, adds the complex origin, tests the
64-step cap before magnitude, then either returns or computes complex square
plus origin. Complex multiplication retains four scalar products, subtraction
and addition. Magnitude squares are not manually reused by the source adapter,
and the real-valued `mbrot` kernel is not substituted.

`mbrotz_port.py` gives each complex value an immutable nominal product with two
F64 components. Complex addition, multiplication, real scaling, rectangular
construction and component extraction become explicit operations. Integer
coordinates use explicit I64-to-F64 conversion. The arithmetic follows the
pinned Chez generic complex product/scalar paths and inexact rectangular
construction. The latter keeps both inexact components, including signed zero.
[Chez arithmetic](https://github.com/cisco/ChezScheme/blob/v10.4.1/s/5_3.ss#L2714),
[Chez rectangular construction](https://github.com/cisco/ChezScheme/blob/v10.4.1/s/cpprim.ss#L5038).

The complex literal `-1.0-0.5i` becomes one shared value initialized before
timing. A shared empty I64 row supplies the outer vector's typed fill; the
original descending initialization replaces every slot before any use. Inner
rows receive explicit zero fills. All descending x/y loops and stores remain.
The actual I64 size crosses a value-returning host identity import once per
invocation; it is not a detached Boolean barrier.

The unchanged original Chez program is preserved. The second Chez program uses
the exact adapted kernel and arithmetic-helper text, with two-element vectors
as complex values. Its harness and numeric predicate remain unchanged. The
complete-source restoration proof accounts for every kernel edit and helper.
Chez's native complex values, vectors and WasmGC structs have different physical
representations; matching arithmetic does not establish equal allocation costs.

The strict positive-count loop uses an unobservable I64 initializer. Zero and
negative repetitions trap, preserving the original numeric predicate's failure
on its initial false result. Empty and negative matrix sizes also fail. Error
messages and runtime exception classes are not promised to match. The port's
domain is the benchmark's inexact complex arithmetic and feasible Wasm vector
sizes, rather than Scheme's full numeric tower.

[Correctness evidence](correctness-summary.json) contains twelve canonical runs
at counts 1, 2 and 1,000. Separate probe modules run 24 cases across all four
systems: six complete grids and descending store sequences, ten exact
component-bit cases, and eight escape-radius/cap cases. The full 5,625-pixel
grid agrees with an independent scalar Python oracle. Signed zeros, subnormal
results, rounding and overflow are checked bit for bit. Seven further harness
cases across four systems cover small input, wrong expected values, invalid
sizes and nonpositive repetitions: 124 supplementary checks in total. The empty
grid probe returns the matrix directly; the original canonical `test(0)` still
fails when projecting its first element. Source and Wasm inspection establish
that the cap check precedes magnitude; the scalar result 64 alone cannot
distinguish those two checks' order.

The [retention audit](retention-audit.json) inspects the exact 2,143-byte
optimized canonical Wasm, whose only exports are `bench` and `main`.
`function36` feeds the identity import's returned size into the matrix routine
on every repetition. `function31` calls the escape loop and writes its result
into the indexed pixel. `function34` retains two F64 fields in each updated
complex object and tail-calls the escape loop.

Binaryen removes the temporary coordinate, scale and product objects when only
their fields are observed. The retained complex constructions are one initial
point per pixel and one updated value per escape step. The original source
contains additional intermediate objects; this report makes no equal-allocation
claim between the controls.

Separate count-1, count-2 and full-count observers recover every original
function exactly when erased. The full run completes 5,625,000 pixel stores,
75,000 row stores, 1,000 outer array constructions, 75,000 row array
constructions and 172,189,000 complex constructor instructions after subtracting
setup. Constructors and stores increment only after successful completion.
These are diagnostic instruction counts, not physical allocator events.

Default-tier V8 code from the unchanged canonical binary independently retains
a 32-byte bump-allocation path and both F64 stores in `function34`; the pixel
result store remains in `function31`. Those paths establish retained native
work, not an exact total of physical allocations. No diagnostic duration is
used as a clean performance observation.

`make test` and `make check` pass. All 25 earlier specifications and generated
strict sources are byte-identical. The fresh no-file behavioral explanation and
debate are recorded in [simplify-review.md](simplify-review.md), with the review
boundary distinguished from independent code or observer inspection.

Restore and verify the complete archive without executing workloads:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-mbrot-z-replay \
  --report benchmarks/results/2026-10-13-strict-mbrot-z
```

All 274 archived files were restored and hash-verified. The restored raw and
optimized Wasm and both Chez programs passed the count-2 canonical input; see
[replay-check.json](replay-check.json). Their diagnostic durations are not clean
performance observations.

Rebuild using the pinned tools:

```sh
python3 benchmarks/strict-suite/measure.py prepare --output build/strict-mbrot-z \
  --benchmarks mbrotZ --compiler-basis 7ff18c0
```
