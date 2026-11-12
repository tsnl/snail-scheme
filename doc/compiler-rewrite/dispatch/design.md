# The `dispatch` and `cohere` passes: design

Files beside this one: `inventory.md` (every old behavior, its function,
message, place, phase and pass), `language.sld` (Dispatched, a draft in the
style of `derive/language.sld`), `listing.sld` (Listed, what one instance is
between libraries, a draft), and `probes/` (programs run on the old
compiler; each result is cited where it is used).

## 1. The proposal in one table

| Pass | Unit | Reads | Writes | The one thing it does |
| --- | --- | --- | --- | --- |
| `dispatch` | library | Declared, Declarations, Listed | Dispatched | Dispatch clauses and `dynamic-instances` forms become instances with methods. |
| `cohere` | library | Dispatched, Listed | nothing | No two instances that can be active together overlap on their selecting types. |

```text
dispatch : Declared (List Declarations) (List Listed) -> (Result Dispatched (List Feedback))
cohere   : Dispatched (List Listed) -> (Result Unit (List Feedback))
```

**`dispatch` is one pass, not two.** Its two jobs could be split, clauses
then families, since no source of a family is ever a dispatch-clause
instance (a source's head must match two non-Any types, and a clause's head
holds Any). The split is rejected for two reasons. First, both write the
same runtime contract, the code that recovers a value from Any and the
CastError that fails it (`conversion-error`, `recover-value`); under the
import rule a second pass could not import the first's part, so the
contract would have two homes. Second, the old checks are interleaved in
written order in one discipline, D-phase problems (clause domains DC2 and
every family check DY3-DY12) stopping the library before any Y-phase
problem (clause methods DC7). One pass reproduces that order exactly
(probe `dispatch-d-before-y.sld`: the family's problem at 12:3 is the only
one reported, though the clause before it has a method problem); two passes
would add a listed difference for nothing. Inside the pass the two jobs are
two parts.

**`cohere` is one thing**: overlap, the one decision in I11, X3 and Y12.

### The layout

```text
dispatch/
  language.sld     Dispatched
  listing.sld      query: Listed, every instance a library declares, selecting types, active?
  matching.sld     query: one-way matching of an instance's head (old match-types), for dispatch and solve
  text.sld         query: a type, a Global and a place as the old compiler writes them
  runtime.sld      rule: the Globals the generated code names (CastError, Ok, Pair, ...)
  known.sld        rule: a class as known where a form is: kinds, outputs, each method's member and own scheme
  domains.sld      rule: what a dispatch clause covers (DC2, DC3) and each method's shape (DC7)
  binary.sld       rule: a binary family: its class (DY3, DY4), each pair's case (DY5-DY7), the heads (DY9), a head's cases, output and row (DY10), a head's row check (DY12)
  state.sld        the numbers it hands out, and numbering-let*
  conversions.sld  part: the code that recovers a value from Any, and the CastError that fails it
  clauses.sld      part: an instance's dispatch clause becomes its methods
  families.sld     part: a dynamic-instances form becomes its instances
  pass.sld         (snail compiler dispatch pass): the walk
cohere/
  overlap.sld      rule: when one head overlaps another (old head-overlaps?)
  pass.sld         (snail compiler cohere pass): the checks
```

Rules return shapes, not Booleans, so nothing downstream needs a panic:
`domains` answers a clause's erased parameter with its targets; a method's
selector index and which parameters are erased; `binary` answers a
`BinaryClass` (its row parameter, its two type parameters, its output, its
methods), and each pair a `Case` (inputs, output, effects, and for each
method of the class the source's implementation Global). The one invariant
left, that a source passing DY7 implements every method, is stated where
the case is built: such a source was declared after its class (a source
before it could not give its row parameter a row, I15), so declare's I10
holds for it.

### The walk

`pass.sld` walks the tops in order, threading a `Walk`: the next number;
the library's classes reached so far; the instances before the current
top (the earlier libraries' listings, then this library's own, from
`tops-instances` of each top the walk has written); the sets of the scopes
around it; and the Y-phase problems so far. A D-phase problem ends the walk
with that problem alone; at the end, any Y-phase problems are the answer,
in order; else the tree.

- `TopClass`: the class is reached.
- `TopInstance` or an instance in a set, with `Dispatch` body: `clauses`
  checks DC2 (D) against the class as known, then, for each method of the
  class as known, DC7 (Y, one problem per method, each recorded and the
  walk going on) or the method's code; a Y problem leaves that method out
  of the tree, which then fails anyway.
- `DynamicInstances` in set g: `families`, with active sets g and the
  scopes' sets, and the instances before the form: DY3, DY4, DY5, every
  pair's DY6 and DY7, then the heads, the I15 row check per head, then the
  instances and their methods' code (all D).
- Anything else is copied; `InstanceScope` pushes its sets for the tops it
  holds.

What is known of a class (`known.sld`): an imported class from the
closure's Declarations, complete; a class of the library reached, as its
entity; one of the library not yet reached, its shape: every parameter a
type, its outputs, no method (probes `class-later-dispatch.sld`, accepted
with no methods, and `class-later-dynamic.sld`, refused by DY3); a field
class `::label`: parameters R and T, no row, no output, one member,
`FieldReader label`, whose own scheme is `(Fn R -> T)`. Lifecycle classes
are Drop and Clone of (snail core base).

Numbering: from Declared's `first-unused-number`, in walk order; for a
clause, each implementation's Global then its lambda's locals; for a form,
each instance's Global, then each implementation's and its locals. An
implementation's Global is named for its member, as `declare` names
written ones; a generated instance's `dynamic`. The root keeps where it
stopped.

## 2. Dispatched

The grammar, the data definitions and the guarantees are in
`language.sld`. The decisions:

- **Declared afresh**: the root, `Top`, `Instance` and `InstanceBody`, the
  rules `dispatch` looks inside or changes. Everything else is Declared's,
  including `Expr`: `dispatch` writes expressions but never looks inside
  one, as `derive` writes Bound's.
- **An instance set holds `Instance*`**. With `dynamic-instances` gone,
  `SetMember` would have one alternative; the list says the guarantee.
- **`InstanceBody ::= Methods InstanceMethod* | Dispatching
  InstanceMethod*`.** Who wrote the methods is the one fact the old Program
  keeps that no other node gives: a written method's `Defined` has
  `function? #f` (`instance-method` 2958), a dispatched or generated one's
  `#t` (2622, 2560). It follows from nothing else, so it is stored.
  (`Generated` would read better, but Outline's `Generated` is in the
  integrator's scope.)
- **A generated instance is an ordinary `Instance`** at its form's place
  in the set, in head order, `loc` the form's. So `cohere`'s I11 covers X3
  with no special case, and the adapter's item order is the tree's.
- **The dispatch clause's types are dropped.** The old Instance keeps no
  record of them; the methods are what they meant.
- **CastError texts are `Literal (Text ...)`**, decided once by `dispatch`
  through `text.sld` (risk 1).

A generated instance as source, from `tests/programs/binary-dispatch-errors.sld`
(pairs `(I64 I64) (I64 F64) (F64 I64)`, sources in `ordinary`), the head
`(Any I64)`, whose cases are `(I64 I64)` and `(F64 I64)`:

```scheme
(instance (Combine (! dyn-cast) Any I64)
  (type Output Any)                        ; outputs I64 and F64 differ
  (define (combine left right)
    (match (try-convert left I64)
      ((Ok left1) (convert (S1.combine left1 right) Any))
      (_ (match (try-convert left F64)
           ((Ok left2) (convert (S3.combine left2 right) Any))
           (_ (match (conversion-failed
                      (CastError (UnsupportedInstance)
                                 (Cons "I64" (Cons "F64" (Nil)))
                                 (any-type-id left)
                                 ".../binary-dispatch-errors.sld:21:19"
                                 "main:combine"
                                 0)))))))))
```

`S1.combine` and `S3.combine` stand for the implementation Globals of the
sources `(Combine (!) I64 I64)` and `(Combine (!) F64 I64)`. The heads, in
order, are `(Any I64) (I64 Any) (Any Any) (Any F64) (F64 Any)`. The
program's checks of the texts, lines 39-43, follow from them, worked by
hand from `binary-failure`: line 42, `(combine (ann #t Any) 2.0)`, selects
`(Any F64)`, whose one case is `(I64 F64)`, so it fails at index 0 naming
`"I64"`; line 41 selects `(Any Any)` and, its left being an F64, fails at
index 1 naming the Rs of F64's cases, `"I64"`; line 39's left is no case's,
so index 0 names every L, `"I64,F64"`. The comparison in S3 checks every
such text against the old program's.

## 3. Instances between libraries

**One instance**, as the passes that compare or choose instances need it,
is a `Listed` (`listing.sld`): an `Instance` node with its set, or a
`FieldInstance` (a struct with no mutable field, and one of its fields).
From it, queries answer its class; its variables; its types, rows
included; its outputs; its requirements and Copy variables; its set; its
selecting types, the types that are no row (outputs never); and whether it
is active under a list of sets. Where it was written is its instance's
`loc`; a field instance is never reported at (F1).

**The listing**: `library-instances : Dispatched -> (List Listed)`, every
instance in the order the old compiler enters them, the field instances of
a struct at its declaration, an instance scope's in turn, a set's in order.
It reads Dispatched, so generated instances are in it; it is the one home
(declare needs none; inventory, disagreement 1).

**What each pass is handed**:

- `dispatch`: the Declared library; the Declarations of its import
  closure (a class's parameters and kinds, outputs, methods' own schemes);
  and the listings of every library before it in the program's order,
  concatenated. It finds its own earlier instances itself, by
  `tops-instances` of each top it writes.
- `cohere`: the Dispatched library and the same listings. It needs no
  class: selecting types come from the instance. It lists its own library
  with `library-instances`.
- The integrator keeps, of each library, its Declarations, its listing and
  its latest tree, now Dispatched, and runs expand, bind, derive, declare,
  dispatch and cohere on it before the next.

**What `solve` would need beyond these**:

1. The method implementations of the chosen instance and, for a field
   instance, its accessor: both are in `Listed` already.
2. Every instance of the **whole program**, not of the libraries before.
   The old checker runs only after every library has expanded, over the
   whole Program (session.sld 75-143), so `matching-instance` (CK2) can
   choose an instance a later library declares, and the checker's own
   overlap check (CK1) sees later libraries' instances. A `solve` handed
   only earlier libraries would refuse the first and miss the second. The
   spec's Words say "every instance in the program"; the decision handed
   to me says "every library before this one". Risk 3.
3. CK1 itself: expression `with-instances` and each scoped top-level
   definition. It stays the old checker's at milestone A, and is `solve`'s
   (or a check of its own) at B.
4. One-way matching (`matching.sld`) and a type's text for its messages
   (`text.sld`), both queries here so that it can import them.

## 4. Overlap

**Selecting types**: an instance's head's types that are no row; a field
instance's record and field types. Outputs and rows never select.

**When one head overlaps another**, `a` against `b` (the old
`head-overlaps?`, in Declared's types; `cohere/overlap.sld`):

- `a` is `Con g as`: overlaps `Con g bs` when each of `as` overlaps the
  `b` at its position and there are as many; overlaps any `Var`; nothing
  else.
- `a` is `Callable f c _` but not `Callable Dyn FnContract _`, or `Code
  _` (the old `TCon "FnMut"`, `"$impl.Fn"`, `"fn"` of an arrow): overlaps
  a `Callable` of the same former and contract, or `Code` for `Code`, and
  any `Var`; nothing else.
- `a` is `Callable Dyn FnContract _` (the old bare `TFun`), `Var` or
  `Row`: overlaps everything.

Instance `i` overlaps `j` when their selecting types are as many and each
of `i`'s overlaps `j`'s at its position. A repeated variable is not
unified. The rule is sound for the checker's choice (`match-types`: a Con
pattern matches Cons only, an arrow pattern arrows only, a row pattern
nothing), so no two instances it accepts both match one set of types.

**Active together.** An instance is active under a context's sets when it
is in no set or in one of them. A top-level `with-instances` activates its
sets and those of every scope around it; a `dynamic-instances` form its
own set and the scopes' around its set; an expression `with-instances`
its sets, those around it, and the top-level scopes' around its
definition. Two instances can be active together when one context
activates both.

**The old checks**, all with the one message:

| Check | Pairs | Which instances | When | Place |
| --- | --- | --- | --- | --- |
| I11 | new `a` against each earlier `b` of its class | both in no set, or both in one set, active or not | D, as each instance is declared; a field instance is never `a` (F1) | the instance |
| X3 | the same, for each generated instance | the same | D, at the form | the form |
| Y12 | every ordered pair of distinct instances, every class | active under the scope; the library's instances in full, later ones too | Y, one problem per scope, all reported | the scope |
| CK1 | the same as Y12 | active under the scope and those around it; the whole program | after every library expands | the scope's expression |

They agree on the rule and the selecting types. Where one is stricter:
I11 refuses two overlapping instances of one set though nothing ever
activates it, which no "active together" check would; I11 never compares
an instance in no set with one in a set, or two sets, which Y12 does at a
scope; Y12 is symmetric where I11 is not (probes: `asym-refused.sld`
refused at the instance 8:1, `asym-accepted.sld` accepted, `asym-scope.sld`,
the accepted one under a scope activating an empty set, refused at the
scope 11:1); Y12 reads instances declared after the scope
(`scope-later.sld`, refused at the scope 8:1); CK1 reads later libraries.

**`cohere`** reproduces I11, X3 and Y12 exactly. First, over its
library's listing in order, each `ListedInstance` against the earlier
libraries' and its own earlier entries of its class with the same set or
both none, as `a`; the first overlap is the only problem, at the
instance's `loc`. Otherwise, for each top-level `InstanceScope` in walk
order (a scope before what it holds), the instances active under its sets
and those around it, from the earlier listings and the whole of its own,
every ordered pair of distinct entries (by position) of one class; one
problem per overlapping scope, at its `loc`, all in order (probe
`scopes-all.sld`).

## 5. The order of problems

Every program under `tests/programs/` whose `.err` names a dispatch,
dynamic-instance or overlap problem has one problem in the old compiler,
so the order between passes never shows.

| Program | Old check | Place | Pass | Same message and place |
| --- | --- | --- | --- | --- |
| error-associated-overlap | I11 | 11:1 | cohere | yes |
| error-binary-domain | DY6, pair entry | 9:3 | dispatch | yes |
| error-binary-family-overlap | Y12 | 18:1 | cohere | yes (generated `(Any I64)` in `dynamic` and in `other`) |
| error-binary-source-inactive | DY6, no source | 13:3 | dispatch | yes |
| error-class-row-overlap | I11 | 18:1 | cohere | yes |
| error-dynamic-instance-any | DC2c | 4:1 | dispatch | yes |
| error-dynamic-instance-duplicate | DC2d | 4:1 | dispatch | yes |
| error-dynamic-instance-empty | DC2b | 4:1 | dispatch | yes (`dispatch-types` admits no type) |
| error-dynamic-instance-nested | DC7d | 7:1 | dispatch | yes |
| error-dynamic-instance-result | DC7e | 7:1 | dispatch | yes |
| error-instance-set-nested | Y12 | 17:17 | cohere | yes |
| error-instance-set-overlap | Y12 | 16:1 | cohere | yes |
| error-overlap | I11, against (snail core base)'s `(Show (! e) (List T))` | 4:1 | cohere | yes |

These are refused by the old checker, at milestone A still the old one,
and depend on `dispatch` writing the old code at the old places:
error-dynamic-instance-missing and -effects (the generated call, at the
instance), error-binary-dyn-cast, -effects, -linear, -no-boxing-retry and
error-dyn-cast-pure-class (the generated instances' rows and conversions).
error-instance-set-empty is expand's, error-instance-set-lifecycle
declare's (I13), -import and -inactive the checker's.

Where the new order differs, always under the accepted rule that an
earlier pass's problems are reported: declare's D problems now precede a
clause's DC2 (the old checks DC2 before I10-I18, inventory disagreement
4), and any declare problem precedes dispatch's; dispatch's precede
cohere's, so an overlap (I11, D) before a later DC2 or DY problem, or
before a DC7 (Y) problem, is no longer the one reported.

## 6. The milestone adapter

What these passes produce, and where the old entity's content comes from.
"Spelled" is the adapter's spelling of a Global, through `text.sld`'s
`global-text`, so the texts in the code and the names in the tables
agree.

| Old entity | From Dispatched | Recomputed by the adapter |
| --- | --- | --- |
| `Instance` of a clause instance | the `Instance` with `Dispatching` body | name spelled; class; vars `()`; types `types ++ outputs`; requires and copy `()`; methods `(member's old name . implementation spelled)` in order; set: the `InstanceSet` around it, else none |
| `Instance` of a generated instance | the `Instance` in its set | the same; set: that set |
| per-class instance order | the listing, library by library | the old per-class lists are the listing filtered by class |
| `Defined` of each dispatched or generated method | its `InstanceMethod` | scheme: declare's `implementation-scheme` at the instance; signature none; `function?` #t for `Dispatching`, #f for `Methods` |
| `Define` items | each `Dispatching` method's value | at the instance's place, in method order; for a form, each instance in order; Lambda `captures? #f`; `Match`, `Destructure` as `PCon`, `Bind` as `PVar`, `Wild`; `TryConvert`, `Convert`, `TypeTest` with their types; `Call` as `App`; `TopRef` as `Var name () ()`; `Literal` Text and Integer as `DString`, `DInt`; every node's type `unchecked`, where the old `call` helper wrote the call's type and type arguments, which the old checker reads neither of (`infer`, check.sld 584-595) |
| field instances `lib:::label@S` | `FieldInstance` | declare's half of the adapter |
| `ScopedInstances` | the `InstanceScope`s around a definition or statement | as declare's design says, twice for a definition; never around an instance's methods, dispatched ones included (as `instance-method` and `install-generated-instance` write none) |

## 7. Slices

Each leaves `make test-compiler` and `make compare-compiler` passing.

| Slice | Content | Judged by |
| --- | --- | --- |
| S0 Shared queries (declare) | `declare/equality.sld` and `declare/forms.sld` marked queries; `declare/schemes.sld` exports its substitution, `pure-struct?` and the field class's member scheme. No behavior changes. | `scripts/compiler-imports --check`; existing tests |
| S1 Language and queries | `dispatch/language.sld`, `listing.sld`, `matching.sld`, `text.sld` | unit tests by hand: a library's listing (scopes, sets, pure and impure structs, order); `matching` cases read off `match-types`; `text` cases read off `type->string`, `loc->string` and old unique names |
| S2 Dispatch clauses | `runtime`, `known`, `domains`, `state`, `conversions`, `clauses`, `pass.sld` for every top but `DynamicInstances` | unit tests building Declared instances by hand, one per DC2 and DC7 message, and the code for `Num` at `(dispatch I64 F64)` and `Describe` at `(dispatch I64 String (List I64))` against the old `dispatch-method`'s output written down; one test per probe it reproduces (per-method problems, class declared later) |
| S3 Families, wiring, comparison | `binary`, `families`; the integrator runs declare then dispatch; the comparison runs them after derive | `make compare-compiler`: failures alike (error-binary-domain, -source-inactive, error-dynamic-instance-*); every instance dispatch wrote beside the old instance of its class and head, in the old order of its class: set, variables, requirements, and each method's value in the normal form, now including dispatched methods, CastError texts compared as texts; the listing of each library beside the old program's instance tables |
| S4 `cohere` | `overlap.sld`, `cohere/pass.sld`, the integrator | unit tests over literal listings, one per behavior: I11 asymmetric, same set, never a field instance as `a`, X3 within one form, Y12 symmetric, later instances, every scope reported; the comparison: the seven overlap programs fail alike; and the probes added to `tests/programs/` as programs with `.err` (asym-refused, asym-scope, scope-later, field-after, scopes-all) or expected output (asym-accepted, field-before), pinning the old behavior |
| S5 Milestone adapter | section 6, after declare's half | the whole suite through the old checker and backend: `make test`, `test-chibi`, `bootstrap`, `check` |

S2 and S3 are about 600 lines each with tests, S4 about 300.

## 8. Risks and open questions

Most important first.

1. **CastError texts spell names.** The generated code puts in the running
   program a type's text (short names), a place, and the method's
   `library.parts:name`; programs read them (`binary-dispatch-errors.sld`,
   `dynamic-instance-mismatch.sld` print `expected`). That builds a text
   from names, which the conventions forbid for names. Recommendation:
   allow it as display text, like a message, in one query, `text.sld`,
   which the adapter's old names and the later passes' messages also use;
   list that a macro-written method or type is spelled by name and serial,
   where the old spells its mark's stamp (no program in the suite has one
   under dispatch).
2. **The asymmetric rule.** Reproduce it exactly (the probes); making it
   symmetric would refuse `asym-accepted.sld`, which the old accepts. File
   an issue to make it symmetric, and precise for repeated variables,
   after the replacement.
3. **Which instances `solve` sees.** The old checker sees every library,
   later ones too (section 3). Not blocking `dispatch` or `cohere`, whose
   old counterparts see only earlier libraries. Recommendation: decide
   before `infer`: run `solve` once every library is through `cohere`,
   handed every listing, as the spec's Words say.
4. **Shared operations live in declare's rules.** `dispatch` needs type
   equality, row sets, substitution, Drop and Clone, `pure-struct?` and the
   field class's scheme; `cohere` `same-global?`. Recommendation: S0,
   rather than second copies.
5. **Classes as known.** Reproduce the old order dependence by threading
   the library's classes reached, as declare does: a clause instance
   before its class gets no methods, a form before its class is refused.
6. **Selecting types of an instance written before its class** that gives
   a type to a later row parameter (inventory disagreement 2). With the
   no-row rule, `cohere`'s Y12 and `dispatch`'s source match compare that
   type, where the old drops it. Recommendation: accept and list it; the
   instance implements no method, and the exact rule would need the class
   at every check. The alternative is `library-instances` computing
   selecting types with the library's final classes.
7. **`function?`.** Kept by `Dispatching`; the alternative, one body kind
   and a listed difference, is unobservable (the old checker reads
   `function?` only for a name a `Var` uses, `environment-free?` check.sld
   1189, and no Var names a dispatched implementation) but loses the
   exact rebuild.
8. **A domain type that is a row** (DY12): refuse in `dispatch` with I15's
   old message, after every pair resolves, so that Dispatched's head
   invariant holds; the old reports X3 first when a head both overlaps and
   holds a row, an accepted two-pass difference.
9. **Cost of Y12.** Every ordered pair of every class's active instances,
   over the whole program so far, per top-level scope, as the old does.
   Recommendation: measure on Chibi in S4 (`make test-chibi`).
10. **The list of known differences** gains, if accepted: risk 1's
    spelling, risk 6's corner, and the reordering of section 5's last
    paragraph as an instance of the two-pass rule.
