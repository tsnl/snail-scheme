# Compiler passes

**Under construction.** This chapter specifies the compiler being built in
`src/snail/compiler/`. Until its last pass lands, programs are still compiled
by the passes in [Compiler architecture](compilers.md). The Status column
says which passes exist. A grammar marked *sketch* is a plan; one marked
*implemented* is what the code declares, even while the pass that writes
it is still in progress.

The compiler is a sequence of small passes. Each does one thing and writes
its result in a language of its own, so the table below is the compiler's
outline: read it top to bottom to follow a program from text to WebAssembly.

| Pass | Unit | Reads | Writes | The one thing it does | Status |
| --- | --- | --- | --- | --- | --- |
| `read` | file | text | Syntax | Text becomes located forms. | implemented |
| `include` | file | Syntax | Syntax | Each `include-bytes` form becomes the bytes of its file. | implemented |
| `outline` | file | Syntax | Outline | The header is parsed: name, imports, exports. The body stays Syntax. | implemented |
| `expand` | library | Outline, Offer | Expanded, Offer | Macros run, every name is resolved, every core form is parsed. | implemented |
| `bind` | library | Expanded, Supply | Bound | Linked files and requests for other targets become what the build supplied. | implemented |
| `derive` | library | Bound, Offer | Derived | `deriving` clauses become instance declarations. | implemented |
| `declare` | library | Derived | Declared | Written types become types; declarations become entities. | implemented |
| `dispatch` | library | Declared, Declarations, listings | Dispatched | Dispatch clauses and `dynamic-instances` forms become instances with methods. | implemented |
| `cohere` | library | Dispatched, listings | nothing | No two instances that can be active together overlap on their selecting types. | implemented |
| `infer` | library | Dispatched | Inferred | Every node gets a type, with unknowns; constraints are recorded. | planned |
| `solve` | library | Inferred | Solved | Every recorded constraint is decided. | planned |
| `settle` | library | Solved | Typed | Every unknown is replaced. | planned |
| `convert` | library | Typed | Converted | Conversions become tests, boxes and unboxes. | planned |
| `close` | library | Converted | Closed | Each closure gets its captures, or is proved to have none. | planned |
| `place` | library | Closed | Placed | `set!` and `replace!` targets become places. | planned |
| `borrow-check` | library | Placed | Owned | Each use of a local is a use or a loan; linear rules are checked. | planned |
| `confine` | library | Owned | nothing | Functions that forbid `mut` mutate only what they allocate. | planned |
| `specialize` | module | Owned | Concrete | Every type is ground; every call says what it calls. | planned |
| `glue` | module | Concrete | Concrete | Drop, clone and share glue is written for requested types. | planned |
| `restrict` | module | Concrete | nothing | A yield is refused where nothing can carry it. | planned |
| `sequence` | module | Concrete | Sequenced | Each call that may yield is bound by a let. | planned |
| `clean` | module | Sequenced | Prepared | Those lets and one-shot closures get their droppers. | planned |
| backend | module | Prepared | Wasm | Still to be divided into passes. | planned |

A *file* is one source file. A *library* is one `define-library`, or a
program's body, which is the library `main`. A *module* is one WebAssembly
module: a whole program, or one library in a development build.

## Words

- A **language** is the set of data types one pass writes. It is declared in
  one file, under a grammar that states it.
- A **pass** is a pure function from its input languages to its output
  language. A pass over a file also receives what the integrator read or
  decided for it, such as the bytes of the files it includes. A pass over a
  library also receives what the libraries it imports offer, and nothing else
  of them. Instances are the one exception: they are global, so the passes
  that choose an instance receive every instance in the program, whichever
  library declares it.
- A **query** is a pure function that reads a language and answers a fact
  about it, such as the imports of an outline or the files an expanded
  library links. It writes no tree.
- A **rule** is a pure function that makes one decision from the facts it is
  handed and returns the decision as data. It may loop over its own
  arguments, as matching a pattern against a form does, but it does not walk
  the program, does not thread a pass's state and does not report failure.
- The **integrator** is the one place that calls passes. It finds and reads
  files, orders libraries, and runs the loops. Its libraries live in
  `integrate/`, and they are the only libraries of the compiler whose
  functions perform `fs`. What it decides, such as the order libraries load
  in, it decides without the file system, so it can be tested with literal
  values.

Passes are not strictly a chain: a pass may read more than one earlier
language, as `expand` reads Outline and the Syntax inside it. A pass that
only checks, as `cohere` and `confine` do, writes nothing.

## Where the code lives

```text
src/snail/compiler/
  source.sld              (snail compiler source): Loc, beside, Feedback, result-let*, map-results
  read/
    language.sld          (snail compiler read language): the Syntax language
    pass.sld              (snail compiler read pass): the function `read`
    ...                   rules and queries of this pass, one library each
  include/
    pass.sld              (snail compiler include pass): writes Syntax, so no language.sld
    ...
  outline/
    language.sld
    pass.sld
  expand/
    language.sld          Expanded, the tree it writes
    offer.sld             Offer, what a library offers its importers' expansion
    marked.sld            Marked, the syntax it works on
    state.sld             the numbers it hands out, and expanding-let*
    forms.sld             rule: what (snail core forms) offers
    scopes.sld            rule: what an identifier means where it is used
    syntax-rules.sld      rule: which of a macro's rules matches a use
    paths.sld             rule: a field path's labels and a linked file's names
    type-shapes.sld       rule: the shape of type syntax
    form-shapes.sld       rule: the shape of each core form and local definition
    declaration-shapes.sld rule: the shape of each top-level form and declaration
    imports.sld           part: import sets
    macros.sld            part: macro definitions and uses
    types.sld             part: types and schemes, with aliases expanded
    patterns.sld          part: match patterns
    expressions.sld       part: expressions and local bodies
    scan.sld              part: the top level's names, bound in order, and each form's item
    declarations.sld      part: signatures, declarations, then every body
    pass.sld              (snail compiler expand pass): the function `expand`
    subexpressions.sld    query: every expression of a library
    links.sld             query: the files a library links, and when two are one
    targets.sld           query: the targets a library asks for, and where first
    derives.sld           query: whether, and where first, a library derives
  bind/
    language.sld          Bound, the tree it writes
    supply.sld            Supply, what the build found for a library
    linked.sld            query: the file each link names, and the files to read
    needs.sld             part: what a library needs, found in its Supply, and what a miss means
    state.sld             the numbers it hands out, a copy's renaming, and numbering-let*
    pass.sld              (snail compiler bind pass): the function `bind`
    placed.sld            query: the files the build places beside the program
  derive/
    language.sld          Derived, the tree it writes
    implicit.sld          part: the names a derived instance is written with, in the implicit libraries' offers
    instances.sld         part: a derived Serialize or Deserialize instance, built as nodes
    pass.sld              (snail compiler derive pass): the function `derive`
  declare/
    language.sld          Declared, the tree it writes
    offer.sld             Declarations, what a library offers its importers' declaration
    equality.sld          query: when Globals and types are the same, and the order of a row's effects
    forms.sld             query: the builtin types of (snail core forms), with their arities, and the lifecycle classes
    spellings.sld         query: how a Global is spelled in the texts a running program holds
    membership.sld        query: the members an instance of a class implements, and the name each goes by
    misplaced-rows.sld    query: the refusal of a head that gives a type parameter a row
    known.sld             rule: what is known of types and classes where a type is written
    requirements.sld      rule: what a class requirement gives its class
    projections.sld       rule: the type a projection stands for
    callables.sld         rule: the rules callable types obey in a scheme, and executable code's type
    kinds.sld             rule: which of a class's parameters are rows, each one kind
    operations.sld        rule: an operation's parameters, result and latent effects, and its defaults
    host.sld              rule: what a host function may take
    buildable.sld         rule: whether a struct can be built
    members.sld           rule: which member of a class or an effect a label names
    heads.sld             rule: what an instance's head and equations give its class, its rows among them
    determination.sld     rule: whether an instance's outputs are determined by its inputs and earlier requirements
    lifecycle.sld         rule: what a Drop or a Clone instance may be, and the type a Drop instance makes moved
    owned.sld             rule: who may take apart a value of a type with a Drop instance, or replace its fields
    identities.sld        rule: a case's TypeId
    state.sld             the numbers it hands out and what is known, declaring-let* and checked
    types.sld             part: written types, schemes and requirements
    values.sld            part: signatures, definitions' bodies, externs and primitives
    data.sld              part: structs and enums
    classes.sld           part: classes
    effects.sld           part: effects and their defaults
    instances.sld         part: instances and their methods
    expressions.sld       part: bodies
    top.sld               part: the scan, the signatures, each declaration, the structs, then every body
    pass.sld              (snail compiler declare pass): the function `declare`
    schemes.sld           query: the scheme of each value a declaration makes, substitution, and field classes
  dispatch/
    language.sld          Dispatched, the tree it writes
    listing.sld           query: every instance a library declares, and what is read of one
    matching.sld          query: one-way matching of an instance's head
    overlap.sld           query: when one instance overlaps another, and whether two active under some sets do
    text.sld              query: the texts the generated code holds: a type, a place, a method
    runtime.sld           rule: the Globals of the runtime the generated code names
    known.sld             rule: what is known of a class where an instance names it
    domains.sld           rule: what a dispatch clause covers, and what each method of its class must be
    binary.sld            rule: a binary class, each domain pair's case, the heads, and each head's cases, output and row
    state.sld             the numbers it hands out, numbering-let* and numbering-map
    conversions.sld       part: the recovery of a typed value from Any, and the CastError that fails it
    clauses.sld           part: a dispatch clause's methods
    families.sld          part: the instances a `dynamic-instances` form generates
    pass.sld              (snail compiler dispatch pass): the function `dispatch`
  cohere/
    pass.sld              (snail compiler cohere pass): writes nothing, so no language.sld
  ...
  integrate/              the integrator: one library per job
    files.sld             (snail compiler integrate files): every read of the file system
    walk.sld              (snail compiler integrate walk): what to load next, and in what order
    load.sld              (snail compiler integrate load): a program and the libraries it reaches
    sha256.sld            (snail compiler integrate sha256): the digest a linked file is named by
    bind.sld              (snail compiler integrate bind): one library's linked files read, then bound
    compile.sld           (snail compiler integrate compile): each loaded library expanded, bound, derived, declared, dispatched and cohered, in order
```

Each pass is a folder. `language.sld` holds the language the pass writes:
data definitions under their grammar, and no logic. `pass.sld` exports the
pass as one function named for it. A rule or query library sits beside them
under a name that says what it decides or answers.

A pass too large for one library divides its walk into parts: libraries of
its own folder, one for each kind of thing it walks, named for that thing.
A part recurses and reports as `pass.sld` does, and `pass.sld` remains the
entry point. `expand` is such a pass: import sets, macro uses, types,
expressions, patterns and the top level are each a part. It also writes two
languages, the tree in
`language.sld` and, in `offer.sld`, what a library offers the expansion of
the libraries that import it, and works in a third, `marked.sld`'s, which
macros read and write.

The import rule keeps the folders apart, and `scripts/compiler-imports
--check` enforces it:

- `source.sld` imports only `(snail core base)`.
- A `language.sld` imports `(snail core base)`, `(snail core table)`,
  `(snail compiler source)` and the languages of earlier passes.
- Any other library of a pass imports those, the libraries of its own
  folder, and the languages and queries of earlier passes. It never imports
  another pass's `pass.sld` or rules.
- Only the integrator imports a `pass.sld`, and only the integrator imports
  `(snail core io)`.
- The adapter is outside these rules; see the last section.

A query library says so on its first line, which starts `;; Query:`. Any
other library beside `language.sld` and `pass.sld` is a rule library or a
part, and the same imports are open to both.

## Conventions

**A language is copied, not shared.** Each language declares every form it
admits, under the same constructor names as the language before it, so a
form that a pass removes is absent from its output and cannot be matched
there. A language reuses a rule of an earlier language only where its pass
never looks inside it: `Loc`, `Datum`, names, and the `Syntax` an Outline
carries. A pass imports each language it reads under a prefix named for that
language, and the language it writes without one:

```scheme
(import
 (snail core base)
 (snail compiler source)
 (prefix (snail compiler read language) syntax-)
 (snail compiler outline language))
```

**The grammar comes first.** A `language.sld` opens with its grammar in the
notation of this chapter, then one data definition per rule, in the
grammar's order. The grammar says what the language guarantees that its
predecessor did not. A constructor cannot take the name of a type in scope,
so a string literal's case is `Text`, not `String`.

**Failure is a value.** A pass returns `(Result Output (List Feedback))`. A
`Feedback` is a location and a message, and a failure holds at least one. A
pass that can go on past a failed item, such as a definition, checks every
item and returns every item's feedback in source order. No pass performs an
effect: no `mut`, no `fs`, no control effect.

**No internal errors.** A `panic` marks a state the input language should
have made impossible. Prefer changing the language so the state cannot be
written. Where one remains, a comment says which invariant it rests on.

**Names are data.** A global is a library and a name; a local is a name and
a number. No pass builds a name by joining text or reads one by scanning it.
A name is spelled only into the texts a running program holds, a wire
schema's and a `CastError`'s, which `declare/spellings.sld` writes, and
no pass looks a name up by its spelling.

**Sequencing.** `result-let*` from `(snail compiler source)` sequences
steps that return a `Result`, with the scope of `let*`, and `map-results`
steps each item of a list in order, stopping at the first failure. A pass
that threads state defines one binding form for it beside the state, named
with the `-let*` suffix; each step takes the state first and returns its
value with the new state.

**Rules apart from recursion.** The function that walks a tree obtains what
a rule needs, calls it, and carries out what it answers. The rule itself
neither recurses nor builds feedback. A reader should be able to test a rule
with literal arguments.

**Tests build their input by hand.** Each `pass.sld` and rule library ends
with a `Tests` section under the `snail-tests` feature, exporting one
`test-<name>` entry point. A test constructs values of the input language
directly and compares the output with `expect`. It reads no file and calls no
other pass; only the integrator's tests write and read files, in a directory
the runner supplies. `make test-compiler` runs these tests alone and, while the
old compiler exists, the comparisons with it. The comparisons that load or
expand whole programs are compiled instead, by `make compare-compiler`.

**Stage 0 runs it.** The new tree is reached by Chibi through
`bootstrap/chibi-include/`, so it uses only what both hosts agree on:
`(snail core base)`, `(snail core table)`, no reliance on integer overflow or
on the order of table keys. A constructor is never named `Cons` or `Nil`,
which stage 0's `match` reserves for lists, and a step of `result-let*` is
always named, since stage 0 cannot bind `_` there.

## Languages

Grammars use `::=` for a rule, `|` between alternatives, `*` for a list and
`?` for an option. A word that starts with a capital is a rule or a
constructor; a lower-case word is a field of the type its name suggests.
Every node of a tree carries a `Loc` unless its grammar says otherwise.

### Syntax, written by `read` and `include` (implemented)

Every bracket is matched, `'d` is the form `(quote d)`, and each literal's
value is decoded, with an integer that fits in `I64`. A float keeps its
text, and a `Text` holds the characters a string literal stands for. After
`include`, no `include-bytes` form remains: each is the `ByteVector` of its
file, where the form was.

```text
Syntax ::= Atom Datum | Ident name | Form Syntax*
Datum  ::= Integer integer | Float text | Text text | Character character
         | ByteVector bytes | Boolean boolean
```

### Outline, written by `outline` (implemented)

A library's file holds one library, under the name it was found by. Its
declarations are joined into imports, exports and body, each in the order
written, with every `cond-expand` decided, and every import set and export
is well formed. A library name is its parts in order, with an integer part
as its decimal text. A program is its leading imports and its body; when
it is a producer a build printed, it also names the libraries loading as
it starts and its recipe's file. Nothing in a body is read, nor a generated
library's recipe, whose imports and expression become a producer program.

A `Library` is what `expand` takes: a defined library or a program, each
with a body. A generated library is not one, since its body is what its
producer will print; the integrator outlines that output as a `Library`
before anything expands it.

```text
Outline    ::= Written Library                    no Loc
             | Generated library Syntax* Syntax    the recipe's imports and expression
Library    ::= Defined library Import* Export* Syntax*
             | Program key* recipe? Import* Syntax*  no Loc
Import     ::= Whole library | Only Import Identifier* | Except Import Identifier*
             | Prefix Import prefix | Rename Import Renaming*
Renaming   ::= Renaming Identifier name            no Loc but its identifier's
Export     ::= Export Identifier name              no Loc but its identifier's
Identifier ::= Identifier name
```

### Expanded, written by `expand` (implemented)

No macro use or definition remains, nor a top-level `begin` or an
`include-bytes` form, and every form is a core form. Every identifier is
resolved: a value is a `Local`, a `Global` or one of the functions a field
declares; a type is its declaration, a builtin of (snail core forms), a type
variable or a class's associated output; a class, an effect and an instance
set are their declarations. A `Global` is the library that defines it and the
name written there, with a serial of its own when a macro's template wrote
the name, and a `Local`'s number is unique in its library. The root's
`first-unused-number` is the first number the library has not used for a
local, a mark or a serial: every `Local`'s number, and the serial of every
`Global` the library defines, is below it. A later pass that writes locals
of its own, as `derive` and `dispatch` do, numbers them from it, never
walking the tree to find a free one, and writes where it stopped in its own
output's root. A `Label` is the one name not resolved: a field's, a path's,
and that of a class's or an effect's member as a method definition, an
associated output, a default or a handler writes it; the pass that has the
declaration resolves it. A method definition's name is a member's label
unless it is written as a field path, `(define (::x circle) ...)`, which
`expand`'s rule for paths reads into its labels, as it reads a path in an
expression; either keeps the name as written, for messages. A name that is
a path but for an empty label, `::x::`, is a member's label that names no
member, since the old expander reads no path there: it finds the method a
name names by comparing text. Types are
as written, with their names resolved, but an alias is expanded where it is
used, as a macro is, into an `Aliased` type: the arguments the use writes,
expanded where it is, and the alias's body, expanded at the top level of
its library, where each parameter is an `AliasParameter` standing for the
argument at its index. The two stay apart because the old compiler checks
them apart: it resolves every argument first, where the use is, even one
the body does not use, and then the body in the alias's own scope, where no
requirement of the use is in scope. An `if` has its alternative, the unit
value when none is written, which no `Datum` writes, so Expanded's
expressions have constants of their own; a pattern's literal stays the
`Datum` written. A program's statements are its body, each under the
instance sets in scope where it was written. A tree node is at the place
the old expander's messages name.

```text
Expanded    ::= Defined library Top* first-unused-number
              | Program Top* Expr? first-unused-number          no Loc
Top         ::= Define Global Expr
              | Signature TopValue Scheme Annotation*
              | Statement Expr                                  no Loc but its expression's
              | Expose TopValue symbol dynamic?
              | Struct Global parameter* Field* Derivation* Annotation*
              | Enum Global parameter* Case* Derivation* Annotation*
              | Alias Global parameter* Annotation*
              | Class Global parameter* Member* Annotation*
              | TopInstance Instance                            no Loc but its instance's
              | InstanceSet Global SetMember*
              | InstanceScope Global* Top*
              | Extern Global module symbol TypeExpr Annotation*
              | Effect Global Operation* Default* around-main? Annotation*
              | Primitive Global PrimitiveType
Field       ::= Field label mutable? TypeExpr Annotation*
Case        ::= Case Global CaseField* Annotation*
CaseField   ::= CaseField label TypeExpr Annotation*
Derivation  ::= DeriveMove | DeriveSerialize | DeriveDeserialize
Member      ::= MethodSignature Global Scheme Annotation*
              | AssociatedOutput Label Annotation*              no Loc but its label's
Instance    ::= Instance ClassRef variable* TypeExpr* Requirement* Equation* InstanceBody
InstanceBody ::= Dispatch TypeExpr* | Methods InstanceMethod*   Methods: no Loc
InstanceMethod ::= InstanceMethod MethodName Expr               no Loc but its name's
MethodName  ::= MemberName Label | PathName label* Label        no Loc but its label's
SetMember   ::= SetInstance Instance                            no Loc but its instance's
              | DynamicInstances ClassRef (TypeExpr*)*
Operation   ::= Operation Global control? Scheme Annotation*
Default     ::= Default Label Expr
PrimitiveType ::= PrimitiveScheme Scheme | CallableOnce         no Loc
Annotation  ::= Documentation text

Expr        ::= Literal Constant | LocalRef Local | TopRef TopValue
              | Path label* | PathApply label* Expr
              | Lambda Local* Expr | ClosedLambda Local* Expr | Call Expr Expr*
              | If Expr Expr Expr | Seq Expr Expr
              | Let Local Scheme? Expr Expr | LocalSignature Scheme Expr
              | Match Expr Clause* | Handle Global Implementation* Expr
              | WithInstances Global* Expr
              | Ann Expr TypeExpr | Convert Expr TypeExpr | TryConvert Expr TypeExpr
              | TypeTest Expr TypeExpr | CaseId TopValue
              | LinkedFile name* | ArtifactFiles target Expr Expr Expr
Clause      ::= Clause Pattern Expr
Implementation ::= Implementation Label Expr
Pattern     ::= Wild | Bind Local | Equals Datum | Destructure TopValue Pattern*
Constant    ::= Integer integer | Float text | Text text | Character character
              | ByteVector bytes | Boolean boolean | UnitValue    no Loc

TypeExpr    ::= Applied Global written TypeExpr* | Variable name
              | Projection Global member TypeExpr*
              | Callable Former Contract Arrow | Code Arrow | Row Effects
              | Aliased Global TypeExpr* TypeExpr | AliasParameter index
Arrow       ::= Arrow TypeExpr* TypeExpr Effects                no Loc
Effects     ::= Effects Global* TypeExpr?                       no Loc
Former      ::= Impl | Dyn                                      no Loc
Contract    ::= FnContract | FnMutContract | FnOnceContract     no Loc
Scheme      ::= Scheme variable* Requirement* TypeExpr
Requirement ::= CopyRequirement variable
              | ClassRequirement ClassRef TypeExpr* Equation*
              | CallableRequirement Contract TypeExpr Arrow
ClassRef    ::= ClassGlobal Global | FieldClass label           no Loc
Equation    ::= Equation Label TypeExpr                         no Loc but its label's

Local       ::= Local name number                               no Loc
Global      ::= Global library name serial                      no Loc
TopValue    ::= TopGlobal Global | FieldFunction Global label FieldRole   no Loc
FieldRole   ::= Accessor | Replacer | Setter | Swapper          no Loc
Label       ::= Label name
```

`LinkedFile` and `ArtifactFiles` stay in the tree. Queries over Expanded
gather them: the integrator reads the files the links name, and `bind`
finds those files and the other targets' files among what the build
supplied, decides what a miss means, and replaces each form.
A third query says whether a library derives an instance: the integrator
then loads and compiles the libraries `derive` writes instances with,
(snail core primitive) and (snail shell wire), before that library, where
the old compiler puts them.

`expand` checks what needs only syntax and what names mean. What needs a
declaration's content, such as which method or operation a label names,
whether a struct can be built, or what a dispatch clause covers, is
`declare`'s; a program whose only problem is one of those expands, and the
later pass reports it.

### Offer, written by `expand` (implemented)

What a library offers the expansion of each library that imports it: its
exports, and its top level, where the names its macros and aliases introduce
resolve. The integrator keeps each library's offer and hands `expand` the
offers of the libraries an outline's imports reach; `expand` knows the offer
of (snail core forms) itself. Only expansion and `derive` read an offer; the
later passes read Expanded.

The syntax an offer holds, a macro's rules and an alias's body, is
`Marked`. Each scope a mark in an offer names is the top level of a library
in the importer's import closure, since a library reaches an importer only
through the exports of the libraries it imports. No mark in an offer names a
local scope: a mark is made by a use, and a local macro is used only in the
body that defines it, which defines no top-level name, so nothing a local
macro writes reaches a top level.

```text
Offered     ::= Offered library Offer                           no Loc
Expansion   ::= Expansion Expanded Offer                        no Loc

Offer       ::= Offer Export* TopScope                          no Loc
Export      ::= Export name Meaning                             no Loc
TopScope    ::= TopScope Binding* Binding*                      no Loc
Binding     ::= Binding Identifier Meaning                      no Loc
Meaning     ::= Value TopValue | TypeName Global constructs?
              | TypeAlias Global Identifier* Marked library
              | ClassName Global | InstanceSetName Global | Associated Global member
              | EffectName Global | Keyword name | MacroRules Macro
              | ReservedAccessor                                no Loc
```

### Marked, the syntax `expand` works on (implemented)

`expand` reads a library's body into marked syntax, macros write it, and an
offer holds it; no later pass sees it. Each identifier carries the marks of
the macro uses that introduced it, latest first. An identifier is looked up
in the local frames around it, then at the top level they sit over, where a
definition hides an import; one that nothing binds there is looked up again
without its latest mark, in that mark's scope. A mark names the library
whose expansion made it and the scope the macro was defined in: a library's
top level, or, for a macro a body defines, the frames from the macro's own
frame outward, which hold the macro, so its template may use it. A local
macro's scope is found where its name is resolved, so nothing about a body
is kept anywhere else, and the numbers of marks, locals and macros need only
be unique in a library. A type variable, and an alias's parameter standing
for its argument, are frames too.

```text
Marked      ::= Atom Datum | Ident Identifier | Form Marked*
Identifier  ::= Identifier name Mark*                           no Loc
Mark        ::= Mark library number Scope                       no Loc
Scope       ::= TopLevel library | LocalScope Frame*            no Loc
Frame       ::= Frame Identifier Denotation                     no Loc
Denotation  ::= LocalValue Local | LocalMacro Macro
              | TypeVariable name | TypeArgument index          no Loc
Macro       ::= Macro MacroId Marked* Marked*                   no Loc
MacroId     ::= MacroId library number                          no Loc
```

### Bound, written by `bind` (implemented)

No `LinkedFile` and no `ArtifactFiles` remains. Each file a library links
is declared once, by a `LinkImport` among the library's first tops, in
the order the library first names its files and at the place it first
names this one: its Global, named `link-handle` with a serial of its own,
is bound to the import from `snail.runtime.link` named for the SHA-256
of the file's bytes in lowercase hex, a function of no arguments that
answers the file's handle as an `I32`. It holds the path as the library
wrote it, as canonical names, and the file where the build found it. Each
`(link-handle "path")` is a call of that Global with no arguments, at the
form. A request for a target's files is the list of them: for each file,
in the order the build supplied them, `(prepend (file path bytes) rest)`,
ending in `(empty)`, each call at the request. The first file's `prepend`
and `file` are the expressions `expand` wrote, and each later file's are
copies with locals of their own, as the old expander expands the form
again for each file, so every `Local`'s number is still unique in its
library. The root's `first-unused-number` counts the handles' serials and
the copies' locals.

`bind` answers a Result. Its success is the library bound, or, when the
library asks for targets the build did not supply, each of them, in the
order first asked, for the integrator to relay to its caller, as the old
compiler asks its caller for an input. A target not supplied is no
failure of the program. `bind` works in two steps. First it finds what
the library needs, in the old expander's order, which asks for a target
and finds two links clashing while it expands the body, and reads the
linked files once the body is done: the targets the library asks for,
all of them; then two links of one path that name different files, a
problem at the second, "two files link as PATH: FILE and FILE"; then the
first linked file the build found none for, a problem where the library
first writes it, "the library NAME links PATH, but there is no file at
FILE". Then it walks the library, handed what was found and threading
only numbers. The walk's lookups of a file and a target cannot miss,
since the first step took the links and the targets from the same tree
through the queries; a miss is a compiler bug, and panics.

Bound declares afresh the rules `bind` looks inside, which are those that
hold an expression or a pattern, and reuses Expanded's for the rest:
`Field`, `Case`, `Derivation`, `Member`, `MethodName`, `Operation`,
`PrimitiveType`, `Annotation`, `Constant`, the types, `Scheme`,
`Requirement`, `ClassRef`, `Equation`, `Local`, `Global`, `TopValue` and
`Label`.

```text
Bound       ::= Defined library Top* first-unused-number
              | Program Top* Expr? first-unused-number          no Loc
Top         ::= LinkImport Global name* digest file
              | Define Global Expr
              | Signature TopValue Scheme Annotation*
              | Statement Expr                                  no Loc but its expression's
              | Expose TopValue symbol dynamic?
              | Struct Global parameter* Field* Derivation* Annotation*
              | Enum Global parameter* Case* Derivation* Annotation*
              | Alias Global parameter* Annotation*
              | Class Global parameter* Member* Annotation*
              | TopInstance Instance                            no Loc but its instance's
              | InstanceSet Global SetMember*
              | InstanceScope Global* Top*
              | Extern Global module symbol TypeExpr Annotation*
              | Effect Global Operation* Default* around-main? Annotation*
              | Primitive Global PrimitiveType
Instance    ::= Instance ClassRef variable* TypeExpr* Requirement* Equation* InstanceBody
InstanceBody ::= Dispatch TypeExpr* | Methods InstanceMethod*   Methods: no Loc
InstanceMethod ::= InstanceMethod MethodName Expr               no Loc but its name's
SetMember   ::= SetInstance Instance                            no Loc but its instance's
              | DynamicInstances ClassRef (TypeExpr*)*
Default     ::= Default Label Expr

Expr        ::= Literal Constant | LocalRef Local | TopRef TopValue
              | Path label* | PathApply label* Expr
              | Lambda Local* Expr | ClosedLambda Local* Expr | Call Expr Expr*
              | If Expr Expr Expr | Seq Expr Expr
              | Let Local Scheme? Expr Expr | LocalSignature Scheme Expr
              | Match Expr Clause* | Handle Global Implementation* Expr
              | WithInstances Global* Expr
              | Ann Expr TypeExpr | Convert Expr TypeExpr | TryConvert Expr TypeExpr
              | TypeTest Expr TypeExpr | CaseId TopValue
Clause      ::= Clause Pattern Expr
Implementation ::= Implementation Label Expr
Pattern     ::= Wild | Bind Local | Equals Datum | Destructure TopValue Pattern*
```

A query over Bound, `placed-files`, answers what the build must place
beside the program for a library, as the old `library-links` does: each
`LinkImport`'s digest and file, once for each digest, in order. Bound is
the tree that writes the LinkImports, so the query reads it, whichever
tree the integrator keeps.

### Supply, what the build found for `bind` (implemented)

What the build found for one expanded library: the SHA-256 of each file
it read, in lowercase hex, by the file's path; the files of every target
its caller supplied, by target, whichever the library asks for, as
relative paths with their bytes in path order; and, when the library is a
producer program's printed copy, the copy and the recipe it stands for.
Nothing in it is promised complete: a file a library links has no digest
when the build found no file there, and a target the library asks for
may be missing. What a miss means is `bind`'s to decide.

```text
Supply      ::= Supply PrintedCopy? digest-by-file TargetFile*-by-target   no Loc
PrintedCopy ::= PrintedCopy copy recipe                         no Loc
TargetFile  ::= TargetFile path bytes                           no Loc
```

One function, `linked-file` in the query library `bind/linked.sld`,
answers the file a link names: beside the file the link is written in, but
beside the recipe when it is written in the printed copy, so a recipe
names files beside itself wherever its producer is printed. The integrator
reads the files it answers, and `bind` looks up their digests by the same
answer. The integrator decides nothing about the library: it reads,
digests, hands `bind` what it found, and relays the answer.

The integrator takes each library through `expand`, `bind` and `derive`
before it starts the next, so a problem is reported for the earliest
library that has one, as the old compiler reports it. The implicit
libraries a deriving clause needs are compiled after the library that
derives expands and before it is bound. Of each library the integrator
keeps its offer; the files to place beside the program, which it asks
`placed-files` once the library is bound; and its latest tree, the
library derived. It stops at the first library that waits for targets.

### Derived, written by `derive` (implemented)

No `Derivation` remains. A struct or an enum says instead whether it
derives Move, `move?`: whether a deriving clause of its declaration names
Move, which makes its values moved, never copied. That is not all the old
compiler's DataType says with `owned?`: a Drop instance makes a type's
values moved too, which is the instance's to say. Each Serialize and each
Deserialize a deriving clause names is an instance, a `TopInstance` among
the tops its declaration is in, right after the declaration, in the
order the clauses name them, where the old expander scans the instance it
writes for the clause. A derived instance is what the old expander's
syntax for it expands to, up to the names of locals, for the type `T`
declared with parameters `a ...` and constructors `C`, each with its
fields:

```scheme
(instance (Serialize (T a ...)) (requires (Serialize a) ...)
  (define (encode value encoder)
    (match value
      ((C field0 ...)
       (encode-case-id encoder (case-id C))
       (encode field0 encoder) ...
       (unit))
      ...)))
(instance (Deserialize (T a ...)) (requires (Deserialize a) ...)
  (define (decode decoder)
    (let ((id (decode-case-id decoder)))
      (if (case-id=? id (case-id C))
          (let ((field0 (decode decoder))) ... (C field0 ...))
          ...
          (panic "wire data has a different schema")))))
```

The instance's variables are the type's parameters. Its classes and
functions are those the implicit libraries, (snail core primitive) and
(snail shell wire), export under those names, a later library's hiding an
earlier's, as in the scope the old expander makes of their exports; the
forms are written as nodes, and nothing resolves in the library's own
scope. A constructor is the declaration's, a struct's being the struct.
Every node is at the declaration's form, but that a constructor, in a
pattern, a call or a `case-id`, is where its name is written. The locals
of the instances are numbered from Bound's first unused number, and the
root says where they stopped.

Derived declares afresh the rules `derive` looks inside, the roots and
`Top`, and reuses Bound's for the rest: `Instance`, `SetMember`,
`Default`, `Expr` and the rules it holds, and through Bound, Expanded's.

```text
Derived     ::= Defined library Top* first-unused-number
              | Program Top* Expr? first-unused-number          no Loc
Top         ::= LinkImport Global name* digest file
              | Define Global Expr
              | Signature TopValue Scheme Annotation*
              | Statement Expr                                  no Loc but its expression's
              | Expose TopValue symbol dynamic?
              | Struct Global parameter* Field* move? Annotation*
              | Enum Global parameter* Case* move? Annotation*
              | Alias Global parameter* Annotation*
              | Class Global parameter* Member* Annotation*
              | TopInstance Instance                            no Loc but its instance's
              | InstanceSet Global SetMember*
              | InstanceScope Global* Top*
              | Extern Global module symbol TypeExpr Annotation*
              | Effect Global Operation* Default* around-main? Annotation*
              | Primitive Global PrimitiveType
```

`derive` is handed the bound library and the offers of the implicit
libraries, as far as they are loaded, and nothing else. A name it needs
that they do not offer as what it needs is a problem, with the old
expander's message, at the declaration's form, where the old expander
places the names of the syntax it writes: "instance of something that is
not a typeclass" for a class, and for a function "unbound identifier
NAME", or "a type is not a value: NAME" or "syntax used as a value: NAME"
for a name that means something else. A problem with an instance's class
is found as the old expander declares the instance, and ends the
library's declarations, so the first such problem is the only one;
otherwise each instance's body reports the first name it lacks, in the
order the old expander expands the body, and every body's problem is
reported, in order.

### Declared, written by `declare` (implemented)

Every declaration becomes its entity and every body is declared, with
each of the old compiler's checks of them but an instance's overlap with
another, which is `cohere`'s, and what a dispatch clause or a
`dynamic-instances` may name, which is `dispatch`'s.

Every written type is a `Type` and every signature a `Scheme`. A `Con` is a
struct, an enum or a builtin of (snail core forms), at as many arguments as
it takes. No alias remains, nor a projection, which is the type the one
requirement of its class in scope gives the output, matched on the
arguments it gives the class's parameters that are not rows. Types carry no
`Loc`: they are values, compared and substituted as values. A row's
effects are a set, each once, in the order of their Globals (library, then
name, then serial), so equal sets are equal lists. Its tail is what the row
was written to end with: a variable, or, where an alias's parameter ends
it, the type the alias's argument wrote, which may be a row itself; a row
whose tail is a row is not the same value as the one row they make.

A scheme quantifies its written variables; then each output a class
requirement leaves unwritten, `Associated n label` for the requirement at
position `n` among the scheme's requirements; then, when its type is a
callable or code, a `CallableArgument n` for each `impl` parameter, `n` its
position among the scheme's variables, whose callable requirement, of the
parameter's contract, follows the written ones. A number names a variable
by its position in the scheme that introduces it, as the old compiler names
it `$associated.N.label` or `$callable-argument.N`, and keeps it when the
scheme is combined with another, as a method's is with its class's. The
variables `Copy` names are apart from the requirements, which have evidence
by position. A method's, an operation's and a primitive's scheme, and an
extern's type, is executable code's: a callable there is `Callable Dyn
FnContract arrow`, as the old compiler makes it a bare function type.

Every declaration is its entity, in the order written. A struct or an enum
is `Data`: each case tagged by its position, each field's type, whether a
deriving clause names Move, and whether its library declares a Drop
instance for it, which only that library can; a struct can be built. A
class knows which of its parameters are rows, each one kind only, and each
method's own scheme. An operation's type quantifies nothing and never
names its own effect, and a control operation's is total and has no
default; no operation has two. A host function takes a String or Bytes
only last. An instance has a Global of its own and gives each of its
class's parameters, its outputs in place of its equations: a row, closed
or ending with a variable its requirements give a row class, for each
parameter known to be a row where it is written, and a type for every
other. An instance of a class with outputs has them determined by the
variables its head gives the other parameters and by its requirements in
order. A Drop or a Clone instance, a lifecycle instance, is in no named
instance set; its row performs no control effect known where it is
written; beside Copy, either its row is closed and it requires nothing, or
its row ends with a variable and it requires its own class, at that
variable and one of its variables, once at least and nothing else; and it
is for a declared type of its own library at distinct variables. A pattern's
constructor, a `case-id`'s and a reference to a replacer, `Name-field-set`,
of a type with a Drop instance are in that type's library. Each label of a
method definition, a default and a handler clause is the member it names.
A `case-id` is its case and that case's TypeId. Each definition carries
the last signature written for it.

```text
Declared    ::= Defined library Top* first-unused-number
              | Program Top* Expr? first-unused-number          no Loc
Top         ::= LinkImport Global name* digest file
              | Define Global Expr Signed? Annotation*
              | Statement Expr                                  no Loc but its expression's
              | Expose TopValue symbol dynamic?
              | TopData Data                                    no Loc but its data's
              | Alias Global parameter* Annotation*
              | TopClass Class                                  no Loc but its class's
              | TopInstance Instance                            no Loc but its instance's
              | InstanceSet Global SetMember*
              | InstanceScope Global* Top*
              | Extern Global module symbol Type Annotation*
              | TopEffect Effect                                no Loc but its effect's
              | Primitive Global PrimitiveType
Signed      ::= Signed Scheme

Data        ::= Data Global parameter* DataCase* DataKind move? drop? Annotation*
DataKind    ::= StructData | EnumData                           no Loc
DataCase    ::= DataCase Global tag DataField* Annotation*
DataField   ::= DataField label mutable? Type Annotation*

Class       ::= Class Global ClassParameter* Output* Method* Annotation*
ClassParameter ::= TypeParameter name | RowParameter name      no Loc
Output      ::= Output Label Annotation*                        no Loc but its label's
Method      ::= Method Global Scheme Annotation*

Instance    ::= Instance Global ClassRef TypeVariable* Type* Type* Requirement*
                         TypeVariable* InstanceBody
InstanceBody ::= Dispatch Type* | Methods InstanceMethod*       Methods: no Loc
InstanceMethod ::= InstanceMethod Member Global Expr
Member      ::= ClassMethod Global | FieldReader label          no Loc
SetMember   ::= SetInstance Instance                            no Loc but its instance's
              | DynamicInstances ClassRef (Type*)*

Effect      ::= Effect Global Operation* Default* around-main? Annotation*
Operation   ::= Operation Global control? Type* Type Global* Annotation*
Default     ::= Default Global Global Expr
PrimitiveType ::= PrimitiveScheme Scheme | CallableOnce         no Loc

Expr        ::= Literal Constant | LocalRef Local | TopRef TopValue
              | Path label* | PathApply label* Expr
              | Lambda Local* Expr | ClosedLambda Local* Expr | Call Expr Expr*
              | If Expr Expr Expr | Seq Expr Expr
              | Let Local Scheme? Expr Expr
              | Match Expr Clause* | Handle Global Implementation* Expr
              | WithInstances Global* Expr
              | Ann Expr Type | Convert Expr Type | TryConvert Expr Type
              | TypeTest Expr Type | CaseId Global id
Clause      ::= Clause Pattern Expr
Implementation ::= Implementation Global Expr
Pattern     ::= Wild | Bind Local | Equals Datum | Destructure TopValue Pattern*

Type        ::= Con Global Type* | Callable Former Contract Arrow | Code Arrow
              | Row Effects | Var TypeVariable                  no Loc
Arrow       ::= Arrow Type* Type Effects                        no Loc
Effects     ::= Effects Global* Type?                           no Loc
TypeVariable ::= Written name | Associated number label
               | CallableArgument number | Own TypeVariable     no Loc
Scheme      ::= Scheme TypeVariable* Requirement* TypeVariable* Type   no Loc
Requirement ::= ClassRequirement ClassRef Type*
              | CallableRequirement Contract Type Arrow         no Loc
```

Declared reuses Expanded's `Constant`, `Local`, `Global`, `TopValue`,
`FieldRole`, `Label`, `Annotation`, `ClassRef`, `Former` and `Contract`.

`declare` is handed the derived library and the `Declarations` of every
library in its import closure, and, when the library derives, those of
(snail shell wire) and its closure, since a derived instance names wire's
classes; nothing else, and no instance. It writes the library declared and
what it offers the declaration of its importers: its data types, its
classes and each effect's operations, complete, by name.

```text
DeclaredLibrary ::= DeclaredLibrary Declared Declarations       no Loc
Declarations ::= Declarations library Data* Class* Effect*      no Loc
Effect      ::= OfferedEffect Global Operation*                 no Loc
```

The types part converts a written type where it is written, handed a
`Scope`: what is known there, and the requirements in scope. What is known
is the offers of the import closure and, of the library's own
declarations, the shapes its scan finds, each type's parameters and each
class's parameters and outputs, and each declaration once the pass reaches
it, as its entity. So a class of the library's own has every parameter a
type until its declaration is reached, as in the old compiler, where a
declaration sees only the entities before it; the pass threads what is
known through the declarations in order. The requirements in scope are
those a projection reads: none at the start of a signature or for a type in
an expression, the class's own `(Class parameter ... output ...)` for its
methods, and an instance's requirements for its head. Each requirement of a
scheme is in scope for those after it and for the scheme's type, not for
its own arguments. An alias's use converts its arguments where it is, then
its body with each parameter the type its argument became, and no
requirement in scope, as the old compiler resolves the body in the alias's
own scope.

The first problem stops a conversion, in the old compiler's order. A type's
arity is checked before its arguments are converted, and a projection's
arguments are converted before it is looked up. A requirement's types,
then the types its equations give its class's outputs, in the class's
order, come before the checks of the requirement as a whole: that its
equations name distinct outputs of the class, that it gives each of the
class's parameters, and that it gives each parameter known to be a row a
row or a variable. A scheme's type is then made to obey the rules of
callables: its result is no `impl`, each `impl` parameter becomes a
variable, and then no `impl` is within its result or a parameter.

What is known of a class's rows where a requirement is written is all its
rows are checked against, as in the old compiler: a signature knows the
rows of imported classes and refuses at the requirement, a declaration
those of the classes declared before it, and none of a class of its own
declared after it, which it never checks. A definition's body first
checks its signature's requirements again, every class being declared,
and refuses at the signature, before its value is declared.

The rest of a declaration's checks follow its conversion, each refused
where the old compiler refuses it and the first stopping the library. A
class's parameters get their kinds once every method is converted: a
parameter a method's type ends a row with and also writes as a type is
refused, the first in the class's order, outputs last, and then an output
that is a row, both at the class. An operation's type is refused at the
type when it is no function with a closed row, then when it quantifies,
then when a control operation's has latent effects, then when they name
its own effect. Each default, in order, names an operation, refused at its
label, that may have one, refused at the entry; then an operation with two
is refused at the effect. A host function's type is refused at the type
when a String or Bytes is not its last argument. Once every declaration is
reached, each struct, in the order written, is one a program can build,
whose every value does not hold another through struct fields, refused at
its name, and the first such struct stops the library before any body.

An instance's head is checked once its methods are declared, each refusal
at the instance, in the old compiler's order: that its head and outputs
give each of its class's parameters; that a lifecycle instance is in no
named instance set; for a class with outputs, that each requirement's
selecting arguments are determined by those before it, and then that the
outputs and the variables the head's rows end with are determined, no
output being such a variable; then each of its class's parameters in
order, outputs last, a row or a type as its kind asks, a lifecycle
instance's row label by label; then a lifecycle instance's requirements,
each in order, or another instance's rows against its requirements of row
classes; and last a lifecycle instance's type. The class is as known where
the instance is, and an effect a lifecycle row names is checked only when
it is known there, so one declared after the instance goes unchecked, as
in the old compiler. A body refuses a value of another library's type with
a Drop instance where it is taken apart or has a field replaced: a match
clause's pattern before its body, a constructor before the patterns it is
given, and a `case-id`'s constructor before its case is found.

### Dispatched, written by `dispatch` (implemented)

Every instance has its methods. An instance written with a dispatch
clause is the instance it was, with a method for each method of its class
as known where it is written, none when the class is declared later in its
library: a lambda that recovers its erased argument from `Any` for each
target in turn and calls the class's method, and fails with a `CastError`
after the last. Each `dynamic-instances` form is, in its place in its set,
the instances it generates, each at the form, for the heads `(Any R)`,
`(L Any)` and `(Any Any)` of its pairs, whose methods call the one active
source instance of each pair the head accepts. `language.sld` states the
code each writes, up to the names of locals. The texts a `CastError` holds
are the old compiler's: the types it expected, the place and the method,
which only `text.sld` writes. Who wrote an instance's methods is not kept:
the old compiler marks a dispatched method `function?`, and reads the mark
only for a value a program names, which no dispatched method is.

`dispatch` is handed the Declared library; the Declarations of its import
closure, which give an imported class's parameters, outputs and methods;
and the listings of every library compiled before it, in the program's
order, whether or not it imports them, since instances are global. It
walks the library's declarations in the order written, so a class of
the library is known, with its methods, from its declaration on, and
before that only its shape, every parameter a type and no method; and
it lists each instance as it is written or generated, so a form sees the
earlier libraries' instances, then the library's own before it. A
dispatch clause's domain is checked
first, each refusal at its instance: a ground head with exactly one `Any`
and a class no lifecycle class; at least one target; each ground and none
`Any`; none repeated. A domain's refusal is the library's only problem,
though a method's was found before it. Then each method of the class in
order: no requirement of its own, no variable of its own, a function, its
result and each parameter the erased type whole or apart from it, one
parameter the erased type. Each method's refusal is reported, at the
instance, and the walk goes on, so a library fails with every method's
problem in the order written. Each method's implementation Global is
numbered first, then the lambda's parameters, then each target's locals
in turn, from the root's first unused number on.

A `dynamic-instances` form's checks each stop the library, at the form,
in this order: its class as known there is binary, one row parameter,
two type parameters, one output and a method at least; each method in
order has no requirement of its own and is a function, then is of type
`(dyn (Fn A B -> Output ! e))`; the domain is a pair at least, none
repeated; each pair in order is two concrete types with exactly one
source, an instance of the class active where the form is, in no set,
in the form's or in one a scope around the form's set activates, whose
selecting types the pair matches, with no requirements, and an output
and a row that are ground at the match, the row closed; and no head
gives a type parameter a row, the refusal `declare` makes of a written
head, which `declare/misplaced-rows.sld` writes for both. Each head's
instance is numbered in turn: its Global, named `dynamic`, then each
method's implementation, its two parameters, and two locals for each
case.

Dispatched declares afresh the roots, `Top` and `Instance`, and reuses
Declared's for the rest.

```text
Dispatched  ::= Defined library Top* first-unused-number
              | Program Top* Expr? first-unused-number          no Loc
Top         ::= LinkImport Global name* digest file
              | Define Global Expr Signed? Annotation*
              | Statement Expr                                  no Loc but its expression's
              | Expose TopValue symbol dynamic?
              | TopData Data                                    no Loc but its data's
              | Alias Global parameter* Annotation*
              | TopClass Class                                  no Loc but its class's
              | TopInstance Instance                            no Loc but its instance's
              | InstanceSet Global Instance*
              | InstanceScope Global* Top*
              | Extern Global module symbol Type Annotation*
              | TopEffect Effect                                no Loc but its effect's
              | Primitive Global PrimitiveType
Instance    ::= Instance Global ClassRef TypeVariable* Type* Type* Requirement*
                         TypeVariable* InstanceMethod*
```

Instances are global, so the passes that choose or compare them read every
instance of the libraries before the one they work on. One instance, as
they read it, is a `Listed`, which the query library `listing.sld` writes
from Dispatched: an instance of the tree with its set, or the instance a
struct with no mutable field implies for each of its fields, `(::label (S
p ...) type)`, read by the field's accessor. A library's listing is its
instances in the order the old compiler enters them: an instance where it
is written, a struct's field instances at the struct, an instance scope's
in turn and a set's in order. From one entry the listing answers its
class, variables, types, outputs, requirements, Copy variables and set,
whether it is active under a list of sets, and its selecting types: its
head's types that are no row, a field instance's record and field types.

```text
Listed      ::= ListedInstance Instance set?                    no Loc but its instance's
              | FieldInstance Data DataField                    no Loc
```

`matching.sld` matches an instance's head one way against types, as the
old `match-types` does: only the instance's variables bind, a callable
matches a callable of its kind and code matches code by parameters and
result, never by effects, and a row matches nothing.

`overlap.sld` says when one instance overlaps another, as the old
`head-overlaps?` does: they are of one class, and their selecting types
are as many, each of the first's overlapping the second's at its
position. A data type overlaps the same type whose arguments it overlaps,
and a variable; a callable other than `dyn (Fn ...)`, a callable of its
former and contract whatever its arrow, and a variable; code, code and a
variable; and `dyn (Fn ...)`, a variable or a row overlaps anything, since
the old compiler writes `dyn (Fn ...)` as a function type and every other
callable as a type applied to one. So the relation is asymmetric: `(Probe
(dyn (Fn I64 -> I64)))` overlaps `(Probe I64)`, and not the reverse. A
repeated variable is not unified. It also says whether two of some
instances that are active under some sets overlap, either asked about the
other, as the old `check-active-instances` asks at a scope; the checks of
a `with-instances` expression and of a definition under scopes, which the
old checker makes, will ask it too.

### `cohere`, which writes nothing (implemented)

`cohere` is handed the dispatched library and the listings of every
library compiled before it, in the program's order, and lists the
library's own instances itself. It answers `(Result Unit (List
Feedback))`, and every problem is the old one, "this instance overlaps
another instance of the class on its input types". It makes the old
compiler's two checks, in its order.

First, each instance of the library's listing, written, derived or
generated, in order, is asked whether it overlaps an instance of its class
before it, of the earlier libraries or of its own, that is in its set, or
in none when it is in none. The first that does is the library's only
problem, at the instance; a generated one is at its form. An instance
sees only those before it, since the old compiler compares each as it
declares it: a struct's field instance, listed at the struct, is compared
with an instance of the field's class written after the struct, not with
one written before it, and it is never the one asked about, since it
joins its class without being compared. Two sets are compared apart,
though a scope may activate both, and the instances of a set nothing
activates are compared.

Then, when no instance overlaps, each instance scope in order, a scope
before those it holds, is asked whether two instances active under its
sets and those of the scopes around it overlap, among the earlier
libraries' instances and all of the library's own, those written after
the scope too, since the old compiler checks a scope once every
declaration is reached. Each scope where two do is a problem, at the
scope, and every one is reported.

### Typed, written by `settle` (sketch)

Every node has a type and every use of a global its instantiation.

```text
Type     ::= Con Global Type* | Callable ... | Row | Variable name
Evidence ::= Instance Global Type* Evidence* | Given number | Lifecycle Plan
Expr     ::= Term Type
Term     ::= Literal Datum | Local Local | Global Global Type* Evidence*
           | Lambda | Fn | Call | If | Let | Seq | Match | Handle
           | Convert Expr Type | TryConvert Expr Type | TypeTest Expr Type
```

Gone since Expanded: `Ann`, `WithInstances`, `Path`, `TypeExpr`.

### From Typed to Owned (sketch)

Each pass replaces one convention with a constructor.

- `convert`: `Convert` and `TryConvert` become `Box`, `Unbox` and `TypeTest`
  under ordinary branches.
- `close`: `Lambda` and `Fn` become `Closure` with its captures or `Code`
  with none.
- `place`: writes through `set!` and `replace!` become `Assign` and `Swap`
  of a `Place`.
- `borrow-check`: `Local` becomes `Use` or `Lend`.

### Concrete, written by `specialize` (sketch)

Types are ground, and every call says what it calls.

```text
Type     ::= Con Global Type* | Callable ...           no variables
Function ::= Specialized Global Type* | Glue Drop|Clone|Share Type
Term     ::= Literal Datum | Use Local | Lend Local | FunctionValue Function
           | CallFunction Function Expr* | CallValue Expr Expr*
           | Construct Case Expr* | ReadField Case number Expr
           | ReplaceField Case number Expr Expr
           | Assign Place Expr | Swap Place Expr
           | Primitive name Expr* | Foreign Import Expr* | Perform Effect Operation Expr*
           | Closure Local* Local* Expr | Code Local* Expr
           | If | Let | Seq | Match | Handle | Box Expr | Unbox Expr Type | TypeTest Expr Type
Module   ::= Data Global Type* Case* | Define Function Local* Expr | Initialize Global Expr
           | Import Function Type | Statement Expr | Export Function symbol
```

### Prepared, written by `clean` (sketch)

Concrete, except that a call that may yield sits in only two places.

```text
Term    ::= ... | YieldLet Local Call Dropper Expr | TailYield Call | Once Closure Dropper
Dropper ::= (Local Function)*                          owners to release, in order
```

## Replacing the old compiler

This section goes when the last pass lands.

The new tree is built beside the old one, front to back. `adapter/` in the
new tree is the only code that knows both: it converts the newest finished
language into the old compiler's data, so the old passes that remain run
behind the new ones and the whole test suite keeps judging the result. It
may import any library of either compiler or of the core, and it also holds
the comparisons between a new pass and the old code that does its job,
which read and write files as the old functions they call do.

| Milestone | New passes | The adapter hands the old compiler |
| --- | --- | --- |
| A | `read` to `cohere` | an expanded `Program` |
| B | `infer` to `confine` | a checked `Typed` |
| C | `specialize` to `clean` | a `Prepared` module |
| D | the backend | nothing: the adapter and the old passes are deleted |

At each milestone the new passes become the default path, and `make test`,
`make test-chibi`, `make bootstrap` and `make check` pass before the next
begins. Between milestones a pass is judged by its own tests and by a
comparison with the old pass that does its job. For `expand`, `bind` and
`derive`, `make compare-compiler` compiles every suite program that loads
completely, with stand-in files for each target it asks for, handed to
the old expander too, and compares it with the old expansion: both
succeed or both fail; failures by their first problem, message and
place, and every problem when the old expander reports several;
successes library by library, in order, by their exports, their written
definitions and each one's value in a normal form, in which a `case-id`
is the TypeId `declare` gives its case, by each linked file's import and
the files to place beside the program, by each derived instance beside
the old instance of its class and types, its variables, requirements and
method compared up to the renaming of locals, in the old order of each
class, and, for the whole program, by the targets it asks for. For
`declare`, each library's entities are converted to the old compiler's,
as milestone A will hand them over, and compared with the old program's
tables: its data types, with whether each is owned; its classes, with
their rows; its effects; every value it declares, by its kind and its
scheme, but those the old compiler names afresh; and, class by class, its
instances in the old order, written and implied by a struct's fields, by
their heads, variables, requirements, sets, the members their methods
implement and each implementation's scheme. A name a macro's template
wrote is compared by the name written, and a row's effects as a set. A
program `declare` refuses is compared as a failure is, by its first
problem, message and place, or every problem of its bodies. For
`dispatch`, each library's listing is compared with the old program's
instance tables in that way, the instances a dispatch clause or a
`dynamic-instances` form wrote among them, with their implementations'
schemes; and each instance whose methods the old program marks as
dispatched is compared with the instance in its place in the listing, by
its head and each method's value in the normal form, up to the renaming
of locals: the types of its conversions, the source implementation each
call names, by the old instance in the same place, and the texts of its
`CastError`s, compared as written. A conversion's type is part of the
normal form for every definition. A program `cohere` refuses is compared
as a failure is, by its first problem, message and place, or every
problem when the old compiler reports one at each of several scopes. It
also compares the integrator's SHA-256 with the old one, compiled, as
`make test-compiler` does on Chibi.

The language the compiler accepts does not change during the replacement,
so every existing program stays an oracle. Where the new front end
knowingly differs from the old compiler, the difference is listed here,
one line each, with its reason:

- When a library has problems for two passes, the earlier pass's are
  reported; the old expander, one walk, reports whichever it meets
  first. `(List Missing Missing)` is "not a type: Missing", where the old
  expander says the number of type arguments is wrong, since arity is
  `declare`'s to check; a handler clause's value is expanded before
  `declare` asks whether its label is an operation of the effect; an
  instance that overlaps another and has a head `declare` refuses is
  refused for its head, where the old compiler reports the overlap first.
- The field functions and the `Class.Output` names of a declaration that
  a macro's template writes are visible to that expansion, as the old
  expander's comment intends; its code leaves them unreachable. No macro
  in the repository writes such a declaration.
- "not an instance set" is reported once for a `with-instances`; the old
  expander reports it once for every body inside.
- A `syntax-rules` literal that is not an identifier is a problem with a
  message; the old expander panics.
- An instance's equations are expanded in the order written; the old
  expander expands them in the order of the class's outputs, which
  `declare` knows and `expand` does not.
- `artifact-files` expands its three expressions once each; the old
  expander expands them again for every file. `bind` copies them for each
  file instead, and the one use, in `src/snail/shell/artifact.sld`,
  passes three constructors, so nothing shows the difference.
- `bind` asks for every target a library was not supplied at once; the
  old compiler asks for one at a time, since it stops where it first
  reaches one, and asking once saves its caller a build per target.
- `bind` reports two links that clash only when the library otherwise
  expands; the old expander reports it beside the problems of the other
  bodies, since it checks links while it expands each body, and the new
  one checks after expansion.
- A link inside the `file` or `prepend` expression of a target with no
  files is still linked and placed; the old expander never expands those
  expressions when there is no file, and the new one has expanded them
  already.
- `derive` reports a name the implicit libraries lack only when the
  library otherwise expands; the old expander reports it beside the
  problems of the other bodies, or alone when it is a class, since it
  expands the instances it derives among the library's own declarations
  and bodies, and the new one derives after expansion.
- A derived instance's variables are its type's parameters, even one
  named as a type the library's top level declares; the old expander
  resolves the head it writes, the declaration's own, in the library's
  scope, where that name is the type, so its instance is for that type
  alone. `derive` resolves nothing in the library's scope.
- A name `derive` needs that the implicit libraries offer as syntax, a
  keyword or a macro, is refused as syntax used as a value; the old
  expander would expand the form it writes there, and `derive` writes
  nodes, not syntax.
- In a program, `declare` reports the first problem among its statements,
  where the old compiler reports one for each statement, and reports it
  after the problems of the definitions written after them: Expanded
  makes a program's statements its body, one expression, which is
  declared after the library's other bodies.
- A method definition names a declared class's method by the method's
  whole name, so a method whose name holds a `:` is implemented under that
  name, where the old compiler asks for the text after its last colon.
  Names are data.
- A Drop instance written before its type makes the type moved; the old
  compiler fails with an internal error, since it marks the type as it
  reaches the instance, and `declare` finds the Drop instances once every
  declaration is reached.
- The TypeId of a case a macro's template wrote is the hash of a schema
  that spells the case's Global with its serial; the old compiler spells
  the stamp of the macro's use, which no new pass has. None of the
  programs `make compare-compiler` expands writes a `case-id` of one.
- A requirement that does not give each of its class's parameters, and
  an instance whose head `declare` refuses, are refused with the class's
  name as written, as are a lifecycle row's control effect and a type
  with a Drop instance with their names; the old compiler spells the
  text after the last colon of the unique name, which differs for a name
  that holds a colon, and for a name a macro's template wrote, whose
  unique name holds its mark's stamp. Names are data, so `declare` reads
  no name's text.
- When a lifecycle instance's row names two effects with control
  operations, the first in the order of their Globals is refused; the old
  compiler refuses the first by its unique name's text, which can differ
  where one library's name begins another's, as `(a)` and `(a b)` do. No
  program in the repository names two.
- A type or a method a macro's template wrote is spelled in a `CastError`'s
  texts by its name and serial, `Box%12`, where the old compiler spells
  the stamp of the macro's use, `Box%m.12`; and a type whose name holds a
  colon is spelled by its whole name, where the old spells the text after
  the last colon. No program in the repository dispatches over either.
- An instance's selecting types are its head's types that are no row. For
  an instance written before its class in its library, which gives a type
  to a parameter the class later makes a row, the old compiler drops that
  type by the class as it is when it looks, and the new keeps it; so
  such an instance is no `dynamic-instances` source for a pair, where the
  old compiler refuses its row as not closed; and `cohere` compares that
  type, which the old compiler drops when it compares the instance with
  one written after the class or at a scope, so the old compiler may
  refuse an instance or a scope that `cohere` accepts, never the reverse,
  as it refuses `(instance (Late (!) I64))` after `(instance (Late I64
  I64))` and `(typeclass (Late e A) (: late (impl (Fn A -> I64 ! e))))`.
  Such an instance implements no method. No program in the repository
  writes one.
- `declare`'s problems come before `dispatch`'s, and `dispatch`'s before
  `cohere`'s, which runs only once both accept the library: a dispatch
  clause's domain is checked after the instance's head, where the old
  compiler checks it first; an instance that overlaps one before it is
  reported only when the library has no other problem, where the old
  compiler reports it unless a declaration before it has a problem, and
  then checks nothing more; and a scope under which two instances
  overlap is reported only when the library has no other problem, where
  the old compiler reports it beside the problems of the library's
  bodies, in order. So an instance that overlaps another, or a generated
  head that does and also gives a type parameter a row, is refused for
  its domain or its row, where the old compiler reports the overlap.

The integrator compiles everything on each build. Reuse between builds, which
the old session provided, returns with the incremental work that follows the
replacement; until then a development build recompiles the whole program.
