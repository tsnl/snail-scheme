# Inventory: what the old compiler does with a declaration's content

Every function cited is in `src/snail/shell/compiler/expand.sld` unless a
file is named; line numbers are those of the worktree at commit 4c18c0e3.
"Place" is the `Loc` the message is reported at, named by the Bound node
that holds it. "Goes to" is the pass I assign it to; "becomes" is what it
is in Declared (language.sld).

## The old order

`expand-top-level` (1590) runs one library in four phases. The order is
what decides which problem a program with several is told.

| Phase | Function | Discipline |
| --- | --- | --- |
| S, scan | `scan-top-level` | first problem stops the library. `expand`'s, but for the metadata it records. Derived instances are scanned just after their declaration; the implicit libraries are loaded, and fully expanded, at the first deriving clause. |
| G, signatures | `with-signature` (2371), a fold over every pending `(:` form in order, nested ones included | first problem stops the library |
| D, declarations | `declare` (1798), each pending declaration in order; each enters the program as it is made, so a declaration sees exactly those before it | first problem stops the library |
| B, buildable | `check-buildable-structs` (1629) | first problem stops the library |
| Y, bodies | `expand-bodies` (1608): one step per definition, statement, expose, instance scope, instance method, dispatch method, generated definition and default, in pending order | each body stops at its own first problem; every body runs; the library fails with all of them, in order |

The whole program is expanded, library by library in load order, before
the old checker runs anything (`build-session`, session.sld 67).

What a declaration "sees" in D is not uniform, and declare must reproduce
it (see Risks 1):

- A type's arity and a class's parameters and outputs are known from S:
  `scan-struct`, `scan-enum` bind `TypeName` with its arity, and
  `scan-class` (1954) enters `(Class id params () outputs ())`, with no
  rows and no methods.
- A class of the same library gets its rows and methods only when D
  reaches it (`declare-class`, 2414). Until then every one of its
  parameters is a type and it has no method.
- An effect of the same library is in the program's `effects` only once D
  reaches it (`declare-effect`, 3111); `check-head-label` (2741) finds no
  effect before that, and checks nothing.
- A data type of the same library is in `types` only once D reaches it;
  a Drop instance before its type reaches `program-type`'s panic
  (`lifecycle-program`, 2699): "internal error: no type".
- In G no class of the same library has rows, so G checks a same-library
  class's row arguments nowhere; `check-signature` (1874) checks them again
  in Y for a definition's signature, with every class complete.

## T: written types, wherever one is resolved

`resolve-type`, `resolve-scheme`, `resolve-requirements` and their helpers
(3340-3680). They run in G for signatures, in D for every declaration's
types, and in Y for the types in expressions. Each is "first problem stops"
within its phase.

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| T1 | A declared or builtin type takes as many arguments as its declaration's parameters | `resolve-type-name` 3584 | `wrong number of type arguments: NAME` (the name as written) | the type's form, after `expand` found every argument a type | declare | `Con Global Type*` of the right length |
| T2 | A projection gives each declared parameter | `resolve-projection` 3612 | `associated projection gives each declared class parameter` | the projection's form | declare | gone |
| T3 | A projection reads the one requirement in scope of its class whose selecting arguments (`type-arguments`, which drops rows and outputs by the class's rows as known then) equal its own; innermost scopes first | `resolve-projection`, `enclosing-requirements` 3628 | `associated projection needs a matching requires constraint`; `associated projection matches multiple requirements` | the projection's form | declare | the type that requirement gives the output |
| T4 | Evidence scopes: each class requirement is in scope for the requirements after it and for the scheme's type, not for its own arguments; a class's methods are written in the scope of the class itself, `(C p ... out ...)` | `resolve-requirement` 3434, `declare-class` 2404 | — | — | declare | the scope is a parameter of the types part; nothing of it remains |
| T5 | A requirement's equations each name a distinct output of the class | `checked-constraint` 3490 | `constraint has an unknown or repeated associated type equality` | the requirement's form | declare | `ClassRequirement` with each output in place |
| T6 | An output no equation gives is a fresh variable of the scheme, `$associated.N.OUT` for the scheme's Nth class or callable requirement, appended to the scheme's variables | `checked-constraint`, `resolve-requirement` | — | — | declare | `Associated N OUT` |
| T7 | A requirement gives each of its class's parameters | `check-constraint` 3518 | `a constraint gives each of the class's parameters, as in (C P ...)` (parameters include outputs) | the requirement's form | declare | — |
| T8 | A requirement gives a row parameter a row or a variable; only rows known then are checked | `check-constraint` | `a constraint gives the class's row parameter E a row` | the requirement's form | declare | — |
| T9 | A callable requirement is a receiver and an arrow | `resolve-callable-constraint` 3477 | (shape: `expand`'s) | — | declare | `CallableRequirement` |
| T10 | A callable scheme's result is no `impl` | `callable-signature-parameters` 3396 | `a returned callable needs explicit dyn storage; impl is an argument or definition contract` | the scheme's form | declare | — |
| T11 | Each `impl` parameter of a scheme's callable becomes a variable, `$callable-argument.N` (N its position among the scheme's variables), with a callable requirement appended | `callable-parameter` 3413 | — | — | declare | `CallableArgument i` and a `CallableRequirement` |
| T12 | After lifting, no `impl` is inside the result or a parameter | `check-stored-type` from `callable-signature-parameters` | `stored and returned callable types require explicit dyn; impl is a definition or argument contract` | the scheme's form | declare | — |
| T13 | A row's labels are a sorted set (`label-union`) | `resolve-row` 3666 | — | — | declare | `Effects`, a set in Global order |
| T14 | A primitive's, a method's and an operation's scheme is operational: its callable is its bare arrow (`fn-arrow`), whatever its former and contract; an extern's type too | `operational-scheme` 3357, `declare-extern` 3054 | — | — | declare | `Callable Dyn FnContract arrow` |
| T15 | Local signatures in a body keep only their type; let signatures annotate the value | `local-signature` 4009, `signed-value` 4046 | — | — | declare converts; the adapter takes the type | `Let ... (Some Scheme)`; LocalSignature gone |
| — | `not a type`, alias arity and self-reference, a variable's arguments, callable syntax, row variable last, `not an effect`, `Copy names a quantified type variable`, every `expected ...` | | | | expand (done) | |

## G: signatures

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| G1 | Every `(:` form's scheme is resolved, in order, before any declaration (T1-T14, with only imported classes' rows) | `with-signature` | as T | as T | declare | — |
| G2 | The signature table: the last signature written for a Global wins (`table-set`); only `define-top-level` reads it; a signature naming a method, an operation, an extern, a constructor, a field function or an imported value is resolved and otherwise ignored | `with-signature`, `define-top-level` 1852 | — | — | declare | `Define`'s `Signed`; annotations of all its signatures on the Define |
| G3 | A signature's annotations are recorded under this library's prefix and the target's name, whatever the target | `scan-top-level` 1657, `with-name-annotations` | — | — | declare | on the target's entity when this library declares it; dropped otherwise (the old key names no declaration) |
| — | `signature names an undefined top-level definition: NAME` | | | | expand (done) | |

## D: declarations, in the order written

### Data

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| D1 | Each case's fields resolve in the type's parameters (T1-T3, T13; a projection here always fails T3) | `declare-data` 2242, `resolve-field` | as T | as T | declare | `DataField` types |
| D2 | Stored types hold no `impl` | `check-stored-type` 2282 | `stored and returned callable types require ...` | the field's type | expand (done, `field-node`) | — |
| D3 | A case's tag is its position; a struct is one case named for it | `declare-data` | — | — | declare | `DataCase` tag |
| D4 | `(deriving Move)` makes the type owned | `declare-data` (`any? move-class?`) | — | — | declare | `Data` move? |
| D5 | Constructor, Accessor, Replacer, Setter, Swapper values, with schemes; constructing and reading an immutable field are pure, a mutable field's operations perform `mut` | `with-case-values` 2305, `with-field-values` 2326 | — | — | declare decides the kind; query `schemes` derives each scheme | `DataKind`, each field's `mutable?` |
| D6 | A pure struct's fields each have a field-class instance read by its accessor, `lib:::label@Short`, and declare their field class | `program-with-field-instance` (core.sld 552) | — | — | implied by the Data | query `listing` (the library's instances) and the adapter |
| D7 | Field annotations under the constructor and the label | `bind-fields` 2089 | — | — | declare | `DataField` annotations |

### Classes

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| C1 | Each method's scheme is resolved in the scope of the class itself over its parameters and outputs (T1-T14), then made operational | `declare-method` 2475 | as T | as T | declare | `Method` scheme |
| C2 | A method's value scheme quantifies the class's parameters and outputs first and requires the class first | `declare-method` | — | — | query `schemes` | — |
| C3 | A parameter a method's type ends a row with is a row; it may not also be written as a type | `class-rows` 2425 | `the class parameter E is written both as a row and as a type` | the class's form | declare | `RowParameter` |
| C4 | No output is a row | `declare-class` 2411 | `an associated type must have kind Type, not an effect row` | the class's form | declare | — |
| — | `class parameters and associated types must be distinct`, member shapes | | | | expand (done) | |

### Instances (`declare-instance` 2497), in this order

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| I1 | The class: declared, or the field class of `::label`, declared on first use | `instance-class` 2578 | (refusals: expand's) | — | declare; the adapter declares field classes | `ClassRef` |
| I2 | Requirements resolve over the head's free names (T4-T9) | `declared-instance` 2872 | as T | as T | declare | `requirements`, `copied`, `Associated` variables |
| I3 | Head types resolve in the requirements' scope (T1-T3) | `declared-instance` | as T | as T | declare | `types` |
| I4 | Equations give each output exactly once; then each output's type is resolved | `instance-outputs` 2893 | `an instance defines each associated type exactly once` (`missing associated type X` is unreachable after it) | the instance's form | declare | `outputs` |
| I5 | For a class with outputs, the head gives each written parameter | `declared-instance` 2882 | `instance head gives each declared class parameter; associated types belong in its body` | the instance's form | declare | — |
| I6 | The instance is named afresh, `lib:SHORT.N` | `fresh-global` 2914 | — | — | declare | `Instance` global |
| I7 | A dispatch clause's types resolve (T1) | `declare-instance-methods` 2606 | as T | as T | declare | `Dispatch Type*` |
| I8 | The dispatch clause's domain | `parse-dispatch` (dynamic.sld 31) | `dispatch needs a ground instance head with exactly one Any type argument`; `dispatch needs at least one concrete type`; `dispatch accepts concrete types, not Any or type variables`; `dispatch repeats a concrete type` | the instance's form | dispatch | — |
| I9 | A method definition names a class method by its short name (a field class's by `::label`), or it is refused; then it is named afresh | `instance-method` 2933 | `not a method of this class: NAME` | the method's label | declare | `InstanceMethod` member and implementation |
| I10 | Every class method is implemented | `check-instance-methods` 3023 | `instance is missing a method: NAME` | the instance's form | declare | — |
| I11 | No earlier instance of the class in the same set (or both in none) overlaps on the selecting types | `check-overlap` 3012 | `this instance overlaps another instance of the class on its input types` | the instance's form | **cohere** | — |
| I12 | The head gives each parameter, outputs included | `instance-program` 2640 | `a C instance gives each of the class's parameters, as in (C P ...)` | the instance's form | declare | — |
| I13 | No lifecycle instance in a named set | `instance-program` | `lifecycle instances cannot belong to a named instance set` | the instance's form | declare | — |
| I14 | Determination, for a class with outputs: each requirement's selecting variables are known before it; outputs and row tails are known from inputs and earlier requirements; no output uses a row variable | `check-instance-determination` 2660, `determined-requirement` | `a prerequisite input must be determined before that prerequisite`; `instance outputs must be determined by its inputs and earlier requirements`; `an associated output cannot use an effect row as a type` | the instance's form | declare | — |
| I15 | Each row parameter gets a row and no other does; a lifecycle instance's row performs no control effect of an effect declared so far | `check-head-argument` 2727, `check-head-label` 2742 | `a C instance gives its type parameter P a row, not a type`; the row usage message (below); `a drop cannot perform the control effect E`, `a clone ...` | the instance's form | declare | — |
| I16 | A lifecycle instance requires only its own class at `(e A)`, its row tail `e`, `A` one of its variables; an open row needs such a requirement | `check-lifecycle-requirements` 2809 | `a C instance can require only (Copy A) and (C e A)`; `a C instance's row is closed, (! label ...), or ends with the row e of its requirements (C e A), as (! label ... e)` | the instance's form | declare | — |
| I17 | A row class's instance ends its rows with exactly the row variables its row-class requirements give | `check-row-requirements` 2766 | `a C instance's rows are closed, (! label ...), or end with the row e its requirements give a row class, as (! label ... e) with (requires (C e A))` | the instance's form | declare | — |
| I18 | A lifecycle instance is for a declared type of its own library at distinct variables; a Drop instance makes its type owned | `lifecycle-program` 2692, `check-lifecycle-head` 2843 | `a C instance names a row and a declared type`; `a C instance is declared in the library of its type`; `a C instance is for its type at distinct variables` | the instance's form | declare | `Data` drop? |

C is the class's short name. An instance in an instance set belongs to it
(`instance-owner`).

### Dynamic instances (`declare-dynamic-instances` 2531)

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| X1 | The pairs' types resolve (T1), after the class | `declare-dynamic-instances` | as T | as T | declare | `DynamicInstances ClassRef (Type*)*` |
| X2 | Instances generated from the sources visible so far; fresh `lib:dynamic.N`; their methods' Defined values | `generate-binary-instances` (dynamic.sld 234), `install-generated-instance` 2560 | the `dynamic-instances ...` messages of dynamic.sld 238-309 | the form | dispatch | — |
| X3 | Each generated instance against earlier ones | `check-overlap` | `this instance overlaps another instance ...` | the form | **cohere** | — |

### Externs, effects, primitives

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| E1 | An extern's type resolves (T1-T3; no callable-scheme checks: it is `resolve-type`), then is made operational | `declare-extern` 3047 | as T | as T | declare | `Extern` type |
| E2 | A host function takes a String or Bytes only last | `check-host-parameters` 3065 | `a host function can take a String or Bytes only as its last argument` | the extern's type | declare | — |
| F1 | Each operation's scheme resolves (T), operational | `declare-operation` 3123 | as T | as T | declare | — |
| F2 | An operation's type is monomorphic, a function with a closed row; a control operation's is total; no latent row names the effect | `declare-operation-type` 3143 | `an operation's type cannot be polymorphic: a handler implements it once, at one type`; `a control operation has a total function type; its effect is implied`; `an operation's latent row cannot name its own effect`; `an operation has a function type with a closed row; its effect is implied` | the operation's type | declare | `Operation` parameters, result, latent |
| F3 | An operation's value type adds its effect first: `(TRow (Cons effect latent))`, unsorted | `declare-operation-type` 3162 | — | — | query `schemes` | — |
| F4 | Each default entry, in order, after every operation: names an operation of this effect; not a control one; named afresh `lib:OP-default.N` with the operation's type without its effect | `snail-default` 3240, `default-scheme` 3260 | `not an operation of this effect: NAME`; `a control operation has no default` (`an operation with a default must have a monomorphic type` is unreachable after F2) | the label; the entry | declare | `Default` operation and implementation |
| F5 | At most one default per operation | `effect-defaults` 3190 | `an operation has at most one default` | the effect's form | declare | — |
| F6 | `around-main` | `around-main?` 3180 | — | — | expand (done) | `Effect` around-main? |
| P1 | A primitive's scheme resolves (T), operational; `once` typed `callable-once` gets the compiler's scheme | `declare-primitive` 3316, `resolve-primitive-scheme` 3331 | as T | as T | declare | `Primitive` scheme, or `CallableOnce` for the adapter to spell |
| — | default and effect clause shapes, `(snail core primitive) holds only primitive declarations` | | | | expand (done) | |

### Metadata

| # | Behavior | Function | Goes to | Becomes |
| --- | --- | --- | --- | --- |
| M1 | Annotations of a declaration, class member, operation and case, by unique name; field annotations by constructor and label; appended in scan order | `with-name-annotations`, `program-with-field-annotations` | declare (annotations stay on what they annotate) | each entity's `annotations`; the adapter builds the tables. No reader but expand.sld's own test (grep over src, host, tests, apps finds only it, core.sld, and stage 0's generated `::metadata` dispatcher) |

## B: buildable structs

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| B1 | No struct's every value holds another of itself, through struct fields and cells, stopping at enums and builtins | `check-buildable-structs`, `contains-itself?` (capabilities.sld 605) | `the struct NAME can never be built: each of its values would contain another` | the struct's name | declare | — |

## Y: bodies

| # | Behavior | Function | Message | Place | Goes to | Becomes |
| --- | --- | --- | --- | --- | --- | --- |
| Y1 | A definition's signature's requirements are checked again (T7, T8) with every class complete, before its value; failing stops that body | `check-signature` 1874 | T7's, T8's messages | the signature's `(:` form | declare | — |
| Y2 | A definition's value is a Defined of its signature, where the signature is, and whether it is a lambda | `define-top-level` | — | — | declare (Signed); adapter (Defined) | `Define` |
| Y3 | A top-level lambda captures nothing; a definition or statement under instance sets gets them (twice, for a definition) | `top-level-value` 1894, `scope-instance-value` 1767 | — | — | adapter | — |
| Y4 | Types in `ann`, `type-convert`, `try-convert`, `type-test` (T1-T3; no scope, so a projection always fails) | `expand-core` 3904-3928 | as T | as T | declare | `Ann Expr Type` etc. |
| Y5 | Local and let signatures (T, every class complete) | `local-signature` | as T | as T | declare | `Let`'s Scheme |
| Y6 | A reference to a Replacer of a type with a Drop instance, outside its library | `expand-reference` 3850, `check-own-library` 4420 | `T has a Drop instance, so only its own library can replace its fields` | the reference | declare | — |
| Y7 | A handler clause names an operation of its effect by short name | `operation-name` 4143, `named-operation` | `not an operation of this effect: NAME` | the label | declare | `Implementation Global Expr` |
| Y8 | A pattern's constructor of a type with a Drop instance, outside its library | `pattern-constructor` 4404 | `T has a Drop instance, so only its own library can take it apart; drop it instead` | the constructor | declare | — |
| Y9 | `case-id`: the own-library check of Y8 first, then a constructor, then its TypeId, `fnv-1a` of the case's schema text with its fields' types' schemas, as an I32 | `constructor-case-id` 4156, `case-type-id` (core.sld 1440) | Y8's; `not a constructor` | the constructor | declare | `CaseId Global id` |
| Y10 | A path declares its labels' field classes | `expand-path` 3786, `declare-field-classes` | — | — | adapter (nothing to decide: every label has its class) | `Path` labels |
| Y11 | A default's value: a lambda, or a function's name eta-expanded with fresh `argument.N` locals to the operation's arity | `expand-default` 3275, `eta-expand` 3285 | (`a default is a lambda or the name of a function`: expand, done) | — | declare | `Default` value |
| Y12 | A top-level instance scope's active sets (its own, enclosing scopes', the set it is in) have no two overlapping instances, over every class | `check-active-instances` (core.sld 1237), from `declare` 1812 | `this instance overlaps another instance of the class on its input types` | the `with-instances` form | **cohere** | — |
| Y13 | A dispatch clause's methods | `dispatch-method` (dynamic.sld 70) | `dispatch does not support independently polymorphic methods`; `... methods with additional class requirements`; `dispatch needs function methods`; `dispatch needs the erased class type as a whole parameter or result`; `each dispatched method needs an argument of its erased class type` | the instance's form | dispatch | — |
| — | `the builtin effect E has no operations to handle`, `a type is not a value`, the field-read refusal, `not a constructor: NAME` for an unbound one | | | | expand (done) | |
| — | A pattern whose constructor is a value but no constructor | the checker, check.sld 1461 | `not a constructor: NAME` | — | infer (the old checker until then) | `Destructure TopValue` |

## Where the old code and the assignment list disagree

1. "A default is a lambda or the name of a function" is already `expand`'s
   (`default-value`, expand/declarations.sld 683); declare only
   eta-expands.
2. "The rule about a stored dyn" is `expand`'s for fields (`field-node`);
   declare has the same rule only inside callable schemes (T12).
3. "Overlap" and "check-active-instances" cannot be declare's: both read
   the instances `dynamic-instances` generates (error-binary-family-overlap
   fails only at its scope, line 18), which are `dispatch`'s. They become
   the check-only pass `cohere`, after `dispatch`.
4. "Field classes known by label for paths" decides nothing: the old code
   only enters each label's class into the global program; a label names
   its class. It is the adapter's.
5. Two listed messages are unreachable: `missing associated type X` (after
   I4) and `an operation with a default must have a monomorphic type`
   (after F2).
6. A signature's row arguments are checked twice, at different places:
   in G, at the requirement, for imported classes only; in Y, at the
   `(:` form, for a definition's signature only (error-class-row-requires-row
   fails at 9:1, the form).
7. `case-id` runs the own-library check before "not a constructor".
8. Rows are label sets except an operation's value row, which puts its own
   effect first, unsorted (F3).
9. The old compiler finds a member by its short name, the text after the
   last `:` of its unique name. A member a macro's template wrote has the
   mark's stamp in that text (`ident-key`, the `%` key at 4683), so no
   label ever names it: `not a method of this class` and `not an operation
   of this effect`. Declare must match only members written with serial 0
   to keep that (Risks 4).
10. A Drop instance before its type, in one library, is an internal error
    of the old compiler (`program-type`'s panic), not a refusal.
