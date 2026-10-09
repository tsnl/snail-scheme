# Snail-Scheme backend

The compiler remains in Scheme and emits textual LLVM IR. A Rust runtime
provides objects, instruction handlers, garbage collection, and host services.
The same execution model targets native executables and WebAssembly from the
first working milestone. Correct Scheme semantics and a simple bootstrap come
first; specialization and LLVM optimization provide the path to good
performance.

This document records the intended architecture. It does not claim that the
backend or runtime is implemented, and leaves the concrete value encoding and
runtime layouts open for subsequent design.

## Compilation pipeline

```text
Scheme source and libraries
  -> syntax-rules expansion
  -> HIR
  -> Dybvig-style stack-VM instructions
  -> specialized LLVM text IR
  -> native executable or Wasm module
```

Expansion constructs fully expanded HIR with resolved binding identities and
source locations. The dedicated pattern and template machinery, including
`pattern.sld` and the expander, handles `syntax-rules`. Lowering then determines
lexical storage, closure environments, mutable cells, call frames, and tail
positions before emitting VM instructions.

The initial compiler supports `syntax-rules` rather than arbitrary procedural
transformers. It therefore needs no general Scheme evaluator for macro
expansion.
The compiler and its bootstrap libraries must themselves stay within this
supported subset and the runtime facilities implemented for the bootstrap.

The VM instruction set is a compilation representation. A bytecode interpreter
and a serialized bytecode format are not prerequisites for the first backend.
Here, "VM instructions" means the Dybvig-style representation; "LLVM bitcode"
means LLVM's serialized IR. These are different layers.

## Execution model

Use the stack model from Kent Dybvig's *Three Implementation Models for Scheme*
as the starting point. The runtime maintains explicit Scheme registers, a Scheme
stack, closure environments, and continuation state.

Calls push the Scheme state needed to resume the caller. Returns restore that
state. Tail calls rearrange or reuse the current Scheme frame and transfer
control without accumulating host-language frames. Instruction handlers return
to the generated execution function; they do not recursively call the next
handler. Proper tail recursion therefore does not depend on LLVM or Wasm
tail-call optimization.

Continuations capture the Scheme stack and control state. Restoring a
continuation must preserve the identity of mutable bindings shared with closures
or other continuations. Copying stack slots must not create independent copies
of such bindings; lowering introduces shared cells where required. Rest
arguments, `apply`, and multiple values belong to this same calling protocol.

Start with one large generated execution function containing LLVM basic blocks.
Known transfers use branches. Unknown closure entries, return destinations, and
continuation resumes use runtime dispatch. The explicit stack also allows this
function to be split into chunks later without changing Scheme semantics.

## Specialization and instruction handlers

Implement reusable instruction handlers in Rust. The emitter generates calls
with statically known operands and emits the corresponding control-flow edges.
Handlers that affect control flow return the information the generated function
needs to choose its next destination.

This is manual specialization of a known instruction stream. It eliminates
instruction fetching, operand decoding, and opcode dispatch from specialized
sequences. A source loop remains a loop in the generated graph. Dynamic calls
and continuation transfers retain their necessary runtime decisions. A general
partial evaluator is not needed.

Make the handler definitions available as LLVM bitcode to the optimization
pipeline and mark them `alwaysinline`. This lets LLVM combine handler bodies
with constant operands and eliminate temporary register traffic. A handler may
still call a substantial runtime operation, such as collection or port I/O,
without inlining that operation.

LLVM's `alwaysinline` requests inlining whenever possible, ignoring size
thresholds. It still needs a visible definition and a legal inlining
opportunity.
Annotating an external declaration cannot inline a separately compiled machine
code library. [LLVM function attributes][llvm-functions] describe the contract.

Check the actual handler IR when preparing it for linking. Rust documents that
its `inline` attribute is ignored on functions exported with `no_mangle` or
`export_name`; source annotations alone are therefore not the build contract.
The bitcode preparation step must ensure the desired LLVM attributes are present
on the handler definitions. See [Rust code-generation attributes][rust-inline].

LLVM performs the target-specific lowering. Its Wasm backend can wrap
single-entry control-flow regions in structured blocks and loops, and introduce
dispatch for irreducible regions. Generated branches are valid input, but their
cost depends on the graph: specialization does not guarantee removal of every
control-flow dispatch. Inspect the optimized IR and generated Wasm as the
backend develops. See LLVM's [control-flow stacking][llvm-cfg] and
[irreducible-control-flow transformation][llvm-irreducible].

## Runtime interface

Generated LLVM and Rust share a small interface using the target's C calling
convention. This is a calling contract, not a requirement to generate C source.
Rust exports runtime entry points with stable symbol names; generated modules
can export entry points callable from Rust as well.

Define the following together before implementing the instruction set:

- The tagged `Value` representation and the representation of managed
  references.
- Register storage, Scheme stack slots, frame layouts, and code destinations.
- Object headers and any layouts accessed directly by generated code.
- Handler signatures, argument and result passing, including multiple values.
- Root frames, allocation safepoints, and which operations can collect.
- Host hooks and the representation of their results and failures.

Use scalars, opaque pointers, and explicitly specified shared structures at this
boundary. Shared Rust structures need an appropriate explicit representation,
such as `repr(C)`. Rust containers and trait-object layouts remain private.
Generate the correct target data layout, pointer widths, calling convention,
and ABI attributes; hand-written LLVM declarations must already describe the
lowered ABI. The same emitter can support several targets without requiring
identical target-specific LLVM modules.

Apply `noalias` to register-storage pointer arguments only where its access-path
contract holds. Both callers and handlers must uphold that contract throughout
the call. It is a correctness promise, not a runtime check. Distinct register
slots may contain references to the same Scheme object; their separation says
nothing about whether those objects are shared.

Design this together with rooting: collector access through a registered root
can be another access path to a register slot. Do not add `noalias`
indiscriminately to state accessible through the runtime or root registry. See
[LLVM parameter attributes][llvm-parameters].

Scheme control transfers use the explicit execution state. Rust panic handling
must not unwind unexpectedly across generated frames; establish an abort or
contained-error policy at the runtime boundary.

## Objects and garbage collection

Use a precise, nonmoving mark-and-sweep collector. Stable object addresses
simplify the generated code and runtime boundary, but do not keep an otherwise
unreachable object alive.

Managed Rust object types implement `SnailSchemeObject`. Its `mark()` method
reports outgoing managed references to a marker. The intended
`#[derive(SnailSchemeObject)]` implementation traverses fields according to
their tracing implementations. The collector owns mark bits and an iterative
worklist so cycles and deep object graphs do not require recursive traversal
on the Rust stack. Tracing must not invoke Scheme or trigger another collection.

The tracing contract must account for every strong managed edge. A derive must
reject unsupported fields unless their treatment is explicitly specified.
Whether manually implemented tracing requires an unsafe trait contract is part
of the concrete runtime API design. Scheme records can use a generic runtime
record representation; they do not require a generated Rust type per record.

Object tracing and root discovery are separate responsibilities. Roots include
live VM registers, Scheme stack slots, globals, constant pools, captured
continuations, and temporary results in either generated code or Rust helpers.
Every managed value live across an operation that can collect must be reachable
through the explicit root protocol. A value held only in an LLVM SSA value or a
Rust local is not automatically a root.

For example, when evaluating `h(f(), g())`, the result of `f()` must be rooted
while `g()` runs if `g()` can allocate. Collection occurs only at defined
safepoints, initially around allocation. The root representation must remain
visible to the collector after optimization. LLVM provides compiler support for
GC cooperation, not the collector itself; see its [GC documentation][llvm-gc].

The Rust runtime owns the Scheme heap. Reclaiming an object and releasing any
non-Scheme resources need an explicit destruction policy; marking alone does
not define finalization behavior. Keep this distinct from future Scheme-visible
finalizers.

## Targets and host services

Require native and Wasm builds from the first working runtime milestone. Begin
with `wasm32-wasip1`, producing a core Wasm module, and test it in a WASI
runtime.
The generated code and Rust runtime link into one module with shared linear
memory. The Scheme heap and stack live there and use our own collector.

Keep the runtime core suitable for `#![no_std]` plus `alloc`. This still permits
Rust collections, boxed objects, and trait dispatch. The final embedding
supplies allocation and panic handling, and may use `std` in its host adapter.
WASI does not itself require `no_std`; the separation keeps platform
dependencies explicit.
See the [Rust allocation library][rust-alloc] and [WASIp1 target][rust-wasip1].

Host adapters provide ports and file access, arguments, clocks, entropy, and
other services actually required by the language libraries. Native and WASI
adapters implement the same runtime-facing hooks. Browser embedding can provide
those hooks directly or supply the WASI imports used by the module.

Document a Wasm feature baseline and the required host imports. Portability
means the embedding supports that contract. WASIp2 component packaging is a
separate outer interface; it does not change the internal generated-code/runtime
ABI.
Emscripten-specific services are not part of the initial runtime contract.

## Building and linking

Let Cargo and Rust own the final application build and entry point. The basic
build compiles generated `.ll` modules to target object files and links those
objects with the Rust runtime. Calls work in both directions. This provides a
simple correctness baseline before inlining across modules is working.

The optimizing build preserves handler bodies as LLVM bitcode until they are
available alongside the generated program, through bitcode linking or LTO.
It applies the handler attributes and optimization pipeline before final code
generation. Ordinary machine-code linking alone cannot perform that inlining.

Pin compatible Rust and LLVM toolchains for this build and coordinate their LTO
modes. `rustc -vV` reports the LLVM version used by Rust. Object linking needs
compatible target ABIs and object formats; sharing LLVM bitcode additionally
requires compatible LLVM tooling. Keep dependency and support-library linkage
under the Rust build rather than treating one crate's bitcode as a complete
runtime. See [Rust foreign-code linking][rust-linking] and
[cross-language LTO][rust-lto].

## Bootstrapping

1. Run the Scheme compiler on the existing host Scheme implementation. Complete
   enough language libraries and runtime primitives to compile that compiler.
2. Lower the compiler's Scheme sources through HIR and VM instructions to LLVM
   IR. Compile and link the result with the Rust runtime and host adapter.
3. Run the resulting native Snail-Scheme compiler to compile its own sources
   again. Compare behavior and deterministic generated artifacts, accounting for
   intentional metadata differences.
4. Build and exercise the same compiler for Wasm with the chosen host adapter.

This makes the Scheme compiler self-hosting while Rust and LLVM remain build
dependencies. A compiler running inside Wasm can emit LLVM text; producing a new
native executable or Wasm binary from that text still needs an accessible LLVM
toolchain or an explicit host compilation service.

When procedural transformers are introduced, add a way to execute arbitrary
Scheme procedures during expansion. A VM interpreter using the same instruction
semantics is one possible extension. The first bootstrap does not depend on that
choice, nor on JIT compilation or a general partial evaluator.

## Implementation milestones and validation

1. Specify a minimal value, register, root, and runtime-call ABI. Link a small
   hand-written LLVM module with Rust on native and WASI targets, with calls in
   both directions and a rooted allocation surviving collection.
2. Implement VM lowering and emission for a small useful Scheme subset,
   retaining source locations. Validate LLVM modules and run the same programs
   on both targets, comparing their results with the host Scheme where
   appropriate.
3. Extend the runtime and lowering with calls, closures, mutation, tail calls,
   rest arguments, multiple values, and continuations. Exercise deep tail
   recursion and shared mutable state across continuation capture and reuse.
4. Stress collection at allocation safepoints. Test values reachable only
   through each root category, nested allocation, reachable cycles, and
   reclamation of unreachable cycles. Include optimized builds to expose
   rooting or aliasing
   mistakes hidden in unoptimized code.
5. Make handler definitions available for inlining and inspect the optimized IR.
   Confirm the intended calls disappear and constant operands eliminate work.
   Measure native and Wasm execution, code size, and compiler resource usage.
6. Complete the primitives and libraries needed by the compiler and perform the
   self-hosting rebuild.

These are backend implementation checks, not a requirement to build a general
bytecode interpreter first. Keep correctness tests independent of whether a
particular optimization fires.

## Open design decisions

- Exact `Value` tags, immediate values, managed references, and numeric formats.
- Object headers, type metadata, tracing API, and destruction policy.
- Register and frame layouts, code destinations, closure environments, and the
  multiple-value and continuation protocols.
- Root-frame layout, safepoint rules, and the precise aliasing contract between
  generated code, handlers, and the collector.
- The minimal instruction set and its exported handler signatures.
- The concrete bitcode preparation and LTO pipeline, including attribute checks.
- Host-hook signatures and the initial Wasm feature/import baseline.

The initial architecture is fixed independently of these details: a Scheme
compiler, Dybvig-style explicit execution state, manual specialization to LLVM
IR, and a Rust runtime with precise nonmoving collection.

[llvm-functions]: https://llvm.org/docs/LangRef.html#function-attributes
[llvm-parameters]: https://llvm.org/docs/LangRef.html#parameter-attributes
[rust-inline]: https://doc.rust-lang.org/reference/attributes/codegen.html
[llvm-cfg]: https://llvm.org/doxygen/WebAssemblyCFGStackify_8cpp_source.html
[llvm-irreducible]: https://llvm.org/doxygen/WebAssemblyFixIrreducibleControlFlow_8cpp_source.html
[llvm-gc]: https://llvm.org/docs/GarbageCollection.html
[rust-alloc]: https://doc.rust-lang.org/alloc/
[rust-wasip1]: https://doc.rust-lang.org/rustc/platform-support/wasm32-wasip1.html
[rust-linking]: https://doc.rust-lang.org/reference/linkage.html#mixed-rust-and-foreign-codebases
[rust-lto]: https://doc.rust-lang.org/rustc/linker-plugin-lto.html
