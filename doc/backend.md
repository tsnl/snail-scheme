# Backend baseline

Snail-Scheme lowers expanded HIR to Dybvig-style stack instructions, specializes
that instruction stream into textual LLVM IR, and links the resulting object
with a Rust runtime through Cargo. 32-bit native and `wasm32-wasip1` use the same
execution model. The existing Scheme host still runs the compiler.

This milestone establishes working programs and a compiler that can be compiled.
Switching the build to that compiler, type inference, and performance
specialization are subsequent milestones. There is no JIT or compile-time VM.
`syntax-rules` uses the existing pattern machinery; `syntax-case` is deferred.

## Build and run

The Scheme tools and formatter come from `nix-shell`. Also provide Cargo/rustc,
LLVM `llc` and `opt`, and Node with WASI support. Install both Rust targets with
`rustup target add i686-unknown-linux-musl wasm32-wasip1`. Native programs are
static 32-bit Linux executables linked with Rust's `rust-lld`; the CLI driver
still runs on the host. The runtime deliberately rejects 64-bit builds.
Validation uses Rust 1.95.0 (LLVM 22.1.2), LLVM tools 22.1.8, and Node 24.15.0
on x86-64 Linux with support for executing i386 programs.

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
relative to the repository root and use `cargo run -p snail-runner --target i686-unknown-linux-musl`. `CHIBI`,
`LLVM_LLC`, `LLVM_OPT`, and `NODE` select tool executables. The frontend's old
parser inspection entry remains at `src/snail-scheme/main.scm`.

```sh
nix-shell --run 'make test && make check'
cargo test --offline --target i686-unknown-linux-musl
cargo fmt --all -- --check
nix-shell --run 'scripts/test-backend'
nix-shell --run 'scripts/test-cli'
```

Scheme unit tests live in their implementation modules' final `Tests` sections.
`make test` enables `snail-tests` and calls each module's single test entry point;
normal imports and compiled programs omit that code. Integration fixtures remain
in `tests/` and use public interfaces.

The integration suite verifies LLVM and runs bootstrap and VM semantics on
both targets with collection before every allocating operation. It also checks arity,
uninitialized-binding, single-value-context, and overflow errors. A direct
`llvmlite` fixture executes phi backedges, arithmetic, array access, and a switch
through the same native/WASI pipeline. Use
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
| `llvmlite.sld` | Immutable typed LLVM references/definitions, checks, and text serialization |
| `runtime/src/vm.rs` | Stack storage, application preparation, snapshots, multiple values, roots |
| `runtime/src/object.rs` | 32-bit tagged words, fixed object layouts, allocation, tracing, and collection |
| `runtime/src/primitives.rs`, `host.rs` | Primitive operations and host services |
| `runner/` | Target assembly and final Rust application entry point |
| `driver/` | CLI modes, generated Cargo project, subprocesses, and artifact publication |

The emitter constructs IR through the [immutable `llvmlite` API](llvmlite.md).
Branches reference block objects created before their bodies; phi backedges use
previously created value references. LLVM syntax is confined to this wrapper,
while VM semantics and the runtime ABI remain visible in `llvm.sld`.

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
library once, after its dependencies. Lexical bindings occupy stack slots.
An identity-based scan boxes every binding assigned by `set!`, including locals
that no lambda captures: a continuation must share the location rather than
restore an old value. Ordinary immutable parameters, locals, and captures stay
unboxed, with no runtime direct-versus-cell test. Recursive initialization is a
separate reason for indirection: a closure created before a local definition is
initialized captures its cell. Earlier initialized immutable definitions stay
direct. Globals use their indexed slots directly.

Local collection stops at nested lambdas. Capture analysis enters them: a
grandchild's free binding must be available when its parent constructs it.
Every lambda's definitions are in scope before visiting their initializers.
Reading an uninitialized local, cell, or global is a runtime error.

One reusable Rust-owned buffer holds the Scheme stack for each VM. It grows
from high addresses toward low addresses. `s` and `f` are depths measured from
its high end, so resizing preserves every saved offset. A return frame contains
three words: saved closure, tagged saved frame depth, and tagged return label.
Arguments evaluate left-to-right, followed by the operator. Pending arguments
and saved callers remain in the same buffer while nested calls run.

The Scheme-written LLVM handlers implement `frame`, `argument`, `shift`,
`apply`, and `return`. A normal call pushes a return frame; a tail call moves
arguments over the current locals and keeps that frame. Closure entry pads its
local slots in this same buffer. Rust checks callable kind and arity, constructs
rest lists when required, and borrows native arguments from the stack. There is
no per-call argument or local vector for ordinary fixed-arity calls. Rust never
recursively enters Scheme, so tail recursion does not depend on Wasm tail calls.

One value lives in register `a`; zero or multiple values use a count and a
reusable result buffer. Arguments, tests, assignments, and operators require one
value. Returns forward all values; nonfinal body expressions discard them.
`call-with-values` uses a normal frame with a reserved consumer return label.
`apply` rewrites arguments and rejoins the same application loop.

`call/cc` and `call-with-current-continuation` capture an immutable copy of the
active stack through the current return header. Invoking the snapshot preserves
its supplied values, restores a copy into the working stack, and executes the
ordinary return transition. Snapshots are reusable and own their storage. Shared
cells preserve assignment across restoration; heap objects and globals are not
rolled back. `dynamic-wind` and nonlocal parameter/port cleanup remain deferred.

Each VM instruction becomes an LLVM basic block. Known successors branch
directly; application and return share blocks within the same generated
function. The dispatcher contains procedure entries and return addresses.
Reserved labels are `4294967295` (stop), `4294967294` (consume produced values),
`4294967293` (apply), and `4294967292` (return);
ordinary labels fit a nonnegative 31-bit fixnum. LLVM performs native lowering
or WebAssembly control-flow structuring.

## ABI and collection

Generated code passes an opaque VM pointer, fixed-width `i32` operands, and
transient pointers to tagged-word slots. `snail_rt_state` exposes one stable
`repr(C)` register record; LLVM owns its documented fields, not Rust containers
or trait-object layouts. LLVM moves each `Value` as `i32`, including the tagged
cell argument passed to Rust. `ptr` names actual addresses such as register
fields and slots. Ordinary instructions dereference slots,
not object payloads. They move words and compare singleton tags.

`Value` is one 32-bit word. The tags come directly from `origin/v3`:
null is zero, fixnums have low bit 1, interned symbols have low bits 10, and
aligned nonzero addresses name boxed objects. Characters and singletons use
v3's halfword tags. Fixnums span `[-2^30, 2^30-1]`; larger `i64` integers and all
`f64` values are boxed. The old immediate float32 encoding needs 64 bits and is
not used. Symbol IDs and their names remain in the VM's intern table for its
lifetime. Copying a word does not retain its object; stale words are invalid.

Builtin field access checks the pointer tag and header kind, then reads the
concrete payload directly. There is no ownership-map lookup or `Any` downcast.
The private runtime API requires every heap word to belong to the live heap;
it does not accept arbitrary integers or offer durable host handles.

| Handler family | Effect |
| --- | --- |
| `constant`, `refer_local/free/global`, `indirect` | Read direct values or explicit cells |
| `init_local`, `set_local/free/global`, `box` | Initialize slots, assign cells, or create cells |
| `close` | Copy captures into a new closure |
| `frame`, `argument`, `shift`, `apply`, `return`, `test` | Operate on the reusable stack and transfer control |
| `const_atom/pair/vector`, `global_primitive` | Initialize constants and native procedures |
| `halt`, `invalid_pc` | End execution or report an invalid destination |

Ordinary instruction bodies are internal `snail_vm_*` functions with
`alwaysinline`. Their LLVM loads, stores, and branches access the register record
and stack directly. Rust supplies stack growth, checked closure/cell access,
object construction, primitive invocation, and snapshot services. A source word
must be loaded before a service can resize its storage, and live words must be
published before a safepoint. The VM pointer and its embedded register pointer
alias; neither is promised `noalias`.

The generated module exports `snail_program`, `snail_global_count`,
`snail_constant_count`, and `snail_program_abi`. The runner checks the last
against `PROGRAM_ABI` before initialization. ABI **3** describes the register
record, stack/control protocol, and tagged singleton encodings. Older modules
fail before executing. Compound constants refer to earlier constant-pool entries.

The collector is precise, nonmoving mark-and-sweep. Each allocation is one
`Box` containing an aligned kind/mark header followed by its concrete payload.
Pairs, cells, strings, and vectors preserve v3's field model; Rust replaces the
C++ virtual destructor and allocator metadata with static kind dispatch.
Strings contain a byte count, byte pointer, and ownership bit; vectors use a Rust
`Vec` in place of `std::vector`. Additional kinds represent this VM's closures,
records, ports, primitive IDs, bytevectors, and boxed integers.

An ownership vector is used only for sweeping. `gc_mark` dispatches on the
header kind and adds children to an iterative worklist. Only `Extension`
objects have a virtual table: C ABI callbacks report Scheme edges and release
the foreign payload. The unsafe extension contract forbids collection,
reentrancy, managed allocation, or unwinding from those callbacks. Safe foreign
registration and durable host roots remain future work; see [Rust interop](rust-interop.md).

Collection follows three rules:

1. Before an allocating Rust callable, the VM polls with its procedure and all
   arguments included in the roots, then hands it an owned `Allocation`.
2. The callable and its helpers allocate through that capability without GC.
3. The VM publishes results or roots the complete returned call action before
   another allocating boundary. Ending a capability never collects.

Nonallocating primitives and ordinary instruction entry do not poll. Closure
creation, explicit local boxing, continuation capture, rest-list construction, and startup constants
also acquire a capability. Arithmetic is classified as allocating because its
result may require boxing. Interning symbols uses ordinary Rust storage only.
`Runtime` exposes object/host services; the allocating entry receives
`Allocation`, while only `Vm` owns Scheme roots and collection control.

The explicit `collect-garbage` action consumes its inputs and publishes its
result before collecting. Roots include globals, constants, registers, active
stack words, multiple results, and current ports. Frame metadata is encoded as
immediate values, so every word in the active suffix can be scanned uniformly.
Continuation objects trace all words in their owned snapshots.
Large Rust calls may exceed the soft collection budget by their entire burst;
there is no emergency collection from inside those calls. Dropping unreachable
objects releases their owned Rust resources. Host allocator OOM is not a
recoverable Scheme exception.

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
irreducibility to repair. With the check and omission, that earlier compiler
built in about 39 seconds; the current stack emitter's larger output is measured
separately in the [stack report](stack-vm.md#compiler-sized-code-generation).
This policy is for this compiler's generated control
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

The Scheme compiler entry is `src/snail-scheme/compile.scm`, which invokes
`compiler-main` at top level. The historical `main.scm` only defines a parser
inspection procedure; it is not this entry point and does not invoke itself.

Run these commands through the existing Scheme host:

```sh
nix-shell --run './snail-compile src/snail-scheme/compile.scm build/compiler.ll'
SNAIL_LLVM_IR=build/compiler.ll cargo build --release -p snail-runner --target i686-unknown-linux-musl
cp target/i686-unknown-linux-musl/release/snail-runner build/snail-compiler
SNAIL_LLVM_IR=build/compiler.ll cargo build --release -p snail-runner --target wasm32-wasip1
cp target/wasm32-wasip1/release/snail-runner.wasm build/snail-compiler.wasm
```

The resulting compiler accepts `ROOT INPUT OUTPUT [VM-DUMP] [--timing]` after its executable
name. It can emit LLVM text; LLVM/Cargo still perform final code generation.
For example, this writes a file rather than running Fibonacci or printing its
answer:

```sh
./build/snail-compiler "$PWD" examples/fibonacci.scm build/fibonacci.ll --timing
SNAIL_LLVM_IR=build/fibonacci.ll cargo run --release -p snail-runner --target i686-unknown-linux-musl
```

The high-level driver can also build the native compiler directly:
`./snail-scheme src/snail-scheme/compile.scm -o build/snail-compiler`.
The normal build deliberately continues to use `snail-compile` and Chibi.
A subsequent self-hosting milestone should compare artifacts from consecutive
compiler generations before changing that default.

The earlier capability validation compiled the entry point for both native and WASI.
Both executables compiled a small core-library program to LLVM byte-identical
to Chibi's output. The native compiler also compiled Fibonacci with standard
library imports; its identical output ran on both targets. Import-heavy
compilation with that earlier runtime took about 215 seconds,
including 125 seconds in GC and 423 million managed allocations. These are
single-host observations, not benchmark promises. The
[validation record](../benchmarks/results/2026-10-09-compiler-capability.json)
identifies the artifacts and exact scope. The normal build continues to use Chibi.

The 32-bit fixed-layout runtime repeats those correctness checks successfully:
[validation record](../benchmarks/results/2026-10-09-runtime-v3-compiler.json).
Both compiled compilers emit the core fixture identically to Chibi; the native
compiler emits identical Fibonacci IR, which executes on native32 and WASI.
Its Fibonacci compilation took 2.81 seconds in this single check. The earlier
215-second observation used older compiler sources as well as the older runtime,
so these figures are not an isolated runtime speedup comparison.

The ABI 3 stack implementation also compiles the compiler's own source to
byte-identical LLVM on native32 and WASI. Its
[validation record](../benchmarks/results/2026-10-09-ch4-compiler.json) includes
Fibonacci emission and execution on both targets. The compiled WASI compiler
requires Node's explicit `--liftoff-only` workaround in this environment: V8's
optimizing tier exhausts memory on the compiler-sized dispatch function.
See the [host limitation](stack-vm.md#wasi-compiler-host-limitation); ordinary
integration tests and benchmarks retain the default optimizing host.

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
By default the runner also compiles the same workload with Chez Scheme and
reports the ratio of median Snail time to median Chez time. Both targets compare
with native Chez, using equal repetition counts and alternating execution order.
Raw samples are retained in JSON; values above one mean Snail took longer.
The benchmark guide documents the IO adapters and differing collector statistics.
The [performance diagnosis](performance-baseline.md) counts generated Fibonacci
operations and records a native CPU profile. LLVM inlines the instruction
handlers, but the separately compiled Rust services remain opaque; arithmetic
and calls still pay for generic runtime dispatch.

## Baseline limits and next steps

This is the compiler's bootstrap subset, not a complete R7RS implementation.
Exact integers are checked `i64`; bignums, rational and complex values are not
implemented. Nonintegral division yields `f64`. Unicode character case comparison
uses lowercase conversion rather than full Unicode case folding. Scheme
exception handling and `dynamic-wind` are deferred.
Parameterization and file wrappers restore or close on normal returns, including
multiple values; they do not yet implement nonlocal-exit semantics.
Printing cyclic structures produces the diagnostic marker `#<cycle>`, not
readable graph notation.

Source locations survive in VM instruction metadata, but generated executables
do not yet produce Scheme source backtraces. The full bootstrap library is
retained, and dynamic calls share one dispatcher. The reusable stack establishes
the baseline before type inference and specialization; see the
[stack implementation notes](stack-vm.md).

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

## Runtime measurements

[Cross-language LTO](lto-experiment.md) records the earlier trait-object runtime
and the static Rust/LLVM inlining probe. Those measurements describe the old
representation. The runtime now uses the [allocation capability](rust-interop.md#allocation-capability)
and fixed layouts above. Shared LLVM optimization remains optional: ordinary
Cargo release builds already optimize the statically typed Rust object access.

The [fixed-layout runtime report](runtime-v3.md) records the v3 adaptations,
matched 32-bit measurements, inlining evidence, and validation.
