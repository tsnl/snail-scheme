# Inventory: what the old compiler does in dispatch and overlap

Functions are in `src/snail/shell/compiler/`; line numbers are this
worktree's at commit 6054fe79. Phases are the old expander's
(`expand-top-level`, expand.sld 1590; see `build/declare-design/inventory.md`,
"The old order"): **D** declarations in written order, the first problem
stops the library; **Y** bodies in pending order, each stops at its own
first problem, every one runs, all are reported; a D problem means no Y
runs. **CK** is the old checker, which runs only after every library of
the program has expanded (`build-session`, session.sld 67), over the whole
program (`check-library (::program expansion) ...`, session.sld 143).

"Place" is the `Loc` reported, named by the node that holds it in Declared.
"Goes to" is the pass in this design; "becomes" is what it is in Dispatched
(`language.sld`) or the listing (`listing.sld`).

Probes run on the old compiler are under `probes/`; each row that cites one
was observed, not only read.

## DC: an instance whose body is a dispatch clause

`declare-instance` (expand.sld 2497) runs, in D: the class, the head, the
requirements and outputs (`declared-instance` 2872), then
`declare-instance-methods` (2606), then `check-instance-methods` (I10),
`check-overlap` (I11), `instance-program` (I12-I18). So the domain checks
DC2 come before I10-I18.

| # | Behavior | Function | Message | Place | Phase | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DC1 | The clause's types resolve where the instance is, with nothing in scope | `declare-instance-methods` 2609 | as T (declare's inventory) | as T | D | declare (done) | Declared `Dispatch Type* loc` |
| DC2a | The head is ground: no variables (Associated ones included), no requirements, exactly one `Any` among the head's types and outputs together (a row is never `Any`), and the class is not Drop or Clone | `parse-dispatch` dynamic.sld 30 | `dispatch needs a ground instance head with exactly one Any type argument` | the instance's form | D | dispatch | gone |
| DC2b | At least one target | `parse-dispatch` 38 | `dispatch needs at least one concrete type` | the instance's form | D | dispatch | gone |
| DC2c | Each target, in order, is ground (`ground-type?` 48: a Con of ground types, a function of ground parameters, result and a row without tail, a row without tail) and not `Any` | `parse-dispatch` 39 | `dispatch accepts concrete types, not Any or type variables` | the instance's form | D | dispatch | gone |
| DC2d | No target repeats (`type=?`) | `parse-dispatch` 44 | `dispatch repeats a concrete type` | the instance's form | D | dispatch | gone |
| DC3 | The erased parameter is the first class parameter (written ones, then outputs) whose head type is `Any` | `dispatch-variable` 57 | (panic, unreachable after DC2a) | — | D | dispatch | — |
| DC4 | One implementation per method of the class **as known where the instance is** (none for a class of the library declared later: probe `class-later-dispatch.sld` is accepted), in the class's order, each `fresh-global (short-name method)` with `Defined (Some instance-method-scheme) (None) #t`; note `function? #t`, where a written method gets `#f` (`instance-method` 2958) | `dispatch-instance-method` 2622 | — | — | D | dispatch | `Dispatching` body, one `InstanceMethod` per method; the adapter's `Defined` |
| DC5 | Every class method is implemented | `check-instance-methods` 3023 | (cannot fail after DC4) | — | D | — | — |
| DC6 | Overlap with earlier instances | `check-overlap` 3012 | see I11 | | D | cohere | — |
| DC7 | Each method's body, one Y body per method (probe `dispatch-per-method.sld`: two problems at 7:1 for a class of two methods, and the next instance's too) | `dispatch-instance-method` 2632 | — | — | Y | dispatch | — |
| DC7a | The method's value scheme has no requirement but its class's | `dispatch-method` dynamic.sld 74 | `dispatch does not support methods with additional class requirements` | the instance's form | Y | dispatch | — |
| DC7b | The method has no variables of its own (its value scheme's variables are the class's parameters) | `dispatch-method` 76 | `dispatch does not support independently polymorphic methods` | the instance's form | Y | dispatch | — |
| DC7c | The method's type, at the head's other types (`substitute fixed type`), is a function | `dispatch-lambda` 107 | `dispatch needs function methods` | the instance's form | Y | dispatch | — |
| DC7d | The result and each parameter either is the erased variable or does not mention it (`mentions?` 117 looks into a Con's arguments, a function's parameters, result and row, a row's tail) | `check-dispatch-position` 111 | `dispatch needs the erased class type as a whole parameter or result` | the instance's form | Y | dispatch | — |
| DC7e | Some parameter is the erased variable; the first is the selector | `dispatch-lambda` 97 | `each dispatched method needs an argument of its erased class type` | the instance's form | Y | dispatch | — |
| DC8 | The method's value: for each target in order, recover the selector, recover every other erased argument or fail with ArgumentMismatch, call the class's method, convert an erased result to Any; after the last, fail with UnsupportedInstance (the whole code, `language.sld`, "A dispatch clause") | `dispatch-branches` 129, `dispatch-case` 144, `dispatch-argument` 154, `dispatch-call` 170, `recover-value` 202, `conversion-error` conversions.sld 55, `conversion-failure` 67 | — | every node at the instance's form | Y | dispatch | the `InstanceMethod`'s Lambda |

## DY: a `dynamic-instances` form

`declare-dynamic-instances` (expand.sld 2531), in D at the form. Its
active sets (`active-instance-sets` 1747) are its own set and the sets of
every top-level scope around that set.

| # | Behavior | Function | Message | Place | Phase | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DY1 | The class, then each pair's types | `instance-class` 2578, `resolve-type` | expand's and T | | D | expand, declare (done) | Declared `DynamicInstances ClassRef (Type*)* loc` |
| DY2 | Named afresh `lib:dynamic.N`; its instances `NAME.k`, their methods `NAME.k.SHORT` | `fresh-global` 2535, `generate-binary-instances` 244, `generate-binary-instance` 333 | — | — | D | dispatch | a Global per instance and per implementation |
| DY3 | The class, **as known where the form is**, has one row parameter, one output, two other parameters and a method (a class of the library declared later has no rows: probe `class-later-dynamic.sld`, refused at 5:3) | `check-binary-class` dynamic.sld 251 | `dynamic-instances needs a binary class with one effect row and one associated output` | the form | D | dispatch | — |
| DY4 | Each method, in the class's order: a value scheme with no requirement but its class's and a function type, else the first message; then no variables of its own, parameters exactly the two type parameters, result the output, row exactly `(! e)` for the row parameter, else the second | `check-binary-method` 262 | `dynamic-instances does not support independent method requirements`; `dynamic-instances needs methods of type (dyn (Fn A B -> Output ! e))` | the form | D | dispatch | — |
| DY5 | The domain is nonempty and its pairs distinct (`types=?`, which also compares lengths) | `generate-binary-instances` 236 | `dynamic-instances needs a nonempty domain of distinct type pairs` | the form | D | dispatch | — |
| DY6 | Each pair in order: two types, each ground and not Any; then exactly one source: an instance of the class active at the form (no set, or a set among DY's active sets), declared before the form (earlier libraries, then the library's own in D order), whose selecting types match the pair one way (`match-types` core.sld 953) | `resolve-binary-case` 275 | `dynamic-instances domain entries are two concrete, non-Any types`; `dynamic-instances has no active source instance for a domain pair`; `dynamic-instances has overlapping source instances` | the form | D | dispatch | — |
| DY7 | The source has no requirements; its output and row, at the match's bindings, are ground; the row is closed | `binary-case` 293 | `dynamic-instances source instances must have no class prerequisites`; `dynamic-instances source outputs and rows must be determined`; `dynamic-instances source effect rows must be closed` | the form | D | dispatch | — |
| DY8 | Every pair is resolved (DY6, DY7) before any instance is made | `generate-binary-instances` 239 | — | — | D | dispatch | — |
| DY9 | The heads: for each pair `(L R)` in order, `(Any R)`, `(L Any)`, `(Any Any)`, each once, in first order | `erased-heads` 312, 241 | — | — | D | dispatch | the order of the generated instances |
| DY10 | Per head: the cases it accepts (each side `Any` or equal), in domain order; the output, the one they share or `Any`; the row, `dyn-cast` and the union of their effects; the head at each class parameter (row, input by position, output); no variables, requirements or Copy; the methods; set: the form's set | `generate-binary-instance` 323, `binary-head` 343 | (panic "binary input parameter", unreachable after DY3) | — | D | dispatch | a generated `Instance` in the set |
| DY11 | Each method's value (`binary-lambda` 358, `binary-branch` 379, `binary-failure` 396, `binary-side-failure` 423, `binary-call` 433): the source implementation is called directly, not the class method (`language.sld`, "A dynamic-instances form") | | (panic "missing binary implementation", unreachable: a source passing DY7 was declared after its class, so declare's I10 holds for it) | every node at the form | D (made), Y (entered as items) | dispatch | the `InstanceMethod`'s Lambda |
| DY12 | Install each, in head order: its values `Defined (Some instance-method-scheme) (None) #t`, then X3, then `instance-program` (I12-I18), then it joins its class's instances. Of I12-I18 only I15's `gives its type parameter P a row, not a type` can fail, for a domain type that is a closed row (ground, so DY6 accepts it, and a source with a variable there matches) | `install-generated-instance` 2560, `check-head-argument` 2727 | `a C instance gives its type parameter P a row, not a type` | the form | D | dispatch (the row check, after DY8); cohere (X3) | — |
| DY13 | The generated definitions are entered as items, in order | `install-generated-instance` 2571 | — | — | Y | adapter | items from the tree's order |

## Overlap

| # | Behavior | Function | Message | Place | Phase | Goes to |
| --- | --- | --- | --- | --- | --- | --- |
| I11 | An instance (written, derived or with a dispatch clause) against every instance of its class already in the program (earlier libraries, then its own library's in D order, field instances and generated ones included) that is in no set when it is in none, or in its set; the new instance is `a` of the asymmetric `head-overlaps?` | `check-overlap` expand.sld 3012, `check-instance-overlap` core.sld 1245, `heads-overlap?` 1256, `head-overlaps?` 1262 | `this instance overlaps another instance of the class on its input types` | the instance's form | D | cohere |
| X3 | The same, for each generated instance in head order, against those before it, the form's earlier generated ones included | `install-generated-instance` 2570 | same | the form | D | cohere |
| F1 | A pure struct's field instances join the program at the struct's declaration, with no overlap check: probe `field-before.sld` (an explicit `(::x Point I64)` before `struct Point`) is accepted, `field-after.sld` refused at the explicit instance, 6:1 | `program-with-field-instance` core.sld 552, from `with-field-values` expand.sld 2352 | — | — | D | the listing (`FieldInstance`), never `a` in cohere |
| Y12 | Each top-level `with-instances` scope, at its pending place (before what it holds): over every class in the program, every ordered pair of distinct instances active under its sets and those of the scopes around it; both orders, so symmetric (probe `asym-scope.sld`: a pair I11 accepts is refused at a scope activating an empty set); over the library's instances in full, later ones included (probe `scope-later.sld`); one problem per scope, every scope's reported (probe `scopes-all.sld`) | `declare` expand.sld 1812, `check-active-instances` core.sld 1237 | same | the scope's form | Y | cohere |
| CK1 | Each `ScopedInstances` the checker meets: expression `with-instances`, and each top-level definition (twice) or statement under scopes (`scope-instance-value` expand.sld 1767): the same check, with the sets around it added, over the whole program, later libraries included | `instance-scope` check.sld 638, from 615 and 685 | same | the scope's expression | CK | the old checker at milestone A; `solve` after |
| CK2 | A constraint is answered by the first visible instance, in program order, whose selecting types match (`type-arguments` by the class as complete), over the whole program | `matching-instance` check.sld 2247 | `no instance for ...` | | CK | `solve` |

The rule, from the code:

- An instance's selecting types are `type-arguments class types`
  (core.sld 937): its head's types at the class's parameters that are
  neither rows nor outputs, by the class as the program has it when the
  check runs.
- `heads-overlap? as bs`: equal lengths, and `head-overlaps?` at each
  position. `head-overlaps? a b`: when `a` is `TCon name args`, true when
  `b` is `TCon name others` with `heads-overlap? args others`, or `b` is
  `TRigid`, and false otherwise; when `a` is anything else (`TRigid`,
  `TFun`, `TRow`), true. So a variable overlaps everything, a repeated
  variable is not unified (`(a a)` overlaps `(I64 F64)`), and the rule is
  asymmetric: `a` a function and `b` a Con overlap, the reverse does not
  (probes `asym-refused.sld`, refused at 8:1, and `asym-accepted.sld`,
  accepted).

## Where the old code and declare's design disagree

1. Declare's design (section 3) puts the listing query in `declare/`
   (`declare/listing.sld`, "then dispatch's own"). Generated instances are
   instances every later library's checks read (X3, Y12, CK), so the one
   listing must read Dispatched; one home is `dispatch/listing.sld`, and
   declare needs none.
2. Declare's design (section 2) says an instance's selecting types are its
   head's types that are no row, "with no class at hand". The old code
   (Y12, CK2, DY6) uses the class as complete, so they differ for one
   instance: written before its class in its library, giving a type to a
   parameter the class's methods later make a row (I15 accepts it there,
   since no rows are known). Such an instance implements no method (I9
   refuses every definition while the class has none). See risk 6.
3. Declare's inventory, Y12, adds "the set it is in" to a scope's active
   sets. A top-level scope is never inside a set (`scan-instance-set`
   1718 admits only instances and `dynamic-instances`), so that set is
   always none. Y12 is also symmetric and reads the instances declared
   after the scope, which the inventory does not say.
4. Declare's risk 9 says the old checks the domain (DC2) before "the
   instance's missing-method, overlap and arity checks"; it is also before
   I12-I18 (`instance-program` 2640: arity, lifecycle sets,
   determination, head rows, lifecycle heads).
5. Declare's inventory, X2, lists the messages of dynamic.sld 238-309: the
   I15 refusal of a generated head (DY12) is a further one, and the
   panics of DC3, DY10 and DY11 are unreachable.
6. Not in either list: CK1, the checker's own overlap check, which no
   expander pass can take (it sees later libraries and runs after every
   library expands).
