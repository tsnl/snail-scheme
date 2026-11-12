# State of the rewrite

Paused on 2026-11-12 at the owner's request, while a simplification lands
on `main` from other work. Nothing is running.

## On resume, first

1. Look at what changed on `main`. This branch was cut from 6ecf6291. At
   the pause `origin/main` was already past it, at least by "Replace
   overloaded fields with nominal projections" (#747), which changes field
   classes and paths, both of which the new front end models. Decide how
   the branch meets the new `main` before building anything more: what of
   the old compiler, the language, the tests and `AGENTS.md` changed, and
   which passes and comparisons that touches.
2. Rerun every gate on the branch's head, printing each exit status. The
   last commit before the pause, ef9735b2, was verified by the agent that
   wrote it, each gate exiting 0, but not a second time by the supervisor.
3. Then continue with "Next" below, adjusted to what step 1 finds.

## Done and pushed

The front half, each pass with its tests, compared with the old compiler:
`read`, `include`, `outline`, `expand`, `bind`, `derive`, `declare`,
`dispatch`, `cohere`, and the integrator that loads a program and takes
each library through them, with generated libraries and target discovery.

The adapter into the old compiler: the pure conversion to the old
`Program`, the entry `adapted-compile`, and the comparisons that judge it.

The first two parts of the vocabulary folders: `names/`, `literals/`,
`builtins/`, `types/`, `typer/`, with the state-threading binding forms in
`source.sld` and one fresh numbering.

## Verified at the pause

`make compare-compiler`, over the suite programs both compilers load:

| Comparison | Result |
| --- | --- |
| Expansion, `read` to `cohere`, against the old expander | 380 alike, 68 fail alike with the same problems at the same places, none differ, 15 not compared |
| The adapted program against the old expansion's, table by table | 380 alike, none differ |
| The old checker on both | 213 check alike, 167 fail alike, none differ |
| Producers, target discovery, the text of Syntax, decoding, SHA-256 | no differences |

The 15 not compared: 12 reach a generated library, whose producer the
comparison does not run, and 3 do not load in either compiler. The suite
itself judges the 12 once the default path switches.

`make test` is 550 of 550, `make bootstrap` passes, and `make test-chibi`
passed at 96c68050 (550 of 550, 42 minutes). On Chibi the new front end
takes about 12 s over the compiler's own source, against the old
expander's 17 s.

## Next

1. **Vocabulary, third part: `declarations/`.** Not started. The shapes
   are agreed, as in "Shapes for `declarations/`" below.
2. **Switch the default compile path** (`milestone-a/design.md`, slice
   A3a). The old facade calls `adapted-compile`; the driver passes the
   generated directory; the project builder writes each producer's output
   as `KEY.syntax`; `current-compiler` in
   `host/chibi/snail/stage0/build.sld` must list `src/snail/compiler`, or
   the gates run a stale compiler and pass for the wrong reason. Full
   gates, `make test-chibi` and `make bootstrap` included.
3. **Sessions without reuse** (A3b): every build compiles everything; a
   session keeps only the last build's module texts, and a module whose
   text did not change is not reassembled or relinked. The owner agreed.
4. **The build planner** on the new integrator (A4), then the book (A5).
5. **The typed half** (`typed/design.md`), revised first as the owner
   asked; see his decisions below.
6. The module half and the backend are not designed.

## Shapes for `declarations/`

An entity holds no code. It keeps the names later passes look up across
libraries, and the tree beside it holds only each such Global's
expression, never the member or operation again.

```text
Data         ::= Data Global parameter* DataCase* DataKind move? drop? Annotation*
DataCase     ::= DataCase Global tag DataField* Annotation*
DataField    ::= DataField label mutable? Type Annotation*
Class        ::= Class Global ClassParameter* Output* Method* Annotation*
Method       ::= Method Global Scheme Annotation*
Member       ::= ClassMethod Global | FieldReader label
Effect       ::= Effect Global Operation* Defaulted* around-main? Annotation*
Operation    ::= Operation Global control? Type* Type Global* Annotation*
Defaulted    ::= Defaulted Global Global          an operation, and the Global that holds its default
Instance     ::= Instance Global ClassRef TypeVariable* Type* Type* Requirement* TypeVariable*
                          Implementation*
Implementation ::= Implementation Member Global   a member, and the Global that holds its implementation
Declarations ::= Declarations library Data* Class* Effect*
Listed       ::= ListedInstance Instance set? | FieldInstance Data DataField
```

- In Declared, `TopInstance` and a set's member hold the instance with
  either its dispatch clause's types or the values of its
  implementations; `TopEffect` holds the effect with the values of its
  defaults. An instance written with a dispatch clause has no
  implementations until `dispatch` writes them. In Dispatched every
  instance has its implementations and their values.
- The offer holds the `Effect` itself, so `OfferedEffect` and
  `declare/offer.sld` go. `Annotation` moves to `declarations/`. The
  relation on types that overlap uses moves to `typer/`. The walk that
  lists a library's instances stays in `dispatch`, since it reads
  Dispatched.
- Definitions, externs and primitives are not entities yet: their schemes
  are the type checker's to offer. The two views of "a class as known
  where it is written", in `declare` and in `dispatch`, stay until the
  old order dependence they reproduce is removed.
- The bare function type, `Callable Dyn Fn arrow`, matched in six places
  and built in two, gets one constructor and one recognizer in `types/`.

## The owner's decisions since the designs were written

2026-11-12, on the typed half:

- Eager resolution is approved on one condition: "I generally like this
  as long as it doesn't lead to code duplication." The test: "whether the
  same functions that resolve deferred constraints can resolve
  constraints eagerly to simplify them before adding them to a constraint
  pool." And: "I am flexible on changing the type-checker behavior here
  if it produces a cleaner factorization and a simpler implementation."
- Layout: "a separate module or two (I typically call this `types/` and
  `typer/`) defines the 'vocabulary' of types, and algorithms on those
  types for things like conversion, unification, etc. E.g. I usually
  define `Substitution` in `typer/`. We can then compose these together
  in the corresponding pass(es). `types/` is typically depended upon for
  all passes downstream of the typer as well." So the design's queries
  under `infer/` and its `settle/types.sld` become `typer/` and `types/`.
- One `Type` in `types/`, with an unknown case added when the type
  checker is built; a settled tree holds none. A `Term` with types as a
  special case and normalization by evaluation was considered and set
  aside as too much for now.
- A closure's identity must name its library: the old checker names a
  closure's type after a local, and that type can reach a scheme other
  libraries see.

2026-11-12, in general:

- "I'm fine with language reuse, I was a bit too strict earlier with each
  pass having one language. As long as passes are small and languages
  aren't serving too many roles, I'm happy."
- Values and logic that flow through many passes live in top-level
  folders outside any language: `names/`, `literals/`, `builtins/`,
  `types/`, `typer/`, `declarations/`.
- Problems: halting between passes is right; several independent problems
  within a pass are good; no failed body is carried forward as a poisoned
  node.
- `declare` reproduces the old compiler's order dependence, where a
  declaration sees only those written before it. Clean it up after the
  replacement.

## How each slice is run

One implementing agent at a time in one worktree, which does not commit.
The supervisor reads the code, reruns every gate, commits and pushes. Two
habits came from a mistake on this branch, a commit pushed with `make
test-compiler` failing:

- Run each gate to a log and print its exit status. A gate piped through
  a filter loses it.
- Make new files visible to git (`git add -N`) before running the gates.
  The comparisons read only tracked files, so a new test program is
  invisible to them until then.

The gates: `make test-compiler`, `make compare-compiler`, `make check`,
`make test`, `make bootstrap`, and `make test-chibi` when the old
compiler's source or stage 0 changes. Never two at once in one checkout.
