# Typing, check elimination, and i32 specialization

This describes the implemented checker and optimizations, developed from the
measured WasmGC backend at `ed2ad32d0bdc46601d11aa6af6013ba35dd729f5`. The broader
[design](occurrence-typing.md) and [declarative rules](typing-rules.md) include
features that remain unimplemented. This report describes the narrower current
contract. Chibi bootstraps the compiler; the native CLI also hosts it.

## Source interface

```scheme
(import (scheme base) (snail typing))

(: measure (-> (U String ExactInteger) ExactInteger))
(define (measure value)
  (if (string? value) (string-length value) (+ value 1)))

(define-record-type <point>
  (make-point y x) point?
  (x : ExactInteger point-x set-point-x!)
  (y : String point-y))

(: point-measure (-> (U String <point>) ExactInteger))
(define (point-measure value)
  (if (point? value) (point-x value) (string-length value)))

(: checked-length (-> Any ExactInteger))
(define (checked-length value)
  (string-length (ann value String)))
```

`:` associates a type with a resolved definition. `ann` checks an expression;
it also supports explicit shallow assertions from `Any`. Type names and syntax
have binding identities, so import renaming and shadowing behave like other
syntax. Field order in a constructor need not match declaration order.

The type vocabulary is `?`, `Any`, `Never`, `False`, `True`, `Boolean`, `Null`,
`ExactInteger`, `InexactReal`, `Number`, `String`, `Symbol`, `Char`, `Pair`,
`Vector`, `Bytevector`, `Procedure`, `Record`, `Unspecified`, `i32`, nominal
record names, `(U ...)`, fixed-arity `(-> argument ... result)` signatures, and
rank-one `(All (variable ...) (-> argument ... result))` signatures.
Unions are structural and normalized; equal-shaped records remain nominally
distinct. `?` admits supported checked dynamic interactions. `Any` requires
narrowing or an explicit assertion before a specific operation. `Procedure`
permits a dynamically checked call without asserting a particular arrow type.

Checking is bidirectional within this small language: a declaration or `ann`
supplies parameter and result types to a lambda, while literals, references,
calls, and conditionals synthesize information. Ordinary unannotated functions
have dynamic parameters; the analysis can still discover result facts and
predicate summaries. Immediate lambda applications, including expanded `let`,
can use their actual argument facts. Escaping functions do not inherit facts
from an arbitrary caller. There is no general unification or automatic
polymorphic generalization.

Function signatures require a checked lambda or a view of an existing checked
implementation, with shallow domains and results. Reassigning a
signature-bearing binding is unsupported. Unknown callers
enter through an adapter that checks arity and the
declared parameter types. Writes to declared bindings are checked against the
storage type; results are checked against the declared result. Annotated
functions require exactly one ordinary result. Opaque arrow casts, higher-order
arrow domains, variadic typed signatures, parameterized records,
and typed local generative records are diagnosed as unsupported. Arrow subtyping
is also outside this implementation.

## Rank-one polymorphism

```scheme
(: identity (All (A) (-> A A)))
(define (identity x) x)
(identity "text")                        ; infer String
(identity #f)                            ; a separate instance

(: text-id (-> String String))
(define text-id (inst identity String))   ; stored callable view
(eq? identity text-id)                   ; #t: no wrapper allocation

(: checked-id (-> ? String))
(define (checked-id x) (identity x))      ; infer String from the result context
```

The body is checked once with fresh rigid variables. Returning the original
`x : A` is valid; returning an arbitrary string as `A` is rejected. Binders scope
the `All` type expression. There is no implicit generalization, higher-rank
argument, or type-variable name introduced into the separately written body.
Imported, renamed, and macro-generated signatures retain their binding identities.

Each use gets independent constraints. Arguments provide lower bounds, and an
expected result provides upper bounds. Repeated variables can infer a structural
union: `All A. Boolean × A × A → A` accepts string and Boolean alternatives.
Every substitution is checked against the complete signature. A dynamic `?`
argument alone provides no solution; unresolved or ambiguous inference reports
the source location and asks for `inst`. Explicit `(inst identity ?)` expresses
an intentionally dynamic instance. Instantiation arguments remain shallow;
arrows and nested `All` are rejected.

Instances are static views of the same procedure value. Calls through a known
view evaluate operands and the operator, then enforce any unproved concrete
domains before entering the body. The generic entry itself enforces every
concrete slot and normalizes all parameter counts, with abstract variables
erased to `Any`. An opaque route such as `apply` uses that erased interface;
its result has no instantiated guarantee. For example, untyped
`(apply (inst identity String) (list 42))` returns 42, and a surrounding checked
String result rejects it. This is the supported shallow gradual boundary;
instantiation does not install a higher-order runtime contract.

A strengthening from `?` to erased `A` cannot be checked and is rejected.
This includes unknown callback results and writes into abstract typed slots.
Mutable unannotated locals lose inferred precision, so copying an `A` value into
a mutable local cannot create an unchecked route back to `A`. Returned opaque
closures do not export captured abstract facts or callable signatures.

Occurrence tests preserve abstract membership: after `(string? x)`, the same
value has the internal intersection `A ∩ String` and can still be returned as
`A`. A newly computed String does not inherit that membership. These internal
intersections have no source syntax or runtime predicate.

Direct recursive calls use the definition's rigid instance. The checker also
tracks implementation origins through aliases, explicit/contextual instances,
and callable joins. In a recursive component, generic call edges must use the
caller's type variables in declaration order. This supports ordinary mutually
recursive generics with different binder names; concrete recursive instances,
parameter permutations, and cycles through ordinary helper definitions are
diagnosed. Immediate lambdas such as expanded `let` keep the enclosing checking
context. Dynamic reentry without a checked polymorphic relationship remains
ordinary dynamic execution.

Standard `define-record-type` field forms retain their old interpretation,
including a standard accessor named `:` and fields omitted from the constructor.
Only four/five-element fields add a type, and explicitly precise fields must be
initialized by the constructor. Untyped local records remain generative. This
preserves those standard forms; it does not claim that Snail's entire existing
frontend is R7RS-complete.

## Analysis and enforcement

`types.sld` owns the type algebra, rigid identities, and located type diagnostics.
`type-inference.sld` solves per-use shallow instantiation constraints.
`type-analysis.sld` contains pure rules that consume facts for already visited
children. The `wasm.sld` visitor threads immutable binding scopes, invokes those
rules, and immediately passes their results to emission. A declaration scan
records source declarations, assignments, and record identities; it does not
infer expression types. A checked binding may retain a declared signature,
verified predicate contract, and implementation origin. Forward references can
use declared signatures, but cannot borrow an unverified body summary.

An expression returns its fact, code, and output obligations to its parent. No
expression-to-type, expression-to-guard, or lambda-to-signature map is built.
Call-site checks and recursive-instantiation edges are returned explicitly.
Partial evaluation also returns a candidate value directly, after all source
children have been checked. IR binding identities and the ordinary Scheme value
representation remain unchanged.

Tail code is assembled after enclosing guards are known. A tail builder captures
only selected WAT fragments and runtime check recipes; it cannot inspect facts,
perform inference, or answer subtype questions. Each builder is consumed once
before its enclosing function is emitted. This keeps the existing pending-result
check protocol without retaining a typed copy of the source tree.

Each transient result also carries compatibility with raw partial evaluation.
A generated guard, checked entry, or guarded child makes that compatibility
false. This includes checks inferred inside immediate lambda workers from an
expected result type. Otherwise, folding the raw call could erase its guard
while retaining the guard's postcondition. Incompatible initializers never enter
the evaluator's known-value environment. The interpreter does not consult type
declarations to reconstruct rejected closures. Its separate fuel, initialization,
arity, and effect rules still govern every speculative attempt.

An expression fact contains a value type, independent single-value evidence,
an optional stable object identity, positive/negative occurrence filters, and
an optional known callee. These components answer different questions. Knowing
the category of a value does not prove its initialization, result count, numeric
representation, or field contents.

Unknown untyped parameters and heap reads have no single-value guarantee: Rust
AWI can retain a callback's multiple-value envelope and pass it back directly or
inside a pair/vector. Ordinary binding stores normalize their initializers, and
typed entries normalize parameters. Those operations establish count evidence;
a name read does not manufacture it. Immediate lambda arguments also normalize
before invocation. This preserves ignored raw callback arguments and multiple
values returned from them, without moving a use-site error to function entry.

Primitive predicate meaning comes from the immutable resolved core binding.
Aliases can preserve that identity; spelling a different function `string?`
cannot acquire it. User predicate summaries are inferred from analyzed bodies,
published afterwards, and substituted only onto stable actual arguments. The
positive and negative summaries are independent. There is no speculative
recursive predicate summary or user-supplied unchecked proposition.

All assignments, including those in nested closures, are collected first.
Assigned bindings lose reusable occurrence identity and known-callee evidence.
An immutable copy of a mutable read can obtain its own identity and narrow
safely. No reusable heap-field facts exist. A field read is checked again even
if a previous read passed, or the public record interface omitted a setter.
Foreign calls and callbacks therefore cannot invalidate a retained field fact.

The logical domain retains conjunctions and common guarantees at branch joins,
with at most 32 accumulated filters. Exceeding that bound drops information.
Subtraction is an overapproximation: `ExactInteger` minus `i32` remains
`ExactInteger`, since the remaining disjoint intervals are not represented.
`integer?` deliberately does not prove `ExactInteger`: integral floats satisfy
the former. `exact-integer?` provides the stronger fact.

## Soundness audit

The intended claim is partial correctness of checked uses and preservation of
observable behavior when optional optimizations are enabled. Divergence,
arithmetic overflow, and runtime type errors remain possible. There is no
termination proof, public effect system, dependent typing, or SMT solver.

The implementation relies on these invariants:

1. Incoming evidence decides whether a guard is required. Only the guard's
   successful continuation receives its postcondition. The emitter executes a
   recorded guard even when surrounding code uses that postcondition.
2. Every route into a typed worker establishes its domains. Generic adapters use
   checked entries; a direct call bypasses them only with static subtype proofs.
   Parameter guards run before boxing mutable parameters.
3. Every declared storage write is checked, including writes inside unannotated
   nested functions. No occurrence fact narrows a reusable mutable location.
4. Nominal identity requires an immutable top-level descriptor allocated by the
   actual core `%make-record-type`. Schema metadata alone is insufficient:
   a forged schema naming an alias cannot introduce a supposedly disjoint type.
   Type/filter comparisons use binding identity, including hygienic binders
   whose names and source locations happen to match.
5. Callee evidence and predicate summaries refer to implementations, independently
   of the written interface. Missing or recursive summaries provide no facts.
6. Argument evaluation, operator evaluation, call-boundary checks, and explicit
   inner assertions retain their original order. Effects of predicates remain.
7. Initialization and value-count obligations remain separate. A binding read
   is single-valued only because its initializer/write was normalized, not
   because an analysis borrowed evidence from a future initializer. Untyped
   callback parameters and heap reads retain their use-site count checks.
8. A typed result obligation belongs to the logical invocation, not each tail
   caller. Tail calls transfer a bounded ordered set of pending check sites;
   ordinary calls and Rust callbacks start fresh. Checks run on the final result
   in inner-to-outer order, including single-value normalization for `Any`.

The emitter carries local assertions down to return expressions. Local results
are checked inline, with no pending-list allocation or return helper. The first
guarded tail call retains one checking frame and creates a shared mutable context;
later tail calls update that context and transfer control with `return_call`.
The retained frame executes the pending checks after the final result arrives.
Thus the number of checking frames is bounded independently of tail-call depth.

The private closure ABI carries this optional context. Reentering a static site
moves its existing check to the front, removing its older occurrence. This is
sound because a successful shallow check preserves its value and performs no
mutation or callback. Nominal descriptors are read when the check executes,
never when it is registered. The runtime's sole multiple-value constructor
returns the value directly for a singleton; envelopes contain zero or at least
two values, so successful single-value normalization is also idempotent.
The number of retained entries is bounded by the program's static check sites.
`apply` forwards the pending set; `call-with-values` gives its producer a fresh
set and transfers the caller's set to its consumer. The public AWI handle ABI
is unchanged, and no pending state is captured in Scheme closures.

This repairs a concrete space leak: an annotated function tail-calling an
untyped callback previously retained a Wasm frame for its result guard. The
regression fixture executes million-step loops through dynamic callbacks,
`apply`, `call-with-values`, and explicit tail assertions. Additional cases
check error order, nominal initialization, multiple values, and Rust reentry.
Synchronous Scheme/Rust callback cycles that retain host frames are still nested
host calls; this does not introduce a tail-transfer protocol for foreign code.

These give an induction argument for the supported checker: literals and trusted
primitive contracts establish base facts; enforced entries/writes establish
environment facts; sound intersection/subtraction establish branch facts;
conservative joins preserve them; checked results establish the interface for
callers. An omitted check must follow from facts valid at its exact use.

For `All`, the body proof is uniform in its rigid variables. A checked call
establishes each substituted domain before invoking that body, so substitution
preserves the result guarantee. Any obligation involving an erased variable
requires existing static evidence; it cannot be implemented by treating the
variable as a successful predicate. Independent finite-set tests assign type
variables every subset of representative values and check intersection, union,
subtyping, and conservative subtraction against a membership oracle.

This is an audit and proof outline, **not a completed soundness theorem**. A
formal operational semantics, preservation proof, and simulation of the complete
Wasm/AWI runtime remain work. The implementation assumes the existing runtime's
primitive contracts and one initialization of the program's libraries. It does
not establish blame theorems, parametricity, or a full gradual guarantee.

The most consequential rejected shortcuts were treating `integer?` as exact,
negating one-sided predicate summaries, reusing mutable-field facts, assuming
nominality from metadata alone, trusting opaque arrow annotations, and deleting
initialization/count checks merely from a value type. Regression cases cover
each applicable boundary.

The AWI audit produced a concrete failing counterexample: a multi-value callback
argument used by `+` raised the baseline single-value error in guarded mode but
reached a numeric error after an unjustified count-check removal. The corrected
analysis derives count evidence from normalization sites. Regression tests cover
raw arguments, pair/vector storage, unused arguments, raw returns, assignments,
and typed callback entries, including output before failure.

The hygiene audit found a second concrete counterexample. Chibi's `equal?`
compares compiler record objects by their fields. Expanding the same record
macro twice produced distinct descriptor bindings with equal-looking names and
locations; structural equality incorrectly justified bypassing a nominal check.
The type algebra now compares opaque binding leaves by `eq?`, and filter joins
do the same. A linked regression passes a value from one expansion to the
other expansion's accessor and requires the original type error in both modes.

## Optimizations

The boxed path removes single-value checks with independent count evidence,
bypasses redundant typed entry checks at known calls, selects integer-only
addition/subtraction/comparison helpers, and selects known String and nominal
record access helpers. Runtime i31/boxed dispatch, overflow checks, field-name
lookup, field-result guards, array bounds, and required Wasm casts remain.
This is why fewer checks need not mean a large speedup on boxed arithmetic.

The optional representation pass accepts this uncurried signature:

```scheme
(: fibonacci (-> i32 i32 i32))
(define (fibonacci n offset)
  (if (< n 2)
      (+ n offset)
      (+ (fibonacci (- n 1) offset)
         (fibonacci (- n 2) offset))))
```

`i32` is a checked signed range, not wrapping arithmetic. The current Scheme
integer runtime itself has checked signed 64-bit arithmetic. Specialized workers
use an i32 ABI and widened i64 intermediates, retaining unproved i32 checks at
returns and recursive entries. Thus `(- (+ a b) b)` still works for two maximum
i32 arguments, while returning `(+ a 1)` at that maximum fails. Intermediates
that might overflow i64 force ordinary emission for the whole function.
Range-endpoint calculations check their own i64 bounds before performing
arithmetic, allowing the same analysis to run on the native compiler host.
An unrepresentable endpoint declines specialization without clipping its range
or overflowing during compilation.

Eligibility is deliberately narrow: an immutable top-level bare lambda, only i32
parameters/result, integer literals/parameters, binary `+`, `-`, `*`, comparisons,
conditionals, and self recursion. Calls to other functions, captures, mutation,
local bindings, and unsupported syntax fall back. The range analysis recognizes
parameter-left/literal-right comparisons. Impossible refinements retain the old
ordered interval, which can conservatively force fallback on dead code.
Comparisons use i32 instructions only when both computed operand ranges fit;
otherwise they keep i64 width, including sums that exceed i32 before comparison.

The recursive emitter returns code with interval bounds or failure; it does not
retain a second planning tree. A failed candidate publishes no partial worker.
Recursive operands that need range checks are all evaluated before those entry
checks. Tail self calls update parameter locals and branch to a Wasm loop.
All operands are saved before any parameter is replaced, so permutations and
nested ordinary calls see the previous iteration's values. Checked narrowing
reestablishes i32 domains before the next iteration. A million-step three-argument
case executes in tests; ordinary recursive calls retain their call semantics.
Only immutable self initialization is elided: entering that bare-lambda worker
proves its own initializer completed. Other initialization checks remain.

Ordinary closures still use eqref arguments and results, with a boxed bridge
around the specialized worker. This is monomorphic representation specialization,
not a generic `All` monomorphizer or a change to record/container layout.

## Measurements

At implementation commit `e3d916657357e8fb0a64a075fdb3161d3e24e5d3`, eight
rotating rounds measure specialized two-argument recursive Fibonacci at 0.173662
seconds, compared with 0.392312 for untyped Scheme and 0.171902 for checked
C-to-Wasm. Specialization is **2.26× faster than untyped Scheme** and within
about 1% of checked C-to-Wasm. Check elimination alone is neutral for untyped
and boxed i32 Fibonacci, while ExactInteger checks lose most of their annotation
overhead. The boxed string/record workload takes 0.064886 seconds, against
0.129638 guarded: **2.00× faster**, without representation specialization.
Its optimized time is essentially unchanged from the prototype; correcting
guarded tail-result handling increased the guarded baseline's cost.

The efficient tail version has signature `(-> i32 i32 i32 i32)` and carries
`n`, `a`, and `b`. It returns `a` for nonpositive `n`, `b` at one, and otherwise
tail-calls with `(- n 1)`, `b`, and `(+ a b)`. Each sample performs 4,194,304
top-level calls and 94,371,840 tail updates after an equally sized untimed
warmup. The complete specialized Scheme workload takes **0.117819 seconds**,
against 0.289357 untyped: **2.46× faster**. Exposing only its i32 worker to the
same JavaScript driver used by C-to-Wasm takes **0.058404 seconds**, versus
**0.043914** for checked C-to-Wasm and **0.033144** for checked native C.
The isolated worker remains 33% slower than checked C-to-Wasm, and the complete
Scheme workload takes 2.68× its time.

The tail worker improved across the measured revisions, but the complete Scheme
workload is slower than the earlier `return_call` version's 0.101298 seconds.
Base-case layout and warmup also changed; this history does not isolate the
loop transformation. Additional diagnostics show sensitivity to V8 tiering,
and full in-process warmup does not eliminate the gap. Boxed driver work,
representation boundaries, and engine code generation have not been individually
profiled. The loop transformation is not claimed as a whole-program speedup.

The full tables, raw [recursive Fibonacci](../benchmarks/results/2026-10-10-typing-production-fibonacci.json),
[tail Fibonacci](../benchmarks/results/2026-10-10-typing-production-tail-fibonacci.json),
and [occurrence](../benchmarks/results/2026-10-10-typing-production-occurrence.json)
reports, source/artifact hashes, historical comparisons, and reproduction
commands are in [the benchmark guide](../benchmarks/README.md#typing-and-i32-specialization).
Measurements exclude compilation and startup. V8's default tiering remains
enabled; only the tail workload uses a full in-process warmup. The isolated
worker comparison bypasses the boxed Scheme entry and outer driver. No native
Snail executor is measured.

For non-tail recursive Fibonacci, Clang's unchecked C assembly replaces one
recursive branch with a loop and accumulator. Its checked version retains two
calls and a result-range test. Specialized Snail takes 2.53× native C's time,
or 1.62× checked native C's time. An i32 annotation alone cannot justify
removing range tests: other inputs really do overflow. Proper tail recursion
addresses stack use, independently of numeric range. The self tail loop preserves
argument checks; reassociating the non-tail recursion would need a separate
argument that failures and their order are preserved, or tighter input bounds.

## Validation and simplification

`make test` includes a finite membership model checking subtyping, union,
intersection, and conservative subtraction over scalar regions and distinct
nominal identities, including all subsets assigned to rigid type variables.
`scripts/test-typing` compares guarded and optimized linked
Wasm on success, failure, stdout effects, type diagnostics, mutation, predicate
aliases, initialization, multiple values, records, and tail recursion. Seeded
numeric and boundary examples use Python exact arithmetic as an independent
oracle. Static rejection tests cover unsupported or incompatible interfaces.
Range-bound unit tests compare 972 signed i64 edge combinations against Chibi's
arbitrary-precision arithmetic. The native CLI test bootstraps with Chibi, then
deliberately blocks it while rebuilding the compiler and compiling typed scripts.
Those scripts exercise rank-one instantiation, widened i32 intermediates, and
fallback when a range bound exceeds i64.

Validation passed: `make test`, `make check`, `scripts/test-typing`,
`scripts/test-backend --target both`, `scripts/test-build`, `scripts/test-self-host`,
`cargo test --offline`, and `cargo fmt --all -- --check`. The typing suite has
66 differential fixtures (each guarded and optimized), 1,443 independent numeric results within those
fixtures (477 arithmetic and 966 comparison results), and 35 expected static
rejections. Rust's 14 tests pass after rebasing onto the native CLI baseline.
Guarded and optimized success, polymorphism, and million-step tail fixtures also
passed as native executables. The native CLI rebuilt itself with Chibi deliberately
blocked and compiled the typed scripts above using its replacement.
No native Snail result is counted without executing an actual native executor.

Full-compiler bootstraps use Chibi's `-h512M` initial heap setting. An eight-second
CPU profile of the default-heap bootstrap collected 795 samples, all in
`sexp_try_alloc`, mostly allocating output strings during WAT serialization.
The larger-heap bootstrap completed in 96.15 seconds; the default-heap run was
interrupted after 1,306.12 seconds while still serializing WAT. These are single-run
measurements of the bootstrap host. The [build guide](book/builds.md) records the
heap setting used by `scripts/test-self-host`.

The pinned simplify workflow reviewed the checker, polymorphic inference,
tail-result handling, and i32 emitter through independent explanations and
critical follow-ups. The resulting design keeps rigid body checking separate
from per-use bounds and represents instances as identity-preserving static
views. Local return guards stay in the emitter until a tail transfer requires
one shared runtime context. A helper on every return was rejected after measuring
its overhead. Self tail updates save every operand before checked parameter
replacement; widening the worker ABI was unnecessary.

Earlier accepted changes documented the incoming/outgoing guard boundary and
kept stored intervals ordered. The visitor refactor removed mutable expression
indexes and signature registration entirely: pure branch rules now consume child
facts, and checked binding contracts live in immutable scopes. A second
specialization plan tree was rejected because code-plus-bounds already provides
whole-function fallback. Facts, guards, and summaries remain distinct because
merging them would obscure the soundness argument. The few functions beyond
the ten-line target retain complete operations: exhaustive type/expression
dispatch, declaration validation, sequence traversal, and branch checking/join.
Splitting those into forwarding
fragments would hide the premises from their consequences. The bounded rank-one
solver does not introduce a general inference or callback framework. Each
remaining piece of state and control flow serves an explicit invariant above.

The predicate design follows the distinction between positive and negative
propositions in [Typed Racket's occurrence-typing guide](https://docs.racket-lang.org/ts-guide/occurrence-typing.html).
The [formal draft](typing-rules.md) records the research references and the
additional obligations for polymorphism and richer gradual boundaries.
