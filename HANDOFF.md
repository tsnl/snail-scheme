# Snail-scheme handoff, 2026-10-22

What landed, what comes next, and how to work in the repository. The in-repo
homes for this material are the book's roadmap, `doc/book/roadmap.md` (open
work), and the runtime and graphics plan, `doc/book/graphics/plan.md` (the
design of the next milestones); this page points into them rather than
replacing them. Paths below are relative to the repository unless absolute.

## Where things stand

`origin/main` is at `34eef43c`. The local main checkout in
`~/Developer/snail-scheme` is still at `358ab270`: run `git pull` there first.

Landed on 2026-10-22:

| PRs | What |
| --- | --- |
| #367, #377 | Live reload; one library at a time, relinked live; the toolchain in a browser. |
| Stack #391: #386, #390, #379–#383 | Roadmap in the book and the runtime plan; pinned tools (npins, Node 26, podman devcontainer); byte literals and `generate-library` as syntax; textured sprites and 2D; Hearsay's design, prototypes, LPC art, faces, map and guides. |
| #394 | `make fetch` for the Rust crates; a podman Devcontainer workflow in CI. |
| Stack #393: #392, #388, #385 | Private build directories and `build/lock`; structural `Any` TypeIds and `type-test`; the expander without mutation; the browser IDE. |
| #327 | `doc/getting-started.md`, rewritten for the current toolchain. |
| #396 | Simplification of all of the above: one loader (`src/app/load.mjs`), one build key, one Tarjan and one FNV in core, retention decided by the dev loop, one home per documented topic, `rust-toolchain.toml` as the only Rust pin. |

Still open on GitHub:

- **#384**, njayinthehouse's Siegework PR (enemy AI, workers, portals,
  walls). Not under tsnl; needs a review and probably a rebase onto
  today's main.
- **#325**, the Ott/Rocq formation-proof draft. Intentionally left as a draft.
- **Issue #378** tracks the Hearsay PRs, all merged; it can be closed.

## Next: the runtime and graphics rewrite

Six milestones in `doc/book/graphics/plan.md`; the first (tools) is done.
Each milestone is its own PR, linked into a GitHub stack and merged
atomically once CI is green (see "Landing" below).

### 1. Runtime: an application loop on JSPI (milestone 2)

The application runs its own loop and calls the host; the host calls one
export. Still drawn with today's renderer. Decisions already made with the
user:

- **`reset` returns a binder.** `define-application` gains `(reset reset)`;
  `reset` returns `(lambda (run) ...)` that installs handlers around whatever
  the runtime runs: the loop, a test, or the next run after a reload.
  Message handlers never call one another; only the runtime does. The
  effect row is quantified on `reset` itself, so no higher-rank type.
- **`app_main`.** `define-application` generates `app-main : (Option Any)
  -> (Option Any) ! events storage webgpu`, exported as `app_main`. It runs
  `((reset) (lambda () (run (boot handover))))`.
- **`boot`** adopts a handed-over state with `type-test` (on main since
  #392), else restores the last save (`load-save`, suspending on
  IndexedDB), else calls `init`; it reports `Adopted`, `Restored` or `Fresh`
  to the host through an import, so a reload can say whether the game
  survived.
- **A state cell.** The loop calls `remember!` with each state; `app_state`,
  a plain export, returns the cell as an `Any`. After a trap the instance
  survives, so the host reads the state from before the trapping event and
  hands it to the program the fix builds.
- **Events.** `next-event` drains the host's queue through `poll-event`, a
  plain import, and suspends through `wait-event` only when the queue is
  empty: V8 does not fast-path a suspending import that returns at once
  (measured: ~85 ns suspending, ~115 ns for a plain return through JSPI,
  ~10 ns for a plain import). Events: `Frame elapsed`, `Input`, `Hidden`
  (save, continue) and `Reload` (save, return the state as `Some Any`).
- **The host.** `WebAssembly.promising(instance.exports.app_main)`;
  suspending imports wrapped in `WebAssembly.Suspending` (`wait-event`,
  `load-save`, `store-save`, later `request-device`, `map-read`,
  `create-render-pipeline-async`, `on-submitted-work-done`,
  `decode-image`). DOM listeners push into a queue that coalesces pointer
  moves and resizes, holds at most one pending frame, and requests the next
  animation frame only after the loop takes the last one. The HTML HUD is
  driven from the loop.
- **Hot reload.** The host pushes `Reload`; the loop saves and returns its
  state; with no Lofi frames on the stack, the host relinks with
  `relinkProgram` (`src/app/load.mjs`) and calls the new `app_main` with
  the handover. No suspended stack is ever abandoned.
- **Invariants to keep beside the code:** (1) the host calls only
  `app_main`, and `app_state` after a trap; everything else arrives as an
  event. (2) Only Lofi code calls suspending imports, never a Rust service:
  Rust's shadow stack lives in linear memory, which JSPI does not switch.
  (3) Host imports are leaves: no Wasm function is handed to a JavaScript
  API that calls back, since a JS frame between the entry and a suspension
  makes suspension fail.
- **Headless.** Node 26 enables JSPI by default (Node 22 has neither JSPI nor
  stack switching). `shell.nix` and CI already use Node 26. Alternatively
  handle `events` in Lofi with scripted events.

Starting points on main:

- `lib/lofi/app.sld`: `define-application`, today's `app_state`/`app_adopt`
  (adopt returns 0 when adopted, 1 on a mismatch, via `type-test`).
- `src/app/host.mjs`: `startApplication`, `screenImports`, `takeState`,
  `relinkAll`, `saveAll`; `src/app/load.mjs`: `createWasi`, `instantiate`,
  `linkProgram`, `relinkProgram`, `commandImports`, `readEvent`;
  `src/app/hud.mjs`, `storage.mjs`, `reload.sld`, `reload-client.mjs`.
- Users to port: `apps/siegework`, `apps/hearsay`, `tests/apps/counter`.
- Tests to port: `tests/develop.mjs` (relinks and checks adoption),
  `apps/siegework/tests/headless.mjs`, `tests/browser/reload.mjs` and
  `ide.mjs`, and the IDE preview (`src/ide/preview.mjs`).
- Docs to update when it lands: `doc/book/lofi/applications.md` (via the
  anchored section in `doc/language.md`), `doc/toolchain.md` section 4,
  TOUR.md's `src/app` row, AGENTS.md's live-reload section, and the plan's
  status line and milestone list.

### 2. `ctl` operations on JSPI (milestone 3)

- Operations are `fun` (default; a direct call, as today) or `ctl` (the
  handler receives `resume`, callable once, later, or never; a second call
  traps).
- A `handle` with `ctl` operations runs its body on its own stack through a
  host trampoline. Performing is a suspending import that sets the body's
  stack aside; `resume` settles the body's promise, then suspends the
  handler until the body performs again or returns. An operation the
  innermost handler does not handle is forwarded from its stack.
- Handler stacks are global variables in `src/lofi/compiler/wasm.sld`
  (`handler.E.current`, one per effect), so each switch saves and restores
  them with the stack they belong to.
- Cost: ~300 ns per perform/resume on JSPI (45 ns with native stack
  switching), so `ctl` is for coarse operations: events, readbacks,
  asynchronous GPU work, a few coroutines.
- Later (a roadmap item): move to native stack switching. Chrome 156 has it
  behind `--js-flags=--wasm-wasmfx`; Binaryen 132 accepts
  `--enable-stack-switching`. No build flag in the meantime.

### 3. WebGPU through an effect (milestone 4)

- A procedural `gpu` effect mirroring WebGPU's operations and descriptors
  (op list in the plan): handlers can trace, record for tests, validate
  handles, capture a frame, or decode compressed textures.
- Long-lived objects created by resource path, returning the existing
  object for the same path and descriptor, so a reloaded module reattaches.
  Lifetimes follow scope (run vs frame); per-frame marking, an LRU pool
  evicted only past the memory budget, a panic with a report when marked
  objects alone exceed it; handles carry generations.
- Device baseline: `texture-compression-bc`, `shader-f16`,
  `indirect-first-instance`, `float32-filterable`,
  `rg11b10ufloat-renderable` (`timestamp-query` when present); raised
  buffer and texture limits; 64 bytes of color attachments per sample.
- A recording handler for headless tests.

### 4 and 5. The `graphics` libraries (milestones 5 and 6)

- 2D: `(graphics pod)` (`deriving Pod`: WGSL layout, packer, declaration),
  `(graphics wgsl)` (shaders as S-expressions, printed to WGSL by recipes;
  embedded WGSL is acceptable), `(graphics atlas)`, `(graphics quad)`
  (world units, pixel snapping in the vertex shader). Port Hearsay.
- 3D: `(graphics mesh)`, `(graphics raster)` (deferred G-buffer),
  `(graphics passes)`. Port Siegework and delete `src/app/renderer.mjs`.
- User decisions: rasterize only (path tracing later, see
  `doc/book/graphics/path-tracing.md`); uncompressed texture heaps first,
  BC required at the device level; fix atlas sampling (gutters, half-texel
  insets, `textureSampleGrad`); `update` stays total, prefetching happens
  from `view`; images decoded by the browser behind `decode-image`.

## Other open work

All tracked in the roadmap unless noted.

- **The dev loop cannot build `generate-library` recipes**, so `lofi serve`,
  `lofi watch` and the IDE cannot build Hearsay; use `make site`.
- **Hosts disagree on emitted text.** The backend numbers closures, strings
  and lambdas while evaluating call arguments, which Chibi evaluates right
  to left; Chibi's character classes accept Unicode where Lofi's accept
  ASCII. `make bootstrap` compares only the Wasm stages, so it misses both.
- **Hearsay** is unpublished: its LPC art needs credits the page doesn't
  show (`lib/lpc/ATTRIBUTION.md`). The third prototype waits until the first
  two hold up.
- **Siegework water routes** (not in the roadmap; deferred by the user on
  2026-10-21 for 2026-10-22): let enemies float over water, so water only
  stops building, Ice merges into Water, the `mainland` mask and siege's
  across-water checks go away, and passes cut only rock. Re-measure route
  lengths (archipelago fronts reached 104 steps); it changes every map, so
  its own PR with regenerated goldens.
- IDE items (inlaid previews, semantic highlighting, a language server,
  undo per buffer) and the build cache on disk.

## How to work here

- **Tools:** `source ~/.local/lofi-tools/env.sh` (Chibi, Binaryen, Rust).
  Chromium for browser tests:
  `CHROMIUM=~/.cache/ms-playwright/chromium-1248/chrome-linux64/chrome`.
  mdBook: `make pages MDBOOK=~/.local/lofi-tools/mdbook-0.5.4/mdbook`.
  `make fetch` once per checkout. Docker works locally; podman is not
  installed (CI uses podman for the devcontainer).
- **Checks:** `make test`, `make check` (needs `nixfmt`, absent locally;
  CI runs it), `cargo test` and `cargo fmt --check` for `src/runtime` and
  `src/assembler`; compiler changes also `make test-chibi` and
  `make bootstrap`; browser and IDE changes `make test-browser` and a look
  through `node tests/browser/page.mjs URL SCREENSHOT`.
- **Commits:** author and committer `nikhil.idiculla@gmail.com` (Nikhil
  Idiculla), e.g. `git -c user.email=nikhil.idiculla@gmail.com -c
  "user.name=Nikhil Idiculla" commit`. No Claude or AI attribution in
  commits or PRs, and no "claude" anywhere in messages. Titles are plain
  imperative sentences; bodies say why.
- **Branches:** rebase onto `origin/main` and force-push with lease; never
  merge main into a PR branch.
- **Landing:** link PRs with `gh stack link A B C` (bottom to top); once
  every "Complete correctness checks" is green, `gh pr ready` each and run
  `gh stack merge N --yes --squash`. Single PRs:
  `gh pr merge N --squash --author-email nikhil.idiculla@gmail.com`.
  Main's rules: that CI check is required (tsnl may bypass), and only tsnl
  may force-push. Anyone with write access may merge.
- **Style:** AGENTS.md (CLAUDE.md is a symlink to it). Use the pinned
  simplify skill (`.agents/skills/simplify`, lossy and top-down) on new
  modules before landing.
- **Pitfalls:** run Chibi with `-h` before `-D` (the Makefile does);
  `map` and `for-each` order is unspecified on Chibi; each compile works in
  a private directory under `build/lofi-run/`, so generated libraries are
  produced again on every compile; `lofi serve` serves every file in
  `src/app` and keeps only the last two builds' modules.

## Local cleanup

These worktrees hold merged or superseded work and can be removed with
`git worktree remove`:

- `~/Developer/snail-scheme-{bytes,sprites,hearsay-design,lpc,hearsay,roadmap,tools,start}`
- `~/Developer/snail-simplify{,-compiler,-devloop,-docs,-games}`
- `/tmp/lofi-{adopt,expander,ide,assembler,hot-reload,notebook,toolchain-design,verify}`,
  left by the other session (its branches have merged or were superseded).

Backup branches `backup/pre-stack/*`, `backup/pre-restack/*`,
`backup/pre-land/*`, `backup/pre-rewrite/*` and
`backup/hearsay-pre-split-20261021` can go once nothing more is needed
from them. The devcontainer images `snail-dev` and `snail-dev-docs` are
local Docker leftovers.
