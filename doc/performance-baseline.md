# Understanding the first backend's cost

This is the historical baseline before the 32-bit fixed-layout runtime.
The [runtime comparison](runtime-v3.md) records the new implementation and
matching-target measurements; the instruction safepoints below are historical.

The first backend compiles VM control flow to native code, but executes Scheme
operations through a dynamically checked Rust runtime. Inlining the LLVM
instruction handlers does not make the Rust implementations visible to LLVM.
This distinction explains why successful native code generation alone does not
put this baseline close to Chez Scheme.

## What LLVM can optimize

`runner/build.rs` runs `always-inline,default<O2>,verify` on the Scheme module,
then uses `llc` to produce a machine object. Cargo links that object with the
separately compiled Rust runtime. LLVM can simplify the generated control flow
and instruction wrappers, but cannot inline runtime bodies into that module.
Rust likewise compiles those bodies without the generated caller's constant
slot index, slot kind, or primitive identity.

Inspection of the optimized CPU benchmark confirms that no `snail_vm_*`
definitions remain: handler inlining succeeds. However, `snail_program` contains
no LLVM arithmetic instructions. Even Fibonacci's comparison, subtraction, and
addition go through ordinary Scheme invocation and runtime primitive dispatch.
A local reference retains three external calls: `snail_rt_enter`,
`snail_rt_slot`, and `snail_rt_result`, plus checked branches and a word copy.

## Counted Fibonacci paths

These are counts reconstructed from generated instructions, not sampled timing
or measured allocation counts. The [path breakdown](../benchmarks/results/2026-10-09-fib-paths.json)
records labels, instruction kinds, and source identities. It describes only `fibonacci` in
[`cpu.scm`](../benchmarks/cpu.scm), excluding surrounding checks and checksum work.

| Per invocation | Recursive case | Base case |
|---|---:|---:|
| VM instructions | 29 | 9 |
| External Rust service calls | 80 | 24 |
| Instruction-entry safepoint checks | 29 | 9 |
| Numeric operations | 4 | 1 |

The recursive path has twelve references/constants, ten pushes, six calls, and
one conditional test. References and pushes each invoke three Rust services;
calls and tests invoke two. The arithmetic remains fully dynamic even when the
source visibly applies a primitive to two integers.

For inputs 22, 23, 24, and 25, the recursive tree has 271,439 non-base invocations
and 271,443 base invocations. One workload repetition therefore makes
`80 × 271439 + 24 × 271443 = 28,229,752` external service calls and
`29 × 271439 + 9 × 271443 = 10,314,718` safepoint checks.

The emitted CPU LLVM used for this inspection has SHA-256
`49f995515e2b290f2ec10201a651e2aa26bbf8483b91e24192d90f7757cf9658`.
Fibonacci starts at `b745`; its recursive branch runs through `b738` to `b717`.
Labels are evidence for this artifact, not a stable compiler interface.

## CPU profile

A Linux `perf` profile sampled the native release implementation with direct locals,
borrowed string reads, and single-result buffer reuse. The 64-repetition run
returned checksum `269118144`. Its 8,081 user CPU-clock samples had no reported
loss. The [raw profile report](../benchmarks/results/2026-10-09-cpu-profile.txt)
records exclusive samples, including:

| Function | Samples |
|---|---:|
| `Vm::dispatch` | 17.13% |
| libc `free` | 12.91% |
| libc `malloc` | 8.98% |
| `snail_rt_call` | 6.39% |
| `Vec::from_iter` | 5.36% |
| `BuildHasher::hash_one` | 5.16% |
| Generated `snail_program` | 3.46% |
| `snail_rt_enter` | 3.40% |

These percentages locate execution; they do not predict independent speedups.
The profile includes process initialization and untimed correctness checks;
the long repeated workload dominates it. Benchmark ratios use the programs'
internal timers instead and exclude compilation and startup.

Reproduce profiling after building a release CPU executable:

```sh
perf record -e cpu-clock:u -F 997 -o build/cpu.perf -- build/benchmarks/native/cpu 64
perf report --stdio --no-children --percent-limit 1 -i build/cpu.perf
```

The profiled executable has SHA-256
`f1560e00a8f1dc27095c825dbd6da95fa826c98317cfcafc69dd78a46189f741`.
Compiler/runtime source identities and individual-change measurements accompany
the [benchmark results](../benchmarks/README.md).

The compiled compiler exercises a different allocation-heavy workload. Compiling
Fibonacci with its standard-library imports took 215 seconds on the finalized
runtime, including 125 seconds in GC and 423 million managed allocations. Its
LLVM matched Chibi's output byte for byte. This capability check is a single
observation, not a controlled compiler-throughput comparison; the Fibonacci CPU
profile should not be generalized to all compiler work.

## Hosted compilation latency

The normal CLI uses Chibi to run the compiler. At the measured revision, a timed invocation of
`./snail-scheme examples/fibonacci.scm --timing --runtime-stats` reported
(the timing flag has since been replaced by [Chromium traces](tracing.md)):

| Reported phase | Seconds |
|---|---:|
| Entry-file parse | 0.511 |
| Expansion, including imported-library reading/parsing | 18.687 |
| Lowering | 0.003 |
| LLVM text emission | 0.110 |
| Cargo build and program execution | 1.598 |
| Program runtime, included in the previous row | 0.779 |

An independent Chibi run wrapped the library loader with timers around file
reading, parser construction, and parser execution. Parsing the 16,801-byte
`bootstrap/scheme/base.sld` took 14.696 seconds; `write.sld` and `time.sld` took
0.099 and 0.101 seconds. Actual expansion after subtracting library loading and
parsing took just 0.025 seconds. These separate observations vary in duration,
but both locate the delay before lowering or machine-code generation.

The `expand` timer currently includes `library-loader` calls to `read-source`.
Libraries are cached within one expansion; every new compilation parses them
again. The immediate bottleneck is therefore parsing imported source, not
repeated macro expansion. `expand-head` already applies head transformers until
none remains before processing the resulting core expression.

`s-expr` constructs its alternative parser graphs inside a runtime binder for
each datum, including the numeric grammar through `s-atom`. Construction and
allocation are candidates for profiling, not a quantified explanation yet.
The landed parser and expander are unchanged by this backend cleanup.

Run mode uses a debug Rust runtime unless `--release` is supplied; that affects
execution speed but does not remove the hosted parsing cost. Each invocation
also creates a fresh Cargo target directory. In this run the entire build and
launch overhead outside program runtime was about 0.82 seconds. To run a program
repeatedly without compiling it each time, build it once with `-o` and invoke
the resulting executable.

## Scope of the baseline cleanup

Ordinary locals now hold direct tagged values. First capture promotes a binding
to a shared cell, preserving mutation and escaping closures. This removes
unnecessary managed allocations without requiring inference. Activation and
argument storage still use Rust vectors; this is not yet a single reusable
contiguous value stack.

Read-only string operations borrow UTF-8 text. Substrings own only their selected
slice. Rust's `string-contains` remains in use; the Chez adapter's search is
written in Scheme, so the IO ratio includes that algorithm difference.

Single-value primitive outcomes carry a value directly, and the VM reuses its
result vector when publishing them. Multiple values retain their explicit vector
path. Separate saved binaries measure each runtime change with the same inputs
and alternating execution order. These runtime changes leave the emitted LLVM
identical.

## Next optimization milestone

Keep the emitter simple for this baseline. Inferred types and function
specialization must eventually expose useful operations directly to LLVM:
typed arithmetic, known calls, and local value flow. Merely attaching type
information while retaining the current opaque service calls would leave much
of this cost in place. Dynamic operations still need a checked fallback.

This evidence identifies substantial dispatch, allocation, and visibility costs.
It does not establish a guaranteed speedup or a promised ratio against Chez.
Use the retained baseline and individual-change measurements to assess later
specialization; keep the correctness tests independent of optimization choices.
