# The typed half: `infer` to `confine`, design

This designs the passes that replace the old checker
(`src/snail/shell/compiler/check.sld`, 3,680 lines, with `ownership.sld`,
`conversions.sld` and the parts of `capabilities.sld` and `core.sld` it
calls). `inventory.md` lists every behavior of the old checker, its message,
place and phase, and the pass each goes to; this file cites its rows (U1,
C10, ...). `inferred.sld` and `owned.sld` are drafts of the first and last
languages. Code wins where the book disagrees; each such place is named.

Facts below were read in the code at 17ed1f95 unless a probe is cited
(section 5, "Probes").

## 1. The proposal in one table

The old checker is one function per library with six phases (inventory,
"The old order"). The proposal keeps the eight passes of `passes.md` and
adds four check-only passes, each one cut where the old checker already
has a boundary between what it decides and what it then checks.

| Pass | Unit | Reads | Writes | The one thing it does | Why it is its own pass |
| --- | --- | --- | --- | --- | --- |
| `hold` | program | every library's Declarations | nothing | Every data type's fields can be owned: no Borrow, no linear element or cell content, unrestricted parameters (O1). | The old check covers the whole program's types at the first library's final checks (probe `hold-first`), so it is not any one library's. |
| `scope` | library | Dispatched, every instance | nothing | The instances active together under each `with-instances` do not overlap (X2's check). | Needs no type; asks of a use site what `cohere` asks of a declaration, over the whole program. |
| `infer` | library | Dispatched, Declarations and Definitions of the import closure, every instance and every library's Declarations | Inferred | Every node gets a type; what a node's checking decides is decided there; what it leaves open is recorded. | The old phase I, which must stay one walk (section 2.1). |
| `cover` | library | Inferred | nothing | Every clause of every match is useful, and the clauses are exhaustive (X8). | Usefulness reads only patterns and constructor sets. |
| `solve` | library | Inferred, every instance and every library's Declarations | Solved | Every recorded constraint is decided: defaulting, literal and Copy checks, class evidence (S1-S10). | The old phase S. |
| `expose` | library | Solved | nothing | Exposed functions are defined, monomorphic, keep linear values and borrows inside, and a dynamic one is pure first-order data (E1-E4). | Reads types as solved but unsettled: an unsolved type is refused here, which settling would make Unit (E4). |
| `settle` | library | Solved | Typed, Definitions | Every unknown and hole is replaced; every definition has its scheme (Z1, Z2). | The old zonk. |
| `convert` | library | Typed | Converted | Each Any boundary is checked, then becomes a box, or a test guarding an unbox (V1, V2). | The old phase C. |
| `close` | library | Converted | Closed | Each lambda gets its captures, or is code that reads no local around it (L1). | The first of the old final checks. |
| `place` | library | Closed | Placed | Each write through `set!` and `replace!` names a place (W1). | Parse, don't validate: the old check becomes a value. |
| `borrow-check` | library | Placed | Owned | Each local read is a use or a loan; the linear and borrow rules hold (B1-B7). | The old `ownership.sld`. |
| `confine` | library | Owned | nothing | A function whose type forbids `mut` mutates only storage it allocates (M1). | The old confined check. |

`Definitions` is new: what a typed library offers its importers' typing,
each definition's scheme (section 4). `settle` writes it, as `declare`
writes Declarations beside Declared.

### The loop

Instances are global, so the integrator already runs `read` to `cohere`
over every library before any library is typed (milestone A design,
"Dispatch and cohere in the loop"). After them it runs `hold` once over
every library's Declarations in program order, then, library by library
in program order, `scope` to `confine`. A library that fails stops the
program, as the old `check-program` does (a `compile-error` ends it).
Each library's `infer` is handed the Definitions of its import closure,
which the earlier libraries' `settle` wrote.

### Layout

```text
src/snail/compiler/
  hold/
    pass.sld            the function `hold`; check-only, so no language.sld
  scope/
    pass.sld            the function `scope`
  infer/
    language.sld        Inferred
    solution.sld        query: a type or evidence through a solution; free unknowns
    unify.sld           query: the solution two types' unification extends, or the mismatch (U1-U4)
    rows.sld            query: what a context must add to include a latent row (U5)
    text.sld            query: a type as messages print it (U8)
    groups.sld          query: the dependency groups of unsigned definitions (G1)
    linearity.sld       query: whether a type is linear or unrestricted
    lifecycle.sld       query: a type's drop and clone rows and plans (S6)
    improvement.sld     query: what a constraint's known inputs decide of its other types (C8, C9)
    evidence.sld        query: the evidence a constraint has, or why it has none (S4-S10)
    boundaries.sld      query: what an Any boundary refuses of a type (F5, V1)
    literals.sld        rule: a literal's type, or its unknown (N4)
    generalization.sld  rule: the unknowns a group quantifies, and the names they get (G4)
    host.sld            rule: whether a row's effects have host implementations (G3)
    performed.sld       rule: the effects a signed body declares but never performs (G5)
    state.sld           the inference state, inferring-let*
    fitting.sld         part: a value fitted to an expected type (F1-F5)
    calls.sld           part: calls (C1-C10)
    patterns.sld        part: patterns (P1)
    handlers.sld        part: handlers (H1, H2)
    cleanup.sld         part: cleanup charges (K1)
    expressions.sld     part: every other node (X1-X7, N1-N6)
    definitions.sld     part: groups, signed items, statements, the body, recovery (G2-G8)
    pass.sld            the function `infer`
  cover/
    usefulness.sld      rule: whether a pattern row is useful after others (Maranget)
    pass.sld
  solve/
    language.sld        Solved
    defaulting.sld      rule: which literal unknowns default, and to what (S1)
    pass.sld
  expose/
    pass.sld
  settle/
    language.sld        Typed
    offer.sld           Definitions
    types.sld           query: storage, Any and representation facts of Typed types
    pass.sld
  convert/
    language.sld        Converted
    lowering.sld        rule: the shape a conversion lowers to (V2)
    pass.sld
  close/
    language.sld        Closed
    pass.sld
  place/
    language.sld        Placed
    links.sld           rule: what one link of a place is (W1)
    pass.sld
  borrow-check/
    language.sld        Owned
    paths.sld           the state of a path through a body, path-let*
    ...                 parts as ownership.sld's sections
    pass.sld
  confine/
    storage.sld         rule: whether a parameter, result or read could hold outside storage
    pass.sld
```

The machinery that decides constraints is needed by `infer`, which
decides some of them at the node, and by `solve`, which decides the rest
(section 2.1). The import rule forbids `solve` importing `infer`'s rules,
so each such library is a query (`;; Query:`): each answers a fact about
Inferred's types and solutions, such as the most general unifier or the
one matching instance, as mechanical as matching a head, which
`dispatch/matching.sld` already offers as a query. What is a choice of
policy stays a rule of the pass that makes it: generalization is
`infer`'s, defaulting `solve`'s. This reading of "query" is open question
1.

## 2. `infer`, `solve` and `settle`

### 2.1 What `infer` decides, and why at the node

The old checker decides some constraints while it walks and records the
rest. A faithful port must decide the same ones at the same moment: each
below changes which programs are accepted, or where a problem is
reported, if moved to `solve`.

1. **Every equality** (U1-U4). Checking is bidirectional: a lambda's
   parameters come from the type expected of it (X3), and whether a value
   meets Any by conversion or by unification depends on what is known of
   both at that moment (F1, F5, C3). The solution is threaded through the
   walk.
2. **Row inclusion** (U5, U6, U7): each call's latent row is included in
   its context where the call is checked, and a signed body records what
   it performs.
3. **Improvement within a call** (C9): the result of `(::f r)` is known
   from `r`'s type before the next argument is fitted, and an associated
   output before the result is.
4. **Row classes whose selecting inputs are known at the call** (C10).
   Probe `charge-at-call`: `release` has no signature and drops a
   `Handle`, whose Drop instance performs `log`; the Drop constraint is
   solved at the drop (8:3), `log` joins `release`'s row before
   `release` is generalized, and the problem is reported at the call in
   `quiet` (11:3). Deferred, `release`'s row would generalize without
   `log` and the problem would move to the drop, or vanish.
5. **Callable evidence and erasure** (F2, F4, C7, C8), which decide a
   lambda's identity and whether a closure can be stored.
6. **Cleanup charges** (K1), at the end of each definition, statement and
   lambda body. They read evidence as known then (a hole is an ordinary
   call) and change the row that generalization then quantifies.
7. **Generalization** per group, in dependency order (G4): later groups
   instantiate the scheme.
8. **Checks of the moment**: host effects (G3), the total initializer and
   the performed effects of a signed definition (G5), the clause-less
   match (X7, which reads the scrutinee's type as known when the match is
   checked), and the early refusals at an Any boundary (F5).

Everything else is recorded and decided by `solve`.

### 2.2 What a recorded constraint is

A `Pending` (`inferred.sld`, "Constraints"), in the order raised, which is
the order the old `pending` list is read in (oldest first):

- `WantClass hole requirement scope loc`: a class or callable requirement
  of a use's instantiation, at the types instantiated, whose evidence is
  the hole numbered `hole` (N1). `scope` is what was in force where the
  use was: the givens of the enclosing signature (evidence `Given n` is
  the n-th), the variables it says Copy, and the instance sets of every
  enclosing `with-instances`.
- `WantLiteral unknown constant loc`: a numeric literal whose type is the
  unknown (N4).
- `WantCopy type scope loc`: a variable a use's scheme says Copy,
  instantiated at `type` (N1).

The solution holds what `infer` decided: each unknown's type, each
hole's evidence when found at the call (C10, F2), and the counter. Holes
and unknowns share one counter with lambda identities, as the old
`fresh-identity` does (check.sld 189), so `infer` allocates in the old
order and a closure's identity text is the old one (risk 3).

### 2.3 Definitions: order, groups and generalization

`infer` walks a library's code in the order the milestone-A adapter hands
the old checker its items: the tops in order, an instance's method
implementations at the instance, an effect's defaults at the effect, and,
for a program, the body last (milestone A design, "What adapted-program
fills"). From that list (G1-G8):

1. The unsigned definitions are grouped by strongly connected components
   of their references, numbered in that order (`infer/groups.sld`, the
   old `definition-groups` and `strong-components`).
2. Each group, in the components' order: provisional types (a lambda's is
   its closure type, identified by the definition); each member inferred
   in a fresh row; cleanup; unification with the provisional type; host
   effects; then generalization, if every member is a lambda. The
   quantified unknowns are the group's free unknowns less those free in
   an earlier unsigned definition's type, in a constraint the group
   raised, or in an exposed definition's row; they are named
   `Generalized 1 ...` in order of first occurrence, which the adapter
   spells `t1 ...`; no requirement is generalized.
3. Every item in order: a signed definition, method or default is checked
   against its scheme (G5, G6); a statement in the context of the
   `around-main` effects (G7); an exposure is skipped.
4. Recovery (G8): a failed item's step is undone, which threading makes
   keeping the state from before it; its problems are kept; a failed
   unsigned group's names fail with it; an item that names a failed name
   is not checked. The pass fails with every item's problems in source
   order, and then no constraint is solved.

A program's body, which Declared keeps as one expression, becomes what
the old `with-one-body` writes (expand.sld 924): an unsigned definition
of a nullary closed lambda of its own Global, defined after every other
item, and one statement calling it, at the body's place. `infer` takes
the Global's number from `first-unused-number`. The body is a definition
because the old checker groups and generalizes it as one.

A definition's lambda value is written as a `ClosedLambda`, because the
old expander marks it `captures? #f` (`top-level-value`, expand.sld 1894,
applied to definitions, methods and defaults alike) and the old checker
cannot tell it from a `fn` (F3, `environment-free?` check.sld 1189).

Paths are desugared as the old expander does (N6): one label is a use of
its field class's method; several are a closed lambda over a fresh local
applying each reader in turn; `(::a::b r)` is the readers applied in turn,
all at the path's place. A `case-id` is typed I32 and raises no literal
constraint (N5). A `with-instances` is gone: its sets are in the scope of
the constraints raised under it. An `ann` is gone once its value is fitted.

### 2.4 `solve`

`solve` reads only the constraints and the solution; it never walks the
tree. In order (S1-S10):

1. Improvement over every pending constraint, to a fixed point.
2. Defaulting (`solve/defaulting.sld`): each float literal whose type is
   still unknown becomes F64, then each integer literal I64, in pending
   order. Improvement again.
3. Each literal checked against its type, and each Copy constraint, in
   pending order.
4. Each class constraint, oldest first, under its own scope: `Unboxed`
   from the representation or a given; a row class or a class with
   outputs from its selecting inputs; Drop and Clone from the type's
   lifecycle; any other from a given with equal types, else the one
   matching instance among those active under the scope's sets, whose
   requirements are satisfied in turn, with the termination check.
5. The first problem stops the pass, as in the old phase S.

`solve` writes Solved: Inferred's tree unchanged and the complete
solution. It is handed every instance of the program, and every library's
Declarations for the classes those instances require (section 4).

### 2.5 `settle`

Each type through the solution: an unsolved unknown is Unit, an unsolved
row tail closes; each hole its evidence; each unsigned definition's
scheme zonked; a signed one's as written (Z1, Z2, `final-schemes`
check.sld 3529). It writes Typed, which has no unknown and no hole, and
the library's Definitions.

### 2.6 State

The old checker already threads its state (`learning`, `resumed`, no
cell), so the port keeps that shape: `infer/state.sld` holds the
`Inferring` state, scope (locals, givens, Copy variables, sets, the
signed body's performed set, whether the body is confining) and learned
(the solution, the schemes so far, the pending constraints, the
definitions still open, the counter), with `inferring-let*`. A sub-check
under another scope returns its value and the learned part, as `within`
does (check.sld 674).

## 3. The languages

| Language | Pass | Declares afresh | Reuses |
| --- | --- | --- | --- |
| Inferred | `infer` | root, Top (Define, Statement, Expose only), Origin, Expr and Term, Clause, Implementation, Pattern, Type with `Unknown` and `Closure`, Arrow, Effects, TypeVariable with `Generalized`, Scheme, Requirement, Evidence, Plan, Pending, Solution | Expanded's Local, Global, TopValue, Constant, Annotation, ClassRef, Former, Contract, Member; Syntax's Datum |
| Solved | `solve` | the root alone: the tree and a complete solution | everything else of Inferred, which `solve` never looks inside |
| Typed | `settle` | everything Inferred declares but Pending and Solution: Type without `Unknown`, Evidence without `Hole`, Define with a final Scheme | as Inferred |
| Converted | `convert` | root, Top, Expr and Term without Convert and TryConvert, with Box and Unbox | Typed's types, Scheme, Evidence, Plan, Pattern (open question 2) |
| Closed | `close` | root, Top, Expr and Term with Closure and Code for Lambda and ClosedLambda | as Converted |
| Placed | `place` | root, Top, Expr and Term with Assign and Swap, Place, Link | as Converted |
| Owned | `borrow-check` | root, Top, Expr and Term with Use and Lend for LocalRef | as Converted |

Inferred keeps only a library's code, as the old `Item` does: definitions
(written, an instance's method implementations, an effect's defaults, the
body), statements and exposures. Declarations stay in Dispatched and its
offers, which the integrator holds and later passes may read; nothing
after `infer` reads an instance's untyped method bodies.

Converted to Owned reuse Typed's types, schemes and evidence: none of them
writes a new form of them, and each reads them through `settle/types.sld`.
The convention reuses a rule only where the pass never looks inside it;
`borrow-check` and `confine` do match on types. Copying would add five
copies of the type rules and a type map per pass. This is open question 2.

### Proposed text for `passes.md`

The pass table gains four rows and corrects one:

```text
| `hold` | program | Declarations | nothing | Every data type's fields can be owned. | planned |
| `scope` | library | Dispatched, every instance | nothing | Instances active together under a with-instances do not overlap. | planned |
| `infer` | library | Dispatched, Declarations, Definitions, every instance | Inferred | Every node gets a type; constraints a node does not decide are recorded. | planned |
| `cover` | library | Inferred | nothing | Every match's clauses are each useful and together exhaustive. | planned |
| `solve` | library | Inferred, every instance | Solved | Every recorded constraint is decided. | planned |
| `expose` | library | Solved | nothing | Exposed functions are monomorphic and keep linear values and borrows inside. | planned |
| `settle` | library | Solved | Typed, Definitions | Every unknown and hole is replaced; every definition has its scheme. | planned |
```

The Typed sketch (passes.md "Typed, written by settle") is wrong in three
places against the old checker's output, which milestone B must rebuild:
`Lambda | Fn` are `Lambda | ClosedLambda` until `close`; the evidence
rules are `FromInstance InstanceRef Type* Evidence* | Given n | Derived
Plan?` (the old `EvDerived` holds callable, Unboxed and lifecycle
evidence, core.sld 740); and Typed also holds `Erase Expr` and a call's
`Invocation`, the two `Ann` forms the old checker leaves (check.sld 1045,
1134). Its "Gone since Expanded" line should name `PathApply` and `Let`'s
signature too. Proposed replacement:

```text
Typed       ::= Typed library Top* first-unused-number
Top         ::= Define Global Expr Scheme Origin Annotation* | Statement Expr | Expose TopValue symbol dynamic?
Expr        ::= Expr Term Type
Term        ::= Literal Constant | LocalRef Local | TopRef TopValue Type* Evidence*
              | Lambda Local* Expr confined? | ClosedLambda Local* Expr confined?
              | Call Expr Expr* Invocation? | If | Seq | Let Local Expr Expr | Match | Handle
              | Erase Expr | Convert Expr Type | TryConvert Expr Type | TypeTest Expr Type | CaseId Global id
Type        ::= Con Global Type* | Callable Former Contract Arrow | Code Arrow
              | Closure Contract Identity Arrow Type* | Row Effects | Var TypeVariable
Evidence    ::= FromInstance InstanceRef Type* Evidence* | Given number | Derived Plan?
```

"From Typed to Owned" should say: `convert`: Convert and TryConvert
become `Box`, `Unbox` and `TypeTest` under ordinary branches, a let of
the Any and a `conversion-failed` failure; `close`: `Lambda` becomes
`Closure` with its captures and `ClosedLambda` becomes `Code`; `place`:
calls of `set!` and `replace!` become `Assign` and `Swap` of a `Place`;
`borrow-check`: `LocalRef` becomes `Use` or `Lend`. The milestone table's
B row should read `hold` and `scope` to `confine`.

## 4. Between libraries

What each pass is handed beyond its library:

- **Declarations** of the import closure (`declare/offer.sld`): data,
  classes, effects. `infer` needs two facts an offered effect lacks:
  which operations have a default (G3: an effect is host-implemented when
  every operation has one) and whether the effect is `around-main` (G7).
  Recommendation: `OfferedEffect` gains `defaulted (List Global)` and
  `around-main? Bool`, since `declare` decides both.
- **Definitions** of the import closure (`settle/offer.sld`, new): for
  each definition, its scheme (signed, or as generalized and settled; an
  `impl` signature's type is the closure named by the definition, N2),
  `function?` (its value is a lambda, F3), and `primitive-alias?` (its
  value is a primitive's name, which `confine` treats as acting only on
  its arguments, M1; the old scans every item of the program for it,
  check.sld 2513). The old threads one table of every earlier library's
  schemes (`check-program`); only imported names can be read, so the
  import closure suffices. Constructors', fields', methods',
  operations', externs' and primitives' schemes stay
  `declare/schemes.sld`'s.
- **Every instance**, as the listing (`dispatch/listing.sld`) of every
  library, earlier and later: `scope`, `infer` (C10 selects at the call)
  and `solve`. Probe `scope-later` shows the old overlap check at a
  `with-instances` sees a library loaded after the one that writes it.
- **Every library's Declarations**, to `infer` and `solve`, for the
  classes an instance from a library outside the import closure requires,
  and its Drop instances' rows. `hold` reads every library's data.

### The old checker's overlap check

`check-active-instances` (core.sld 1237) is the old checker's own: at each
`with-instances`, every class's instances visible under the sets in
force, including those of enclosing scopes, pairwise, over the whole
program, reported at the scope's place among the item's problems (probe
`scope-expression`: a type mismatch at 12:17 and the overlap at 14:18,
both reported). The dispatch design left it to milestone B (its CK1).
`scope` checks it, for each expression's `with-instances` and each
definition under a top-level one, the item stopping at its first, every
item checked, all in source order. A top-level scope wraps a definition's
value twice in the old expander (`scope-instance-value` twice, expand.sld
1864), which reports the same problem once, since the item stops.

The overlap relation is the one `cohere` uses. A pass cannot import
another's rule, so it should be a query beside `dispatch/matching.sld`
(`dispatch/overlap.sld`, `;; Query: whether two instances' heads
overlap`), which `cohere` and `scope` both import; the dispatch design
planned it as `cohere/overlap.sld`, a rule.

## 5. The order of problems

The old order (inventory, "The old order"): a library's phase I reports
every failed item's first problem, sorted; else S's first; else E's first;
else C's first; else F: the program's first bad field, else every item's
first of closed, places, ownership, and every confined function's, sorted.

The new order: `hold` once; then per library `scope`, `infer`, `cover`,
`solve`, `expose`, `convert`, `close`, `place`, `borrow-check`,
`confine`. A collecting pass (`scope`, `infer`, `cover`, `close`,
`place`, `borrow-check`, `confine`) checks every item, each stopping at
its first, and reports them sorted by place; `solve`, `expose` and
`convert` stop at the first, as the old phases do.

A program with one problem reports the same message at the same place.
Differences, all of the accepted kind (two passes have problems, and the
earlier one's are reported), unless marked:

- **D1, scope before infer.** An overlap at a `with-instances` and a type
  problem elsewhere: the old reports both (probe `scope-expression`); the
  new reports the overlap alone. Within one item the old reports
  whichever comes first in the walk; the new reports the overlap.
- **D2, cover after infer.** A useless or missing clause and a type
  problem: the old reports, per item, whichever its walk met first, and
  every other item's; the new reports only the type problems, then only
  the clause problems.
- **D3, hold before every library.** A bad field and a problem of the
  first library the old checks: the old reports the first library's
  problem; the new reports the field. With a bad field the old reports
  it at its first library's final checks, ahead of every later library's
  problems (probe `hold-first`), as the new does.
- **D4, which bad field.** With several, the old reports the first in the
  program's data table order, which is the table's key order and so
  differs between Chibi and Wasm; the new reports the first in program
  order. Not of the accepted kind: listed.
- **D5, the final checks.** The old collects, per item, the first of
  closed, places and ownership, and the confined functions', in one sorted
  list. The new reports `close`'s, else `place`'s, else `borrow-check`'s,
  else `confine`'s. Within one item both report the same one.
- **D6, `?N` in messages.** A message that prints an unknown prints the
  old meta's number, which follows the counter (U8). The port allocates
  in the old order, so it prints the same; a deviation changes the number
  only. No `.err` pins a `?N`: `error-field-path-ambiguous.err` stops at
  `(::x`.

Tests: of the 250 `.err` files, every one but eight is one line, and the
multi-line ones are either one problem's substrings in order
(`error-callable-repeat-once`, `error-dynamic-instance-missing`,
`error-implicit-any-container`, `error-scheme-call-effects`,
`error-scheme-procedure-effects`) or several problems of one pass
(`error-several-types`: three of `infer`; `error-several-ownership`: two of
`borrow-check`; `error-several-bodies` is the front end's). The overlap
tests (`error-overlap`, `error-instance-set-overlap`,
`error-instance-set-nested`, `error-associated-overlap`,
`error-class-row-overlap`, `error-binary-family-overlap`) and the coverage
tests (`error-exhaustive`, `error-redundant`) are single problems. So no
expected output changes under D1-D6; `make compare-compiler` will show
whether any suite program has problems in two passes.

### Probes

Each ran on the old compiler, once, without a rebuild, from the worktree:

| Probe | Command | Printed |
| --- | --- | --- |
| `probes/hold-first.sld`: a struct with an `(Array (dyn (FnOnce -> Unit)))` field, and a type error in a body | `./scripts/snail-tool wat build/typed-design/probes/hold-first.sld > /dev/null` | `ownership: a type argument must be unrestricted: a Vector or Array holds no linear value` |
| `probes/scope-expression.sld`: two sets of overlapping instances activated together, and a type error in another definition | same, `scope-expression.sld` | `...scope-expression.sld:12:17: type mismatch: expected I64, found String` and `...scope-expression.sld:14:18: this instance overlaps another instance of the class on its input types` |
| `probes/scope-later.sld`: `(probe policy)` activates a set; `(probe later)`, loaded after it, declares an overlapping instance | same, with `-I build/typed-design/probes` | `.../probe/policy.sld:11:28: this instance overlaps another instance of the class on its input types` |
| `probes/charge-at-call.sld`: an unsigned function drops a `Handle` of `(owned handle)`; a pure signed function calls it | same, with `-I tests/programs/lib` | `...charge-at-call.sld:11:3: this performs effects its context does not allow: log` |

The comment inside `charge-at-call.sld` names lines 9 and 12; the drop is
at 8:3 and the call at 11:3.

## 6. The milestone B adapter

`adapter/typed.sld` (new) converts each library's Owned, with its
Definitions, into the old `Typed` (check.sld 155): the milestone-A
adapter's `Program`, every library's items in order, and the table of
every definition's scheme. The old specializer and backend then run as
they do now. What it rebuilds:

- **Types.** Declared's types as the declaration adapter spells them
  (`old-type`, adapter/declaration.sld 134); `Closure kind identity arrow
  captures` as `TCon "$callable.KIND:ID" (arrow . captures)` (core.sld
  234), ID being `file:line:column.N` for `AtLambda`, the local's spelling
  for `OfLocal`, the old name for `OfGlobal`; `Generalized n` as `TRigid
  "tn"`.
- **Expressions.** `Use` and `Lend` as `Var`; `TopRef` as `Var` with its
  types and evidence; `Closure` as `Lambda ... #t` and `Code` as `Lambda
  ... #f`; a call's invocation as `Ann callee (TCon "$invoke" ...)`
  (check.sld 1051); `Erase` as `Ann e T`; `Box` and `Unbox` as `Convert`
  (the old lowering keeps `Convert` for both, conversions.sld); `Assign`
  and `Swap` as the call of `prim:set!` or `prim:replace!` of the place
  rebuilt from its links; `CaseId` as `Lit (DInt id)` of type I32, which
  is what the milestone-A adapter's `Ann` checks to; a generated local
  (a path's, `%dyn-cast`) spelled from its Local. Captures are dropped.
- **Evidence.** `FromInstance` as `EvInstance` with the instance's old
  name (a field instance's as the milestone-A adapter names it); `Given`
  as `EvParam`; `Derived` as `EvDerived`, an `Implemented` plan with the
  old `Instance` from the program's table.
- **Items.** `Define`, `Do`, `Expose` in Owned's order, which is the
  milestone-A order (2.3); the body as `Define "main:%body"` and its
  `Do`.
- **Schemes.** Each library's Definitions plus the schemes of method
  implementations and defaults, by old name, accumulated over the
  libraries in order, as `check-program` does.

Before the new path is the default, each slice is judged against the old
checker through the same adapter (section 7), and the old checker's
remaining phases fill in for passes not yet written: from slice B5 the
adapter maps settled Typed to old items and runs the old
`lower-conversions` and final checks on them. `lower-conversions` and
`check-item-ownership` are exported now; `check-conversions`,
`check-closed-item`, `check-places-item` and `check-confined` are not,
so slice B5 adds them to `check.sld`'s exports, marked for the adapter,
until slice B10 deletes the use (open question 6).

## 7. Judging each pass

**Unit tests.** Each rule and query library tests literal arguments:
unification and rows (including two open tails, rigid tails, the
inclusion cases), improvement of fields and outputs, evidence choice with
givens, sets, Copy requirements, non-termination at the repeat and the
depth, lifecycle plans, generalization's fixed set, defaulting order,
usefulness matrices, overlap, the conversion shapes, place links,
storage. Each `pass.sld` tests hand-built input: a small Dispatched
library for `infer` (a let-polymorphic group, a signed body that
performs too little, a recovered failed group and the skipped item that
names it, an at-call row solve), a hand-built Inferred for `cover` and
`solve`, and so on, each with `expect` on the output or its feedback.

**The comparison.** `make compare-compiler` gains a typed stage: for each
program both front ends compile alike, run the old `check-program` on
the milestone-A `Program`, and the new typed half followed by the
adapter, and compare:

- both succeed or both fail;
- failures: every new problem is among the old ones, by message and
  place, and the two lists are equal when the old problems all belong to
  one new pass, by the inventory's "Goes to" for each message (D1-D5 are
  the only way they can differ);
- successes, library by library: the items in order and the scheme of
  each definition, in a normal form that prints every type, evidence and
  expression, renames closure identities and generated locals in order of
  first appearance per library, and spells everything else as the old
  does. Two runs of the old compiler agree on this form, so any
  difference is the port's.

Identity renaming in the normal form means the comparison judges the
typed result even if a numbering differs (risk 3); the adapter's exact
spelling is judged separately by the gates once B is the default.

## 8. Slices

Sizes are lines with tests, estimated from the old code's (the front end
ran about 1.3 new lines per old line: `declare` is 9,512 lines).

| Slice | What lands | Judged by | Size |
| --- | --- | --- | --- |
| B0 | `passes.md` corrections; `OfferedEffect` gains defaults and `around-main?`; the overlap relation as a query | the front end's comparison, unchanged | 300 |
| B1 | Inferred; `solution`, `unify`, `rows`, `text`, `groups`, `linearity` | unit tests | 1,400 |
| B2 | `infer` without classes: literals, locals, instantiation, lambdas, let, if, seq, patterns, handlers, signed and unsigned definitions, generalization, recovery, the body | unit tests | 2,200 |
| B3 | `lifecycle`, `improvement`, `evidence` queries | unit tests | 1,800 |
| B4 | `infer`'s calls and fitting: at-call solving, callable evidence, erasure, Any boundaries, cleanup charges | unit tests | 1,800 |
| B5 | `solve`, `expose`, `settle`, Definitions; the integrator runs them; the adapter from Typed, with the old remaining phases; the typed comparison | the comparison over the suite | 1,800 |
| B6 | `hold`, `scope`, `cover` | the comparison | 800 |
| B7 | `convert`, replacing the old lowering in the adapter | the comparison | 700 |
| B8 | `close`, `place` | the comparison | 800 |
| B9 | `borrow-check` (ownership.sld is 1,064 lines) | the comparison | 1,700 |
| B10 | `confine`; the adapter from Owned; the new path as default | `make test`, `test-chibi`, `bootstrap`, `check` | 700 |

About 14,000 lines. B2 to B4 cannot be compared with the old checker
alone, since nearly every program uses classes from its first library,
`(snail core base)`; B5 is the first comparison, so B2 to B4 lean on their
unit tests.

## 9. Risks and open questions

1. **Shared deciding machinery.** `solve` needs unification, improvement
   and evidence, which `infer` also runs. Recommendation: they are queries
   in `infer/` (section 1, "Layout"). The alternative, a library outside
   any pass, has no place in the import rule.
2. **Reusing Typed's types after `settle`.** Recommendation: Converted to
   Owned reuse Typed's Type, Scheme, Evidence, Plan and Pattern; none
   rewrites them. Strictly the convention asks for a copy wherever a pass
   matches a rule, which `borrow-check` and `confine` do.
3. **Numbering.** A closure's identity, `?N` in messages and generated
   names come from one counter. The port allocates in the old order to
   rebuild the old spellings; the comparison's normal form does not
   depend on it, so a deviation shows only as different names in the
   specialized functions (spec keys, specialize.sld 344), not different
   behavior.
4. **Two answers to "live across a yield".** `infer`'s cleanup (K1)
   reads evidence as known mid-walk; `borrow-check` (B5) reads final
   evidence. The old makes both decisions with one function
   (`consumed-references`) at different moments, and they can differ, so
   they stay two decisions, one per pass, on their own languages.
5. **The early refusals at an Any boundary** (F5) and the final ones (V1)
   are one check on types known at two moments. Recommendation: one
   query, `infer/boundaries.sld`, called by `infer` and `convert`.
6. **Old exports for the interim adapter** (section 6): four names added
   to the old `check.sld`. The alternative is to compare B5 only up to
   zonking, which the old checker does not expose either.
7. **`expose` reads unsettled types** so that an unsolved type in a
   dynamic export is refused as the old refuses it (E4). Settled first,
   it would be Unit and accepted.
8. **`cover` reads types at the end of `infer`**, the old at the match.
   The constructor sets come from the patterns, which are checked before
   coverage in both, so the answer should agree; the comparison checks.
9. **`confine` reads the lowered tree.** The old checks the unlowered
   zonked lambdas (check.sld 3418). Lowering adds reads of constructors,
   `conversion-failed` and a local the function binds, none of which can
   hold outside storage (M1's `reaches-storage?`), so the answer agrees.
10. **Owned's `Use` and `Lend`** are unread until milestone C. Lend is a
    loan's root, the owner `with-borrow` names (`check-let`,
    ownership.sld 325) or a call's receiver (`check-receiver-call`, 405);
    every other read is a Use. Milestone C may want borrow scopes too.
11. **Stage 0.** New walks: `scope`, `cover`, `expose`, and tree copies
    for Closed, Placed and Owned. Saved: `hold` once per program, where
    the old checks every type of the program at every library
    (check.sld 3427). Not measured; measure `make bootstrap` at B5 and
    B10.
12. **`t1` across groups.** Two groups' first quantified variables are
    the same rigid name in the old; they never meet, since a group's
    pending constraints keep their unknowns out of its scheme. The port
    keeps this.
