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

## Complete external-operation inventory

A lexical audit of all 1,345 top-level forms finds 108 external names and 4,580
references, including primitives passed as values. It accounts for function
parameters, internal definitions, named loops, binding scopes and quoted data;
quoted primitive descriptions are not calls made by the compiler. The retained
`compiler-operator-audit/references.json` records each name, containing top-level
definition, source line, byte offset and operator/value role. Its adjacent
`audit.py` is a source-specific audit, not a new compiler or measurement layer.
The following groups cover that complete name set. Paths and line numbers in
this section refer to the unchanged pinned
`benchmarks/r7rs-benchmarks/src/compiler.scm`.

| Group | Complete external names | Existing boundary or required adaptation |
| --- | --- | --- |
| Arithmetic and comparison | `+`, `-`, `*`, `/`, `<`, `<=`, `=`, `>`, `>=`, `quotient`, `remainder`, `abs`, `min`, `max`, `even?`, `odd?`, `zero?`, `negative?` | `(snail strict)` supplies bounded scalar operators; `(snail integer)` and `(snail number)` supply exact and general numeric operations. Unary/n-ary calls and `apply min/max` require explicit typed operations/folds. Operand/position arithmetic is distinct from arbitrary exact literal arithmetic. |
| Numeric domain and conversion | `number?`, `integer?`, `rational?`, `exact-integer?`, `exact?`, `inexact?`, `exact`, `inexact`, `truncate`, `real-part`, `imag-part`, `numerator`, `denominator`, `number->string`, `string->number` | Concrete Number/Datum tests and named operations. Numeric reader results distinguish invalid syntax, diagnostics and a number. Numeric constants require explicit construction when their storage is Number or Integer. |
| Lists and association tables | `append`, `assoc`, `assq`, `assv`, `caar`, `cadddr`, `caddr`, `cadr`, `car`, `cdadr`, `cdar`, `cdddr`, `cddr`, `cdr`, `cons`, `for-each`, `length`, `list`, `list-ref`, `map`, `memq`, `memv`, `null?`, `pair?`, `reverse`, `set-car!`, `set-cdr!` | Mutable homogeneous list spines and separately typed dotted entries; fixed equality callbacks; direct fields for records. Lookup returns the matching entry/tail or explicit absence, preserving index zero and suffix identity. Fallible callbacks propagate CompilerResult before later traversal. |
| Vectors | `make-vector`, `vector`, `vector-length`, `vector-ref`, `vector-set!`, `vector?` | Homogeneous native storage for actual arrays; typed records/closed cases for heterogeneous vectors. Explicit uninitialized cases retain construction state where no valid element exists yet. |
| Characters, text and symbols | `char->integer`, `integer->char`, `char=?`, `char?`, `char-alphabetic?`, `char-downcase`, `char-numeric?`, `char-whitespace?`, `make-string`, `string`, `string->symbol`, `symbol->string`, `string-append`, `string-length`, `string-ref`, `string-set!`, `string<?`, `string=?`, `string?`, `symbol?` | Existing scalar characters, native Unicode strings and interned Symbol. Unicode classification/downcase and lexical string comparison need the narrow reusable layer listed below. Explicit Datum cases supply heterogeneous type tests. |
| Truth and equality | `not`, `eq?`, `eqv?`, `equal?` | Bool control, explicit optional/value cases, designated mutable-field identity, symbol identity and Number equivalence. Structural metadata comparison at line 8575 remains distinct from identity. The final harness compares the whole output list at line 11198. |
| Ports, reading and output | `open-input-file`, `close-input-port`, `open-output-file`, `close-output-port`, `current-output-port`, `read-char`, `peek-char`, `eof-object?`, `read`, `write`, `write-char`, `display`, `newline` | `(snail io)`, `(snail read)` and the separate `(snail write)` prerequisite. Character/end-of-file and optional ports use explicit cases. The five top-level `read` calls at lines 11185–11189 configure the original full workload; the located reader at lines 545–695 retains its own algorithm. |
| Calling and failure | `apply`, `call-with-current-continuation`, `error` | Fixed positional calls and typed folds; the audited error-only escape becomes CompilerResult propagation. Ordinary host primitive failures remain outside that escape. `scheme-global-eval` at line 69 retains its existing fatal failure. |
| Benchmark harness | `hide`, `run-r7rs-benchmark` | Existing suite barriers/driver, preserving the three hidden inputs and the complete result predicate. No language runtime feature is inferred from these harness names. |

The reusable text-library boundary has concrete callers:

| Operation | Exact compiler callers | Reusable implementation boundary |
| --- | --- | --- |
| `char-downcase` | `string->canonical-symbol`:353; `read-source`:598, 602, 633 | Expose Unicode simple lowercase, reusing `src/unicode.rs::lowercase` and its pinned Unicode case exceptions. Do not use full string lowercase or an ASCII-only table. |
| `char-alphabetic?` | `read-source`:639; `build-c-procedure`:1697; `scheme-id->c-id`:1845 | A scalar character predicate. The older boxed runtime's implementation in `src/lib.rs` is not a strict scalar API. |
| `char-numeric?` | `scheme-id->c-id`:1845 | Decimal-digit classification, reusing the Unicode digit semantics in `src/unicode.rs::digit_value`. |
| `char-whitespace?` | `valid-module-name?`:4864 | Existing strict reader scalar service `snail:datum/whitespace` is private; expose the same classification through a cohesive character library. |
| `string<?` | `sort-variables`:5430 | Ordinary lexicographic Unicode-scalar comparison in Scheme, including prefix ordering. No locale or byte-order substitution. |

The separate prerequisite `2035bc2` implements these five operations in
`(snail text)` and has its own target checks. The collection checks here use the
writer prerequisite only. A future compiler build importing both libraries must
build their combined runtime; neither standalone runtime supplies both sets of
new scalar exports.

The located reader indexes its own 256-entry `read-table` at lines 552, 561 and
616. That source restriction must remain visible: providing Unicode character
operations does not authorize changing this reader algorithm or silently making
its table accept every scalar. Conversely, canonical symbol conversion and C
name handling must not acquire an extra ASCII restriction. File opening retains
the host primitive failure behavior of the original R7RS `open-input-file` alias
at line 50; the source's subsequent false-port branch does not justify catching
ordinary file errors as compiler aborts.

The I/O prerequisite owns default/explicit output, stable current-output identity,
and all Datum variants, including graph-aware diagnostic writing. The adapter
must additionally project its concrete records into an explicit diagnostic view:
parse-node graphs can cycle through parent/child links, and procedure records
can contain fixed typed callbacks. Callback values must not be hidden in a
universal evaluator box merely to print a diagnostic. Their opaque printed
representation is an explicit target difference to settle with the complete
record audit; dropping the diagnostic argument is not an accepted mapping.

## Source-derived collections

`compiler-collections.scm` declares the concrete storage and fixed callback
contracts for 41 complete upstream utility, list-set, graph and queue functions.
`collection_adaptation` changes those exact forms in the complete source and
records every counted edit. Reversing the ledger restores every original byte;
the remaining forms are still present and are not yet typed. Three complete
diagnostic functions similarly retain their ordered newline, text, spaces and
argument-writing work before returning the explicit compiler abort.

List lookup returns the matching tail or entry, preserving index zero, duplicate
keys and mutable association-value aliases. Pair-up stops when its left list
ends and returns dotted rows; an exhausted right list remains an ordinary host
failure. The alternating merge sort retains its split, recursive-call and
equal-key choice order, including sharing a singleton tail. Removal copies the
prefix and shares the suffix after a hit; a miss copies the whole list. Union
keeps duplicates from its first input when absent in its second, and its n-ary
fold retains the original operand orientation. It is not a mathematical set
replacement.

Graph closure computes each round from the previous graph and allocates fresh
wrappers even on the converged round. Variable labels and graph wrappers have
separate identities. Grouping retains the original no-edge/cycle selection and
ordered occurrence-set operations. Queues retain their stored last link. Two
wrappers sharing that link can overwrite each other's appended tail; later
appends may mutate a detached tail. The port does not rescan or repair that
source behavior. Dequeuing the final item clears that wrapper's head and tail.

Fallible collection callbacks use explicit CompilerResult propagation before
later callbacks, tail reads or payload rereads. Pure identity and sort callbacks
stay pure. The chosen callback order is left to right under both typed targets
and the exact adapted Chez control. A separate complete-source experiment
renames all 72 executable `map` calls to that helper, then additionally sequences
`set-map` and `set-keep` heads before recursion. All three original/chosen-order
Chez controls pass the unchanged 2,000-compilation, 497-line canonical predicate.
This isolates those ordering choices; it does not establish a complete typed
compiler port. Actual set callbacks inspect graph/variable metadata and cached
free variables, without mutating their traversed list spines.

The list-to-vector adaptation allocates a concrete default from the first item
for a nonempty vector, then retains the original complete fill loop. This adds
one head read and initialized storage work. Empty vectors use the ordinary empty
constructor. The same adaptation is executed by Chez, so these representation
costs remain visible.

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
indices. They establish no numeric-domain coverage. The separate numeric-library
prerequisite `6925f1c` supplies arbitrary integer/F64 conversion, normalized
rationals and the expanded Number/Datum reader domain. The checks below exercise
its shared bodies under Chez; adapting every compiler numeric call is still
part of the unfinished complete port.

The full port must preserve `dump-bignum`'s base-16384 algorithm, rational
numerator/denominator dumping, complex components, the original floating
exponential-format algorithm and its exact mantissa conversion. In particular,
`flonum-sign-bit` is the exact integer 9223372036854775808. Replacing these paths
with bounded integers or precomputed bit output is not an accepted adaptation.

## Adapted Chez numeric boundary

The expanded reader control in `reader_ports.py` and `chez-number.scm` depends
on numeric-library commit `6925f1c`. It places the
unchanged Integer, Rational, Number, Datum and reader bodies in separate lexical
scopes, exposing each library's concrete public operations. Static annotations
and overload declarations are erased. The one- and two-argument string-to-number
entry points call the same named radix parser. Other adapted kernel operations
must call the named numeric functions when Chez cannot resolve a static overload.

Only the scalar service boundary differs. Chez stages text in an owned handle,
classifies it once, and exposes the corresponding machine integer, binary64,
exact digit fields, rectangular components, polar components, or diagnostic.
Invalid syntax is distinct from a numeric diagnostic. A left diagnostic stops
component parsing; an invalid left component still allows the right component's
diagnostic to win. The Scheme bodies retain exact normalization, promotion,
complex shape rules and every arbitrary-precision arithmetic operation.

Exact decimal syntax is checked completely before zero normalization or scale
conversion. The effective decimal scale, exponent minus fractional places, must
fit `[-I64_MAX, I64_MAX]`. An exponent just above I64_MAX can therefore succeed
when fractional places bring the scale into range. Chez bounds the digit scan
using that final range; its bounded index intermediates are not substituted for
Scheme Integer or Rational values. The matching Rust parser uses an i128 index
intermediate and checks the same final scale.

Closing and interning consume their handles. Repeated parsing also consumes the
handle before rejecting it, matching the scalar runtime. Accessors check the
requested component kind. The source representation is explicit: Chez uses host
vectors for temporary handles and the typed Scheme records, while Snail uses
runtime IDs for scalar tokens and its own concrete storage for Scheme data.

The fresh simplify explanation and subsequent critique were performed by a
no-history, no-files Astra/max agent. They retained lexical descriptors, one
cached classification, owned token state and private library scopes; rejected
host arbitrary-precision arithmetic as a replacement for the shared Scheme
bodies; and replaced exact-decimal float validation with a direct grammar check.
The review also rejected a premature claim that Chez and Rust choose identical
shortest binary64 digits. Formatting uses the target's decimal/exponent layout.
An exact byte comparison of 20,084 binary64 patterns now passes, including signed
zero, subnormal and normal boundaries, exponent-layout transitions, neighbors
of selected powers of ten, infinities, NaNs and 20,000 seeded random bit patterns.
That corpus supports compatibility on those cases; it is not an exhaustive
proof for every binary64 value. Chez's subnormal precision suffix is removed
before interpreting the decimal exponent.

The [numeric bridge evidence](../results/2026-10-14-chez-numeric-bridge/README.md)
retains 278 shared Number contracts and 20,135 scalar ABI cases under Chez,
linked raw diagnostic Wasm, mandatory-Binaryen linked Wasm and actual native64.
Thirteen invalid operations each run in a fresh guest process because Rust ABI
failures terminate the process. Separate Chez-only checks observe handle
consumption after locally caught errors; they make no guest recovery claim.
All 36 complete reader streams match the independent Chez reader. Regenerated
original/adapted Chez controls also pass complete canonical Sum1 (25), Read1
(2,500) and Parsing (2,500) with their original result predicates. These are
correctness diagnostics, with no clean timing or compiler-workload coverage.

## Adapted Chez output boundary

`chez_output_program` adds a separate invocation scope for the unchanged I/O and
Datum writer bodies. The existing reader-control generator remains byte for
byte unchanged for its previous inputs. Each typed library keeps its private
definitions; erased default/explicit output overloads call the exact named
Scheme bodies. Datum traversal, graph labelling and numeric formatting remain
in those bodies, never Chez's native Datum printer.

`chez-io.scm` implements only scalar file services. Issued IDs are never reused;
failed opens consume an ID, and exhaustion precedes file creation/truncation.
Each consuming operation takes its staged pathname even on failure. Binary
input preserves BOM, NUL and separate CR/LF scalars and validates complete UTF-8
sequences. One lookahead distinguishes absent, scalar zero and EOF. Reads consume
that cache, including EOF. Invalid UTF-8 remains an ordinary terminal host
failure; it does not enter the compiler's abort handler.

Stdout is one borrowed binary stream at reserved ID -2. Every scalar write flushes
it, and closing it does nothing. Owned files detach before close; invocation
cleanup releases the remaining files in issue order and preserves the original
failure. A concrete `/dev/full` probe established that Chez keeps its descriptor
open after a failed buffered close. The bridge retries pending output once,
then discards failed buffered bytes and closes before propagating the first
error. This follows the Rust provider's explicit close followed by buffered-port
drop, without swallowing the failure. Platform error wording and allocation/
buffer implementation remain host properties; these are correctness controls,
not claims of identical host costs.

The bridge runs the existing complete writer fixture: 68 exact write/display
rows and round trips, eight graph rows, depth 8,192, borrowed stdout/default
overloads, and six independent terminal failures. A separate scalar diagnostic
checks lookahead, ID/path transitions, cleanup ordering and actual descriptor
release. Eighteen malformed UTF-8 cases each use a fresh process and verify
preceding stdout plus pending-file cleanup. Locally caught provider conditions
serve only to inspect ownership transitions; they do not imply guest recovery.

The focused simplify pass obtained a fresh Astra/max model without files or
history, then completed informed critique. It retained one owner per issued ID,
an explicit lookahead and a synchronous pathname transfer, and rejected native
text-port transcoding and host Datum printing. The descriptor probe settled the
remaining close-failure question. The UTF-8 decoder, fixed ABI dispatch and
integration checks are coherent exceptions to the ten-line function target.

## Checks and remaining work

Run `python3 tests/strict-compiler/check.py --runtime PATH --output NEW_DIRECTORY`
with a compatible real runtime artifact. The checker reuses the reviewed
process-group supervisor in `scripts/test-strict-integer`; it retains command
outputs and kills/drains every executing descendant on failure or timeout.
An existing output directory is rejected rather than overwritten.

Add `--collections` for the source-derived collection checks. Use
`--chez-output` instead of `--runtime` for the exact shared writer and scalar
boundary controls, or `--map-order` for the complete original/chosen-order
compiler experiment. All are correctness diagnostics with retained failures;
none starts a clean measurement.

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
