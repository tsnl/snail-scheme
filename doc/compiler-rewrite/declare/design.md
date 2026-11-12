# The `declare` pass: design

Files beside this one: `inventory.md` (every behavior, its function,
message, place, phase and pass), `language.sld` (Declared, a draft in the
style of expand/language.sld), `offer.sld` (Declarations, what a declared
library offers).

## 1. The proposal in one table

| Pass | Unit | Reads | Writes | The one thing it does |
| --- | --- | --- | --- | --- |
| `declare` | library | Derived, Declarations | Declared, Declarations | Declarations become entities, and every written type, member label and `case-id` in the library is resolved against them. |
| `dispatch` | library | Declared, Declarations, Instances | Dispatched | (unchanged: dispatch clauses and dynamic instances become instances and method definitions) |
| `cohere` | library | Dispatched, Instances | nothing | No two instances that can be active together overlap. |

`declare` is one pass: section 4 says why the obvious splits are wrong.
`cohere` is new: it takes the overlap checks, which need `dispatch`'s
generated instances.

## 2. Declared, and the representation of a type

The grammar and data definitions are in `language.sld`, with what Declared
guarantees over Derived at its head. The main decisions:

- **Entities are nodes, in written order.** `Data`, `Class`, `Instance`,
  `Effect`, `Extern`, `Primitive` and `Define` (with its signature) sit
  where they were written, as every earlier language keeps its tops. The
  old `Program` keeps entities in tables and code in items; the adapter
  builds those from the order. `dispatch` needs the order (a dynamic
  instance's sources are the instances written before it).
- **A Define carries its signature** (`Signed`), the last one written for
  it, as the old table keeps. Signature tops are gone; a signature for any
  other value was checked and leaves only its annotations.
- **What follows mechanically is a query, not a field.** The scheme of a
  constructor, a field function, a method as a value, an operation as a
  value, an instance's method implementation and a default all follow
  from the entity. `declare/schemes.sld` (a query, importable by the
  adapter and by `infer`) is their one home; the tree stores only what
  `declare` decided with a check.
- **Field classes have no entity.** A label names its class, `::label`,
  whose shape is fixed. A pure struct's field instances are implied by its
  `Data` (struct, no mutable field); the query `declare/listing.sld`
  answers them among the library's instances.

### Type

```
Type         ::= Con Global Type* | Callable Former Contract Arrow | Code Arrow
               | Row Effects | Var TypeVariable                     no Loc
Arrow        ::= Arrow Type* Type Effects
Effects      ::= Effects Global* Type?
TypeVariable ::= Written name | Associated number label | CallableArgument number
               | Own TypeVariable
Scheme       ::= Scheme TypeVariable* Requirement* TypeVariable* Type
Requirement  ::= ClassRequirement ClassRef Type* | CallableRequirement Contract Type Arrow
```

Old: `TCon name args | TFun params result row | TRow labels tail | TVar id
| TRigid name`, and `Scheme vars constraints copy type`.

Kept, and why:

- **Application by name** (`TCon` → `Con`), **rows as label sets with a
  tail**, used both as a function's effects and as a type argument
  (`TRow` → `Row`, `Effects`), **rigid variables only**, and the
  **scheme's shape** (variables, class requirements whose position is
  their evidence, Copy apart, type). These are what the old checker,
  monomorphizer and backend already rely on, and what `infer`, `solve` and
  `settle` need: unification over `Con`/`Row`, rows unified as sets with an
  open tail (`flatten-row`, check.sld 309), evidence by position. `infer`
  adds `Unknown number` to `Type`; `specialize` removes `Var`.
- **No Loc on a type.** Types are values, compared structurally
  (`type=?`), substituted and matched; Expanded's TypeExpr had locs because
  its problems were syntax's.
- **No projection** survives, as in the old compiler: each becomes the
  output the requirement in scope gives (an equation's type or the
  `Associated` variable).
- **The order of a scheme's variables** is the old one (written, then
  unwritten outputs, then callable arguments), since the adapter must name
  them as the old compiler does and evidence follows requirements' order.

Changed, and why:

- **Names are Globals, builtins included.** `TCon "snail.core.base:Option"`
  and `TCon "I64"` become `Con` of a Global of its library or of
  (snail core forms). Names are data; no pass joins or scans them.
- **Callables are a constructor, not magic names.** The old type encodes
  the former and contract in strings: `TFun` alone is `(dyn (Fn ...))`,
  `TCon "FnMut"`/`"FnOnce"` of a TFun are dyn, `TCon "$impl.Fn"` is impl,
  `TCon "fn"` is code, and `$callable.KIND:ID` is a concrete closure, found
  by prefix (`concrete-callable?`, core.sld 237). Declared has `Callable
  Former Contract Arrow` and `Code Arrow`, with the arrow a record of its
  own. The representation of a function value is what `convert`, `close`
  and `specialize` decide on; it should be matched, not parsed. The
  Typed sketch already keeps `Callable`.
- **The compiler's variables are constructors.** `$associated.N.OUT`,
  `$callable-argument.N` and `$method.x` become `Associated N OUT`,
  `CallableArgument N` and `Own v`. The old compiler finds hidden outputs
  by scanning names for the `$associated.` prefix (`resolve-requirement`,
  3443); a constructor makes the scan unnecessary and collisions
  impossible.
- **A callable requirement is its own constructor.** The old writes
  `Constraint "snail.core.base:Fn" (receiver, TFun)`, matching a class by
  name. Its evidence is never an instance (`instance-class` refuses one);
  the constructor says so.
- **Executable code's callable is `Callable Dyn FnContract arrow`.** The
  old `fn-arrow` makes a method's, an operation's, a primitive's and an
  extern's type its bare `TFun`, which is exactly dyn Fn, whatever was
  written. Declared keeps that meaning without a second function type.
- **A row's set has a canonical order by Global** (library parts, name,
  serial), not by the old unique-name text. Equal rows are then equal
  values. The adapter sorts labels the old way (`label-union`), and so
  will a printer that must match old messages.
- **Kinds live on the class.** A class's parameters are `TypeParameter`
  or `RowParameter`; the old keeps a separate `rows` list of names. An
  instance's head writes a `Row` for each row parameter and nothing else
  (I15), so its selecting types are the head's non-row types, with no
  class at hand: `cohere` and later `solve` match heads without a lookup.

`CallableOnce` stays a primitive form: `once`'s scheme needs a variable
standing for an arrow (`FnOnce F Signature` at `TRigid "Signature"`),
which no Declared type writes; the adapter spells the old scheme, and
`infer` will special-case it as the old checker does.

## 3. Between libraries

`declare` is handed:

```
declare : Derived (List Declarations) -> (Result DeclaredLibrary (List Feedback))
```

1. **The Derived library**, with its root's `first-unused-number`, from
   which `declare` numbers instances, implementations and eta locals.
2. **The Declarations of every library in its import closure**, the
   transitive one `expand` is handed offers for; and, when the library
   derives, those of (snail shell wire) and its closure, since a derived
   instance names wire's classes whether or not the library imports wire.
   What reads them: a type's arity (data, and builtins, which `declare`
   knows itself); a class's parameters, kinds, outputs and methods
   (projections, requirements, instances, method labels, determination);
   an effect's operations (handler labels; the lifecycle control-effect
   rule); a data type's cases, fields and `drop?` (case ids and
   buildability, which follow field types across libraries; the Drop
   rules on replacing and taking apart).
3. **Nothing else.** In particular no instance. The old expander reads
   instances in three places: overlap (now `cohere`'s), dynamic sources
   (`dispatch`'s), and "has this type a Drop instance" for the Drop rules.
   A Drop instance can only be declared in its type's library (I18), and
   the type's library is in the closure of any library that names its
   constructor or replacer, so that fact is the type's, in its library's
   offer (`Data` `drop?`).

`declare` writes `DeclaredLibrary`: the tree, and its `Declarations`
(`offer.sld`): its data types, classes, and effects' operations,
complete, in tables by name. Defaults, instances and value schemes stay
out: no importer's `declare` reads them.

`dispatch` is handed the closure's Declarations (a class's methods'
schemes, rows and outputs) and every instance of the libraries before it;
`cohere` every instance of the libraries before it. Both lists come from a
query over each earlier library's tree (`declare/listing.sld`, then
`dispatch`'s own), which the integrator accumulates.

**The integrator** runs each library through every front pass, expand,
bind, derive, declare (then dispatch, cohere), before it expands the next,
as the old compiler finishes a library before loading the next, so the
first library with a problem is the one reported. The implicit libraries
loaded at the first deriving clause go through all of them before the
deriving library is bound, as they are fully expanded in the old scan.

## 4. One pass or several

Inside `declare` the old order is kept exactly:

1. the scan of shapes: every type's arity and every class's parameters and
   outputs (no kinds, no methods), as the old scan registers them;
2. G: every signature's scheme, in order; the first problem stops;
3. D: each declaration in order, each seeing only the entities before it,
   threaded (no cell); the first problem stops;
4. B: buildable structs; the first problem stops;
5. Y: every body in order, each stopping at its own first problem; all of
   their problems are returned in order.

Parts: `types` (written types and schemes), `data`, `classes`,
`instances`, `effects`, `values` (externs, primitives, signatures),
`expressions` (bodies), `top` (the five steps), `pass.sld`. Rules beside
them, each a decision with literal-testable inputs: `forms` (builtin
arities; the classes and types the compiler knows by Global: Drop, Clone,
String, `(Vector U8)`), `kinds` (class rows), `requirements` (arity,
rows, equations), `projections`, `callables`, `heads`, `determination`,
`lifecycle`, `operations`, `host`, `buildable`, `owned` (the Drop rules),
`identities` (a case's TypeId). Queries: `schemes`, `listing`. State:
`state.sld`, the numbers and the entities known so far, with
`declaring-let*`.

Splits considered and rejected:

- **"Written types become types" as its own pass before declare.** The
  meaning of a written type depends on entities declared before it: a
  projection's selecting arguments and a requirement's row check use the
  class's kinds as known at that point (T3, T8), and those kinds come from
  converting the class's own method types (C3). In the old order a
  same-library class has no kinds in G and gains them in D. A types pass
  would either duplicate the kind rule or change which programs are
  refused. The table's two clauses are one job because each half needs
  the other in written order.
- **Expression labels as their own pass** (`refer`: handler labels, case
  ids, the Drop rules). A handler's label and a default's label are one
  decision, `not an operation of this effect` (`named-operation`), and
  expression types must be converted by the pass that owns the type rules,
  since the import rule forbids sharing rules across passes. A second walk
  would also reorder each body's problems, which the old reports first in
  the body. Declare's expressions part is small (about 300 lines).
- **Buildable structs as a check-only pass.** One rule of 30 lines, run
  between declarations and bodies in the old order; a pass of its own
  would report it after every body's problems instead.

`cohere` is a real split. Overlap is one decision in three places in the
old code (an instance against earlier ones, a generated instance against
earlier ones, a top-level scope's active instances), and the second and
third need the instances `dispatch` generates (error-binary-family-overlap
fails only at its scope). One home after `dispatch` takes all three, and
leaves `declare` with no need for global instances. Cost: an overlap is now
reported after every other `declare` and `dispatch` problem of its
library, where the old reports it in D (accepted: two passes' problems).
Its input is the query's instance listing, not a tree, so it can run over
Declared before `dispatch` exists and over Dispatched after.

## 5. The milestone adapter

For each part of the old `Program` (core.sld 1141), where its content
comes from, and what the adapter recomputes. "Old name" means the
unique-name text: `library.dotted:name` for serial 0; for a serial, the
adapter's own spelling `name%serial`, which matches no old text (the old
spells a mark's stamp, which no new pass has); bare for (snail core
forms).

| Old | From | Recomputed by the adapter |
| --- | --- | --- |
| `Defined` of a definition | `Define`: value, `Signed` | the scheme's old form; signature loc = `Signed`'s; `function?` = value is Lambda or ClosedLambda |
| `Defined` of an instance method | `InstanceMethod` implementation | scheme from query `schemes` (class method's at the head, own variables renamed `$method.x` as `rename-method-variables` does); no signature; `function?` #f |
| `Defined` of a default | `Default` | scheme: the operation's type without its effect; signature loc = the Default's; `function?` #f; name `OP-default.N` |
| `Defined` of dispatch and generated methods | `dispatch`'s | — |
| `Constructor`, `Accessor`, `Replacer`, `Setter`, `Swapper` | `Data`: kind, each case and field | names `Case-field`, `-set`, `-set!`, `-replace!`; index; schemes from `schemes`; every pure struct field has an Accessor too |
| `Method` | `Class` method | value scheme from `schemes` (class parameters and outputs first, the class first) |
| `::label` class and `Method` | every label the library uses: paths, field requirements, field instances, pure struct fields | `Class "::label" (R T) () () ("::label")` and its method |
| `Operation` | `Operation` | `TFun params result (TRow (effect . latent))`, effect first, unsorted |
| `Primitive` | `Primitive` | `prim:name`; `CallableOnce` spelled as `resolve-primitive-scheme` does |
| `Foreign` | `Extern` | `Import module symbol`, mono scheme |
| `DataType`, `Case`, `Field` | `Data` | `enum?`, `owned?` = move? or drop?; case `type` |
| `Class` | `Class` | params = written ++ outputs; rows = RowParameters; methods' old names |
| `Instance` | `Instance` (in an InstanceSet: `set`), the implied field instances (`lib:::label@Short`), `dispatch`'s generated | name, vars, types = types ++ outputs, requires and copy; methods as (method . implementation); per class in program order |
| `Effect` | `Effect` | operations, control, defaults as old names; around-main |
| `metadata` | each entity's annotations, fields' annotations | the two tables |
| `items`, `libraries` | the tops in order: Define, Statement (`Do`), Expose; instance methods at their instance; defaults at their effect; `dispatch`'s at theirs; a program's body as Expanded already settles it against the old items | top-level lambdas `captures? #f`; `ScopedInstances` from enclosing InstanceScopes (twice for a definition, as `define-top-level` does); `Let` signature → `Ann value type`; `CaseId` → `Ann (Lit (DInt id)) I32`; one run per library |
| types everywhere | `Type` | `Con` → `TCon` old name; `Callable Dyn Fn` → `TFun`; `Callable Dyn FnMut/FnOnce` → `TCon "FnMut"/"FnOnce"` of TFun; `Callable Impl k` → `TCon "$impl.k"`; `Code` → `TCon "fn"`; rows sorted by `label-union`; variables `$associated.N.x`, `$callable-argument.N` (its position in the scheme's variables), `$method.x` |

Nothing of a check is recomputed. What the adapter recomputes is spelling
and the derived schemes, through the same query `infer` will use, so the
adapter and the new checker cannot disagree on a scheme.

## 6. Slices

Each slice is one commit series, reviewable alone, and leaves `make
test-compiler` and `make compare-compiler` passing. The comparison is
extended in S2 to run `declare` after `derive` and compare each library's
entities with the old Program's tables through the adapter's conversions,
which are built here as the first half of the milestone adapter.

| Slice | Content | Compared by | Turns into "fail alike" |
| --- | --- | --- | --- |
| S1 Types | language.sld's types; part `types`; rules `forms`, `requirements` (arity, equations), `projections`, `callables`; T1-T15 | unit tests built by hand, one per old message and per hidden-variable order, with expected values read off the old functions | none (not yet run on programs) |
| S2 Entities | the rest of Declared and the offer; state; parts `data`, `classes` (kinds computed, not yet checked), `instances` (head, requirements, outputs, methods, identities), `effects` (operations, defaults, eta), `values`, `expressions` (types, handler labels, case ids), `top`, `pass.sld`; queries `schemes`, `listing`; the integrator's loop; the refusals the entities cannot be built without (T*, I4, I5, I9, I10, F4's first, Y7, Y9's second) | every program that expands alike: each library's data types, classes (with rows), effects, instances (in order), and every value's scheme, against the old tables; fresh names by role and order; case ids now compared, not reported | associated-duplicate, associated-missing, associated-projection, class-row-requires-arity |
| S3 Classes, effects, externs, structs | rules `kinds` checks (C3, C4), requirement rows in G, D and Y1, `operations` (F2), `host` (E2), F4's second, F5, `buildable` (B1) | as S2 | associated-row, class-row-kind, class-row-requires-row, control-default, control-latent-ctl, effect-operation-polymorphic, effect-operation-polymorphic-row, host-buffer-position, struct-contains-itself |
| S4 Instances | rules `heads`, `determination`, `lifecycle`; I12-I18 | as S2 | class-row-arity, class-row-usage, clone-requires-class, drop-control, drop-foreign, drop-open-row, drop-requires-class, drop-requires-row, dyn-cast-drop, instance-set-lifecycle |
| S5 Drop rules | rule `owned`; Y6, Y8, Y9's first | as S2 | drop-match, replace-owned |
| S6 `cohere` | the pass over the listing query; I11, X3, Y12 | as S2, over Declared until `dispatch` lands | associated-overlap, class-row-overlap, instance-set-nested, instance-set-overlap, overlap; and binary-family-overlap once `dispatch` lands |
| (`dispatch`) | not this design | | binary-domain, binary-source-inactive, dynamic-instance-any, -duplicate, -empty, -nested, -result |

4 + 9 + 10 + 2 + 6 + 7 = 38. Every message of the 38 is in inventory.md
with its pass. S2 is the largest (about 1,500 lines with tests); it can be
reviewed part by part, each part a commit, since the comparison judges
only the whole.

## 7. Risks and open questions

Most important first: the first are the ones that change what programs
mean or which are refused.

1. **The old compiler's order dependence.** A declaration sees only the
   entities before it: an instance before its class in one library finds
   no methods and no kinds; a lifecycle head's effect declared later goes
   unchecked; a signature's row arguments on a same-library class are
   checked only for definitions, at the `(:` form; a projection compares
   with the kinds known then. Making declare order-independent would
   accept programs the old refuses. Recommendation: reproduce it, by
   threading the entities known so far, with the library's own classes
   known by shape from the start; state each case beside the code; open an
   issue to remove the order dependence after the replacement.
2. **A path-named method definition.** `(instance (::x Circle I64) (define
   (::x c) ...))` (tests/programs/field-paths.sld 54) gives its method the
   label `::x`. Declare must decide it names the field class `x`'s reader,
   which takes reading the label as a path: `expand`'s `field-path` rule,
   which declare may not import. Recommendation: `expand` resolves it, an
   `InstanceMethod` whose label is a path carrying its labels, a small
   change to Expanded (and Bound, Derived) before S2; scanning the text in
   declare would break "names are data" and give the rule two homes.
3. **Overlap moves later.** With `cohere` after `dispatch`, a library with
   an overlap and any other declare or dispatch problem reports the other
   one. Recommendation: accept, under the rule already accepted for two
   passes; the six overlap programs in the suite have one problem each.
4. **Members written by a macro.** The old finds a method or an operation
   by the text after the last `:` of its unique name, which for a macro's
   name holds the mark's stamp, so no label names it (inventory, note 9).
   Recommendation: match only members of serial 0, for fidelity, and file
   it as a bug to fix after the replacement. The same stamp makes a macro
   type's case id, and the type names in messages, differ from the old;
   unavoidable, since no new pass has the stamp.
5. **Case ids hash text.** The TypeId is FNV-1a of a schema text that
   spells names as the old unique names (and `#N` for parameters, `fn` for
   callables and rows). It must be spelled exactly so for serial-0 names,
   or wire data written by an old program stops reading. That builds a
   text from names, which the conventions forbid for names; here it is a
   wire format, never looked up. Recommendation: allow it in `identities`
   alone, saying so in the spec; serial-N names use the adapter's spelling.
6. **A Drop instance before its type** is an old internal error.
   Recommendation: an approved deviation: accept it, since `drop?` is only
   read once the library is declared.
7. **Dead metadata.** Annotations are read by nothing but expand.sld's own
   test. Declare keeps each on what it annotates; the order of one name's
   annotations, when both a signature and the declaration write some, may
   differ from the old's scan order, and an imported target's signature
   annotations are dropped (the old keys them under a name nothing has).
   Recommendation: accept, and say so in the comparison.
8. **Row tails written through an alias.** The old keeps an alias
   argument's row as a row's tail, unflattened; Declared keeps it as
   written too (`Effects` tail is a `Type?`), so the adapter is exact.
   Recommendation: keep; flatten in `infer`, where rows are unified.
9. **`dispatch`'s view of order.** Dynamic instances' sources are those
   visible before the form; Declared keeps order, but `dispatch` must
   restrict itself to it. Also, the old checks a dispatch clause's domain
   (I8) before the instance's missing-method, overlap and arity checks;
   after the split `declare`'s come first. Recommendation: note both in
   `dispatch`'s design.
10. **Default and instance names.** The old joins `OP-default` and
    `SHORT.N`; Declared names an implementation by its operation's or
    method's name with a serial, and the adapter spells the old form.
    Recommendation: keep; nothing but messages shows these names.
11. **Speed on stage 0.** Every type reference is a lookup through the
    closure's offers; tables by name keep it to a table read and a short
    list. Recommendation: measure on Chibi at S2 (`make test-chibi`).
