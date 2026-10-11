# Native lowering audit

This experiment asks what remains expensive after Snail's WasmGC datums become
LLVM. The baseline is `12c09c3`, with the Rust symbol interner and BDWGC's default
heap growth; no 4 GiB minimum is in use. These are execution measurements, not
compiler preparation or LLVM linking times. Chibi remains the supported compiler
host.

## What we give LLVM

The compiler is built with `clang -O3 -flto -fuse-ld=lld`; missing optimization
flags are not the explanation. Several expensive choices precede LLVM:

- Generic Scheme calls can allocate an argument vector, dispatch through a
  closure, check arity and values, and box the result. A typed direct C call
  passes arguments in registers or stack slots instead. A C implementation of
  our same generic ABI would also pay for that ABI.
- Native lowering represents every Wasm reference as an `i64` and performs GC
  operations through C helpers. The emitted operand records retain LLVM scalar
  types, not Wasm reference/nullability facts. LLVM must rediscover facts after
  that lowering, with less information about objects and allocation.
- Every array element occupies an eight-byte slot, even `i8` bytes and `i32`
  characters. This inflates allocation volume without requiring any Scheme type
  inference: the Wasm declaration already specifies the element width.
- Every allocation uses scanned `GC_malloc` and polls finalizers. Numeric arrays
  are also scanned; transient argument vectors use the same allocator as
  long-lived objects. These are runtime design choices, not requirements of
  LLVM or proper tail recursion.
- The portable pipeline runs Binaryen `-O3 --closed-world`, inlining threshold
  40, and convergence before V8. Native consumes the earlier datums directly.
  Equal input datums therefore do not imply equal optimization pipelines.

Entry-block local slots are not evidence of an interpreter: LLVM promotes those
slots. Replacing `tailcc` globally with `fastcc` is only a diagnostic, since proper
tail recursion across different signatures must be retained.

## A small, local construction error

Before this change, `array.new_fixed` called the generic array allocator with a
zero initial value, then performed separately checked stores at constant indices.
The allocator filled slots that would immediately be overwritten, and its loop
survived in the optimized compiler executable. BDWGC already supplies zeroed
memory. This is unnecessary work even under the existing representation and GC.

The preserved prototype allocates the known byte count and writes the header,
length and element fields directly, just as struct construction does. It retains
allocation, operand evaluation order, packed storage, GC roots, and all checks on
subsequent dynamic accesses. It does not introduce a new analysis pass.

## Measurement contract

Three exploratory rotating rounds follow one discarded fresh-process run per
case on logical CPU 2 of an Intel Core Ultra 7 270K Plus. Clang is 21.1.8, Node
24.19.0, Binaryen 132 and Chibi 0.12.0. No task-owned build, test or profiler runs
concurrently with the timing windows. Native compiler samples have substantial
variation; small differences are inconclusive.

The frozen compiler input and required output are held constant. Every compiler
sample must produce WAT with SHA256
`658af1403c7313bef3efde25c7383e8bcf68fec34d758c0fdbed6911a27bdb0a`.
Recursive Fibonacci uses 256 repetitions and checksum `1076472576`; three-argument
tail Fibonacci uses 1,048,576 repetitions and checksum `4409231671296`, after an
equally sized in-process warmup. Both include their complete Scheme driver and
boxed entry, not just the specialized arithmetic worker.

Internal timers exclude AOT preparation and process startup. Lazy JIT compilation
and tiering can occur inside them. PGO is trained on the measured workload itself,
so it is an in-sample diagnostic rather than a claim about generalization.
The no-single-value-check and no-GC cases are explicitly diagnostic and must not
be shipped. Compiler/no-GC is excluded because its uncollected allocation volume
is excessive. The fastcc substitution also has no proper-tail-call guarantee.

## Controlled lowering screen

Median seconds from [lowering-results.json](lowering-results.json):

| Variant | Compiler | Recursive Fibonacci | Tail Fibonacci |
| --- | ---: | ---: | ---: |
| Native baseline | 22.368 | 0.111446 | 0.303023 |
| Direct fixed-array construction | 19.649 | 0.114008 | 0.294192 |
| fastcc, diagnostic only | 20.118 | 0.111208 | 0.302415 |
| Natural load/store alignment | 19.651 | 0.109961 | 0.303554 |
| inbounds field addresses | 19.905 | 0.111256 | 0.304287 |
| Workload-trained PGO | 19.313 | 0.118837 | 0.240869 |
| Wasm / V8 | 3.720 | 0.173767 | 0.114701 |

Compiler baseline samples span 19.61–23.25 s. The apparent compiler gains for
several unrelated variants are not enough to rank them. Calling convention,
alignment and field-address changes leave the tail workload essentially unchanged;
fixed-array construction saves about 3%. PGO saves about 20% there but regresses
recursive Fibonacci. None closes the native/compiler gap.

## Earlier allocation and check screen

[allocation-screen.json](allocation-screen.json) is a separate three-round screen:

| Variant | Compiler | Tail Fibonacci |
| --- | ---: | ---: |
| Native baseline | 22.715 | 0.304528 |
| Poll finalizers only at the existing host safepoint | 18.303 | 0.263112 |
| Always inline the single-value helper, retaining checks | 18.510 | 0.272719 |
| Larger LLVM inlining budget | 18.108 | 0.268977 |
| Remove single-value checks, unsound diagnostic | 17.746 | 0.263297 |
| BDWGC inline small-object free list | 18.338 | 0.281087 |
| No per-allocation poll + inline helper + free list | 16.324 | 0.207396 |
| Disable GC, diagnostic | excluded | 0.435959 |
| Wasm / V8 | 3.712 | 0.114869 |

The combined prototype still takes 4.40 times V8's compiler time and 1.81 times
its tail time. Disabling collection actually slows the tail workload; it does
not remove the allocation and page-touching costs. No causal claim about cache
behavior is established by that result. These changes remain experimental.

## Confirmation and disposition

Eight fresh rounds confirm tail time improving from 0.304815 to 0.295166 s
(3.2%), but recursive time regressing from 0.111276 to 0.114020 s (2.5%). The
recursive worker has identical hot instructions at different addresses; the cause
of that timing regression is unresolved. These results do not justify presenting
the constructor cleanup as a general performance improvement.

The production backend is therefore unchanged. The candidate and its execution
regressions are preserved in [fixed-construction.patch](fixed-construction.patch).
With that patch applied, `make test`, `make check`, `scripts/test-native` and
`scripts/test-backend --target both` passed. Checks execute packed values, floats,
empty-array identity, allocating operand order, forced collection, Rust callbacks,
resource cleanup and proper tail calls. The initial f32 test used unsupported
`f32.const`; the final fixture uses the already-supported f64-to-f32 conversion.

## Default-heap native profile

A separate 199 Hz user-cycle profile of the checked baseline attributes **75.54%**
of samples to BDWGC, including **40.26%** in marking and **8.40%** in allocation.
The single-value helper accounts for **7.79%** and generic array creation **2.81%**.
This is the default automatic heap policy, unlike the earlier 4 GiB profile.
The profile's output matches the reference, and no samples were reported lost.
See [DSO totals](default-heap-dso.txt), [symbols](default-heap-dso-symbol.txt), and
[the command](default-heap-profile.json). Function names were resolved from parsed
Wasm declarations: `f.62` is `single`, `f.105` is `same`, and `f.307` is the
`eq?` primitive adapter. Regex counting named text lines is not a reliable way
to assign Wasm function indices.

## V8 GC diagnostic

A separate CPU2 run with `--prof --trace-gc-nvp` validates the same output.
V8 classifies 270 samples (**7.6%**) as GC; 461 trace events report a total of
**299.1 ms of pauses** across the process. Retained evidence includes the
[CPU profile](v8-profile.txt), [GC trace](v8-gc.txt), and
[command](v8-profile.json).

This strengthens the diagnosis that native memory management is expensive on this
workload. It is not an isolated collector speed ratio: native perf samples user
cycles inside the BDWGC library, including allocation, while V8's profiler reports
main-thread ticks and GC state. Pause totals exclude background work and are not
allocator CPU time. We have not measured the number of actual V8 object allocations.
V8 uses a [generational collector](https://v8.dev/blog/trash-talk), while our current
BDWGC configuration uses [conservative mark-sweep collection](https://hboehm.info/gc/gcdescr.html)
and supplies no pointer-layout descriptors. Short-lived argument vectors and
pointer-free data are therefore important separate experiments.

## Allocation diagnostics

A separately instrumented baseline executable counts calls and requested bytes;
its timings are not performance samples. Every diagnostic result passes the same
output validation. Counts cover the entire process, including the tail warmup.

| Workload | Allocations | Requested bytes | Array allocator calls | Collections |
| --- | ---: | ---: | ---: | ---: |
| Compiler | 556,599,605 | 16,341,522,904 | 378,944,575 | 2,222 |
| Recursive Fibonacci | 5,008 | 140,256 | 2,533 | 2 |
| Tail Fibonacci | 35,651,995 | 1,006,646,488 | 16,777,705 | 7,732 |

These are Snail native allocation requests, not live heap size, GC rounding, Rust
allocation, or a measurement of V8 allocations. The instrumented compiler ends
with a 97,660,928-byte BDWGC heap, demonstrating automatic expansion. See
[allocation-counts.json](allocation-counts.json) and its instrumented host source.
The recursive worker's internal calls already use specialized integer arguments;
its allocation count is tiny compared with the generic surrounding workload.

## Binaryen control

With the same frozen compiler datums and Rust runtime, removing Binaryen's
optimization passes increases V8 compiler time from 3.711 s to 5.200 s. Assembly,
linking and removal of the unused initialization export are retained. Every
output still matches the reference. Thus preprocessing matters, but cannot by
itself explain native's roughly 20–23 s result.

[Pipeline samples](pipeline-results.json) also record `--no-wasm-tier-up` controls.
Those flags have little effect here; that observation does not prove the engine
executes these GC functions in a particular tier or that V8 optimization is
unimportant. We have not collected a per-function tier trace.

## Small C comparison

The retained `counterpart.wat` and `counterpart.c` construct the same three-word
array layout through the same allocator. The assembly files show `clang -O3`
output **before LTO with the runtime**, not an extra performance measurement.
The new constructor is allocation followed by five stores, like the C version.
The old constructor uses generic allocation and element-address helpers. LTO can
inline access helpers; the separately retained full-compiler disassembly proves
that the generic fill loop still survives in the real optimized executable.

The C heap version also retains allocation: an opaque GC allocator is not made
free just by writing C. The C local-value version reduces to returning its second
argument. That is the optimization opportunity we should expose while objects
and escape behavior are still visible, rather than expecting LLVM to reconstruct
it from tagged integer references and arbitrary runtime calls.

## Next decisions

Preserve typed object operations long enough to simplify them before turning
them into opaque allocations and integer-address operations. First measure
argument-vector elimination and direct typed entries at the boxed call boundary;
then measure compact numeric-array layout and allocation policy separately.
Neither requires replacing the Scheme frontend or abandoning WasmGC datums.
Allocator attributes, unchecked access and LLVM alias metadata require actual
proofs; making stronger promises to LLVM without them is not an optimization.

## Reproduction and retained evidence

The compressed WAT and linked Wasm artifacts are frozen inputs. `artifacts.json`
records their compressed hashes and the native Rust archive's hash. Build records
retain complete commands and LLVM/source/binary hashes; the original absolute
paths identify the measurement environment. The common compiler input is exactly
[the earlier frozen source archive](../2026-10-10-compiler-simplification/after-source.tar.gz)
(all 62 archived files were compared byte for byte with the measured tree).

Use a worktree at `12c09c3` and that revision's Nix shell. Copy this report's
Python/Scheme experiment scripts to `build/ablation/`, decompress the seven input
artifacts there, and extract the common compiler source to a separate directory.
Set the `INPUT` constant in `experiment.py` to the extracted source directory;
`ROOT` is inferred from the script's `build/ablation/` location. The runners are
archival experiment scripts, not production APIs. Build the native Rust archive
with the recorded `cargo rustc --release --crate-type=staticlib
--features=native-runtime` command and copy it to `build/ablation/runtime.a`.

Inside `nix-shell`, prepare all binaries before timing:

```sh
chibi-scheme -h512M -I src build/ablation/translate.scm \
  build/ablation/compiler build/ablation/fibonacci build/ablation/tail
python3 build/ablation/experiment.py prepare
python3 build/ablation/prepare-lowering.py
python3 build/ablation/prepare-pgo.py
```

The PGO script's `llvm-profdata` path must name the same LLVM major version as
Clang. Preserve the recorded toolchain for direct reproduction. PGO training is
not part of timings. Run the screens serially, with no concurrent builds:

```sh
python3 build/ablation/experiment.py measure \
  --variants baseline,no-poll,inline-single,inline-budget,no-single,freelist,combined,no-gc,v8,v8-no-inline,v8-no-opt
python3 build/ablation/experiment.py measure \
  --variants baseline,fixed,fastcc,align,inbounds,pgo,v8 \
  --workloads fibonacci,tail,compiler --output build/ablation/lowering-results.json
python3 build/ablation/experiment.py measure --workloads compiler \
  --variants v8,v8-no-binaryen,v8-no-binaryen-liftoff,v8-liftoff \
  --output build/ablation/pipeline-results.json
python3 build/ablation/experiment.py measure --rounds 8 \
  --variants baseline,fixed,v8 --workloads fibonacci,tail \
  --output build/ablation/confirmation-results.json
```

CPU 2 is hardcoded; change it consistently to an allowed CPU on another machine.
All successful samples are retained, without outlier removal. Early screens keep
timers/checksums/stderr; later confirmation and pipeline samples also retain raw
stdout and complete execution commands. Exclusions are described above. The
failed full-Binaryen-to-native attempt produced recursive type groups unsupported
by this backend; the partial-pass translation was stopped, so neither has timing
results or is evidence of a supported native optimization pipeline.

`prepare-allocation-counts.py`, `prepare-counterpart.py` and `profile-v8.py` collect
diagnostics separately. Native profiling used the command retained in its JSON.
Do not treat instrumentation times as benchmark samples. The simplify skill's
independent explanation review favored direct construction without new rooting,
size, or visitor machinery; the parent verified its behavior. The benchmark
review distinguished timing boundaries, diagnostic weakening, and confirmation
from exploratory screening. The constructor is preserved as one coherent operation
rather than split solely to meet a line-count target.
