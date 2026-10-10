# Fixed-layout Rust runtime

This report records the ABI 2 baseline at `03d02cf`. The later
[chapter-4 stack implementation](stack-vm.md) supersedes its per-call vectors
and capture-time boxing; the measurements below remain historical results.

The runtime ports the object model from `origin/v3` at
`041877ac4e421cab432f198ae563ce8e55743a05`, especially
`inc/ss-core/object.0.hh`, `object.1.hh`, and `src/ss-core/object.cc`.
It keeps builtin operations in Rust. Scheme still emits instruction handlers
through `llvmlite`; Chibi still hosts the compiler.

## Representation and boundaries

Values are actual 32-bit tagged pointers, with v3's fixnum, symbol, character,
boolean, null, EOF, and undefined encodings. Native programs target
`i686-unknown-linux-musl`; WASI targets `wasm32-wasip1`. The CLI driver stays
host-native. The generated-code ABI is version 2 and rejects old modules.

A single allocation contains a header and concrete builtin payload. Kind checks
lead directly to fields, without an ownership-map lookup or `Any` downcast.
Pairs retain car/cdr fields; cells retain one word; text retains count, byte
pointer, and ownership; vectors own their element storage. This is a port of the
field model, not a promise of C++ binary compatibility:

- The header replaces C++ virtual destruction and allocator metadata with kind
  and mark fields; static dispatch traces and destroys builtin payloads.
- Rust `Vec` replaces `std::vector`.
- The 64-bit immediate float32 encoding cannot fit; floats remain boxed `f64`.
- This VM needs additional kinds for closures, records, ports, primitive IDs,
  bytevectors, and exact integers outside the signed 31-bit immediate range.
- Symbols are immediate IDs whose names survive for the VM's lifetime.

Only foreign `Extension` objects use a vtable. Its C ABI callbacks report strong
Scheme edges and destroy the payload. The interface is unsafe; safe foreign
registration, persistent host roots, and reusable embedding remain future work.

An allocating callable owns `Allocation`; nonallocating callables receive
`Runtime` access. The VM collects before creating the capability, rooting the
procedure and arguments, and publishes its outcome before another boundary.
Internal construction cannot collect. A private `HeapAccess` key gates the
low-level allocator, collector, and heap construction without wrapping every
field accessor. No callable receives that key or VM execution control.

Closure construction, captured-local promotion, rest lists, and startup
constructors also use the capability. Arithmetic may box and therefore has an
allocating signature. Ordinary instruction entry and nonallocating primitives
never poll. The complete allocation-effect inventory is tested against dispatch.
A large Rust operation may exceed the soft GC budget; it cannot collect from an
untraced Rust stack to recover memory.

## Matched runtime comparison

The [raw report](../benchmarks/results/2026-10-09-runtime-v3.json) compares the
old runtime at `41b92a6` with the new runtime, using identical 32-bit targets.
All programs use Cargo release and LLVM O2, without LTO. CPU, memory, and GC use
16 repetitions per sample; I/O uses four. Each target/workload has one warmup
and six rotated samples of old Snail, new Snail, and native Chez 10.4.1 at safe
optimization level 2. All 144 measured answers pass. Compilation, process
startup, and warmups are excluded.

Times below are median milliseconds per repetition. Speedup is old/new on the
same target; Chez ratios are new Snail/native Chez.

| Workload | Native32 ms | Speedup | Native32 / Chez | WASI ms | Speedup | WASI / Chez |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| CPU | 145.572 | 2.05× | 322.1× | 111.225 | 1.77× | 245.3× |
| Memory | 131.499 | 2.49× | 256.6× | 101.201 | 2.21× | 197.0× |
| I/O | 19.285 | 1.37× | 2.67× | 14.143 | 1.39× | 1.94× |
| GC | 16.981 | 2.19× | 116.1× | 13.310 | 2.29× | 89.9× |

This bundles fixed layouts, allocation boundaries, immediate symbols, enum
primitive dispatch, and removal of temporary numeric argument vectors. It does
not isolate their individual contributions. The GC workload performs 864
collections per 16-repetition sample in both versions; median total collection
time falls from 113.83 to 30.02 ms natively and 110.61 to 22.34 ms on WASI.

Earlier native reports used x86-64 GNU/Linux, whereas this native target uses
32-bit musl. The matched 2.05× CPU gain is **not** a speedup over that older
64-bit executable: the new native32 CPU result is slower than the historical
64-bit baseline. Pointer width, target code generation, and system allocator
all changed. The matched old native32 build removes those factors from the
runtime comparison above. Chez remains a 64-bit reference.

A separate [native32 target diagnostic](../benchmarks/results/2026-10-09-runtime-v3-gnu32.json)
links the same runtime and CPU LLVM against GNU/glibc instead of musl. Three
alternating samples put GNU32 at 1415.77 ms versus musl32 at 2317.03 ms for
16 repetitions, a 1.64× difference. This compares complete target/linking
configurations, not an isolated allocator substitution. It shows that some
native cost belongs to the host runtime configuration; it does not close the
Chez gap. The portable static musl build remains the current native default.

## Comparison with Chibi

The [Chibi report](../benchmarks/results/2026-10-09-chibi.json) compares the same
canonical CPU, memory, and I/O bodies with Chibi 0.12, Chez 10.4.1, and the saved
ordinary/shared-LTO Snail executables. Every implementation gets one warmup and
four rotated measured samples. All 64 measured answers pass. Compilation,
parsing, process startup, and output are outside the timers.

These are median milliseconds for 16 CPU/memory repetitions or four I/O
repetitions. Ratios above one mean Snail takes longer than Chibi.

| Workload | Chez ms | Chibi ms | Native32 ms | Native32 / Chibi | WASI ms | WASI / Chibi |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| CPU | 7.269 | 117 | 2354.753 | 20.13× | 1787.566 | 15.28× |
| Memory | 8.318 | 153 | 2139.505 | 13.98× | 1622.084 | 10.60× |
| I/O | 29.049 | 551 | 78.603 | 0.143× | 56.467 | 0.102× |

Shared LTO puts CPU at 15.18× Chibi natively and 10.88× on WASI; memory at
10.71× and 7.77×. Chez is about 16–19× faster than Chibi on these workloads.
Chez's optimizer advantage therefore does not explain Snail's additional gap
to Chibi. Generic VM bookkeeping and host allocation need investigation before
attributing the remaining cost to missing type inference.

Chibi's clock is millisecond wall time; the other clocks are monotonic. Chibi
and Chez use native 64-bit builds, unlike Snail's 32-bit targets. I/O deliberately
compares each implementation's port/search services: Snail's 7–10× advantage
there is not a general Scheme execution result. GC is omitted because Chibi
does not provide the canonical check's reclamation counter. The Chibi search
adapter also passes multibyte, nonzero-start, absent, empty, and overlapping
match checks.

## What LLVM does now

The [inlining audit](../benchmarks/results/2026-10-09-runtime-v3-inlining.json)
inspects shared-LTO output for CPU on both targets. Pair access compiles to a
pointer-tag check, kind-byte check, and direct field load/store. `Heap::find`
and pair/predicate helpers disappear into their callers. Rust does expose these
operations to LLVM as intended; handwritten LLVM object primitives are not
needed to obtain this form of code.

The generic VM dispatcher and builtin dispatchers still remain. Shared LTO
removes instruction-entry/result/push service calls, but ordinary Scheme calls
still use runtime argument/frame handling. Direct object access does not by
itself turn an emitted Scheme arithmetic call into an LLVM arithmetic instruction.
The Chez gap remains large, and these changes do not establish a ten-times target.

The [LTO comparison](../benchmarks/results/2026-10-09-runtime-v3-lto.json) uses
four rotated samples per variant and target, after every build has finished.
These are median milliseconds for 16 repetitions, with compilation excluded:

| Target/workload | Ordinary release | Rust LTO | Shared LTO | Ordinary/shared |
| --- | ---: | ---: | ---: | ---: |
| Native32 CPU | 2328.90 | 2034.83 | 1774.45 | 1.31× |
| WASI CPU | 1786.98 | 1591.98 | 1271.13 | 1.41× |
| Native32 memory | 2144.53 | 1843.04 | 1640.45 | 1.31× |
| WASI memory | 1603.13 | 1459.44 | 1184.35 | 1.35× |

Shared LTO builds took roughly 9–12 seconds natively and 37–56 seconds for
WASI in this check. It remains an explicit experiment, not the CLI default.
The static builtin field accesses already inline within ordinary Rust release
compilation; shared LTO mainly exposes more Rust services to generated callers.

## Successful reads were allocating error strings

Profiling the saved native32 CPU executable exposed a concrete bug in the VM:
three slot lookups used `ok_or("error message".into())`. Rust evaluates that
argument before calling `ok_or`, so successful reads also constructed and
discarded an owned string. Both ordinary machine code and shared-LTO output
retain the allocation. The fix uses `ok_or_else` at those three sites, preserving
the errors while constructing their strings only when a lookup fails.

The [profile and assembly evidence](../benchmarks/results/2026-10-09-runtime-v3-profile.json)
records 4,585 CPU-clock samples, with one lost sample. Roughly half the samples
fall in allocator/free machinery. A second frame-pointer profile recovers some
Rust caller chains but cannot fully unwind the allocator; it does not establish
an exact time attribution for each allocation site. The profile includes process
setup and checks; the repeated timed workload dominates it.

Ordinary calls also allocate an argument vector through `split_off`; Scheme
closure entry allocates a locals vector. Machine-code inspection confirms both
allocations survive optimization. These are host allocations, invisible to the
Scheme heap's object/collection counters. Reusing Scheme stack storage for
arguments and locals is the next runtime investigation; it does not require
type inference or special arithmetic emission.

The [static path audit](../benchmarks/results/2026-10-09-runtime-v3-call-costs.json)
counts the following costs within the timed Fibonacci subtrees over 16
repetitions, excluding benchmark setup and checking code:

| Operation | Count |
| --- | ---: |
| Eager error-string constructions before the fix | 47,773,392 |
| Argument-vector allocations | 30,401,296 |
| Activation-local-vector allocations | 8,686,112 |
| Rust ABI service calls in the ordinary build | 451,676,032 |

These are counts reconstructed from emitted control flow, supported by assembly
inspection of the allocation sites, rather than dynamic allocator counters.
Shared LTO removes many service calls; its counts must not be inferred from the
ordinary-build row.

The comparison tables above preserve the executables measured before this
three-line fix. The separate ablation below isolates the fix rather than
replacing those historical samples.

The [lazy-error ablation](../benchmarks/results/2026-10-09-lazy-errors.json)
reuses identical LLVM and changes only those three lines. All eight executables
build before four alternating before/after samples, with fresh Chez and Chibi
references. Times are median milliseconds for the same repetitions as above:

| Workload | Native32 before | Native32 after | Speedup | WASI before | WASI after | Speedup |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| CPU | 2352.243 | 1717.524 | 1.37× | 1777.313 | 1585.727 | 1.12× |
| Memory | 2122.388 | 1672.183 | 1.27× | 1631.009 | 1494.556 | 1.09× |
| I/O | 77.203 | 74.873 | 1.03× | 57.079 | 55.561 | 1.03× |
| GC | 268.731 | 212.328 | 1.27× | 213.721 | 197.058 | 1.08× |

Corrected ordinary native32 remains 14.81× Chibi on CPU and 11.11× on memory;
WASI is 13.50× and 9.83×. Native32 CPU remains 233.53× Chez. The bug explains a
measurable part of the gap, not the whole gap. Argument/local allocation and
hundreds of millions of runtime service calls remain. Shared LTO has not been
remeasured with this final fix; its earlier table describes the saved pre-fix
executables.

## Verification and simplification

All 40 runtime tests execute on native32 and WASI. Backend integration runs both
targets under GC stress; CLI tests check execution, output publication, and stale
ABI rejection. Scheme tests and formatting checks pass. Separate compiler
checks reject attempts to mint the authority key, allocate or collect without
it, construct a capability, or replace the heap through `Default`.

Tests exercise a detached child held only in a Rust local during an allocation
burst, incoming call arguments, captures, rest lists, multiple values, cycles,
extension tracing/destruction, and complete builtin allocation classifications.
The [compiled-compiler check](../benchmarks/results/2026-10-09-runtime-v3-compiler.json)
also passes; it does not switch the build to self-hosting.

The simplify review kept field access direct and kept returned call operands as
explicit extra roots, avoiding a second pending-call state machine. Exhaustive
kind/builtin dispatch and atomic VM transitions remain together even when they
exceed the ten-line logic target. The landed frontend's structure is unchanged.
