# Backend baseline

Snail-Scheme lowers expanded HIR to Dybvig-style stack instructions, specializes
that instruction stream into textual LLVM IR, and links the resulting object
with a Rust runtime through Cargo. Native and `wasm32-wasip1` use the same
execution model. The existing Scheme host still runs the compiler.

This milestone establishes working programs and a compiler that can be compiled.
Switching the build to that compiler, type inference, and performance
specialization are subsequent milestones. There is no JIT or compile-time VM.
`syntax-rules` uses the existing pattern machinery; `syntax-case` is deferred.

## Build and run

The Scheme tools and formatter come from `nix-shell`. Also provide Cargo/rustc,
LLVM `llc` and `opt`, and Node with WASI support. Install Rust's WASI target with
`rustup target add wasm32-wasip1`. Initial validation used Rust 1.95.0 (LLVM
22.1.2), LLVM tools 22.1.8, and Node 24.15.0 on x86-64 Linux.

```sh
mkdir -p build
nix-shell --run './snail-scheme examples/fibonacci.scm --release --timing --runtime-stats'
nix-shell --run './snail-scheme examples/fibonacci.scm -o build/fibonacci'
nix-shell --run './snail-scheme examples/fibonacci.scm --target wasm32-wasip1'
nix-shell --run './snail-scheme examples/fibonacci.scm --target wasm32-wasip1 -o build/fibonacci.wasm'
nix-shell --run './snail-scheme examples/fibonacci.scm --emit-llvm -o build/fibonacci.ll --dump-vm build/fibonacci.vm'
```

The example prints `fib(25) = 75025`, elapsed monotonic-clock jiffies, and
`1000000000` jiffies per second. Nanosecond units do not imply nanosecond hardware
resolution. Compare repeated release runs on a stable machine; the executable
includes the full unspecialized bootstrap library.

The command follows [Resin's](https://github.com/tsnl/resin) invocation shape:
an input runs, `-o` builds without running, and flags select other modes.
The Bash launcher starts the Rust driver; the driver invokes the hosted Scheme
compiler and then `cargo run` or `cargo build` in an isolated generated project.
Run mode defaults to debug; `--release` selects release, and output builds
always use release. Arguments after `--` are passed literally to the program.
`--emit-llvm` writes LLVM to stdout or `-o`, without building the target program.
`--keep-build` retains the generated Cargo project and prints its path on stderr.
Normal success and failure remove the invocation's temporary files. Requested
artifacts are staged before publication, so a compiler failure does not replace
an existing executable, LLVM output, or VM dump.
The VM dump is published after Scheme compilation succeeds, independently of
whether the subsequent Cargo build succeeds. An existing executable survives
Cargo failure as well. A retained project's LLVM can be rebuilt by setting
`SNAIL_LLVM_IR` to its absolute `program.ll` path when invoking Cargo.

`snail-compile INPUT OUTPUT [VM-DUMP] [--timing]` remains the lower-level emitter.
For direct workspace builds, set `SNAIL_LLVM_IR` to an absolute path or a path
relative to the repository root and use `cargo run -p snail-runner`. `CHIBI`,
`LLVM_LLC`, `LLVM_OPT`, and `NODE` select tool executables. The frontend's old
parser inspection entry remains at `src/snail-scheme/main.scm`.

```sh
nix-shell --run 'make test && make check'
cargo test --offline
cargo fmt --all -- --check
nix-shell --run 'scripts/test-backend'
nix-shell --run 'scripts/test-cli'
```

The integration suite verifies LLVM and runs bootstrap and VM semantics on
both targets with collection at every handler boundary. It also checks arity,
uninitialized-binding, single-value-context, and overflow errors. Use
`scripts/test-backend --target native` for a native-only iteration. Normal-mode
GC scheduling and reclamation have separate Rust tests: stress mode alone cannot
validate the automatic collection threshold.

## Compilation stages

```text
source -> located syntax -> expanded HIR -> stack VM -> LLVM text
                                                        |
                                                  llc target object
                                                        |
                                              Cargo + Rust runtime
```

The new modules have explicit boundaries:

| Module | Responsibility |
| --- | --- |
| `compiler.sld` | Source/library loading and stage orchestration |
| `bootstrap.sld`, `bootstrap/scheme/` | Primitive inventory, derived syntax, Scheme library procedures |
| `lower.sld` | Library initialization order, storage, captures, tail positions, literals |
| `vm.sld` | Target-independent instructions, constants, metadata, readable dump |
| `llvm.sld` | Inline LLVM instruction bodies, static branches, and dynamic destinations |
| `runtime/src/vm.rs` | Activations, continuations, calls, multiple values, roots |
| `runtime/src/object.rs` | Tagged words, concrete trait objects, allocation, tracing, and collection |
| `runtime/src/primitives.rs`, `host.rs` | Primitive operations and host services |
| `runner/` | Target assembly and final Rust application entry point |
| `driver/` | CLI modes, generated Cargo project, subprocesses, and artifact publication |

The only expander integration change is an optional initial library cache and
`make-core-library`. Existing callers retain their builtin `(scheme base)`.
The compiler supplies `(snail-scheme core)` and loads the new bootstrap libraries
normally. Imported aliases retain HIR definition identity.

## Stack machine

Kent Dybvig's [*Three Implementation Models for Scheme*](three-imp.pdf) supplies
the starting model. The checked-in PDF is the highlighted copy recovered
byte-for-byte from `v3`. VM instructions here are a compilation representation,
distinct from LLVM bitcode; a bytecode interpreter is not needed for this stage.

Lowering assigns one global slot per defining binding and initializes each
library once, after its dependencies. All local parameters and definitions get
heap cells at activation entry. Closures capture cells rather than their current
values, preserving mutation, recursion, and lifetime across tail calls. Globals
use their indexed slots directly, including through imported aliases.

Local collection stops at nested lambdas. Capture analysis enters them: a
grandchild's free binding must be available when its parent constructs it.
Every lambda's definitions are in scope before visiting their initializers.
Reading an uninitialized cell or global is a runtime error.

Arguments evaluate left-to-right, followed by the operator. Pending arguments
remain on the operand stack while nested calls run. A normal call saves the
caller activation, operand extent, and return label. A tail call replaces the
activation while retaining its continuation. Rust handlers never recursively
enter Scheme, so proper tail recursion does not depend on Wasm tail-call support.

The result register contains a sequence, including zero or multiple values.
Arguments, tests, assignments, and operators require one value. Returns forward
the sequence unchanged; nonfinal body expressions discard it when the following
expression replaces it. `apply` and `call-with-values` use the same explicit
invocation loop, including rooted consumer continuations.

Each VM instruction becomes an LLVM basic block. Known successors branch
directly. Calls and returns obtain a label from Rust and enter a dispatcher whose
cases contain procedure entries and non-tail return addresses. The stop sentinel
is `4294967295`; unexpected destinations become errors. LLVM performs native
lowering or WebAssembly control-flow structuring.

## ABI and collection

Generated code passes an opaque VM pointer, fixed-width `i32` operands, and
transient pointers to tagged-word slots. No Rust container layout or trait object
crosses this ABI. LLVM copies a `Value` as one target-sized word using `ptr` on
the supported integral-pointer targets. The copied word is never dereferenced
as an object. It only moves between slots or compares against singleton tags.

`Value` is a `usize`: odd values are signed fixnums, characters and singletons
use other tags, and aligned addresses name nonmoving heap allocations. The
immediate integer range is `[-2^62, 2^62-1]` on 64-bit targets and
`[-2^30, 2^30-1]` on 32-bit targets. Larger `i64` integers and all `f64` values
are boxed. Heap ownership is checked through an address-keyed map rather than
by reconstructing a Rust reference from the tagged word. A collected unrooted
word is invalid; address reuse means it is not a durable identity handle.

| Handler family | Effect |
| --- | --- |
| `constant`, `refer_local/free/global` | Replace results with a stored value |
| `set_local/free/global` | Store a single result |
| `capture_local/free`, `close` | Capture raw cells and construct a closure |
| `push`, `call`, `return`, `test` | Evaluate calls and transfer control |
| `const_atom/pair/vector`, `global_primitive` | Initialize constants and native procedures |
| `halt`, `invalid_pc` | End execution or report an invalid destination |

The instruction bodies above are emitted as internal `snail_vm_*` functions
with `alwaysinline`. Rust supplies checked `snail_rt_*` slot and frame services,
defined in `runtime/src/lib.rs`. Reference, assignment, capture, push, and test
instructions perform their loads, stores, and tag tests in LLVM. Variable-sized
closure and call-frame work stays in Rust. Load a source slot before calling a
service that may clear or grow its storage; publish the word before the next
instruction's safepoint.

The generated module exports `snail_program`, `snail_global_count`,
`snail_constant_count`, and `snail_program_abi`. The runner checks the last
against `PROGRAM_ABI` before initialization. This version covers slot services
and tagged singleton encodings; stale generated code fails before executing.
Compound constants refer to earlier constant-pool entries, so construction
preserves roots without temporary object layouts in LLVM.

The collector is precise, nonmoving mark-and-sweep. Objects remain in stable
boxes; an iterative worklist follows managed references through
`SnailSchemeObject::mark`. Each allocation owns a real
`Box<dyn SnailSchemeObject>`: pairs, vectors, cells, closures, records, text,
numbers, and ports are concrete Rust types. An aligned header keeps the trait
metadata and mark bit outside the tagged word. The small internal `object!`
macro supplies tracing implementations. A public derive macro and safe native
extension API remain future work; see [Rust interop](rust-interop.md).

Collection follows three rules:

1. An instruction may collect at entry, before removing VM roots.
2. Allocation and all subsequent helper work within that handler are GC-free.
3. Surviving values are published into VM roots before the handler returns.

Slot and frame services must not reenter an automatic safepoint after taking
values out of roots. Internal helpers and ordinary invocation do not collect.
The explicit `collect-garbage` dispatch action is an audited exception: it first
consumes its inputs and publishes its result, then collects with complete roots.
Roots
include globals, constants, results, operands, current and saved activations,
multiple-value consumers, and current ports. Large atomic operations can briefly
exceed the collection budget; this is the baseline's simplicity tradeoff.
Dropping unreachable objects also releases their owned Rust resources.

Scheme errors stop the VM and subsequent handlers do nothing. No Rust unwind
may cross generated code. Debug builds contain unexpected Rust panics at handler
boundaries; release builds use abort-on-panic. This policy is separate from
future Scheme exception support.

There are no speculative `noalias` promises on slot pointers. Locals, captured
cells, and VM storage can alias through legitimate Scheme programs. Any future
annotation must prove its contract, including accesses made by the collector.

## Native and WASI hosts

Cargo owns the final application, Rust dependencies, and target support
libraries. `runner/build.rs` asks the same `rustc` for the target's LLVM triple
and data layout using a tiny `no_std` probe, then prepends that metadata to the
Scheme-emitted module. `opt` runs `always-inline`, O2, and verification; the build
checks that every `snail_vm_*` function disappeared before `llc` emits the object.
Rust links it into the executable. There is no handwritten LLVM runtime, Rust
bitcode linking, or cross-language LTO requirement. Compatible LLVM tools still
matter: the supported toolchain above was tested together.
For WASI, `verify_reducible` checks LLVM's cycle report after optimization: every
cycle must have one entry. The emitter's ordinary edges are acyclic; calls and
returns go through the shared dispatcher. The build then omits LLVM 22's
irreducible-control-flow repair pass. Its
[all-pairs reachability analysis](https://github.com/llvm/llvm-project/blob/llvmorg-22.1.8/llvm/lib/Target/WebAssembly/WebAssemblyFixIrreducibleControlFlow.cpp)
consumed over 24 GB on the compiler-sized dispatch loop despite having no
irreducibility to repair. With the check and omission, the tested WASI compiler
built in about 39 seconds. This policy is for this compiler's generated control
flow; it is not a general-purpose LLVM assembler setting. A regression fixture
with a two-entry VM loop confirms that the build rejects an irreducible module.
The WASI module contains generated code and Rust in
one linear memory, using this collector rather than Wasm GC.

The initial host uses Rust `std` for files, arguments, ports, and `Instant`.
Host operations are separated into `host.rs`; a complete `no_std + alloc`
embedding remains future work. WASI itself does not require `no_std`.
`scripts/run-wasi.mjs` exposes the working directory and forwards arguments and
environment variables. Other embeddings must supply WASIp1 imports or implement
an alternative host adapter. Browser and WASIp2 component packaging are not yet
provided. No Emscripten services are used.

## Compiling the compiler

Run these commands through the existing Scheme host:

```sh
nix-shell --run './snail-compile src/snail-scheme/compile.scm build/compiler.ll'
SNAIL_LLVM_IR=build/compiler.ll cargo build --release -p snail-runner
cp target/release/snail-runner build/snail-compiler
SNAIL_LLVM_IR=build/compiler.ll cargo build --release -p snail-runner --target wasm32-wasip1
cp target/wasm32-wasip1/release/snail-runner.wasm build/snail-compiler.wasm
```

The resulting compiler accepts `ROOT INPUT OUTPUT [VM-DUMP] [--timing]` after its executable
name. It can emit LLVM text; LLVM/Cargo still perform final code generation.
The normal build deliberately continues to use `snail-compile` and Chibi.
A subsequent self-hosting milestone should compare artifacts from consecutive
compiler generations before changing that default.

Capability validation compiled the current entry point for both native and WASI.
Both executables compiled a small core-library program to LLVM byte-identical
to Chibi's output. The native compiler also compiled Fibonacci with standard
library imports; its identical output ran on both targets. Import-heavy
compilation is still slow: that native compiler run took about 490 seconds,
including 323 seconds in GC. These are single-host observations of the baseline,
not benchmark promises. The normal build continues to use Chibi.

## Measurements

`--timing` reports parse, expand, lower, LLVM emission, and optional VM dump
durations in microseconds on stderr. Imported libraries are read during the
expand phase. The driver labels Cargo time as `cargo-build` or
`cargo-build-and-run`; the latter includes execution. `--runtime-stats` adds
total runtime duration, collection count, cumulative and maximum collection
nanoseconds, allocated/reclaimed/live/peak object counts, and maximum saved
frames. It is available in run mode; built executables accept
`SNAIL_RUNTIME_STATS=1` in their environment.

`(snail-scheme runtime)` exposes `collect-garbage`, `gc-statistics`, and bulk
`string-contains`. The statistics vector is
`#(collections total-ns max-ns allocated reclaimed live peak-live)`.
Collection time includes gathering roots and cleaning the weak symbol table.
Counts describe objects, not a byte quota. A statistics snapshot precedes the
allocation of its returned vector. Maximum time is cumulative, not an interval
maximum obtained by subtracting two snapshots.

The [four benchmarks](../benchmarks/README.md) measure fixed CPU, memory, file IO,
and GC workloads and verify independent answers. They print exactly three lines
and preserve separate native and WASI artifacts. Use several samples on an idle
machine; the IO comparison deliberately includes warm-cache host work that
Scheme type inference cannot remove. The runner records executable hashes and
measurement context, avoiding claims that an old artifact came from the current
checkout.

## Baseline limits and next steps

This is the compiler's bootstrap subset, not a complete R7RS implementation.
Exact integers are checked `i64`; bignums, rational and complex values are not
implemented. Nonintegral division yields `f64`. Unicode character case comparison
uses lowercase conversion rather than full Unicode case folding. Full
continuations, Scheme exception handling, and `dynamic-wind` are deferred.
Parameterization and file wrappers restore or close on normal returns, including
multiple values; they do not yet implement nonlocal-exit semantics.
Printing cyclic structures produces the diagnostic marker `#<cycle>`, not
readable graph notation.

Source locations survive in VM instruction metadata, but generated executables
do not yet produce Scheme source backtraces. All locals are boxed, the full
bootstrap library is retained, and dynamic calls share one dispatcher. These
choices establish a measurable baseline before representation and flow analysis.

The instruction functions are already inlined; Rust service calls remain
ordinary ABI calls. This deliberately exposes a simple baseline for later
representation analysis without making Rust's internal layouts compiler-owned.
After this baseline is measured, pursue the separately discussed type-inference,
occurrence-typing, and specialization work. Keep correctness tests independent
of whether a particular optimization fires.

The new backend follows the shared `simplify` skill: direct representations,
independent behavioral explanations, and small helpers. Exhaustive HIR/primitive
dispatch, ABI declarations, and atomic VM transitions may exceed its ten-line
target where splitting would hide the operation's contract. Refactoring is
confined to new modules; existing frontend code retains its structure.
The ten-line function target is guidance, not a reason to fragment coherent
operations. [Per Vognsen's Bitwise](https://github.com/pervognsen/bitwise) is an
inspiration for direct representations and code a reader can follow locally.

Independent explanation passes covered runtime ownership, LLVM slot lifetimes,
CLI modes, and the benchmarks. The first passes clarified rooted dispatch,
source-load ordering, artifact publication, retained benchmark data, and timing
boundaries. Fresh second passes converged after debating those invariants against
the implementation. Complete dispatch tables, command construction, and atomic
transitions remain together where splitting would scatter their guarantees.

Further references: [LLVM attributes](https://llvm.org/docs/LangRef.html#function-attributes),
[Rust inline attributes](https://doc.rust-lang.org/reference/attributes/codegen.html#the-inline-attribute),
[WASIp1](https://doc.rust-lang.org/rustc/platform-support/wasm32-wasip1.html), and
[cross-language LTO](https://doc.rust-lang.org/rustc/linker-plugin-lto.html).
