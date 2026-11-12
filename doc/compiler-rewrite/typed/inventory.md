# Inventory: what the old checker does

Functions are in `src/snail/shell/compiler/`, line numbers this worktree's at
17ed1f95 (`check.sld` unless another file is named). Every row was read in
the code; rows that cite a probe were also observed (`probes/`, section 5 of
`design.md`).

## The old order

`check-program` (3372) checks the libraries one at a time in program order,
threading the table of schemes. `check-library` (3388) runs, for one library:

| Phase | What | Function | Problems |
| --- | --- | --- | --- |
| **I** | every item inferred: first the unannotated groups in dependency order, then every item in written order | `check-items` 3459 | each item stops at its first; every item runs; all reported, sorted by place (`in-source-order`, read.sld 303); an item naming a failed group's name is skipped |
| **S** | the constraints still pending: improvement, defaulting, literal and Copy checks, class constraints | `solve-pending` 1652 | the first stops the library |
| **E** | each `expose` | `check-exposures` 3441 | the first stops |
| **Z** | every type and evidence hole replaced, the schemes made final | `zonk-item`, `final-schemes` 3529 | none |
| **C** | every conversion checked, then lowered | `check-conversions` 2751, `lower-conversions` (conversions.sld 283) | the first stops |
| **F** | the fields of every data type **of the whole program**; then per item closed, places, ownership; then each confined function | `check-final` 3425 | owned fields: the first stops, before anything else of F; then each item stops at its first (closed before places before ownership); every item and confined function runs; all reported, sorted by place |

A library that fails stops the program. I is the only phase that recovers
past an item; F collects per item but does not mask.

"Goes to" names the pass in this design (`design.md` section 2): **scope**,
**infer**, **hold**, **cover**, **solve**, **expose**, **settle**, **convert**,
**close**, **place**, **borrow-check**, **confine**; "integrator" or a
query library where it is not a pass's.

## I: unification and rows

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| U1 | Unification with occurs check; a failed attempt may leave bindings, which nothing reads | `unify?` 240, `bind?` 287, `occurs?` 293 | — | — | infer, query `infer/unify.sld` (solve imports it) | the Solution's types |
| U2 | A mismatch reports the two types resolved | `unify` 224 | `type mismatch: expected A, found B` | the node checked (each caller's loc) | infer (and solve, through U1) | Feedback |
| U3 | Structure: Con by name and arguments; functions by parameters, result, then row; rows as sets; rigid variables by name | `unify-structure?` 258, `unify-function?` 279 | — | — | `infer/unify.sld` | — |
| U4 | Rows unify as sets: shared labels match, each open tail takes the other side's extra labels; two open tails share a fresh tail | `unify-rows?` 334, `flatten-row` 309 | — | — | `infer/unify.sld` | fresh unknowns |
| U5 | A call's latent row is included in its context, not equal to it: a shared tail with known labels inside is accepted; otherwise a fresh tail opens a closed latent row and it unifies | `perform` 368 | `this performs effects its context does not allow: L ...` | the call | infer (and solve, at a charge, S6) | — |
| U6 | In a confining body (a lambda whose row forbids `mut`, X5) `mut` is discharged before inclusion, and the body is marked as having mutated | `performed-labels` 391, `discharge-mut` 402 | — | — | infer | the Lambda's `confined?` |
| U7 | In a signed body (a lambda checked against its type), each call records what it performs: its labels and a rigid tail | `record-performed` 421 | — | — | infer | the body's performed set |
| U8 | Printing a type: short names, `?N` for an unknown, rows sorted by unique-name text | core.sld `type->string` 433 | — | — | query `infer/text.sld` | (difference D9, D10) |

## I: instantiation, literals and references

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| N1 | A use of a global: fresh unknowns for its variables, a hole and a pending class constraint per requirement (with the givens, Copy variables and instance sets in scope), a pending Copy constraint per variable it says Copy, and a fresh tail on a closed outermost row | `instantiate` 472, `want-class` 451, `copy-requirements` 486, `open-row` 519 | — | — | infer | TopRef types and evidence; Pending |
| N2 | A global's scheme: an inferred or provisional one first, else the declared one; a signed `impl` definition's type is its own closure type, named by the definition | `global-scheme` 532, `named-callable-scheme` 3559 | `internal error: no type for N` | — | infer, from the offers and `declare/schemes.sld` | — |
| N3 | A local's type is its binding's, monomorphic | `variable-type` 560 | — | — | infer | LocalRef type |
| N4 | Literals: Bool, Char, String, Bytes (`(Vector U8)`), Unit are known; a number gets an unknown and a pending literal constraint | `literal-type` 571 | — | — | infer | Pending `WantLiteral` |
| N5 | A `case-id` is `(ann <id> I32)` in the old program, so its literal's constraint always holds | expand, the milestone-A adapter | — | — | infer | CaseId typed I32, no constraint (unobservable) |
| N6 | A path: one label is the field class's method; several are a lambda that applies each in turn; `(::a::b r)` is the readers applied in turn, all at the path's place | expand.sld `expand-path` 3786, `apply-path` 3806 | — | — | infer | Calls of `FieldReader`; a Lambda for a path value |

## I: expressions

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| X1 | Inference by node: If (test, consequent, alternative inferred, then the test fitted to Bool and the branches unified at the alternative), Let, Seq, Match, Handle, Ann (checked against its type then fitted), Convert (inferred then fitted), TryConvert and TypeTest (inner fitted to Any) | `infer` 584 | U2 | each node | infer | the typed node; Ann gone |
| X2 | `with-instances` adds its sets to those in scope for the body, and checks that the instances active under them, **of the whole program**, do not overlap (probes `scope-expression`, `scope-later`) | `instance-scope` 638, core.sld `check-active-instances` 1237 | `this instance overlaps another instance of the class on its input types` | the ScopedInstances node: an expression's, or a scoped definition's value (a lambda's body) | sets: infer (each Pending keeps them); the overlap: **scope** | WithInstances gone |
| X3 | Checking against a known type: a lambda takes its parameters and row from the type; If, Let, Seq, Match and calls pass the type inward; a `fn` type checks against its arrow then fits; an `impl` contract or FnMut/FnOnce gets a concrete closure type; an unknown callable type looks for a pending callable requirement | `check-value` 683, `check-constrained-lambda` 738, `check-result` 754 | — | — | infer | — |
| X4 | A lambda's type is a concrete closure: its contract, an identity (`loc.N`, or the name a let or a definition binds), its arrow, and the types of the enclosing locals its body reads | `lambda-contract` 759, `capture-types` 770, `local-placeholder` 1210 | — | — | infer | `Closure` type |
| X5 | A lambda checked against its type: a fresh row bound to the type's, the body signed (U7); a body whose row forbids `mut` is confining (U6), and a lambda whose body did mutate goes to the confined list | `check-lambda` 795, `forbids-mut?` 851, `finish-lambda-scope` 823 | — | — | infer | `confined?` on the Lambda |
| X6 | `let`: a placeholder (a closure type named by the local when the value is a lambda), the value with its own name in scope when it is a lambda, then the body | `infer-let` 1200, `infer-let-value` 1222, `infer-local-lambda` 1229 | U2 | the value | infer | — |
| X7 | A clause-less match is allowed only when the scrutinee's type, as known when the match is checked, is an enum with no cases | `check-empty-match` 1262 | `a match needs at least one clause, unless its value's type has no cases` | the match | infer (depends on the moment) | — |
| X8 | Usefulness: a clause not useful after those before it; a wildcard useful after all | `check-coverage` 1525, `useful?` 1606 | `unreachable match clause`; `match is not exhaustive` | the match | **cover** | — |

## I: calls

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| C1 | Order of a call: callee; the result's type constructor passed in when it matches the expected type; arguments checked by the callee's contract (a projection's argument without fitting); a borrowed accessor; fresh result and latent row; unify-call; the invocation marked; improvement (C9) over the constraints raised in the call; inclusion of the latent row (U5); row classes with known inputs solved here (C10) | `infer-app-at` 861 | — | — | infer | — |
| C2 | Arity and callability | `unify-call` 989 | `expected N arguments, found M`; `not a function: T` | the call | infer | — |
| C3 | Arguments with known types fit first, so an Any argument does not decide a shared variable | `fit-known-arguments` 1062 | — | — | infer | — |
| C4 | Calling a FnOnce or a `fn` calls the procedure it holds; a callable's contract comes from its type or a given callable requirement | `unify-call` 1012, `callable-contract` 1025, `given-callable` 1033 | — | — | infer | — |
| C5 | A call through a concrete closure, a rigid variable or a FnMut records the receiver contract chosen | `mark-invocation` 1045 | — | — | infer | Call's `Invocation` (old `Ann $invoke`) |
| C6 | A field read on a Borrow reads through it: Copy fields owned, linear fields borrowed; a path's field is found through its instance first | `borrowed-accessor` 931, `borrowed-method` 949, `borrowed-field` 967 | `a Borrow requires a concrete immutable field accessor`; `a Borrow can read only immutable fields` | the record | infer | the callee's type |
| C7 | A once argument (pending FnOnce requirement over an unknown signature) whose lambda is inferred gets the FnOnce identity | `infer-once-argument` 917 | — | — | infer | — |
| C8 | A callable requirement whose receiver's contract is known is improved: its signature unified; its contract must imply the class | `improve-callable` 2117, `callable-implies?` core.sld 266 | `K does not satisfy C` | the constraint | `infer/improvement.sld` (solve imports it) | — |
| C9 | Improvement to a fixed point over the constraints raised since a point: field types from the one matching instance or given (`::f R T` decides T from R); associated outputs from the selected evidence; callable signatures (C8) | `improve-types` 2083, `improve-output` 2100, `improve-field` 2130, `field-type-of` 2145 | U2, C8, S7-S10 when the selection fails | the constraint | `infer/improvement.sld` | the Solution |
| C10 | A row class's constraint (rows or outputs) whose selecting inputs are known once its call is checked is solved there, its rows charged in the call's context and recorded in a signed body (probe `charge-at-call`: the problem is at the caller, 11:3, not at the drop) | `solve-found-rows` 2029, `solve-known-row` 2048, `charge` 2010 | S5-S12, U5 | the constraint | infer, through `infer/evidence.sld` | the hole's evidence; Pending shrinks |

## I: fitting a value to an expected type

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| F1 | Directed fitting: an `impl` contract asks for callable evidence; a concrete closure where a dyn callable is expected is erased; Any meets Any; an unknown unifies, except a numeric literal's unknown at Any, which converts; a known type at Any, or Any at a known type, converts; at a `fn`, F3; a `fn` where a dyn arrow is expected is refused; otherwise unify | `fit` 1080 | `a fn is not a closure; wrap it in a lambda, as (lambda (x) (f x))` | the value | infer | — |
| F2 | Callable evidence at an `impl` contract | `fit-callable-contract` 1123, `callable-evidence` 2209 | `a callable implementation type must be known`; `T does not satisfy C` | the value | infer | — |
| F3 | Only a `fn` or a top-level function's name has a `fn` type (`function?`) | `fit-code-pointer` 1108, `environment-free?` 1189 | `only a fn or a top-level function has type T; a lambda, or a local bound to one, may capture` | the value | infer (needs the offer's `function?`) | — |
| F4 | Erasure to a dyn callable improves the callable requirement; dyn Fn storage needs Copy captures | `erase-callable` 1134 | `dyn Fn storage requires Copy captures; keep the concrete impl callable to retain owned captures` | the value | infer | `Erase` (old `Ann e dyn`) |
| F5 | A conversion inserted at an Any boundary first refuses, on the types as zonked so far, hidden effects and function references (C-phase checks, early); from Any it needs `dyn-cast` in the row, then performs it | `convert-value` 1164, `require-conversion` 1179 | the C1, C2 messages; `conversion from Any to T requires dyn-cast; handle or declare dyn-cast, or use try-convert` | the value | infer | `Convert` |

## I: patterns and handlers

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| P1 | Wild, Bind, literal (unified with the literal's type), constructor: instantiated, arity, mutable positions only `_`, the scrutinee's Borrow read through | `check-pattern` 1430, `check-mutable-positions` 1466, `borrowed-fields` 1486 | `C has N fields`; `a pattern cannot read the mutable field F; write _ there and read it with C-F`; `not a constructor: N` | the clause's body (`body-loc`, 1276) | infer | typed patterns |
| H1 | A handler implements each operation exactly once | `infer-handle` 1306 | `a handler implements each operation of its effect exactly once` | the handle | infer | — |
| H2 | Implementations in the outer row; the body in `{effect \| rest}`, fitted to the result; `rest` included in the outer row; a control operation's implementation takes `resume`, a FnOnce performing the outer row, unless it answers Never | `infer-implementation` 1347, `implementation-type` 1407, `fit-lambda-result` 1392 | U2, U5 | implementation, body | infer | — |

## I: cleanup effects

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| K1 | After each definition, statement and lambda body, every owned value live where a call may yield (or a handle leaves a yield, or a conversion may fail) has its drop rows charged to the row, less effects a handler around it catches; types still unknown then are skipped; evidence still a hole reads as an ordinary call | `infer-cleanup` 2973, `cleanup-lambda` 3014, `charge-cleanup` 2934, `cleanup-yields` 2903, ownership.sld `consumed-references` | U5 | the call, handle or conversion | infer (part `cleanup`) | — |

## I: definitions, groups and recovery

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| G1 | Unannotated definitions are grouped by strongly connected components of their references, numbered in item order, edges in first-reference order; groups come in the components' order | `definition-groups` 3633, core.sld `strong-components` 1590 | — | — | query `infer/groups.sld` | — |
| G2 | A group: provisional monomorphic types (a closure named by the definition for a lambda); each member inferred (a fresh row; a lambda's value at its placeholder; cleanup; unified with its placeholder); host effects of each initializer's row; generalization | `check-group` 3033, `infer-definition` 3076 | U2, K1 | — | infer | — |
| G3 | Host effects: every effect of an initializer's row is `mut`, `host`, or has a default for every operation | `check-host-effects` 3344, `check-effects-with` 3351 | `the effect E has no host implementation here` | the value | infer (the row as known then) | — |
| G4 | Generalization, only when every member is a lambda: the unknowns of the group's types, less those free in an earlier unannotated definition's type, in a constraint the group raised, or in an exposed definition's row, become `t1 ...` in order of first occurrence; no requirement is generalized | `generalize` 3102, `exposed-row-metas` 3140 | — | — | infer | Definition scheme with `Inferred n` variables |
| G5 | A signed definition: the signature's requirements cannot select alike for a class with outputs; givens and Copy are the signature's when it quantifies, otherwise its requirements are wanted; the value checked and fitted; cleanup; host effects; a polymorphic definition's initializer is total; a signed lambda performs every effect its row names (but a method, which has no signature place, and a non-lambda value) | `check-annotated` 3195, `check-associated-givens` 3209, `want-closed-requirements` 3275, `check-annotated-value` 3221, `check-performed` 3244 | `associated projection matches multiple requirements`; G3; `a polymorphic definition must have a total initializer`; `N declares the effect(s) ... but never performs it/them`, a default named `the default of OP` | the value; the performed check at the signature | infer | — |
| G6 | Instance methods, defaults and dispatched methods are signed items at their instance or effect | the items (expand) | as G5 | | infer | Definition items |
| G7 | A program's statements are one unannotated nullary function `%body`, after the other items, called by one statement at the first statement's place, which runs under `around-main` effects | expand.sld `with-one-body` 924; `check-statement` 3286, `check-body-effects` 3294 | G3 with around-main allowed | | infer | Definition and Statement |
| G8 | Recovery: a failed group's or item's step is undone; its diagnostics kept; an unannotated group's names fail with it, a signed item's do not; an item naming a failed name is not checked; all sorted by place | `each-recovered` 3602, `recover` 3616, `check-items` 3459 | — | — | infer | Result |

## S: solving (solve-pending)

| # | Behavior | Function | Message | Place | Goes to |
| --- | --- | --- | --- | --- | --- |
| S1 | Improvement over every pending constraint; float literals still unknown default to F64, then integers to I64, in pending order; improvement again | `solve-pending` 1652, `default-literal` 1677 | U2 | the constraint | solve |
| S2 | Every literal's type fits, then each Copy constraint, interleaved in pending order | `check-literal` 1692, `check-copy` 3160, capabilities.sld `copy-refusal` | `the literal N does not fit T`; `a numeric literal cannot have type T`; `this use needs (Copy T), which the definition must require`; `a type variable requires an unrestricted type, and T is linear` | the literal; the use | solve |
| S3 | Each class constraint, oldest first, under its own sets, givens, Copy | `solve-class` 1719 | — | the constraint | solve |
| S4 | `(Unboxed T)`: decided by the representation, or a given | `solve-unboxed` 1738 | `ambiguous constraint ...`; `T is not unboxed: an array element is one Wasm slot, ...` | the constraint | solve |
| S5 | A row class: by its selecting inputs, a given or the one matching instance; outputs unified; rows charged with no call context | `determined-evidence` 1874, `determined-source` 1899, `determined-instance` 1924 | `ambiguous constraint ...`; U2; U5 | the constraint | query `infer/evidence.sld` |
| S6 | A lifecycle class: rows found from the type's structure; evidence the plan charged | `lifecycle-evidence` 1987, capabilities.sld `lifecycle-rows` 399, `checked-plan` 266 | `ambiguous constraint ...`; `dropping a value of type A needs (Drop e A); ...`; `glue cannot drop T, which contains itself ...`; the Refused reasons (`a FnOnce runs once, so it has no clone`, ...) | the constraint | `infer/evidence.sld` |
| S7 | Any other class: a given with equal types, else the one matching instance | `find-evidence` 2188, `given-evidence` 2220, `instance-evidence` 2237, `matching-instance` 2247 | `no instance for (C ...)`; for a field class with a known record, `R has no field f` or the Borrow advice | the constraint | `infer/evidence.sld` |
| S8 | An instance applied: its Copy variables bound to unrestricted types; each requirement satisfied in turn (row requirements as S5) | `instance-application` 2279, `requirement-evidence` 2318, capabilities.sld `instance-copy-refusal` 205 | `the instance (C ...) requires (Copy A), and T is linear`; `ambiguous requirement ...` | the constraint | `infer/evidence.sld` |
| S9 | Requirements that do not terminate (a goal met again, or 128 deep) | `enter-instance` 1939 | `instance requirements do not terminate` | the constraint | `infer/evidence.sld` |
| S10 | An unsolved constraint is ambiguous, or names the missing field | `unsolved-constraint` 1789, `missing-field` 1807, `ambiguous-constraint` 1965 | `ambiguous constraint (C T ...); add a signature or an annotation`; `R has no field f`; `field f of (Borrow R) was checked before the borrow's type was known; ...` | the constraint | solve |

## E: exposures

| # | Behavior | Function | Message | Place | Goes to |
| --- | --- | --- | --- | --- | --- |
| E1 | An exposed value is a definition | `check-exposed` 3303 | `an exposed function must be defined` | the expose | **expose** |
| E2 | Monomorphic and a function, by its type as resolved (not zonked) | `check-exposed` 3307, `check-exposed-type` 3315 | `an exposed function must be a monomorphic function` | the expose | expose (reads Solved, so unsolved stays unsolved) |
| E3 | No Borrow, no linear parameter or result; host effects | `check-exposed-type`, ownership.sld `check-boundary-type` | `a Borrow cannot escape through an Any or host boundary`; `an exposed function cannot take or return a linear value`; G3 | the expose | expose |
| E4 | A dynamic export: first-order data, pure | `check-dynamic` 3331, capabilities.sld `first-order-type?` 37 | `a dynamic export takes and returns only data, with no function or Any inside`; `a dynamic export cannot perform effects: ...` | the expose | expose (an unsolved type is not data: the old refuses it; after zonk it would be Unit) |

`an exposed function must be defined with lambda` is prepare.sld's, after
the checker (milestone C).

## Z: zonking

| # | Behavior | Function | Goes to |
| --- | --- | --- | --- |
| Z1 | Every type through the solution; an unsolved unknown is Unit, an unsolved tail closes; every hole its evidence | `zonk` 2364, `zonk-row` 2377, `zonk-evidence` 2382, `zonk-expr` 2394 | settle |
| Z2 | Schemes: unannotated definitions' zonked, signed ones as named | `final-schemes` 3529 | settle; the offer is a query over Typed |

## C: conversions

| # | Behavior | Function | Message | Place | Goes to |
| --- | --- | --- | --- | --- | --- |
| V1 | A conversion's endpoints hide no effects and are no `fn`; a type-convert goes to or from Any or changes nothing; no Borrow crosses; pre-order over items, first stops | `check-conversions` 2751, `check-through-any` 2780, `refuse-function-reference` 2796, `refuse-hidden-effects` 2807 | `an Any does not record what a function performs, so F cannot take T[, since A may stand for one]`; `F cannot take T: an Any holds no function reference; wrap it in a lambda`; `type-convert converts to or from Any, not from S to T`; `a Borrow cannot escape through an Any or host boundary` | the conversion | **convert** |
| V2 | Lowering: same type, nothing; to Any, a box; from Any, a let of the Any, a type test, the checked value or a CastError failure; try-convert the same with Ok/Err; an immediate `(Ok x)`/`_` match, or a Pair of two, without the Result | conversions.sld `lower-expr` 199, `projection` 93, `lower-match` 244 | — | — | convert |

## F: final checks

| # | Behavior | Function | Message | Place | Goes to |
| --- | --- | --- | --- | --- | --- |
| O1 | Every data type of the program: no Borrow field; no linear element of a Vector or Array; no linear content of a Ref; parameters unrestricted; in table order, first stops, at every library's check-final (probe `hold-first`: reported over main's type error) | ownership.sld `check-owned-fields` 92, `check-type` 42 | `a Borrow cannot escape into an owned type, result or storage`; `a type argument must be unrestricted: a Vector or Array holds no linear value`; `a cell holds no linear value: own it in a frame or in the application's state` | `ownership` line 0 | **hold** |
| L1 | A `fn` reads no local from around it but its own let name; pre-order, first per item | `check-closed` 2709, `captured-read?` 2728 | `a fn has no environment, so it cannot read the local X; use lambda` | the read | **close** |
| W1 | `set!`/`replace!` write a place: links followed inward to the first mutable field; each a struct's own field, by accessor or through the struct's own instance | `check-places` 2634, `check-place-links` 2648, `place-link` 2655, `link-field` 2672 | `a place is a cell's content, (ref-get cell), or a chain of struct fields read from one`; `cannot write a computed field: its instance has no slot to write`; `cannot write a field through a requirement: the record's type must be known`; `cannot write through an enum's case; replace the whole enum` | the link | **place** |
| B1 | An item's types: no Borrow in an owned type or result; no linear global; expression types representable | ownership.sld `check-owned-types` 102, `check-expression-types` 138 | O1's; `a linear value cannot be a global` | the node | **borrow-check** |
| B2 | Paths: a linear local used once on every returning path; alternatives agree; a scope's linear names consumed; Never and panic do not return | ownership.sld `consume`, `require-live`, `close-scope`, `join`, `agree`, `check` | `linear value used more than once: X`; `linear value never consumed: X; use it once, or drop it`; `alternatives must consume the same linear values: X` (each with the Copy advice) | use, scope, branch | borrow-check |
| B3 | Field operations work in place; reads, setters and replacers may not duplicate or discard linear content | `check-field-grades`, `check-field-value`, `check-place`, `check-chain` | `destructure a linear record with match ...`; `reading a mutable field would duplicate ...`; `setting a mutable field would discard ...`; `a replacement would discard ...`; `apply a field operation to a linear record by name ...`; `a field operation works on a linear record in place; ...` | the callee or record | borrow-check |
| B4 | Lexical borrows and receivers: with-borrow lends a local or an immutable field path; a borrowed owner is frozen; FnMut needs exclusive access; shared captures are read-only; no closure captures a borrow; no continuation while a borrow is active; Fn to FnOnce adaptation | `check-let`, `lend`, `lend-field`, `check-receiver-call`, `check-write-loan`, `check-lambda`, `check-yield-holds`, `check-consuming-adaptation` | `an owner cannot be moved while it is borrowed`; `a borrow must be introduced by with-borrow`; `alias a Borrow with let; ...`; `a borrow must name a local owner or an immutable field path`; `a borrow cannot refer to mutable field storage`; `an FnMut call requires exclusive access to its receiver`; `mutating an owned capture requires an FnMut receiver`; `a closure cannot capture a Borrow or a frozen owner`; `a call cannot capture a continuation while a lexical borrow is active`; `an owned shared or exclusive receiver cannot adapt to a suspending FnOnce call ...` | as each | borrow-check |
| B5 | Drops that may run: a once lambda's captures, values live across a yield, a generic use's linear types, fit the row of who may drop them | `check-capture`, `check-yield-holds`, `check-instantiation`, `check-drop-rows` | `a once lambda captures X, which it drops ...`; `X is live across a call that may yield, ...`; `N may hold a T across a yield, ...`; `..., whose drop this function's row ... bounds ...` | as each | borrow-check |
| B6 | Closures, wildcards, conversions, statements: an unrestricted procedure captures no linear value; a wildcard discards none; none crosses Any; a statement is not linear | `check-lambda`, `bind-pattern`, `check-conversion`, `check-discardable` | `an unrestricted procedure cannot capture a linear value`; `a wildcard cannot discard a linear value; ...`; `a linear value cannot cross a dynamic type boundary`; `a linear value cannot be discarded; drop it` | as each | borrow-check |
| B7 | Foreign references obey the host boundary | `check-instantiation`, `check-boundary-type` | E3's Borrow message | the reference | borrow-check |
| M1 | A confined function (X5) whose parameters, result or outside reads could hold storage: first parameter, then result, then the reads in order; on the zonked, **unlowered** lambda | `check-confined` 2454, `check-outside-read` 2483, `reaches-storage?` 2494, `primitive-alias?` 2513, `holds-storage?` 2543 | `this function's type does not allow mut, so it may mutate only storage it allocates, but its parameter X, a T, / its result, a T, / N could hold storage from outside` | the function; the read | **confine** |

## What the checker reads of the program

From `Program` (core.sld 1141): values (schemes, `function?`, signature
places, accessor and constructor cases, method classes, operations' effects),
data types (cases, fields, `enum?`, `owned?`), classes (parameters, rows,
outputs), every instance of the whole program by class, effects (operations,
control operations, defaults, `around-main`), and the items of every library
(`primitive-alias?`). Each is placed in `design.md` section 4.
