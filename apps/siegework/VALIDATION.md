# Playable prototype validation

Verified on 2026-10-16 against compiler base `0f5fd391`. The simulation and shader
source checkpoint is `228076e5`; the packaged artifact generation is
`1d46c0ecf3d3af647b07f42f`. Host/runtime follow-up checks live beside this record.
These are correctness checks, with no performance or hardware-GPU claims.

| Environment | Observed |
| --- | --- |
| Compiler host | Chibi 0.12.0, Binaryen 132 |
| Authority/runtime | Node 24.19.0, generated WasmGC, private `snail.reducer` scalar provider |
| Browser | Chromium 152.0.7977.82, `http://127.0.0.1:4173`, two independent sessions |
| GPU | Real WebGPU using Google's SwiftShader software Vulkan adapter |

`scripts/test-applications` builds the real game and small fixtures. The runtime
checks cover shared Scheme/Lofi APIs, retained immutable snapshots, automatic
hauling, pure view, declarative client effects, compatible reload with changed
behavior, hostile candidates and views, rejection of invalid encoded states,
startup checks before publication, rollback after staged writes/effects,
ordered submissions, contested purchases, durable failure, SQLite restart/retry,
and deterministic losing and winning runs. Compile-negative fixtures reject a
wrong state result, wrong payload and command from the wrong application owner.

The suite has 15 runtime checks and three compile-negative cases. The
[browser runner](../../tests/applications/README.md) verifies actual GPU
pixels, independent shader candidate validation, two-client purchases and
convergence, stale snapshot rejection, combat and cargo in transit, changed Wasm
behavior after reload, exact pending-request preservation, and continued
rendering after invalid WGSL or an
incompatible schema. A Chromium window on an isolated Xvfb display was also
visually inspected. The headless compositor's screenshot is not used as evidence
of GPU rendering; GPU texture readback is.

Formatting, changed Markdown links, `git diff --check`, and the mdBook build pass.
The parent PR owns compiler/backend validation; this app does not repeat the
performance suite or change the compiler implementation.

Two independent Luna builders started from public libraries, documentation and
the game contract at `228076e5`, without reading the reference implementation.
Their experimental apps remain on local branches rather than becoming extra
reference games in this PR:

| Experiment | Local commit | Observed result |
| --- | --- | --- |
| `experiment/siegework-newcomer-a-20261016` | `0ce891a3` | App-local build, Scheme victory/loss/reset and upgrade income, two clients, real WebGPU pixels, changed module replacement with identical world/client snapshots. |
| `experiment/siegework-newcomer-b-20261016` | `c375d62d` | App-local build, Scheme extractor income/artillery/victory/reset, two clients, real WebGPU pixels and reconnect to the retained match. |

Each experiment records commands and failures in its app's `NEWCOMER.md`. The
feedback exposed missing import guidance, `I64` vector indices versus `I32`
snapshot words, the limited arithmetic surface, constructor-name collisions,
owner/handler settings wiring and unlinked browser flags. The chapter now covers
those boundaries and includes a runnable immutable-state codec. A mismatched
codec length also motivated the executable packaging preflight and a regression
that rejects invalid encoded replacements before durability. These small
experiments test usability; they do not establish full Scheme conformance or
replace the reference game's integration checks. One builder used the shared
replacement API manually after a server restart; automatic polling during live
combat is covered by the reference browser runner.

The scope remains one local authority, bounded scalar snapshot copying, a small
shader vocabulary and the current typed Scheme subset. There is no automatic
schema migration, durable external-effect outbox, distributed writer protocol,
GPU device recovery or model checker. Host JavaScript/HTML/CSS changes require a
restart; Scheme modules and shader pipelines have the state-preserving path.
