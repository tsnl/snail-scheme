# Complete compiler port: source contract and foundations

The complete compiler workload is still being adapted. The files described here
establish concrete storage and the compiler's error-only escape protocol. They
do **not** emit a complete typed compiler kernel, add `compiler` to the measured
strict suite, or establish canonical benchmark correctness or a speedup.

## Source and input extent

The corpus revision is `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`.

| Input | Preserved extent | SHA-256 |
| --- | --- | --- |
| `src/compiler.scm` | 459,221 bytes; 11,198 lines; 1,344 definitions and one import | `e4444c65d55712d7141f147661efcc744df5e4b5699bbbf73b27d16eaf441209` |
| `inputs/compiler.input` | 8,377 bytes; five datums | `baba2d35f2c354ccd96dc3d1797bf2bc164f6f94884b9c9cad50419f791e6105` |

The input requests 2,000 compilations of the complete supplied Scheme program,
target `m68000`, option `asm`, and compares the full ordered list of 497 assembly
strings. The program includes all supplied fib, tak, ack and list-processing
definitions and calls. No input or oracle is shortened.

`compiler_port.py` scans complete top-level forms, including parenthesis character
literals and quoted forms. `kernel` removes only the import and `run-benchmark`
forms, wherever they occur. Every other byte remains; definitions following a
harness would remain too. In this pinned file the harness actually is the final
form. The retained source inventory records each form's name, line, byte range
and hash. This extent check does not mean every definition is already typed.

## Required mapping

The source-wide form inventory and representation/call-site audit identify these
subjects. The original passes and their control flow must remain in the port.

| Source area | Concrete adaptation |
| --- | --- |
| Utilities, ordered list sets, queues and graph algorithms | Rank-one helpers; mutable list links; separately typed association entries; explicit identity operations. Preserve traversal, prefix copying, suffix sharing and source set algorithms. |
| Located reader and expression conversion | Closed source-code and list-spine cases, including improper tails and located vector elements. Literal data stays in `Datum`. Keep the original reader algorithm. |
| Environments and parse nodes | Shared variable-list roots; separate macro and declaration lists; ten closed node kinds; mutable parent, child, free-cache and source fields. |
| Parsing, partial evaluation, assignment conversion and lambda lifting | Original pass bodies over those records, with explicit mutations and abort propagation. |
| Virtual operands, frames, procedures and blocks | Preserve the encoded integer operands and operand-interning search; give table entries closed cases. Typed frame/block/instruction records retain all GVM, closure and slot passes. |
| Target and primitive callbacks | Fixed signatures for beginning/dumping, primitive lookup/specialization, apply generators, branch generators, counters and deferred-code thunks. Procedures never enter a universal data box. |
| Assembly and object dumping | Closed instruction/directive shapes with shared label cells. Retain branch tensioning, relocation, object queues and all exact, rational, inexact and complex dumping paths. |
| Diagnostics and compiler abort | Explicit typed normal/abort results across every intervening abort-capable call and callback. Only the handler boundary consumes an abort. |

Several source functions use `apply` for list/set or string folds, one fixed
seven-argument primitive constructor, macro calls and diagnostic forwarding.
Those require explicit typed folds or fixed positional calls. They do not justify
an arbitrary-arity boxed call path. The source's `scheme-global-eval` already
raises `"scheme-global-eval is no more"`; the port must retain that behavior.

The first data module covers mutable pairs, located syntax, lexical identities,
environments and parse-tree nodes. It is not yet a complete schema for GVM and
assembly records. For example, temporary-variable names include numeric positions
as well as symbols and the anonymous sentinel; optional fields and uninitialized
source-vector elements have explicit cases instead of fabricated valid values.

## Error escape contract

The only executable `call-with-current-continuation` occurs in
`with-exception-handling` at source line 184. Its only call is in `compile-program`
at line 4838, around a Boolean-returning compiler body. The saved handler is only
installed, restored, and invoked by `compiler-abort` with `#f`. No source path
exposes it, resumes it, or invokes it with another value.

`compiler-result.scm` represents normal completion as `CompilerResult T` carrying
`T`, and abort as a distinct empty case. Every abort-capable expression must be
matched before its enclosing operation or next effect executes. A successful
`#f` remains an ordinary result. The scope saves one global active-handler bit,
sets it, calls its action, restores the saved bit, and then either returns the
normal Boolean or consumes abort as `#f`. Nested scopes therefore restore the
outer scope before returning.

Earlier diagnostics and mutations survive abort; later effects do not run.
There is no rollback, general exception framework, or replacement trap for a
caught compiler abort. Abort outside any installed scope retains the fatal
no-handler diagnostic. Ordinary host primitive failure escapes before source
restoration executes, matching the absence of `dynamic-wind` in the source.
Host recovery followed by invoking a stale captured continuation is not a path
in this audited compiler program; the adaptation does not claim to implement
general first-class continuations.

The result constructors and propagation checks add representation and control
work. The same adapted bodies run under Chez so this cost is visible in the
future original-versus-adapted comparison. No timing claim follows from these
small internal probes.

## Identity, ordering and numerical differences

Each mutable field has an explicit `Ref`. Fresh designated field cells establish
record identity; aliases retain those cells when values change. This changes the
allocation layout from the original mutable vectors/pairs and avoids rebuilding
an entire record for a setter. It does not make every setter allocation-free:
constructing a new optional parent value can still allocate.

Changing children follows the source order: publish the new child list, assign
each child's parent, then invalidate this node and its ancestors. Removed children
keep their old parent link. Invalid free-variable caches and valid empty caches
are distinct. Environment versions share the variable-list root; no extra identity
cell is added for environments because the audited source does not compare their
wrapper identity.

The typed `compiler-map` invokes callbacks left to right and reads the current
tail after each callback. R7RS does not specify `map` callback order. An original
Chez diagnostic with input `(1 2 3)` observed callback trace `312`; when the callback
for `1` replaced the input tail with `(4 5)`, Chez still produced `(1 2 3)`.
The typed helper instead observes `145` and produces `(1 4 5)`. The adapter must
use this identical typed helper under Chez and audit the real compiler callbacks
for dependencies on the unspecified order. This is a stated ordering choice,
not a claim that the original Chez order was preserved. Explicit `begin` and
`let*` sequencing must remain unchanged.

The current foundation probes use Boolean literal data and bounded position
indices. They establish no numeric-domain coverage. Existing `(snail integer)`
provides arbitrary exact integers, but the base Datum reader accepts only I64
exact scalars, F64 inexact scalars and their rectangular combinations. Separate
numeric-library work is supplying arbitrary integer/F64 conversion, normalized
rationals and the expanded Number/Datum reader domain.

The full port must preserve `dump-bignum`'s base-16384 algorithm, rational
numerator/denominator dumping, complex components, the original floating
exponential-format algorithm and its exact mantissa conversion. In particular,
`flonum-sign-bit` is the exact integer 9223372036854775808. Replacing these paths
with bounded integers or precomputed bit output is not an accepted adaptation.

## Checks and remaining work

Run `python3 tests/strict-compiler/check.py --runtime PATH --output NEW_DIRECTORY`
with a compatible real runtime artifact. The checker reuses the reviewed
process-group supervisor in `scripts/test-strict-integer`; it retains command
outputs and kills/drains every executing descendant on failure or timeout.
An existing output directory is rejected rather than overwritten.

The [retained checks](../results/2026-10-14-strict-compiler-foundation/checks.json)
include all initial failed and successful preparation records, final four-target
checks and the added argument-abort check. The
[source inventory](../results/2026-10-14-strict-compiler-foundation/source-inventory.json)
contains every original form and the complete input specification. These are
diagnostic evidence, with no clean performance samples.

The [integration checks](../results/2026-10-14-strict-compiler-foundation/integration-checks.json)
rerun the complete foundation checker on the current stack after normalizing four
Scheme fixtures with the repository formatter. They retain current source hashes,
runtime identity and all execution results separately from the original checks;
the original source hashes and earlier failures remain unchanged.

The checker saves the complete original source/input and form inventory. It runs
the unchanged original continuation helpers under Chez as a control, then runs
identical adapted bodies on Chez, linked raw diagnostic Wasm, mandatory-Binaryen
linked Wasm and actual native64. Positive fixtures check sharing, cycles,
callback order, environment aliases, parent/cache updates, callback failure after
mutation, nesting and successful false. Separate negative fixtures require the
expected diagnostics for ordinary host failure and abort outside a handler.
The argument-abort probe additionally checks that an enclosing sink is never
entered after evaluation of its sole argument aborts.

Initial failures are retained: the first Wasm run used the pure-module harness
against a module requiring the real scalar runtime, and the first Chez run found
that the shared `define-data` macro rejected a generic type header. The real linked
runtime corrected the harness issue; commit `ad29d5d` fixes the macro's syntax
context without changing its representation.

The pinned simplify pass used independent Astra/max explainers with no files or
history. The data critique retained field-cell identity, rejected unnecessary
environment identity and separated the source-list spine from general code.
The error critique independently derived normal/abort status and one active bit,
rejected per-call control-record plumbing, and added the argument-abort probe.
Data definitions and coherent integration tests exceed the ten-line function
target where splitting would hide their contract; production helpers remain
small. No backend/frontend restructuring was needed for these foundations.

Remaining work includes the complete typed source adaptation, all callback/effect
sites, full numeric integration, original and exact-adapted Chez controls, the
unchanged complete Rust compiler reference, canonical 2,000-compile correctness
on every target, and only then an explicitly released clean measurement window.
