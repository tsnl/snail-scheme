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
nix-shell --run './snail-compile examples/fibonacci.scm build/fibonacci.ll build/fibonacci.vm'
opt -passes=verify -disable-output build/fibonacci.ll
SNAIL_LLVM_IR=build/fibonacci.ll cargo run --release -p snail-runner
SNAIL_LLVM_IR=build/fibonacci.ll cargo build --release -p snail-runner --target wasm32-wasip1
node --no-warnings scripts/run-wasi.mjs target/wasm32-wasip1/release/snail-runner.wasm
```

The example prints `fib(25) = 75025`, elapsed monotonic-clock jiffies, and
`1000000000` jiffies per second. Nanosecond units do not imply nanosecond hardware
resolution. Compare repeated release runs on a stable machine; the executable
includes the full unspecialized bootstrap library.

`snail-compile INPUT OUTPUT [VM-DUMP]` writes LLVM and an optional readable VM
dump. It leaves assembly and linking to Cargo. `CHIBI`, `LLVM_LLC`, `LLVM_OPT`,
and `NODE` select tool executables. `SNAIL_LLVM_IR` can be absolute or relative
to the repository root. The existing `snail-scheme` parsing command is unchanged.

```sh
nix-shell --run 'make test && make check'
cargo test --offline
cargo fmt --all -- --check
nix-shell --run 'scripts/test-backend'
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
| `llvm.sld` | Mechanical emission of calls, static branches, and dynamic destinations |
| `runtime/src/vm.rs` | Activations, continuations, calls, multiple values, roots |
| `runtime/src/heap.rs` | Objects, tracing, allocation, and collection |
| `runtime/src/primitives.rs`, `host.rs` | Primitive operations and host services |
| `runner/` | Target assembly and final Rust application entry point |

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

Generated code passes an opaque VM pointer and fixed-width `i32` operands.
No Rust container, enum, trait object, or Scheme value crosses this ABI. The
runtime owns the representation, currently an enum with `i64` integers, `f64`
numbers, characters, immediates, and stable heap handles.

| Handler family | Effect |
| --- | --- |
| `constant`, `refer_local/free/global` | Replace results with a stored value |
| `set_local/free/global` | Store a single result |
| `capture_local/free`, `close` | Capture raw cells and construct a closure |
| `push`, `call`, `return`, `test` | Evaluate calls and transfer control |
| `const_atom/pair/vector`, `global_primitive` | Initialize constants and native procedures |
| `halt`, `invalid_pc` | End execution or report an invalid destination |

The exported names have a `snail_` prefix; `runtime/src/lib.rs` defines the
signatures. The generated module exports `snail_program`, `snail_global_count`,
and `snail_constant_count`. Compound constants refer to earlier constant-pool
entries, so construction preserves roots without temporary LLVM value layouts.

The collector is precise, nonmoving mark-and-sweep. Objects remain in stable
boxes; an iterative worklist follows managed references through
`SnailSchemeObject::mark`. The baseline uses an object enum with a handwritten
tracing implementation. Extensible trait objects and a derive macro are future
work; the generated-code ABI does not constrain that choice.

Collection follows three rules:

1. A handler may collect at entry, before removing VM roots.
2. Allocation and all subsequent helper work within that handler are GC-free.
3. Surviving values are published into VM roots before the handler returns.

An exported handler must not call another exported handler after taking values
out of roots. Internal helpers and the invocation loop do not collect. Roots
include globals, constants, results, operands, current and saved activations,
multiple-value consumers, and current ports. Large atomic operations can briefly
exceed the collection budget; this is the baseline's simplicity tradeoff.
Dropping unreachable objects also releases their owned Rust resources.

Scheme errors stop the VM and subsequent handlers do nothing. No Rust unwind
may cross generated code. Debug builds contain unexpected Rust panics at handler
boundaries; release builds use abort-on-panic. This policy is separate from
future Scheme exception support.

There are no speculative `noalias` promises on register pointers. The opaque
interface currently has one machine pointer; a future split-register interface
must prove its aliasing contract, including accesses made by the collector.

## Native and WASI hosts

Cargo owns the final application, Rust dependencies, and target support
libraries. `runner/build.rs` invokes `llc` for the Cargo target and links the
object into the executable. The WASI module contains generated code and Rust in
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

The resulting compiler accepts `ROOT INPUT OUTPUT [VM-DUMP]` after its executable
name. It can emit LLVM text; LLVM/Cargo still perform final code generation.
The normal build deliberately continues to use `snail-compile` and Chibi.
A subsequent self-hosting milestone should compare artifacts from consecutive
compiler generations before changing that default.

Initial validation compiled this entry point for both native and WASI. Both
executables compiled a literal program to identical, verified LLVM. The native
compiler also compiled a Fibonacci program with library imports; its output
ran on both targets. Import-heavy compilation is still slow in this baseline.

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

The current build links machine objects. It specializes the instruction stream
but does not inline Rust handler definitions into generated LLVM. The next
performance step can preserve runtime LLVM bitcode, verify compatible Rust/LLVM
versions, attach `alwaysinline` to handler definitions, link modules, and run
LLVM optimization before assembly. An attribute on an external declaration
cannot inline a body that is only present as machine code. Rust's source
`inline` annotation is not sufficient for exported `no_mangle` handlers.

After that baseline is measured, pursue the separately discussed type-inference,
occurrence-typing, and specialization work. Keep correctness tests independent
of whether a particular optimization fires.

The new backend follows the shared `simplify` skill: direct representations,
independent behavioral explanations, and small helpers. Exhaustive HIR/primitive
dispatch, ABI declarations, and atomic VM transitions may exceed its ten-line
target where splitting would hide the operation's contract. Refactoring is
confined to new modules; existing frontend code retains its structure.

Further references: [LLVM attributes](https://llvm.org/docs/LangRef.html#function-attributes),
[Rust inline attributes](https://doc.rust-lang.org/reference/attributes/codegen.html#the-inline-attribute),
[WASIp1](https://doc.rust-lang.org/rustc/platform-support/wasm32-wasip1.html), and
[cross-language LTO](https://doc.rust-lang.org/rustc/linker-plugin-lto.html).
