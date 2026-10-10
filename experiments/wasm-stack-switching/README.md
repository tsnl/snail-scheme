# Native stack-switching experiment

This bounded experiment translates real Wasm stack-switching instructions to
native LLVM and keeps parked WasmGC objects alive through BDWGC. It is separate
from the production compiler and is not full continuation support.

`workers.wat` uses the proposal's continuation types, `cont.new`, `resume`, and
`suspend`. Binaryen 132 assembles and validates it with
`--enable-stack-switching`, then the experimental Wasm-to-LLVM translator reads
that actual `.wasm` binary. The generated LLVM calls the glibc `ucontext` runtime
in `proof.c`. Coroutine scheduling, nested handlers, and single-shot tests are
Wasm code; the C driver only initializes the collector and invokes test exports.
There is no private continuation opcode or imported substitute for `suspend`.
The operation semantics follow the
[Wasm stack-switching proposal](https://github.com/WebAssembly/stack-switching/blob/main/proposals/stack-switching/Explainer.md).

Run from the repository root:

```sh
python3 experiments/wasm-stack-switching/run.py
```

The runner uses the experiment's current Nix tool paths. Override `BINARYEN`,
`BDWGC_INCLUDE`, and `BDWGC_LIB` for other installations; `clang` and `opt` must
be on `PATH`. Output goes in `build/wasm-stack-switching/`, including decoded
WAT and verified LLVM. Clang compiles the workers and runtime at `-O3`.
The observed x86-64 Linux result was:

```text
ok: 11 suspensions, 13 completed stacks, 29 collections
ok: --double-resume traps before transferring control
ok: --foreign-escape traps before transferring control
ok: --null-new traps before transferring control
ok: --null-resume traps before transferring control
ok: --unhandled traps before transferring control
ok: --foreign-unmatched traps before transferring control
ok: unsupported standard cont.bind fails explicitly
```

The exact collection count can change with collector versions. Checks cover:

- Normal completion and repeated suspension through fresh tokens.
- Two interleaved coroutines with collection while parked and after resumption.
- Nearest matching handlers, distinct handlers on one resume, and a nested
  nonmatching delimiter that captures both intervening stack segments. A later
  suspension exercises the preserved inner handler and a changed outer handler.
- Consumed-token and null-reference rejection, and an unmatched suspension.
- Foreign-boundary rejection and a fresh delimiter entirely above the boundary.

## Roots and ownership

A stack segment is a fixed 1 MiB traced GC allocation. Its saved registers also
live in traced memory. A continuation handle owns its outermost and innermost
segments; the segments between them retain their resumer links. Suspending cuts
only the outermost captured segment's link to its handler. Resuming consumes the
handle before switching, replaces that link, and enters the innermost segment.
Every alias sees the same consumed handle; another suspension creates a fresh
handle. There is no permanent global root for every parked stack, which would
retain unreachable continuation cycles.

The runtime changes BDWGC's active stack bottom under the collector lock. No
allocation or collection may occur between changing that bound and completing
the switch. While the original OS stack is parked, its live span is temporarily
registered as a root, starting at the actual x86-64 stack pointer minus the
SysV red zone. A local variable's address is not a safe lower bound for other
compiler spill slots. The prototype assumes one OS thread and no asynchronous
collection.

The worker keeps a box alive across suspension, collection, and resumption.
An opaque `observe` import forces its pointer to escape so LLVM cannot replace
the object with a scalar field. The import does not retain it. Optimized machine
code keeps the box pointer in `%rbx` across `native_cont_suspend`, calls the
collector after resuming, then reads the field from `8(%rbx)`. Thus the check
actually exercises a parked GC pointer, rather than just scalar arithmetic. Nine additional boxes stay on the parked
original OS context; optimized code holds five of their pointers in stack spill
slots. Each collection helper collects, allocates 50,000 same-sized boxes with
volatile payload overwrites, then collects again before checking live values.

The existing numeric translator suite still passes: 43 numeric/tail-call cases,
GC-root checks with actual reclamation, and structural-type/store-order checks.
Optimized Fibonacci LLVM is unchanged from before the continuation additions
apart from the input filename; the new runtime introduces no numeric-path calls.
This is a correctness feasibility test, not a continuation performance benchmark.

## Foreign calls and remaining limits

Foreign markers model active Rust calls. A fresh delimiter above a marker may
suspend and resume locally. Suspension crossing a marker traps before control
transfer. A fresh nonmatching child delimiter also traps when its search reaches the
marker. These tests do **not** run actual Rust frames, prove Rust unwinding,
or establish cancellation/destructor behavior. Rust's separate linear-memory
stack is not saved, restored, or rewritten by this experiment.

Only `i64 -> i64` continuation entries and control tags are supported, with at
most 64 tags in one module. `resume` handler payloads become ordinary LLVM
branches carrying the payload and token. Binaryen's folded multi-value block
expressions become LLVM aggregates; ordinary values still use native SSA.
Input must already be valid Wasm; this translator is not a general validator.

There is no `cont.bind`, `resume_throw`, `resume_throw_ref`, `switch`, exception
unwinding, multi-shot continuation, thread migration, stack growth, or guard
page support. A valid `cont.bind` fixture explicitly fails translation. Abandoned
stacks become eligible for conservative GC, but prompt reclamation and resource
finalization are not tested. Single-shot ownership does not justify skipping
Rust destructors. Browser engine execution of these continuation opcodes has
not been tested here.

## Focused simplification

An independent behavioral explanation confirmed that nulling a handle's root
and leaf is sufficient consumption state; a separate live flag is unnecessary.
A context's parent, handler mask, and result mailbox represent its one pending
resumer without another allocated wrapper. The review led to the actual-stack-
pointer root bound and the preserved-inner/changed-outer handler check above.
Lowering keeps event extraction separate from handler branch emission. Atomic
context transitions, structured block emission, and tests remain longer than
ten logic lines where splitting would hide their ordering invariants.
