# Chapter 4 stack baseline

The ABI 3 backend uses one reusable Scheme stack and makes its ordinary
transitions explicit in Scheme-generated LLVM. This replaces ABI 2's argument
vectors, activation-local vectors, and promotion of every captured binding.
The [earlier report](runtime-v3.md) remains the measured ABI 2 baseline.

## Relationship to Dybvig and v3

Dybvig's [chapter 4](three-imp.pdf) supplies the model: accumulator, closure,
frame and stack registers; three-word return records; argument shifting for tail
calls; and stack-copying continuations. Section 4.5, printed pages 99 and 101,
boxes assigned bindings. It describes omitting boxes only when a binding cannot
be retained by either a closure or a continuation. Capture by a lambda alone is
not a sufficient test when full continuation snapshots are available.

The old [`v3` stack](https://github.com/tsnl/snail-scheme/blob/041877ac4e421cab432f198ae563ce8e55743a05/inc/ss-core/vthread.hh)
used preallocated vector storage. Its
[VM transitions](https://github.com/tsnl/snail-scheme/blob/041877ac4e421cab432f198ae563ce8e55743a05/src/ss-core/vm.cc)
pushed closure/frame/return words and moved arguments within that storage.
The current buffer serves the same purpose. It belongs to the Rust VM on its
executing thread; it is heap-backed storage, not recursion through Rust's native
call stack. The requested physical growth direction is high to low addresses.

There are deliberate coordinate and integration differences. Stack depths are
measured from the buffer's high end, and `f` names the end of the return header,
before the arguments. This keeps the existing left-to-right argument evaluation
order and lets a local's position be `f + index + 1`. The buffer grows on demand.
All frame metadata is tagged immediate data, allowing precise tracing to scan
every active word. LLVM basic blocks replace bytecode instruction fetching.

## Representation and transitions

For a frame with two arguments, depth increases down this diagram while the
physical address decreases:

```text
higher address
    ... caller locals and pending arguments ...
    saved closure                  depth f - 2
    tagged saved frame depth       depth f - 1
    tagged return label            depth f
    argument/local 0               depth f + 1
    argument/local 1               depth f + 2
    ... additional local slots ...
lower address                      depth s
```

`frame` writes the header; `argument` pushes an accumulator value. `apply`
sets the frame and closure registers, asks Rust to check the callable, and pads
local slots for a Scheme closure. `shift` uses an overlapping move to replace
locals with tail-call arguments. `return` loads the three saved words and drops
the frame. These are LLVM operations composed in `llvmlite`; none delegates an
ordinary call or return to a Rust activation dispatcher.

`snail_rt_state` exposes a documented `repr(C)` register record. Its pointer is
stable while generated code executes. The stack pointer is reloaded after
storage growth. The VM and its embedded state alias, so neither receives an
unjustified `noalias` annotation. ABI 3 rejects old generated modules.

Rust prepares closures and primitives, supplies managed allocation, and owns
host services. Native primitives borrow a slice of consumed arguments after an
in-place reversal into source order. A fixed-arity call allocates neither an
argument vector nor a local vector. Closure objects still own captured values;
rest lists, `apply` argument flattening, and continuation snapshots perform
work proportional to the data they construct.

The generated function has one dispatcher for dynamic destinations, including
internal apply/return transitions. Post-O2 cycle analysis checks reducibility
before WASI lowering. Directly connecting every shared control block produced
irreducible cycles; routing dynamic transitions through the dispatcher restored
the structured control-flow contract without enabling the expensive LLVM repair
pass for compiler-sized programs.

## Boxing and snapshots

An identity-based `set!` scan decides boxing before emission. Every assigned
lexical binding gets one shared cell when its activation begins. Reads of
immutable parameters, locals, and captures have no direct-versus-cell branch.
Tests assert that these pure cases contain no `box` or `indirect` instruction.

Recursive initialization is a separate exception: if a newly created closure
captures a local definition whose initializer has not completed, that binding
needs a shared location. A definitely-initialized scan tracks evaluation order
and intersects branch results. It boxes self/forward captures; earlier
initialized immutable definitions remain direct. This is initialization support,
not a cost imposed on every pure binding.

A continuation owns an immutable copy of the stack through its return header.
Its length supplies the saved frame boundary; the header supplies the caller
registers and return label. Invocation preserves its arguments as the pending
result packet, copies the snapshot into reusable storage, and runs `return`.
The snapshot remains unchanged for later invocations. Cells, globals, and heap
objects keep their identities and mutations.

The snapshot also saves the number of pushed return records for runtime
statistics. Following saved frame links cannot reconstruct that count: an outer
call's header is already on the stack while its operands run, but the active
frame register still names the caller. Restoration keeps the execution-wide
maximum and restores the captured current count before the ordinary return.

One result lives in `a`; zero results have no payload; multiple results use a
reusable VM vector. `call-with-values` retains its consumer below a normal
producer frame. It loads that consumer before overwriting the argument region
with returned values. These transfers do not collect or enter Scheme through
nested Rust calls.

`call/cc` is available on native and WASI. Scheme exceptions, `dynamic-wind`,
and nonlocal parameter/port cleanup are still outside the implemented subset.
Snapshots belong to one live VM; cross-VM or cross-thread invocation is not an
interop contract.

## Allocation and validation

The VM publishes live values before acquiring an allocation capability.
Allocating Rust primitives may construct arbitrary managed objects during their
burst, but cannot collect or resize the Scheme stack. Allocation alone never
collects. Stack growth and publication of an `apply` request are GC-free, even
though they may allocate ordinary Rust storage. No Rust stack tracing is needed.

Forty-five runtime tests pass on both native32 and WASI. New tests check register
layout, downward storage growth, exact active roots, capability boundaries,
mutable and immutable captures, rest/apply arguments, multiple-value receivers,
snapshot-only roots, reusable snapshots, pending-frame statistics, and mutation
after restoration.
A test-only allocation counter records zero host allocations/reallocations over
10,000 warmed fixed-arity closure preparations and 10,000 nonallocating `car`
invocations. This checks those services; it is not a whole-program allocation
profiler.

The integration suite runs real emitted code on both targets under GC stress.
It covers normal and escaping `call/cc`, multi-shot invocation after return,
zero/multiple continuation values, `apply` to a continuation, uncaptured assigned
locals, closures created after capture, pending arguments during stack growth,
and error paths. Scheme unit tests cover boxing decisions and immutable LLVM
GEP/cast/select construction. Chibi remains the compiler's build host.
A separate [shared LLVM/Rust LTO check](../benchmarks/results/2026-10-09-ch4-cell-lto.json)
executes local and captured assignment on both targets under GC stress, checking
the exact `i32` cell ABI. This validates linkage; it is not an LTO speed claim.

The focused simplify pass retained tagged frame words, a separate reusable
multiple-result buffer, and snapshots without redundant saved registers.
These choices keep root tracing and restoration direct. Atomic stack/control
transitions and exhaustive dispatch exceed the ten-line target where splitting
would hide their invariants; no generic frame or callback framework was added.

## Matched execution measurements

The [raw report](../benchmarks/results/2026-10-09-ch4-stack.json) compares frozen
`03d02cf` ABI 2 executables with this ABI 3 implementation. Both use ordinary
Cargo release and LLVM O2, without LTO, on matching 32-bit native and WASI
targets. CPU, memory, and GC use 16 repetitions; I/O uses four. One warmup per
participant precedes six rotated measured samples. All 180 measured answers
pass. The report retains source patches, source/artifact hashes, commands,
individual samples, and ranges.

Times below are median milliseconds per repetition. Speedups are old/new on
the same target. Both Chez ratios compare against native Chez 10.4.1, compiled
at safe optimization level 2; Chez and Chibi are 64-bit host builds.

| Workload | Native32 ms | Speedup | Native32 / Chez | WASI ms | Speedup | WASI / Chez |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| CPU | 24.049 | 4.48× | 52.5× | 35.310 | 2.80× | 77.0× |
| Memory | 38.602 | 2.76× | 72.7× | 42.340 | 2.23× | 80.2× |
| GC | 4.852 | 2.75× | 32.5× | 5.240 | 2.35× | 35.5× |
| I/O | 15.316 | 1.23× | 2.1× | 12.326 | 1.13× | 1.6× |

Relative to Chibi 0.12 on the same canonical Scheme bodies:

| Workload | Native32 / Chibi | WASI / Chibi |
| --- | ---: | ---: |
| CPU | 3.30× | 4.79× |
| Memory | 3.92× | 4.33× |
| I/O | 0.11× | 0.09× |

The GC workload performs 464 collections per sample instead of 864. Median
cumulative collection time falls from 30.12 to 19.68 ms natively and from 22.84
to 14.12 ms on WASI. This implementation removes per-call vectors and avoids
boxing immutable captures together; the measurement does not isolate each
change. The collector algorithm and its allocation-boundary policy stay the same.

Scheme/LLVM/Cargo compilation, startup, warmups, and printing are outside the
workload timers. V8 can still optimize Wasm during each fresh process; its tier-up
cost is not independently excluded. Chibi uses a millisecond wall clock.
I/O retains Rust substring search and the existing Scheme reference adapters,
so its ratios describe those complete implementations. Chibi is omitted from
GC because it lacks the required reclamation counter.

The stack change removes substantial overhead, but CPU and memory remain
roughly 53–80× native Chez and 3.3–4.8× Chibi on these workloads. The ten-times
Chez target is not achieved. These are baseline measurements for subsequent
specialization work, not evidence that a particular inference pass will close
the remaining gap.

A separate [native CPU profile](../benchmarks/results/2026-10-09-ch4-stack-profile.json)
records 5,976 samples with none lost: 38.00% self time in generated
`snail_program`, 27.06% in application preparation, 8.37% in its ABI boundary,
and 16.21% in allocating/nonallocating primitive dispatch. No allocator or free
symbol was sampled; this does not prove zero whole-program allocation.
The remaining cost is concentrated in generated control and generic call
handling. This profile does not justify attributing the entire gap to type
inference, nor does it isolate a profitable next optimization.

## Compiler-sized code generation

The direct stack implementation increases compiler-sized LLVM output. The final
capability build emitted 6.64 MB with 49,247 blocks; after O2 it was 48.04 MB with
118,351 blocks. Scheme-to-LLVM emission took 14.5 seconds, followed by 241.5
seconds for the native release build and 267.6 seconds for WASI. Other checks
overlapped part of validation, so these are capability-run observations rather
than isolated compile-time benchmarks.

An earlier [five-second sample of native `llc`](../benchmarks/results/2026-10-09-ch4-llc-profile.json)
found 56.2% of samples in live-range checks during register allocation. This
describes that sampled phase, not a whole-build breakdown.

Ordinary execution and compilation need separate measurements. Reducing
compiler-sized IR and register-allocation cost remains follow-up work. No
quadratic optimizer diagnosis is claimed from these counts.

### WASI compiler host limitation

The native compiled compiler emits byte-identical LLVM for its own source. The
same capability works on WASI under Node 24.15.0 with `--liftoff-only`, which
disables V8's optimizing WebAssembly tier. This is a capability check; Chibi
remains the build host.
The [final validation record](../benchmarks/results/2026-10-09-ch4-compiler.json)
includes both self-source checks (29.0 seconds native, 61.4 seconds WASI),
byte-identical Fibonacci emission, and execution of the generated native/WASI
Fibonacci programs. These individual durations are not throughput benchmarks.

Default Node execution of this compiler-sized module fails with a V8 `Zone`
out-of-memory error during optimization. Symbolized traces identify the
Turboshaft variable-snapshot merging machinery. Disabling loop unrolling moves
the failure into required Wasm lowering, so that individual flag does not fix
it. Keeping `frame` and `argument` out of line reduced the largest Wasm function
from 3.61 MB to 2.04 MB and shortened an experimental build, but still failed
under default Node. Neither emitter change nor a global optimizer override was
adopted.
The [diagnostic record](../benchmarks/results/2026-10-09-ch4-wasi-diagnostics.json)
preserves these commands, binary/IR hashes, failures, and the successful
baseline-tier control; those experiments preceded the final ABI/statistics fixes.

The native and WASI integration tests and small benchmarks use the ordinary
optimizing host unchanged. For the compiled compiler itself, the explicit
baseline-tier workaround is:

```sh
./snail-scheme src/snail-scheme/compile.scm --target wasm32-wasip1 -o build/compiler.wasm
node --liftoff-only --no-warnings scripts/run-wasi.mjs build/compiler.wasm \
  . src/snail-scheme/compile.scm build/compiler-self.ll
```

The flag is a V8 testing option, not a portable WASI requirement or a permanent
backend design. Compiler-sized code generation and host optimizer scalability
remain open work before switching the build to self-hosting.
