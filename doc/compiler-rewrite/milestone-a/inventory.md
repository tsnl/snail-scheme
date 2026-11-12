# Milestone A: seam inventory

Read at HEAD ed2ff3fc, with the worktree's uncommitted declare edits
present but not relied on. Line numbers are HEAD's. "Reads" means the
code was read; anything else is marked as inferred.

Everything below consumes what the old expander produces
(`ExpandedProgram`, `Expanded`, `LinkedFile`, `ArtifactUse`, `Reached`)
or the old input protocol (`Inputs`, the `generate` callback, the
`compile` effect's `need`, `request.datum`). Nothing downstream of the
old expander reads more than `(::program expansion)` plus the links and
the per-library keys: the old checker reads only `Program`
(core.sld 1141: values, types, classes, instances, effects, metadata,
items, libraries), and `metadata` is read only by expand.sld's own test
(expand.sld 4763-4783), so the adapter may leave it empty.

## The old compiler's own seams

| Where | What | Uses of the old expander or protocol |
| --- | --- | --- |
| `src/snail/shell/compiler.sld` 40-88 | the facade: `source->expanded`, `source->wat`, `source->modules`, `source->schemas`; `WholeProgram(text links)` | `expand-program directories generate inputs source empty-expansion`; `program-links`; `check-program (::program expanded)`; `wire-schemas (::program typed)` |
| `src/snail/shell/compiler/session.sld` 36-195 | `Compiled(key items schemes emission)`, `Session(directories expansion compiled)`, `Built(name text compiled? links)`, `build-session` | `expand-program ... (::expansion session)` as predecessor; `library-items`/`program-items`; `library-key expansion name` as the reuse key; `library-links expansion name`; `control-modules` compares with the previous expansion's control effects |
| `src/snail/shell/compiler/driver.sld` 25-89 | `compile-command-line`, modes `wat`, `modules`, `schema`; `links.datum` | `generate` = `generated-syntax generated directories loading forms`; on `Requested` writes `request.datum` (`publish-request`) and panics, status 1 |
| `src/snail/shell/compiler/inputs.sld` | `Inputs(artifacts generated)`, `supply-artifact`, `supply-generated` 62, `producer-text` 73, `producer-key` 77, `generated-output` 86, `request-input`, `parse-request` 120 (grammar: exactly one `(generate "KEY")` or `(artifact "name" "file" line col)`), `generated-syntax` 163, `print-producer` 174, `printed-producer-text` 180, `generating-stack`, `read-source-file` | the whole producer and request protocol |
| `src/snail/shell/compiler/read.sld` | `compile` effect (`fail`, `need`), `Stop = Failed | Requested`, `compiling`, `decode-syntax` 771 | `need` is performed only by `request-input`; `decode-syntax` reads a producer's output |
| `src/snail/shell/compiler/expand.sld` | `ExpandedProgram`, `expand-program`, `discover-artifacts` 1165, `library-closure`, `program-imports`, replay and build-key sections | the producer of all of it; stays until milestone D |

## Callers outside the compiler

| Where | What it uses |
| --- | --- |
| `src/snail/shell/project/plan.sld` 33-47 | imports `Inputs producer-text producer-key generated-output print-producer generating-stack read-source-file` and `ArtifactUse discover-artifacts program-imports Reached library-closure`. `reached-producers` 351 walks the old closure and keys each producer by `producer-key (producer-text directories forms)`; `supplied?` 371; `embedded-targets` 384 runs `discover-artifacts`, a whole old expansion with no target supplied; `used-target` raises "artifact target must be a browser build: NAME" and "unknown project build target NAME" |
| `src/snail/shell/project/build.sld` | `compiled` 122 turns `Requested` into "internal error: the build plan did not supply the input ..."; `Retained` 257 holds a `Session`; `supply-embedded` 420 calls `supply-artifact`; `link-program` 624 calls `source->wat` with `generated-syntax working ...`; `develop-program` 712 calls `build-session`; `assemble-modules` 767 reuses assembled bytes when `compiled?` is false; `produce` 867 runs the producer on Node; `supply-producer` 900 recomputes `printed-producer-text` and checks its key |
| `host/chibi/compile.scm` | stage 0's entry: `compile-command-line` |
| `bootstrap/compile.sld` | the compiled compiler's entry: `compile-command-line` |
| `host/chibi/snail/stage0/build.sld` | `run-compiler-into` 210 loops on `request.datum`; `published-request` 230 uses the old `parse-request`; `provide-input!` 236 runs `produce!` for `GenerateInput` and raises "LOC: artifact-bundle requires a project build resolver: NAME" for `ArtifactInput`; `produce!` 264 compiles `GENERATED/KEY.sld` and runs it with `GENERATED/KEY.syntax`; `current-compiler` 351 lists the compiler's sources for staleness and does not list `src/snail/compiler` |

## Tests that touch a seam

| Where | What |
| --- | --- |
| `tests/run.scm` 80-90 | runs `test-inputs`, `test-expand`, `test-session`, `test-plan` of the old tree on Chibi |
| `src/snail/shell/compiler/session.sld` 215-404 | `test-session`: warm against cold, compiled names, unchanged builds, artifact inputs; asserts reuse |
| `tests/artifacts/compiler.sld` | a Wasm compiler fixture with its own `generate` callback and `supply-artifact` inputs; `source->wat`, then `build-session` twice |
| `tests/artifacts/check.mjs` 39-40 | `unchanged/compiled` is empty; `changed/compiled` is `generated.assets main sample.consumer sample.generic` |
| `tests/project-development.mjs` 114, 123, 138 | `compiled` is 0 for unchanged, renamed public paths, and a repaired consumer |
| `tests/project-attempts.mjs` 99 | every target `compiled === 0` on a manual rebuild |
| `tests/development-runs.mjs` 69, 119 | `compiled === 0`, `compiled` 0 |
| `tests/project-reload.mjs` 72 | `compiled` 2 after editing a string in the application ("only the application and its entry need new instance symbols") |
| `tests/project-resources.mjs` 106 | `compiled` 2 after editing a linked file's bytes |
| `tests/project-http.mjs` 53, 57 | the JSON keys include `compiled`; `compiled > 0` on the first build |
| `tests/compare-compiler.sld`, `src/snail/compiler/adapter/{load,expansion,outline}.sld` | the comparisons; call the old `expand-program`, `library-file`, `library-closure`, `program-imports` |

## Test programs on the generated, target and linked-file paths

- tests/programs: `generated`, `generated-syntax`, `error-generated-cycle`
  ("library import cycle through sample.knot"), `link-file`,
  `error-link-file-missing`, `error-link-file-escape`,
  `error-resource-constructor`, `artifact-literal` ("artifact-bundle
  expects a literal target name"), `artifact-no-resolver`
  ("artifact-bundle requires a project build resolver: client", raised by
  stage 0, not the compiler), `wire`, `wire-mismatch`,
  `deriving-libraries`; libraries `tests/programs/lib/sample/{table,blob,
  linked,knot}.sld` and several under `lib/legacy`.
- `tests/artifacts/` (fixture, `lib/generated`), `tests/project-artifacts.mjs`,
  `tests/project-resources.mjs`, `tests/project-bundles.mjs` (Hearsay's
  producers), `apps/hearsay/tests/screens.sld` (reaches a generated
  library).
- `make compare-compiler` (declare-s3 run): 454 programs load, 440
  completely, 12 up to a generated library, 2 failed; 14 not compared,
  so the generated programs are judged only by `make test`.

## The 25 programs only the old compiler refuses (declare-s3 run)

Each must be refused by a milestone-A pass before the new path is the
default, since the old checker does not make these checks (the old
expander does).

- Overlap, for `cohere`: error-overlap, error-associated-overlap,
  error-binary-family-overlap, error-class-row-overlap,
  error-instance-set-overlap, error-instance-set-nested.
- `dispatch` and `dynamic-instances`, for `dispatch`:
  error-dynamic-instance-{any,duplicate,empty,nested,result},
  error-binary-domain, error-binary-source-inactive.
- Lifecycle, rows and owned types, for `declare` (in progress; the
  worktree has `declare/owned.sld` and `determination.sld` appearing):
  error-class-row-arity, error-class-row-usage, error-clone-requires-class,
  error-drop-control, error-drop-foreign, error-drop-open-row,
  error-drop-requires-class, error-drop-requires-row, error-dyn-cast-drop,
  error-instance-set-lifecycle, error-drop-match, error-replace-owned.
