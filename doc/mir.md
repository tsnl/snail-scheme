# Structured middle representation

This is the design contract for the HIR/MIR rewrite. The implementation uses
these boundaries; the benchmark report records the measured migration cost.

## Boundary and size

The pipeline is located syntax → HIR → MIR → LLVM. HIR remains the readable
result of macro expansion, with resolved binding identities. MIR makes the
implementation of Scheme explicit. There is no intervening stack bytecode or
generic optimization-pass framework.

Keep HIR binding identities and binding/capture analyses. Simplify blocks to
one ordered item list and resolve import modifiers entirely during expansion.
Replace the old instruction graph and instruction-handler generator. The LLVM writer should
know how to emit MIR, not how Scheme addition, closures, or assignment work.
The Scheme calling convention belongs beside HIR elaboration, separately from
the small representation and generic LLVM writer.

## Libraries organize both representations

`library.sld` owns three records: a library, a resolved import declaration, and
an exported/imported name attached to its original binding identity. An executable
script is an unnamed library. There is no separate program node. A library's
body is opaque to this module: expansion supplies HIR items, and elaboration
supplies a MIR body.

Each MIR body owns an initializer code identity, procedure/resumption definitions,
constants, global definitions, primitive registrations, and its share of root
local storage. A temporary elaboration context assigns global and constant slots
across the dependency graph. Lowering rebuilds imports to point at the new MIR
libraries, preserving source objects and binding identities. Repeated imports
and diamonds still initialize each dependency once.

Initializers transfer directly to the next library initializer on the existing
root frame. Only the entry script's final expression is in tail position.
LLVM emission concatenates the ordered bodies immediately before generating the
executable; this organization introduces no separate-compilation protocol.

```text
library (example counters)
  imports: resolved interfaces + original import syntax
  exports: counter -> binding #1
  HIR body: [bind #1 (lambda ...)]

            elaboration

library (example counters)
  imports/exports: same interfaces and identities, dependencies now MIR libraries
  MIR body:
    initializer: create closure; store into assigned global slot; transfer onward
    code:        counter entry, nested closure entry, resumption bodies
    constants:   owned constants in assigned slot order
```

## MIR vocabulary

MIR has five instruction forms: `if`, `call-direct`, `call-indirect`, `load`,
and `store`. An instruction is also its SSA value: operands refer directly to
producers, and dumps assign them numeric indices. There is no separate local,
copy, binding, or tail-call instruction. Constructors do not validate whole
programs; integration tests and LLVM verify signatures and dominance.

Ordered regions schedule instructions. `if` owns two regions and can produce
one joined value; LLVM supplies the blocks and phi node. Literals, machine
inputs, code references and C function addresses are operands. Representation
types are `word` (tagged 32-bit Scheme value), `i32`, `i1`, `ptr`, and `void`.
`never` describes a terminated path and has no machine representation.

Every call has an explicit convention and tail-position bit. A C call emits an
ordinary C ABI call, without implicit checks, conversions, argument rearrangement
or GC. A Scheme call transfers through the bounded dispatcher. Known code bodies
and foreign symbols use `call-direct`; computed code addresses and C function
pointers use `call-indirect`. Their calling conventions remain distinct even
though the instruction forms are shared.

Tag tests, integer extraction, machine arithmetic and pointer offsets are all
explicit calls to small Rust functions. Construction helpers such as `binop`
and `offset` produce those calls; they introduce no extra MIR opcode family.
The `let*` construction macro gives a Scheme name to a producer and anchors it
in a region. It creates neither a MIR binding nor another value object.

Shared terminal regions denote one continuation, not a request to copy the
remaining program into both branches. Emission preserves those joins. Region
result types are computed at construction, so determining whether a path ends
never recursively expands a shared suffix.

Code references are not C function pointers. The emitter assigns dispatcher
addresses to code objects. Every Scheme transfer uses the existing bounded
native-stack execution model, including on WASI. Temporaries belong to one body;
anything needed after a transfer must already be in explicit Scheme state.

A foreign descriptor contains symbol, argument types, result type, and a small
effect classification. `pure` means total and memory-independent. Reading heap
fields is a separate effect: `length` cannot be reused across `set-cdr!` merely
because it does not mutate. Existing runtime allocation-boundary services are
explicitly distinguished from leaf callables, which never collect internally.
No effect inference or check elimination is required for this milestone.

`load` and `store` accept an optional proven memory region, `state` or `external`.
The latter covers separately allocated stack, global/constant vectors, and heap
fields. Elaboration supplies these facts; the emitter attaches LLVM alias scopes.
Unclassified accesses and foreign calls stay conservative. The facts concern live
storage, so a stack resize still invalidates old addresses. VM and its interior
State are never declared disjoint. No new MIR instruction or provenance analysis
is involved.

Direct signed31 integer, boolean, character and nil literals become immediate
tagged words. An omitted `if` alternate produces the unspecified word. The machine
module owns these encodings; lowering retains the pool for other literals and for
children of pooled pairs/vectors, whose initialization still uses pool indices.

## Example: a numeric conditional

These are readable notations; names with suffixes denote binding identities.

```scheme
;; Scheme
(define (small? n) (< n 2))

;; HIR
(bind small?#1
  (lambda (n#2)
    (call (ref core:<) (ref n#2) (literal 2))))
```

MIR publishes evaluated operands in Scheme slots, then expresses the fast path:

```scheme
(let ((left (load word left-slot))
      (right (load word right-slot)))
  (if (both (call-direct fixnum? left)
            (call-direct fixnum? right))
      (let ((x (call-direct fixnum->i32 left))
            (y (call-direct fixnum->i32 right)))
        (store (call-direct boolean->word (i32.< x y)) result-slot))
      (call-direct numeric-fallback vm core:<-index))
  (tail-call return-code))
```

The actual elaboration also updates result count and stack depth and handles
stopped/error state. Arithmetic must preserve overflow and boxed-number behavior.
No speculative fixnum assumption follows from the absence of inference.

## Example: capture and mutation

```scheme
;; Scheme
(define (counter n)
  (lambda () (set! n (+ n 1)) n))

;; HIR
(bind counter#1
  (lambda (n#2)
    (lambda ()
      (sequence
        (set! n#2 (call (ref core:+) (ref n#2) (literal 1)))
        (ref n#2)))))
```

Elaboration retains one cell for `n#2`. The outer body publishes that cell as a
capture and calls the closure-allocation service with an inner code reference.
The inner body explicitly loads the cell, computes the new value, and stores it.
There is no closure-construction or assignment opcode in MIR.

All assigned lexical bindings remain cells, even without a nested lambda:
restoring a copied continuation must not roll back mutation. Immutable captures
remain ordinary values. Recursive initialization retains the existing boxing
rules and uninitialized-value errors.

## Example: foreign calls

```scheme
(foreign add "example_add" (i32 i32) i32 pure)
(call-direct add x y)
(call-indirect add function-pointer x y)
```

Neither call validates Scheme values. Packing, unpacking, checks and errors are
separate operations. The `snail-abi` attribute macro produces a stable `extern "C"`
wrapper around an ordinary fixed-signature scalar Rust function; a descriptor makes its ABI visible
to the Scheme compiler. The prototype uses explicit descriptors and a narrow
wrapper contract rather than inventing Cargo reflection or an extension registry.

## Lifetime and control invariants

* Operands retain the existing evaluation order and single-value checks.
* A non-tail Scheme call saves a code-body reference and the caller's frame.
  The resumed body reloads its inputs from explicit state. A tail call reuses
  the existing return frame.
* Snapshot continuations copy stack state and preserve shared heap cells.
* Publish every live managed value before a potentially collecting service.
  Leaf Rust callables never collect; allocation permission is acquired outside
  their body. Publish returned values before the next safepoint.
* Load a source before a service can resize the Scheme stack. Do not retain
  native pointers into that stack across a resize or in a continuation.
* VM and State pointers can overlap. No `noalias` promises are attached to them.
* Foreign functions are synchronous and do not reenter Scheme in this milestone.

## Acceptance

Run native and WASI semantics, errors, mutation, multiple-value and reusable
continuation tests, including GC stress. Exercise genuinely indirect C calls,
not just a constant function pointer optimized into a direct call. Validate
packing/extraction at fixnum boundaries and an allocating call with live roots.

Compare old and new backends under matched optimized build settings, retaining
ordinary-link and shared-LTO controls. Tiny Rust conversion calls must disappear
in the optimized artifact. Report runtime separately from compilation and keep
the Chibi and Chez controls. Ordinary linking remains a correctness path; its
performance is measured rather than assumed equivalent to shared LTO.

The [matched runtime report](../benchmarks/results/2026-10-10-mir.json) uses
64 Fibonacci repetitions, eight rotating rounds, and CPU 2 affinity. Shared-LTO
MIR takes 0.334274 s versus 0.392260 s for the previous shared-LTO backend,
0.461500 s for Chibi, and 0.0298735 s for Chez. That is 14.8% less time than the
matched backend, 0.7243× Chibi's time, and 11.19× Chez's. Compilation, process
startup, and printing are excluded. Every sample checks the same result.
Ordinary linking takes 5.503267 s: shared LTO is essential to this decomposition,
and optimized CLI builds enable it by default.

These are Fibonacci results, not evidence that arbitrary programs share those
ratios. No occurrence typing or general check-elision pass has been introduced.

The [memory follow-up](../benchmarks/results/2026-10-10-mir-memory.json) compares
immediate literals and scoped alias annotations against this committed checkpoint
in eight rotating CPU2 rounds of 64 repetitions. The final implementation takes
0.318272 s versus 0.336965 s: 5.5% less time, 0.6874× Chibi and 10.58× Chez.
Scratch ablations retained in the report isolate alias information, immediate
constants, cold fallback hints, and direct dispatcher edges. Cold hints and direct
edges did not improve this workload; a finer memory partition produced the same
binary. These results support the small memory changes, not a predicted 2–5× gain.

The sampled checkpoint spends 86.63% in generated code and 13.36% in procedure-call
preparation; its 64-repeat run records zero collections. Hot assembly still has
substantial stack/register-state traffic. SSA argument/result retention is a future
experiment, preserving root publication and continuation snapshots. Chez also has
an enabled-by-default [type recovery pass](https://cisco.github.io/ChezScheme/csug10.0/system.html)
that removes redundant checks; safe optimization mode does not retain every check.

The memory follow-up passes 72 native/WASI ordinary/shared-LTO executions under
GC stress, plus unit/format checks and full compiler-source LLVM verification.
Compiled-compiler execution was validated at the preceding MIR checkpoint and
was not repeated for this follow-up.

## HIR rule review

HIR has seven expression forms: name, literal, application, lambda, block,
conditional, and assignment. Value binding is a separate initialization item.
Library containers live in `library.sld`, independently of either body grammar. A block now holds one
ordered nonempty item list; its last expression supplies the result.

Initialization and mutation deliberately remain distinct. Combining them would
move the distinction into a mode bit while making recursive initialization and
assignment-cell analysis harder to see. Replacing a block with a lambda call
would introduce runtime machinery and change its multiple-value behavior.

Resolved imports store library dependencies and named bindings directly, with
original located syntax retained for diagnostics. Import modifier trees disappear
after expansion, including their five-way backend dispatch. Empty binding sets
still retain their library dependency. No sequencing-by-application or assignment
mode flag is introduced just to reduce the grammar count.

## Simplification review

Independent behavioral reviews checked the instruction vocabulary, shared control
joins, library ownership, foreign-call contract, and incremental LLVM output.
The resulting code removes import-modifier trees, the separate program container,
the old instruction graph, and instruction-handler generation. LLVM serialization
releases each completed code body's temporary objects while retaining only the
dispatcher edges; the emitted benchmark LLVM remains byte-identical.

The remaining caches serve distinct correctness requirements: producer availability
preserves SSA dominance, and terminal-region sharing preserves control joins without
duplicating whole continuations. Combining them loses that distinction. No additional
IR form or generic pass framework is needed. Functions exceeding the ten-line target
are cohesive dispatches, graph/pipeline traversals, ABI validation and generation, or
tests; splitting these into forwarding helpers would obscure their contracts. The
review stopped after these invariants were explicit and the native/WASI checks passed.
