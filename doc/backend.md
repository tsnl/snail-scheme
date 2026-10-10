# WebAssembly backend

The compiler remains hosted by Chibi. Source expands into resolved IR, grouped
by library; `wasm.sld` emits WasmGC text directly. Binaryen assembles, links, and
optimizes it with the Rust runtime compiled to Wasm. The old managed Scheme
stack, MIR, LLVM emitter, and native Rust heap are retired.

## Build and run

```sh
rustup target add wasm32-wasip1
./snail-scheme examples/fibonacci.scm
./snail-scheme examples/fibonacci.scm -o build/fibonacci.wasm
./snail-scheme examples/fibonacci.scm --emit-wat -o build/fibonacci.wat
./snail-scheme examples/extension.scm --extension examples/extension
```

`-o` builds without running. Arguments after `--` pass literally to the program.
All normal builds optimize the linked Wasm. `--keep-build` retains intermediate
files. The driver invokes Cargo automatically and uses one generated Rust
cdylib containing runtime and extension dependencies: their pointers all address
one linear memory. Independently merging arbitrary WASI modules would require
preserving which module's memory each pointer-taking WASI import accesses.

Tool overrides are `CHIBI`, `CARGO`, `WASM_AS`, `WASM_MERGE`, `WASM_OPT`, and
`NODE`. Tested tools include Chibi 0.12, Rust 1.95, Binaryen 132, and Node 24.15.
The Node runner supplies WASIp1 and AWI finalization imports. Browser hosting
can reuse `runtime/host.mjs`; a browser WASI adapter is separate work.
WasmGC, typed function references, tail calls, mutable globals, sign extension,
and bulk memory are enabled explicitly. Do not enable every experimental
Binaryen feature: it can produce modules unsupported by the selected engine.

`--actor INPUT.sld -o OUTPUT.wasm` builds a library for the experimental Node
worker host. It requires a single `define-library`. The compiler resolves its
exports alongside the S-expression codec and emits same-instance AWI wrappers.
The linked artifact has `actor_initialize` instead of a command `_start`.
Initialization runs once; the host subsequently invokes exported handlers.
See the [actor example](../examples/actors/README.md) and `scripts/test-actors`.

## Source to WebAssembly

| Module | Responsibility |
| --- | --- |
| `ir.sld` | Seven resolved expression forms and shared binding identities |
| `library.sld` | Library containers, imports, exports, dependency order |
| `expand.sld` | Located syntax to IR, including `syntax-rules` expansion |
| `wasm.sld` | Binding/capture analysis and direct folded WAT emission |
| `runtime/wasmgc.wat` | Value representations, checked primitives, calls |
| `runtime/awi.wat` | Root handles and scalar accessors for foreign Wasm code |
| `awi/src/lib.rs` | Rust ownership and checked conversions over AWI |
| `runtime/src/lib.rs` | Rust ports, formatting, text search, clocks, process services |
| `driver/src/main.rs` | Hosted compilation, Cargo, linking, execution/publication |
| `actor-wire.sld` | Data-only S-expression calls and readable portable results |
| `runtime/actor-instance.mjs` | WASI initialization and same-instance AWI ownership |
| `runtime/actors.mjs`, `runtime/actor-worker.mjs` | Worker lifetimes and connection-owned promises |

IR expressions are names, literals, applications, lambdas, blocks, conditionals,
and assignments. A library owns its body and dependencies. Expansion retains
binding identity; shadowing a primitive cannot silently select its fast helper.
There is no second internal IR or compiler-managed operand stack.

The emitter analyzes assignment, captures, and initialization. Immutable,
already-initialized captures travel as values; assigned or early-captured
bindings use shared cells. Recursive cells exist before their initializers run.
Reading an uninitialized binding fails, including when a known callee can be
called directly. Library initialization follows dependency order.

A fixed-arity lambda has a worker taking its environment and individual
arguments, plus a uniform closure adapter taking an argument array. Proven
immutable fixed callees call workers directly, so Fibonacci does not allocate
argument vectors. Unknown calls and `apply` use adapters. Tail positions emit
`return_call` or `return_call_ref`; different argument counts need no trampoline.
`apply` and `call-with-values` invoke Scheme in Wasm, preserving tail calls.

A single return value is an ordinary reference. Zero or multiple values use a
private packet, checked at single-value contexts and propagated at returns.
Nonfinal block expressions discard any value count.

## Representations and ownership

Scheme values are `eqref`. Signed31 integers use `i31ref`; larger exact integers
use an `i64` box and inexact numbers an `f64` box. Pairs, vectors, text, closures,
cells, records, and multiple-value packets use WasmGC structs and arrays.
Equivalent Wasm types are structural: names alone do not distinguish them.
Atoms and text wrappers therefore carry explicit category tags.

The Wasm engine sees references in globals, locals, arrays, tables, and active
frames. It owns collection and relocation. Rust does not scan its own stack for
Scheme roots: owned AWI handles retain references in a Wasm table. Temporary
arguments and results use that same mechanism. The Rust `Root` wrapper releases
its table slot on `Drop`, retains a separate slot on `Clone`, and transfers
ownership on return. See [AWI](rust-interop.md).

WasmGC removes the single 32-bit linear-memory address-space limit from Scheme's
object heap. It does not promise an unlimited heap or arrays; engines still
impose implementation limits. Rust currently targets ordinary wasm32 linear
memory and retains its own address-space limit.

Portable WasmGC does not expose forced collection, collector statistics, or
finalizers. `collect-garbage` and `gc-statistics` diagnose this limitation rather
than inventing values. Explicit close releases external resources promptly.
The JS host additionally registers extension objects with `FinalizationRegistry`
and calls the Rust resource-release export when cleanup occurs. This is a
host service, not a WasmGC opcode; it is neither timely nor guaranteed at shutdown.

## Continuations and native execution

`call/cc` and `call-with-current-continuation` are unsupported in this backend.
The accepted direction is single-shot, delimited continuations through Wasm
stack switching, with an independent native Wasm-to-LLVM execution backend.
A consumed continuation cannot be resumed again. Ordinary Rust-to-Scheme
callbacks are supported; allowing suspension or escape across Rust frames
requires a separate ownership and cleanup contract.

Suspending preserves a stack; abandoning a Rust frame must account for its
pending destructors. A future cancellation operation can unwind a suspended
stack when the toolchain supports it. Host finalization could schedule that
cancellation, but does not itself implement unwinding. Current Rust release
builds use `panic = "abort"`; no Rust forced-unwind support is promised.

`--native` delegates to `SNAIL_WASM_NATIVE`. The separate
[bounded translator](../experiments/wasm-llvm/README.md) has measured competitive
performance but lacks the arrays, memories, imports, and other operations needed
for the complete linked program. Its [continuation experiment](../experiments/wasm-stack-switching/README.md)
decodes real `cont.new`, `resume`, and `suspend` instructions for a bounded
`i64 -> i64` subset. It verifies single-shot consumption, nested handlers, foreign
barriers, and GC roots across suspension. This is not yet a Scheme coroutine API
or support for Rust unwinding.
Wastrel remains a useful reference and optional translator: the tested revision
`ad0b577df0773a1fc825b2a2455e23bf03ea9dcc` supports WasmGC but lists stack
switching as future work. A native host can implement the same finalization
import through BDWGC without making the translator depend on Scheme IR.

## Validation and measurements

Run `make test`, `make check`, `cargo test --offline`,
`cargo fmt --all -- --check`, `scripts/test-backend`, and `scripts/test-cli`.
The integration suites execute real linked Wasm, including closures, mutation,
recursive initialization, rest arguments, values, numeric boundaries, proper
tail calls, errors, and Rust callbacks with retained roots. Unit tests remain in
implementation modules; integration fixtures remain in `tests/`.

To check that the compiler can compile its own source without switching hosts:

```sh
./snail-scheme src/snail-scheme/compile.scm -o build/compiler.wasm
node scripts/run-wasi.mjs build/compiler.wasm . examples/fibonacci.scm build/fibonacci.wat
```

The generated compiler has executed this command successfully; its Fibonacci
output was assembled, linked with the Rust runtime, and executed. Chibi remains
the default build host.

The [production WasmGC report](../benchmarks/results/2026-10-10-wasmgc-production.json)
measures the full linked CPU benchmark under Node/V8: 0.08627s versus Chez
0.03053s and Chibi 0.48150s. That is 2.83× Chez's time and 5.58× faster than
Chibi. Binaryen inlining threshold 40 plus convergence reduced execution time
from 0.33860s, with representation checks preserved. Eight rotating rounds use
the same source and checksum; compilation and process startup are excluded.
V8 tiering during the timed workload remains included.

The [October 10 experiment](../benchmarks/results/2026-10-10-wastrel.json)
measured fixed Fibonacci work with compilation/startup excluded: Chez 0.03015s,
our bounded native LLVM translator 0.04695s (1.56× Chez), and tuned Wastrel
0.04801s (1.59×). These are experimental modules, not measurements of the full
new production backend. Old stack/LLVM measurements remain historical evidence
in [stack-vm.md](stack-vm.md) and the benchmark reports.
