# Milestone A: the new front end as the default path

Design only. Read at HEAD ed2ff3fc (`git diff HEAD` was empty when the
integrator and adapter were read; declare files were being edited
later). `inventory.md` beside this file lists every seam with its lines.
Where the book and the code disagree, the code is taken: passes.md's
milestone table says A ends at `dispatch` and hands "an expanded
`Program`"; the supervisor's brief adds `cohere`, which writes nothing,
so A ends once a library is dispatched and cohered, and what the
adapter hands is the old `Program` (core.sld 1141), the value the old
expander's `ExpandedProgram.program` holds.

Nothing here was run. Times are read from the gate logs in `build/` or
the book, or estimated, and each says which.

## 0. The decisions

| Question | Decision |
| --- | --- |
| Where old and new meet | One adapter entry, `adapted-compile`, called by the old facade (`src/snail/shell/compiler.sld`) in place of `expand-program`. Nothing else of the old shell imports a new library. |
| What it hands over | `AdaptedProgram`: the old `Program`, and for each library in program order its old name and its `LinkedFile`s. |
| Failure | The new tree answers `Result`; the adapter performs the old `fail` with the feedback converted; nothing else crosses. |
| Waiting | The integrator answers as data. The adapter turns it into old `CompilerRequest`s and producer texts; the facade prints the producers and performs `need` for the first, so `request.datum`, stage 0's loop and the project builder's handler are unchanged. |
| Producer outputs | The integrator reads `GENERATED/KEY.syntax`; every caller puts outputs there. |
| Producer key | The new printer reproduces the old `producer-text` byte for byte, so old and new keys agree while the planner moves over. |
| Target discovery | A second integrator entry, `discover-targets`, expands every library without binding any and answers each target asked for. |
| Sessions | No reuse: each build compiles everything. A session keeps only the previous build's module texts, so `compiled?` means "its text changed" and assembly is skipped for unchanged text. |
| Old expander | Reachable only from the adapter's comparisons and its own unit tests; deleted at milestone D with the rest. |

## 1. Seam inventory

Summarised; `inventory.md` has the lines.

- **Facade** `compiler.sld`: `source->wat`, `source->modules`,
  `source->schemas`, all `(directories source generate inputs)`.
- **Session** `session.sld`: `build-session` keys reuse by
  `library-key`, reads `library-links`, replays the previous expansion.
- **Driver** `driver.sld`: the `generate` callback is
  `generated-syntax`; `Requested` becomes `request.datum`.
- **Inputs and requests** `inputs.sld`, `read.sld`: `Inputs`, the
  producer text and key, the request grammar, `need`, `decode-syntax`.
- **Planner** `project/plan.sld`: `library-closure`, `program-imports`,
  `discover-artifacts`, `producer-text`, `generated-output`.
- **Builder** `project/build.sld`: `link-program`, `develop-program`,
  `Retained`, `assemble-modules`, `produce`, `supply-producer`, the
  `compiled` handler.
- **Stage 0** `host/chibi/snail/stage0/build.sld`: the request loop,
  `produce!`, `current-compiler`'s source list. Entries
  `host/chibi/compile.scm` and `bootstrap/compile.sld` call the driver.
- **Tests**: the old unit tests run by `tests/run.scm`, `test-session`,
  `tests/artifacts/`, seven project suites that count `compiled`, and the
  comparisons.

What the old passes after the expander read of it is only `Program`, the
links per library, and, for sessions, the library keys. That is the whole
contract the adapter must meet.

## 2. The adapter

### Libraries

- `adapter/declaration.sld` (exists): entities, `old-name`, `old-type`,
  `old-scheme`, `old-data`, `old-class`, `old-effect`, `old-instance`.
  It stays the one home of spelling (see "Names").
- `adapter/expressions.sld` (new): a Dispatched expression to an old
  `Expr`. Pure.
- `adapter/program.sld` (new): `adapted-program : (List DispatchedFile)
  -> AdaptedProgram`. Pure: no `fs`, no `compile`.
- `adapter/feedback.sld` (new, moved): `feedback->old`, now in
  `adapter/outline.sld`, so the default path does not import a
  comparison library.
- `adapter/compile.sld` (new): the entry.

```text
AdaptedProgram ::= AdaptedProgram old:Program AdaptedLibrary*
AdaptedLibrary ::= AdaptedLibrary old-key old:LinkedFile*      in program order
Adapted        ::= AdaptedBuild AdaptedProgram
                 | AdaptedRequests old:CompilerRequest+ Printed*
Printed        ::= Printed key text                             a producer to print
```

```scheme
(: adapted-compile
   (impl (Fn (List String) String old:Inputs String -> Adapted ! fs old:compile)))
(define (adapted-compile directories generated inputs path) ...)
```

It calls the integrator's `compile-program` (section 3), converts the
`Inputs`' artifacts to the integrator's `Table (List TargetFile)`
(`TargetFile path bytes`, from `(Pair path bytes)`), and:

- `Err feedback`: `old:fail` with `(map feedback->old feedback)`, in
  order, so a program with several problems prints them as the old
  expander did ("fail alike, several problems" is the comparison that
  holds this today).
- `Ok (CompiledAll files)`: `AdaptedBuild (adapted-program files)`.
- `Ok (WaitingForProducers producers)`: `AdaptedRequests` with one
  `GenerateInput key` per producer and its `Printed`.
- `Ok (WaitingForTargets requests)`: `AdaptedRequests` with one
  `ArtifactInput name loc` per target, `loc` converted.

The old facade keeps its signatures but for the `generate` callback,
which becomes the `generated` directory:

```scheme
(source->wat directories generated inputs source)       ; WholeProgram
(source->modules directories generated inputs source)   ; (List Built)
(source->schemas directories generated inputs source)   ; String
```

On `AdaptedRequests` the facade writes each `Printed` to
`GENERATED/KEY.sld` and performs `need` with the first request, which
is the old protocol exactly (section 4). On `AdaptedBuild` it runs
`check-program` on the program, as now, and takes links from the
libraries instead of `program-links`/`library-links`.

### What `adapted-program` fills

The per-entity mapping is the two earlier designs':
`build/declare-design/design.md` section 5 and
`build/dispatch-design/design.md` section 6. Beyond them, assembling a
program needs:

- **Order.** Libraries in the integrator's order (`CompiledAll` is the
  order compiled, the implicit libraries where the integrator compiled
  them). `make compare-compiler` already compares this order against the
  old expansion ("expand alike" includes it). `Program.libraries` is
  `(old-key . item-count)` per library; the primitive library records no
  run and contributes only its `prim:` values, as `primitive-delta`
  does (core.sld 1686).
- **Items.** Per library, in the order of its tops: `Define`,
  `Statement` as `Do`, `Expose`; instance methods at their instance,
  defaults at their effect, dispatched methods at theirs. A program's
  body, which Declared keeps as one expression, becomes what
  `with-one-body` writes: `Define "main:%body"` of a `Lambda ()`, placed
  after the other items, with `Do (App (Var "main:%body"))` at the
  first statement's loc.
- **Linked files.** A `LinkImport (global path digest file loc)` becomes
  the `Foreign` value `(Import "snail.runtime.link" digest)` with scheme
  `TFun () I32 empty-row`, as the old expander writes it, under the
  global's old name; the library's `AdaptedLibrary` carries the
  `LinkedFile digest file` of each of the library's `placed` files.
- **Paths.** `Path` and `PathApply`, which the old expander resolves
  (expand.sld 3786), are written as it writes them: one label is
  `Var "::label"`; several are a `Lambda` over a fresh local applying
  each field class in turn. Each label used adds its field class with
  `program-with-field-class`.
- **Locals.** `Local name number` is spelled `name.number`. The number
  is the library's own (expand/language.sld 748: "numbered within the
  library"), and the old analyses need a name unique only within its
  body (ownership: "Names are unique, so a name's liveness needs no
  scoping"), so library-local numbers suffice; `local-name` strips after
  the last `.`, so messages print what they print now. Fresh locals the
  adapter needs (a path's) take numbers from the library's
  `first-unused-number` upward.
- **Instances.** Global, as the old checker expects: `Program.instances`
  holds every library's instances, per class in the listing's order
  (dispatch design section 3). The old checker's whole-program view at
  milestone A is unchanged.
- **Metadata.** Empty: nothing on the default path reads it
  (inventory, first paragraph).

### Names

One function spells a Global for every table, every expression and the
TypeId schemas, so the old backend's `case-type-id` over the adapted
program (core.sld 1441) equals the `case-id` literal declare computes.
Today `adapter/declaration.sld`'s `old-name` spells serial 0 as
`lib.dotted:name`, builtins of (snail core forms) bare, and a serial as
`name%m.SERIAL`; declare's own TypeId schema spells a case's Global
with its serial (passes.md, known differences). These must be one
spelling, or a macro-written wire case gets a `case-id` the backend's
schema disagrees with. No program in the suites writes one (passes.md),
which is why no test would show it.

Where the old compiler names a value afresh from a program-wide counter
(`show.12`, `op-default.N`, `dynamic.N`, locals `x.N`), the adapter
spells the new Global or Local instead. Messages print the text after
the last `:` (`short-name`), so such a name prints differently, e.g.
`show%m.5` where the old printed `show.12`; a grep of the 250 `.err`
files finds neither form, so no expected output pins one.

### Determinism

The adapter builds lists in program order and never lists a table
without sorting it by key, because Chibi and Wasm disagree on key order
and `make bootstrap` compares the two hosts' texts of the compiler.

### Checking the adapter before it is the default

A comparison added to `make compare-compiler` (slice A2): for each
program that expands alike, run the old `check-program` on both the old
expansion's `Program` and the adapted one, and compare the outcome:
both succeed, or both fail with the same first diagnostic, message and
place. That covers the ~250 error programs' checker messages, which
print names, types and locations from what the adapter wrote. It costs
two checks per program; an estimate for the comparison as a whole is
60 to 120 s, up from 22-25 s (gate logs), still outside `make test`.

## 3. The integrator's remaining work

### Dispatch and cohere in the loop

After `declare`, each library is dispatched and cohered before the next
starts, as the dispatch design's section 3 says; `CompiledFile` keeps
its listing and its Dispatched tree in place of `declared`. `cohere`
answers `Result` and writes nothing.

### Generated libraries

Today `load` stops at a Generated outline and `compile-loaded` answers
`WaitingForLibraries` before compiling anything. Needed:

1. **The producer program, a query.** `outline/producer.sld`
   (";; Query:"): from `Generated library imports expression` and the
   recipe's file, the producer's forms, as the old `producer` writes
   them: the recipe's imports with
   `(only (snail shell syntax) write-generated-library)`,
   `(recipe "FILE")`, `(write-generated-library (lambda () EXPRESSION))`;
   its text; and its key.
2. **Text the reader reads back, a query.** `read/written.sld`: Syntax
   as text, matching the old `syntax->string` and `datum->string`
   (read.sld 128-162) exactly, escapes included (`\"`, `\\`, `\n`). The
   key is `fnv-1a` of the quoted directories, a newline, and the forms
   joined by newlines, as `producer-text` and `producer-key` compute it
   (inputs.sld 73-78); the printed file adds the `(generating ...)` line
   first, which the key does not cover. `fnv-1a` is in
   `declare/identities.sld` today and moves to a library both can read
   (`source.sld`).
3. **Decoding the output, part of `read`.** A second entry beside
   `read`, from a producer's bytes and the recipe's Loc to Syntax, with
   the old `decode-syntax`'s format and messages (read.sld 771-822): tags
   0 to 7, every node at the recipe's loc, a number read as the reader
   reads it (`read/literals.sld`).
4. **The walk.** For a Generated outline, the walk computes the key,
   reads `GENERATED/KEY.syntax` when it is there (`files.sld`, the only
   reader), decodes it, outlines it as a `Library` (passes.md: "the
   integrator outlines that output as a `Library`"), checks its name as
   the old `output-library-file` does, and walks its imports. When it is
   not there, the library waits. `Loaded.waiting` becomes
   `(List Producer)`, `Producer library key text loading`, so the answer
   carries what the caller must print.

`ProgramCompilation`'s second case becomes
`WaitingForProducers (List Producer)`. The cycle through a producer
("library import cycle through sample.knot") is already the walk's:
the printed producer's `(generating ...)` libraries count as loading
(walk.sld 160, 273).

### Inputs

```scheme
(: compile-program
   (impl (Fn (List String) String (Table (List TargetFile)) String
             -> (Result ProgramCompilation (List Feedback)) ! fs)))
(define (compile-program directories generated targets path) ...)
```

Directories, the generated directory, the targets' files as data, the
program's path. Linked files are read by the integrator from where
`linked-file` answers, as now.

### Target discovery

The planner needs every target a program asks for before it builds
anything. The old `discover-artifacts` is a whole expansion with no
target supplied. The new one:

```scheme
(: discover-targets
   (impl (Fn (List String) String String
             -> (Result (List TargetRequest) (List Feedback)) ! fs)))
```

loads the program, expands every library in order, handing each the
offers of those before it, and answers `requested-targets` of each,
each target once at its first request. It binds nothing, so nothing
waits; derive is not needed, since a derived instance adds no name to
an offer. It may answer `WaitingForProducers`-like data only in the form
of an error, since the planner runs it once every producer has run, as
the old one does (`unsupplied-producer` panics, expand.sld 1176); it
answers `Err` with "internal error: discovery reached a producer whose
output was not supplied" as feedback rather than panicking.

`compile-loaded` keeps stopping at the first library that waits: the
driver path wants one request, and a project build supplies every
discovered target first.

## 4. The request protocol

Inside the new tree a wait is data; across the process boundary it is
the old protocol, unchanged.

```text
integrator   Ok (WaitingForProducers producers) | Ok (WaitingForTargets requests)
adapter      AdaptedRequests (GenerateInput key | ArtifactInput name loc)+ Printed*
facade       write each Printed to GENERATED/KEY.sld; perform need with the first
driver       Requested -> request.datum, status 1        (driver.sld 29-32, unchanged)
stage 0      parse-request, produce! KEY or raise the resolver error   (unchanged)
builder      Requested -> "internal error: the build plan did not supply the input ..."
```

`request.datum` keeps "exactly one" request (inputs.sld 136), so stage
0, whose loop is Chibi code reading it with the old parser, needs no
change. A program reaching N producers costs N+1 compiles under stage 0,
as it does now. `artifact-no-resolver.err` stays "LOC: artifact-bundle
requires a project build resolver: client", raised by stage 0 from the
first target's loc.

Recommendation: do not widen the request to several in milestone A.
`bind` asking for every target at once saves a build per target only
for a caller that can supply targets, which is the planner, and the
planner gets them from `discover-targets` in process.

## 5. Sessions and the development server without reuse

### The session

```scheme
(struct Session
  ((directories (List String))
   (texts (Table String))))         ; each module's text in the last build, by name
```

`build-session` adapts the whole program, checks every library in order
(`check-libraries` without its `checked-library` shortcut), emits every
library, and marks a `Built` `compiled?` when its text differs from
`texts`. The control module is compiled when its text differs. The
project builder's `assemble-modules` keeps assembling only modules
marked `compiled?`, so unchanged modules keep their bytes and digests,
and the page relinks only what changed.

This needs a library's text to depend only on the library and what it
imports. The adapter's names give that: serials and local numbers are
the library's own. The old cold build did not (its fresh names came
from a program-wide counter; its session hid that by replaying), so a
cold old build and a cold new build agree less than warm ones did.

Recommendation, an owner call: the text comparison and the assembly it
saves are not compiler reuse, since every library is compiled every
build and the comparison is of finished output; keep them. Without them
every module is reassembled and relinked on every edit, and every
module's globals start over on each relink.

### What gets slower

Unmeasured; estimates from the book's warm compile times (bootstrap.md:
Siegework 0.36 s and the compiler 1.31 s, Node, one module) and
AGENTS.md's dev figures.

| Workflow | Now | Without reuse, estimate |
| --- | --- | --- |
| `snail dev`, Siegework, a function body edited | ~100 ms (AGENTS.md) | 0.5-1.5 s: the whole program, standard libraries included, checked and emitted per library |
| `snail dev`, Hearsay | ~750 ms, producers every time | 1-2 s |
| `snail build`, `snail run`, `make test` compiles | already cold | unchanged but for the front end's own cost (section 6) |
| Editor diagnostics | through the dev build | as `snail dev` |

### What breaks or changes

Nothing stops working. What changes:

- The meaning of `compiled` in the service's status JSON
  (toolchain.md 365-368, "how many libraries that build compiled rather
  than reused") becomes "how many modules' text changed". The JSON key
  stays, since `tests/project-http.mjs` 53 pins the keys.
- The counts the project suites assert (section 7).
- The book: AGENTS.md's "rebuilds only the libraries an edit reaches,
  about 100 ms", toolchain.md 159-162 (retained sessions),
  compilers.md's separate-compilation passages (94, 124, 184).
- The old session tests that assert reuse.

To list on the PR as future work: reuse between builds returns with the
incremental work after the replacement (passes.md's last line).

## 6. Stage 0 and the bootstrap

- **Include path.** `bootstrap/chibi-include/snail/compiler` already
  links the whole new tree, the adapter included, and the old tree is
  linked too, so no symlink is added.
- **Paths.** `scripts/chibi-paths` already scans `src/snail/compiler`;
  each new struct's labels need a regenerated section, which the gates'
  `--check` catches.
- **Staleness.** `current-compiler` (stage0/build.sld 351-363) does not
  list `src/snail/compiler`. Once the driver imports the new tree, an
  edit there must rebuild `snailc.wasm`; without the entry, every gate
  after an edit to a pass runs the stale compiler and passes for the
  wrong reason. Add it in the slice that makes the new path the default.
- **Host agreement.** The adapter and the new passes must not depend on
  table key order or overflow. `make test` compares hosts on
  `examples/fibonacci.sld` and the control programs; `make bootstrap`
  compares Chibi's stage 1 with stage 2 over the compiler.
- **The first bootstrap after the switch.** Stage 1 is the previous
  compiler's output (old front end) or Chibi's (new front end); stage 2,
  compiled by stage 1, and stage 3 by stage 2 both use the new front
  end, so the fixpoint check compares new with new. Nothing special.
- **Size.** The compiled compiler's closure gains the new front end and
  the adapter, and loses the old expander and most of `inputs.sld`: by
  line counts (tests included), old 22.2k with expand.sld 5.1k; new tree
  through declare 25k, adapter 3.4k of which the comparisons are most,
  dispatch and cohere not written. So roughly 1.8 to 2 times the source.

### Gate times

From the logs in `build/` (`/usr/bin/time` lines):

| Gate | Now | Milestone A, estimate |
| --- | --- | --- |
| `make check` | 2 s | 2 s |
| `make test` | 2:01-2:13 | +5-15 %: each compile runs the new front end (the compiled comparison runs old and new front ends over 440 programs in ~22 s, ~50 ms a program for both) and starts a larger `snailc.wasm`; plus a slower self-build of the compiler and tools when stale |
| `make compare-compiler` | 22-25 s | 60-120 s with the check comparison |
| `make test-compiler` | 2:32 | +unit tests of the new pieces |
| `make test-chibi` | no log | unknown; every compile runs the new passes on Chibi |
| `make bootstrap` | no log | three self-compiles of ~2x the source: on Node ~1.3 s each now (book), ~2.5-3 s after; Chibi's stage 1 unknown |

Recommendation: before the switch, measure stage 0 on Chibi with the
new front end on two inputs, `examples/fibonacci.sld` and the compiler
itself, against the old front end; the 6 GB `SNAIL_STAGE0_HEAP` is the
limit to watch.

## 7. Tests

### Expected outputs that change

None of `tests/programs`' `.out` or `.err` is predicted to change,
because:

- the last comparison (declare-s3) reports 0 programs failing
  differently, 0 whose several problems differ, and 0 expanding
  differently;
- no `.err` holds a name the adapter spells differently;
- the known differences in passes.md show in no suite program.

Three conditions, each a gate of slice A3a:

1. The 25 programs only the old compiler refuses are refused by
   declare, dispatch or cohere (`inventory.md`): the old checker does
   not make those checks, so otherwise they compile and their `.err`
   fails.
2. A2's check comparison agrees on every program.
3. The 12 programs that reach a generated library, which no comparison
   expands, pass in `make test`.

### Assertions that change with reuse

| Test | Assertion | Prediction |
| --- | --- | --- |
| `tests/project-development.mjs` 114, 123, 138 | `compiled` 0 | holds if texts are deterministic |
| `tests/project-attempts.mjs` 99 | every target 0 | holds, same condition |
| `tests/development-runs.mjs` 69, 119 | 0 | holds, same condition |
| `tests/project-reload.mjs` 72 | 2, "the application and its entry need new instance symbols" | likely 1: the entry's text changed only because old fresh names shifted |
| `tests/project-resources.mjs` 106 | 2, "the library that links the file, and its importer" | likely 1: the importer's text holds no digest |
| `tests/artifacts/check.mjs` 40 | `generated.assets main sample.consumer sample.generic` | likely smaller: modules whose text does not hold the target's bytes drop out |
| `session.sld` `test-session` | reuse counts, warm against cold | rewrite: a warm build's texts equal a cold build's, and an unchanged build marks none compiled |
| `tests/artifacts/compiler.sld` | its `generate` callback and `Inputs` | rewrite to the new facade: answer each request in a loop, writing the producer's output as `KEY.syntax` |

The predictions are reasoning, not runs; the slice that lands them
names each changed assertion on the PR.

### Tests over generated libraries, targets and linked files

Listed in `inventory.md`. All run in `make test`; the project suites
cover the planner and builder paths, `tests/artifacts/` the Wasm
compiler with supplied targets.

### `make compare-compiler`

Keep it through milestone A as the oracle while dispatch, cohere and
the adapter land, adding the producer-text comparison (A1) and the
check comparison (A2). After the switch it still compares the new
expansion with the old, reachable through `adapter/load.sld`. Delete it
at milestone D with the old compiler, as the owner ruled for the
adapter.

## 8. Slices

Each leaves `make test`, `make test-chibi`, `make bootstrap` and
`make check` passing, with the old expander reachable for comparison.

- **A0, the passes.** declare finished, with its 12 refusals; dispatch
  and cohere as the dispatch design's section 7 slices them, in the
  integrator's loop, judged by `make compare-compiler`. Gate to leave
  A0: "only the old fails" is 0.
- **A1, producers in the new tree.** `read/written.sld`, the decoding
  entry, `outline/producer.sld`, `fnv-1a` moved, the walk reading
  `KEY.syntax`, `Producer` in the answer, `compile-program`,
  `discover-targets`. The default path is untouched. Comparisons:
  for each of the 12 generated programs, the new producer text and key
  equal the old `producer-text` and key; for every program,
  `discover-targets` equals `discover-artifacts` by name and first loc.
- **A2, the adapter.** `adapter/expressions.sld`, `adapter/program.sld`,
  `adapter/feedback.sld`, `adapter/compile.sld`, and the check
  comparison. Default path untouched.
- **A3a, one-off compiles.** The facade calls `adapted-compile`; the
  driver passes `generated` to it; `link-program` writes the plan's
  outputs into its working directory as `KEY.syntax` before compiling;
  `current-compiler` lists `src/snail/compiler`. The planner still uses
  the old closure, which works because the keys agree (A1). Development
  builds still go through `build-session` on the old expander. All test
  programs now compile through the new front end. Measure the gates.
- **A3b, sessions.** `Session` keeps texts; `build-session` over the
  adapter; `develop-program` and `Retained` unchanged in shape; the
  reuse assertions and `tests/artifacts/` updated and named.
- **A4, the planner.** `plan.sld` uses the integrator's producers and
  `discover-targets` through adapter functions that answer old Locs;
  `produce` writes outputs beside the printed producers; `Inputs`
  keeps only targets; the old `generated-syntax`, `producer-text` and
  `discover-artifacts` lose their last default-path callers. From here
  the printer may change, since no old key is compared on the default
  path, but the comparison of A1 would then have to go.
- **A5, the book.** compilers.md's tour and separate compilation,
  toolchain.md's sessions and status, passes.md's milestone A status and
  the integrator's description, AGENTS.md's live-reload figures; the
  PR's list of slower workflows.

## 9. Risks and open questions

1. **Checks only the old expander made.** If a milestone-A pass misses
   one, the old checker accepts the program and an `.err` fails (or
   worse, a program compiles that should not). Recommendation: A0's exit
   gate, "only the old fails" at 0, before A3a.
2. **Invariants the old checker took from the old expander.** Beyond
   `Program`'s shape: where `ScopedInstances` sit, `function?` and
   `captures?`, every signature's loc, the item order of instance methods
   and defaults. The earlier designs map these; A2's check comparison is
   what proves them, over every program.
3. **Spelling.** One function for old names, TypeId schemas included
   (section 2, Names). Recommendation: make declare's TypeId schema and
   the adapter's `old-name` call one spelling before A2.
4. **Host agreement.** Any table listed unsorted in the adapter or a new
   pass breaks `make bootstrap`'s Chibi check, possibly only on the
   compiler's own source. Recommendation: review every `table-keys` and
   table fold in A2's diff.
5. **Chibi time and heap.** Unmeasured for the new passes. If stage 1 on
   Chibi becomes too slow or exceeds 6 GB, the bootstrap fails, and
   stage 0 must run the same source, so there is no fallback but making
   the slow pass faster. Recommendation: measure in A3a first.
6. **The staleness list.** Section 6. A silent failure mode; add the
   entry in A3a.
7. **Producer keys.** Old and new printers must agree byte for byte
   until A4. A string with characters the old `string-literal` does not
   escape round-trips identically in both, so matching the old exactly
   is the rule, not fixing it.
8. **Assembly by text.** Section 5; an owner call whether comparing
   texts counts as reuse.
9. **The `compiled` count's meaning.** Changes for every client of the
   status JSON; only `project/build.sld` and `project/service.sld` read
   it in the tree (the IDE's pages were grepped, not read).
   Recommendation: keep the key, change the book.
10. **Problem order across libraries.** The integrator reports the
    earliest library's problem, as the old compiler does; the suites
    show no difference. A problem the old expander found late in its
    walk (an overlap) and `cohere` now finds per library could in
    principle reorder two libraries' problems. Recommendation: add a
    line to passes.md's known differences if a test ever shows it.
11. **Instances.** `cohere` sees the libraries before; the old checker,
    still running at A, sees the whole program and checks overlap again
    (dispatch design, risk 3). A program cohere accepts but the old
    checker refuses still fails, with the old message, so A is safe; B
    must settle it.
12. **Discovery cost.** `discover-targets` is a second expansion of the
    whole program per planned target with embedded targets, as the old
    discovery was; no change.
