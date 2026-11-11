# Compiler passes

**Under construction.** This chapter specifies the compiler being built in
`src/snail/compiler/`. Until its last pass lands, programs are still compiled
by the passes in [Compiler architecture](compilers.md). The Status column
says which passes exist. A grammar marked *sketch* is a plan; one marked
*implemented* is what the code declares.

The compiler is a sequence of small passes. Each does one thing and writes
its result in a language of its own, so the table below is the compiler's
outline: read it top to bottom to follow a program from text to WebAssembly.

| Pass | Unit | Reads | Writes | The one thing it does | Status |
| --- | --- | --- | --- | --- | --- |
| `read` | file | text | Syntax | Text becomes located forms. | implemented |
| `include` | file | Syntax | Syntax | Each `include-bytes` form becomes the bytes of its file. | implemented |
| `outline` | file | Syntax | Outline | The header is parsed: name, imports, exports. The body stays Syntax. | implemented |
| `expand` | library | Outline | Expanded | Macros run, every name is resolved, every core form is parsed. | planned |
| `derive` | library | Expanded | Derived | `deriving` clauses become instance declarations. | planned |
| `declare` | library | Derived | Declared | Written types become types; declarations become entities. | planned |
| `dispatch` | library | Declared | Dispatched | `dispatch` clauses become method definitions. | planned |
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
  handed and returns the decision as data. It does not visit children, does
  not thread a pass's state and does not report failure.
- The **integrator** is the one place that calls passes. It orders
  libraries, runs the loops, reads files and decides what is reused.

Passes are not strictly a chain: a pass may read more than one earlier
language, as `expand` reads Outline and the Syntax inside it. A pass that
only checks, as `confine` does, writes nothing.

## Where the code lives

```text
src/snail/compiler/
  source.sld              (snail compiler source): Loc, Feedback, result-let*, map-results
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
  ...
  integrate.sld           (snail compiler integrate)
```

Each pass is a folder. `language.sld` holds the language the pass writes:
data definitions under their grammar, and no logic. `pass.sld` exports the
pass as one function named for it. A rule or query library sits beside them
under a name that says what it decides or answers.

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
other library beside `language.sld` and `pass.sld` is a rule library.

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
other pass. `make test-compiler` runs these tests alone and, while the old
compiler exists, the comparisons with it.

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

```text
Outline    ::= Defined library Import* Export* Syntax*
             | Generated library Syntax* Syntax    the recipe's imports and expression
             | Program key* recipe? Import* Syntax*  no Loc
Import     ::= Whole library | Only Import Identifier* | Except Import Identifier*
             | Prefix Import prefix | Rename Import Renaming*
Renaming   ::= Renaming Identifier name            no Loc but its identifier's
Export     ::= Export Identifier name              no Loc but its identifier's
Identifier ::= Identifier name
```

### Expanded, written by `expand` (sketch)

No macro use or definition remains, every identifier is resolved, and every
form is a core form. Types are still as written.

```text
Name     ::= Local name number | Global library name
Top      ::= Define Global Expr | Signature Global TypeExpr | Statement Expr
           | Expose Global symbol
           | Struct | Enum | Alias | Class | Instance | InstanceSet | Effect | Extern
Expr     ::= Literal Datum | Ref Name | Lambda Local* Expr | Fn Local* Expr
           | Call Expr Expr* | If Expr Expr Expr | Let Local Expr Expr | Seq Expr Expr
           | Match Expr (Pattern Expr)* | Handle Effect (Operation Expr)* Expr
           | Ann Expr TypeExpr | Convert Expr TypeExpr | TryConvert Expr TypeExpr
           | TypeTest Expr TypeExpr | WithInstances InstanceSet* Expr
           | Path label+ | LinkedFile path | ArtifactFiles request
Pattern  ::= Wild | Bind Local | Literal Datum | Case Global Pattern*
TypeExpr ::= Named Name TypeExpr* | Callable ... | Variable name
           | All name* Requirement* TypeExpr | Projection Name member TypeExpr*
```

`LinkedFile` and `ArtifactFiles` stay in the tree. Queries over Expanded
gather them for the integrator, which reads the files and builds the other
targets.

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
| A | `read` to `dispatch` | an expanded `Program` |
| B | `infer` to `confine` | a checked `Typed` |
| C | `specialize` to `clean` | a `Prepared` module |
| D | the backend | nothing: the adapter and the old passes are deleted |

At each milestone the new passes become the default path, and `make test`,
`make test-chibi`, `make bootstrap` and `make check` pass before the next
begins. Between milestones a pass is judged by its own tests and by a
comparison with the old pass that does its job.

The language the compiler accepts does not change during the replacement,
so every existing program stays an oracle.

The integrator compiles everything on each build. Reuse between builds, which
the old session provided, returns with the incremental work that follows the
replacement; until then a development build recompiles the whole program.
