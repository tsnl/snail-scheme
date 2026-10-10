# Backend baseline

Snail-Scheme expands source into HIR, elaborates HIR into structured MIR, emits
textual LLVM IR, and links it with Rust through Cargo. Native32 and
`wasm32-wasip1` share the same downward-growing Scheme stack, continuation model,
and precise collector. Chibi still hosts the compiler. There is no JIT,
compile-time VM, type inference, or self-hosting build switch.

Libraries organize both stages. Each has an interface, dependencies, and a
phase-specific body; an executable script is an unnamed root library. HIR
preserves readable Scheme expressions and binding identities. MIR exposes
checks, representation conversions, memory access, and calls. Its five
instruction forms are `if`, `call-direct`, `call-indirect`, `load`, and `store`.
See [the MIR design](mir.md) for their contracts and Scheme/HIR/MIR examples.

## Build and run

Use `nix-shell` for Scheme tools and formatting. Also provide Cargo/rustc, LLVM
`opt` and `llc`, LLD, and Node with WASI support. Install the Rust targets with
`rustup target add i686-unknown-linux-musl wasm32-wasip1`. Native output is a
static 32-bit Linux executable; the host must support executing i386 programs.
The runtime deliberately rejects 64-bit builds. Validation uses Rust 1.95.0
(LLVM 22.1.2), LLVM tools 22.1.8, and Node 24.15.0.

```sh
mkdir -p build
nix-shell --run './snail-scheme examples/fibonacci.scm --release --runtime-stats'
nix-shell --run './snail-scheme examples/fibonacci.scm -o build/fibonacci'
nix-shell --run './snail-scheme examples/fibonacci.scm --target wasm32-wasip1 --release'
nix-shell --run './snail-scheme examples/fibonacci.scm --target wasm32-wasip1 -o build/fibonacci.wasm'
nix-shell --run './snail-scheme examples/fibonacci.scm --emit-llvm -o build/fibonacci.ll --dump-mir build/fibonacci.mir'
```

The example prints `fib(25) = 75025` and elapsed seconds. Its clock uses monotonic
nanosecond units internally; this does not imply nanosecond hardware resolution.

The command follows [Resin's](https://github.com/tsnl/resin) invocation shape:
an input runs, `-o` builds without running, and flags select other modes. The
Rust driver invokes the hosted compiler and then `cargo run` or `cargo build`
in an isolated generated project. Arguments after `--` go to the program.

Run mode defaults to debug. `--release` selects release, and output builds
always use release. These optimized CLI modes enable shared Scheme/Rust LTO so
tiny representation calls can disappear across the language boundary.
`SNAIL_SHARED_LTO=0` selects ordinary linking for ablations or custom Rust flags;
debug runs also use ordinary linking. The driver owns its shared-LTO flags and
rejects conflicting `RUSTFLAGS` or `CARGO_ENCODED_RUSTFLAGS`. Compatible LLVM
versions matter when Rust and Scheme bitcode meet in the same optimization.

`--emit-llvm` writes LLVM to stdout or `-o` without building an executable.
`--dump-mir PATH` also writes MIR; `--dump-vm` remains a compatibility alias.
`--keep-build` retains the generated Cargo project and reports its location.
Each invocation owns its temporary project and Cargo target directory.
Requested artifacts are staged before publication. A Scheme compilation failure
preserves existing outputs; the MIR dump is published after successful emission,
and a subsequent Cargo failure still preserves an existing executable.

`snail-compile INPUT OUTPUT [MIR-DUMP]` is the lower-level emitter. `CHIBI`,
`LLVM_LLC`, `LLVM_OPT`, and `NODE` select tools. The old parser inspection entry
is `src/snail-scheme/main.scm`, not the compiler entry point.

### Direct Cargo builds

`SNAIL_LLVM_IR` selects the emitted file, either absolutely or relative to the
repository root. A direct Cargo invocation does not inherit the driver's LTO
configuration. For an ordinary native build:

```sh
SNAIL_LLVM_IR=build/fibonacci.ll cargo run --release -p snail-runner --target i686-unknown-linux-musl
```

To reproduce the optimized CLI path, explicitly enable shared LTO and its Rust
flags:

```sh
SNAIL_LLVM_IR=build/fibonacci.ll SNAIL_SHARED_LTO=1 \
RUSTFLAGS='-Cembed-bitcode=yes -Clinker-plugin-lto -Clto=fat -Clink-arg=--lto-O3 -Clinker=rust-lld' \
cargo run --release -p snail-runner --target i686-unknown-linux-musl
```

For WASI, use `--target wasm32-wasip1`, replace the linker flag with
`-Clinker=wasm-ld`, and configure Cargo's runner or run the resulting `.wasm`
with `node --no-warnings scripts/run-wasi.mjs`. A retained CLI project can be
rebuilt the same way using its absolute `program.ll` path.

## Checks

```sh
nix-shell --run 'make test && make check'
cargo test --offline --target i686-unknown-linux-musl
cargo fmt --all -- --check
nix-shell --run 'scripts/test-backend'
nix-shell --run 'scripts/test-cli'
```

Scheme unit tests live in their implementation modules' final `Tests` sections.
`make test` enables `snail-tests` and calls one exported entry point per module.
Integration fixtures remain in `tests/`; normal imports omit the unit tests.

The backend suite executes native and WASI programs under GC stress, including
mutation, recursive initialization, multiple values, reusable continuations,
arity errors, single-value errors, and numeric boundaries. Standalone fixtures
exercise llvmlite and MIR, including genuinely indirect C calls. The foreign-call
proof runs with ordinary linking and shared LTO. LLVM verifies emitted code.
Use `scripts/test-backend --target native` for a native-only iteration. Rust tests
also check normal collection scheduling; stress mode alone cannot validate it.

## Compilation stages

| Module | Responsibility |
| --- | --- |
| `compiler.sld` | Source/library loading and stage orchestration |
| `library.sld` | Independent library containers, resolved interfaces, dependency order |
| `expand.sld`, `hir.sld` | Macro expansion, resolved binding identities, readable Scheme |
| `bootstrap.sld`, `bootstrap/scheme/` | Primitive inventory, derived syntax, Scheme procedures |
| `lower.sld` | HIR library bodies to MIR, shared storage, captures, tail positions, literals, known calls |
| `mir.sld` | Library code/data bodies, five instruction forms, producer references, regions, dump |
| `machine.sld` | Explicit Scheme stack, frames, closures, and continuation transitions |
| `mir-llvm.sld` | Generic MIR emission, structured branches, and value joins |
| `llvm.sld` | Library flattening, module data, initialization, code addresses, and dispatcher |
| `llvmlite.sld` | Immutable LLVM objects and text serialization |
| `runtime/src/representation.rs`, `abi/` | Representation operations and scalar C ABI export macro |
| `runtime/src/vm.rs` | Stack storage, application preparation, snapshots, and roots |
| `runtime/src/object.rs` | Tagged words, object layouts, allocation, and collection |
| `runtime/src/primitives.rs`, `host.rs` | Builtins and host services |
| `runner/`, `driver/` | Target linking, executable entry, CLI modes, and subprocesses |

`library.sld` knows neither body's grammar. HIR bodies are ordered item lists;
MIR bodies own their initializer, procedure and resume definitions, constants,
global names, and primitive declarations. Lowering rebuilds the import graph
with the new bodies, retaining shared dependencies and original binding
identities. It assigns global and constant slots across the dependency order in
one temporary context. Each library's records remain together until LLVM emission
concatenates them into one executable; this organization does not require
separate compilation or runtime library objects.

MIR instructions are their own SSA references. Ordered regions schedule them;
conditionals own two regions and may produce a value. LLVM emission introduces
blocks and phi nodes. Shared terminal regions retain one continuation instead
of duplicating the rest of the program. There is no stack-bytecode module or
instruction-handler function layer between MIR and LLVM.

Every call carries its signature/convention and tail flag. C calls emit ordinary
direct or indirect calls, without implicit argument checks, conversions, or GC.
Checks and conversions appear as explicit surrounding operations. Scheme
transfers use code identities and the bounded dispatcher; they are not C
function pointers and do not depend on native tail-call support.

Small Rust functions implement tag tests, integer extraction and packing,
arithmetic, pointer offsets, and object predicates. Shared LTO exposes these
bodies to LLVM. MIR effect descriptors distinguish pure operations, heap reads,
and stateful services; no effect inference or check-elimination pass is present.
The `snail-abi` attribute exports fixed scalar Rust functions under explicit C
symbols. It supports `i32`, `u32`, and unit results, with compile-time signature
checks. It does not generate Scheme value conversion, allocation contexts,
export discovery, registration, or a general embedding API.

The compiler supplies a synthetic `(snail-scheme core)` and loads the bootstrap
libraries normally. Chibi uses its own libraries while hosting the compiler.
Imported aliases retain HIR binding identity. HIR blocks keep one ordered item
sequence, with the last expression providing the result.

## Scheme stack and continuations

Kent Dybvig's [*Three Implementation Models for Scheme*](three-imp.pdf) supplies
the starting model. The checked-in PDF is the highlighted copy recovered
byte-for-byte from `v3`. `machine.sld` expresses that model through MIR loads,
stores, conditionals, and calls rather than retaining a bytecode interpreter.

Libraries initialize once, after their dependencies. Their initializer entries
transfer directly to the next library on the same root Scheme frame; the unnamed
script runs last. Only its final expression is in tail position with respect to
the executable. Globals use indexed slots.
Lexical bindings occupy stack slots. Every binding assigned by `set!` gets a
shared cell, including locals that no lambda captures: restoring a continuation
must not roll back mutation. Immutable parameters, locals, and captures remain
direct values. Recursive initialization is a separate reason for indirection:
a closure created before a captured local's initializer must retain its location.
Reading an uninitialized local, cell, or global raises a runtime error.

Local collection stops at nested lambdas; capture analysis enters them because
a grandchild's free binding may need to pass through its parent. Binding
identities are reserved before analyzing recursive initializers.

One reusable Rust buffer holds each VM's Scheme stack, growing from high to low
addresses. `s` and `f` are depths from the high end, so stack growth preserves
saved offsets. A return frame holds the closure, tagged saved frame depth, and
tagged return address. Operands evaluate left-to-right, followed by the operator.
A normal call saves a frame; a tail call moves arguments over the current locals
and reuses that frame. Fixed-arity closure calls allocate no per-call vectors.

Rust checks callable kind and arity and constructs rest lists when required.
Native arguments borrow the stack through `Arguments`, whose source index `i`
maps to physical index `len - 1 - i`. Calls do not reverse or copy the slice.
Rust never recursively enters Scheme in this execution model.

One result occupies register `a`; zero or multiple results use a count and a
reusable buffer. Arguments, tests, assignments, and operators require one value.
Returns forward all values, while nonfinal expressions discard them.
`call-with-values` uses a reserved consumer continuation; `apply` rearranges
arguments and rejoins the common application path.

`call/cc` copies the active stack through the return header into an immutable
snapshot. Invocation preserves supplied values, restores a copy, and performs
the ordinary return transition. Snapshots are reusable. Shared cells preserve
assignments; heap objects and globals are not rolled back. `dynamic-wind` and
nonlocal parameter/port cleanup remain deferred.

## ABI and collection

Generated code passes an opaque VM pointer, fixed-width words, and transient slot
pointers. `snail_rt_state` exposes a stable `repr(C)` register record. MIR knows
its documented fields, not Rust container or trait-object layouts. `Value` is
32 bits. The v3 tags encode null as zero, fixnums with low bit one, interned
symbols with low bits ten, and boxed objects as aligned nonzero pointers.
Characters and singletons use halfword tags. Fixnums span `[-2^30, 2^30-1]`;
larger `i64` integers and all `f64` values are boxed. The v3 immediate float32
encoding requires 64 bits and is not used.

The generated module exports `snail_program`, `snail_global_count`,
`snail_constant_count`, and `snail_program_abi`. The runner checks ABI **3** before
initialization. Compound constants reference earlier constant-pool entries.
Copying a tagged word does not retain an object or create a durable host root.

The collector is precise, nonmoving mark-and-sweep. Each object is one `Box`
containing an aligned kind/mark header and concrete payload. Builtin access
checks tag and kind before direct field access, without an ownership-map lookup
or virtual dispatch. An ownership vector supports sweeping. `gc_mark` follows
fields through an iterative worklist, so cycles are supported. Destruction
releases an object's own Rust resources without recursively destroying children.

Only extension objects use a vtable. Its C ABI callbacks report live same-VM
Scheme edges and destroy foreign payloads; they must not collect, allocate
managed objects, reenter Scheme, or unwind. Safe registration and durable roots
remain future work; see [Rust interop](rust-interop.md).

Collection follows three rules:

1. Before an allocating Rust callable, the VM polls with live values and arguments
   published as roots, then supplies an owned `Allocation` capability.
2. The callable and its helpers allocate through that capability without GC.
3. Results or returned control actions become rooted before another safepoint.
   Dropping the capability never collects.

Ordinary loads, stores, and nonallocating leaf calls do not poll. Closure
creation, cell creation, continuation capture, rest-list construction, and
startup constants use allocation boundaries. General arithmetic can allocate
boxed results; the explicit fixnum fast path cannot. Allocation itself never
collects, and the collector never scans Rust stack locals.

Roots include globals, constants, registers, active stack words, multiple
results, and current ports. Snapshots trace their saved words. Frame metadata is
tagged immediate data, so the active stack can be scanned uniformly.
`collect-garbage` publishes its result before collection. Large Rust calls can
exceed the soft collection budget by their entire allocation burst; there is no
emergency GC inside them. Host allocator OOM is not a recoverable Scheme error.

Load a source before calling a service that may resize its storage. Publish
managed values before a safepoint, and do not retain pointers into movable stack
storage across growth. The VM pointer and embedded State pointer may alias;
no speculative `noalias` promises apply. Scheme errors stop the VM. Rust unwinds
must not cross generated code; runtime service boundaries contain unexpected
panics where supported, and release builds abort on panic.

## Native and WASI hosts

Cargo owns the executable and Rust dependencies. `runner/build.rs` obtains the
actual target triple and data layout from a small `no_std` Rust probe. LLVM
optimizes and verifies the generated module. Shared LTO retains Scheme bitcode
for LLD to optimize with Rust; ordinary linking uses `llc` to emit an object
first. This distinction materially affects tiny foreign-call overhead.

For ordinary WASI object builds, the runner verifies reducibility before
omitting LLVM 22's costly control-flow repair pass. Shared LTO keeps the final
linker's repair enabled because cross-language optimization can change the
graph. The [October 9 stack report](stack-vm.md#compiler-sized-code-generation)
records the earlier compiler-sized diagnosis; its timings predate MIR.

WASI uses one linear memory containing both generated code's data and the Rust
heap, with this collector rather than Wasm GC. The initial host uses Rust `std`
for ports, files, arguments, and `Instant`; complete `no_std + alloc` embedding
remains future work. `scripts/run-wasi.mjs` provides WASIp1 imports, preopens the
working directory, and forwards arguments and environment. Browser and WASIp2
packaging are not provided. No Emscripten services are used.

## Compiling the compiler

`src/snail-scheme/compile.scm` invokes `compiler-main` at top level. The older
`main.scm` only defines a parser inspection procedure and does not invoke it.
The capability check is:

```sh
./snail-scheme src/snail-scheme/compile.scm -o build/snail-compiler
./build/snail-compiler "$PWD" examples/fibonacci.scm build/fibonacci.ll
./snail-scheme src/snail-scheme/compile.scm --target wasm32-wasip1 -o build/snail-compiler.wasm
```

A compiled compiler accepts `ROOT INPUT OUTPUT [MIR-DUMP]`; it emits LLVM rather
than invoking Cargo. LLVM and Cargo still provide final code generation. The
normal build remains hosted by Chibi until a separate self-hosting milestone.

The [MIR capability record](../benchmarks/results/2026-10-10-mir-compiler.json)
validates native32 and WASI compiled compilers emitting Fibonacci. Their output
is byte-identical to each other and structurally identical to Chibi's output;
SSA names and block serialization order can differ between Scheme hosts. The
generated program executes correctly on native and normal Node/WASI.

The native compiler also compiled its own unchanged sources. LLVM verification
and structural comparison with Chibi both passed. This is a capability test,
not a self-hosting build switch. The executing compiler predates incremental
LLVM serialization; its 499-second self-source run is not a throughput measurement
of the final streaming writer. Native shared-LTO linking took 471 seconds and
ordinary WASI linking 212 seconds in this validation; builds were concurrent,
so these are observations rather than controlled compilation benchmarks.

The compiled WASI compiler ran with Node's `--liftoff-only` workaround, retaining
[the existing host limitation](stack-vm.md#wasi-compiler-host-limitation).
Full self-source compilation under WASI was not attempted. Native/WASI semantic,
GC-stress, scalar foreign-call, and CLI tests also pass.

## Measurements and remaining work

Chromium traces are always recorded under `build/traces/`, one file per process.
`SNAIL_TRACE_DIR` selects another directory. Traces include source loading,
compiler passes, Cargo, LLVM, runtime execution, and collection. See
[tracing](tracing.md) for APIs and timing boundaries.

`--runtime-stats` adds execution and GC seconds, allocation/reclamation counts,
and maximum saved frames in run mode. Built executables accept
`SNAIL_RUNTIME_STATS=1`. `(snail-scheme runtime)` exposes `collect-garbage`,
`gc-statistics`, and bulk `string-contains`. Its statistics vector is
`#(collections total-ns max-ns allocated reclaimed live peak-live)`; counts
measure objects, not a byte quota. The snapshot precedes allocation of its own
result vector. Collection time includes root gathering and weak-symbol cleanup.

The [benchmark guide](../benchmarks/README.md) documents fixed CPU, memory, IO,
and GC workloads, correctness checks, artifact hashes, and comparisons with
Chibi and Chez. Runtime samples exclude compilation; compare matched optimized
builds and retain the ordinary-link control when assessing shared LTO.
The MIR migration's performance evidence belongs alongside [its design](mir.md).

Earlier reports describe their dated architectures:

- [October 9 stack implementation](stack-vm.md): reusable stack and continuations.
- [October 9 numeric instructions](numeric-instructions.md): checked numeric calls
  bypassing the general procedure protocol before MIR.
- [October 9 Rust instruction experiment](rust-instruction-experiment.md): tiny
  Rust handlers under shared LTO, before removing that handler layer.
- [Fixed-layout runtime](runtime-v3.md) and [earlier LTO experiment](lto-experiment.md):
  object representation and inlining investigations.

The language remains a bootstrap subset. Exact integers are checked `i64`;
bignums, rational/complex arithmetic, Scheme exceptions, and `dynamic-wind` are
not implemented. Nonintegral division yields `f64`. Unicode case comparison
uses lowercase conversion rather than full case folding. Parameter and port
wrappers restore state on normal returns only. Cyclic printing produces
`#<cycle>` rather than readable graph notation.

The full bootstrap library remains in generated programs. Scheme calls share a
dispatcher. MIR currently omits source locations, and generated executables lack
Scheme source backtraces. Type/effect inference, occurrence typing,
specialization, and check elimination remain subsequent IR passes. The scalar
export proof does not supply the general Rust embedding interface in
[TODO.md](../TODO.md).

Implementation follows the pinned `simplify` skill and the ten-line function
target. Complete dispatch tables and atomic transitions may remain longer when
splitting would obscure their contracts. [Bitwise](https://github.com/pervognsen/bitwise)
inspires direct representations and locally understandable control flow.
