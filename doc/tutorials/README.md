# Programs that define the platform

These three projects are Snail-Scheme's intended integration tests and teaching
examples. They test the design in [Why Snail-Scheme?](../why-snail-scheme.md).
**This directory currently contains specifications only: no runnable actor
examples, test harnesses, or implemented APIs are claimed.**

| Project | Follow the program | Acceptance criteria |
| --- | --- | --- |
| Game | [A game that reloads while you play](01-game/README.md): pure rules, host handlers, frame actors, retained resources, reload. | [G01–G07](01-game/requirements.md) |
| Chat | [A chat application in two places](02-chat/README.md): types, reducer/view, browser/server, discovery, streams, literate publishing. | [C01–C07](02-chat/requirements.md) |
| Tensors | [A graph that learns handwritten digits](03-tensors/README.md): reference math, capture, autodiff, GPU dispatch, training, workbook. | [T01–T09](03-tensors/requirements.md) |

## How to turn these into tutorials

Resin's current
[tutorial guide](https://github.com/tsnl/resin/blob/7a19915229414242bad5ecd7763299532610a02b/doc/tutorials.md)
uses complete programs with explanations beside the code, included directly into
the book. Its
[Mandelbrot program](https://github.com/tsnl/resin/blob/7a19915229414242bad5ecd7763299532610a02b/examples/eg011_mandelbrot.resin)
moves from the numerical rule through resources to interaction, with CPU
checkpoints before a GPU/window is required. Adopt that source-led progression.

Once implementation begins, each folder should gain a runnable project, small
fixtures, and checks tied to its requirement IDs. Put the explanation beside the
tested code and include it into the tutorial; avoid a second copy that can drift.
Start each checkpoint with what the user should observe, then explain the data,
functions, ownership, and effects that produce it. Show reusable libraries and
application code separately. Include exact commands and expected output only
after they have been run and verified.

Each finished project needs a build/export entry, declared dependencies, source
origins, a deterministic small test profile, and a real integration profile. Build
completion alone is not success: windows must receive events, browsers must run
WASM handlers, and a GPU must execute training. An unavailable integration profile
must be reported honestly. No implementation is part of this documentation change.

## Requirements coverage

The original discussion's R01–R37 IDs are retained below. R23 and R27 explicitly
reflect the later decisions about actor state and connection-defined invocations;
the older fire-and-forget/fresh-invocation semantics are not current requirements.
R38–R44 record subsequent refinements. Each row identifies the mechanism and the
project that must make it observable, not a claim that the feature exists today.

| ID | Requirement and mechanism | Tutorial evidence |
| --- | --- | --- |
| R01 | Documents, workbooks, and websites share ordinary functional views with interactive apps. | C02 static/live views, C07 literate publishing, T06 training workbook. |
| R02 | Structural markup with Scheme literals/functions reuses parser and located-syntax facilities where suitable. | C07 reader/document extension. |
| R03 | Explicit wrapper/source paths select readers; no `#lang`, registry, or extension dispatch. | C07 wrapper and dependency cases. |
| R04 | `generate-library` has one generator `begin`, generator imports, separate generated imports, and generated exports. | C07 generated guide library. |
| R05 | Stages, generalized transformers, hygiene, locations, and dependencies preserve meaning without prematurely executing embedded code. | C07 generation checks; T02/T07 capture and artifact boundaries. Transformer machinery is still required separately. |
| R06 | Ordinary Scheme authoring precedes a custom reader. | C02 functional view before C07 markup; G02 pure rules. |
| R07 | Elements, fragments, and functional components form a generic tree API with simple names. | C02 renderer-independent composition; T06 workbook reuse. |
| R08 | Reducers and explicit model/message values replace hidden hook state. | C02/C03 browser reducer; T06 control view. |
| R09 | Use Chibi now and keep application/library code separately readable. | Existing [UI walkthrough](../ui.md); G02, C02, and T01 host checkpoints. No early self-hosting requirement. |
| R10 | HTML/DOM is the first document/UI backend. | C02/C03 browser rendering and focus retention. |
| R11 | Browser Scheme runs through Snail's WASM output. | C03 two actual clients; T06 workbook. WASI and server rendering do not satisfy it. |
| R12 | One authoring source can produce server/browser/GPU payloads with explicit crossings. | C03 roots in one source; T07 graph/coordinator/browser outputs. |
| R13 | A typed Scheme shader dialect can produce statically validated GPU code without being a Scheme-callable procedure. | T08 kernel extension; T02 typed graph IR. |
| R14 | Preserve Resin's host/shader layout ideas and explore its older tensor/autodiff designs. | T08 packing; T01–T05 graph capture through training, with inspected Resin references. |
| R15 | Named configurable targets produce code and supporting artifacts. | G01 root definition, C03/C04 native and WASM, T07 GPU artifacts. |
| R16 | Vendored libraries export composable multi-target applications. | C04 consumer project; T07 backend/configuration selection. |
| R17 | Readers, compilers, and builders are ordinary libraries; local calls need no actor boundary. | C07 reader library; T02/T07 graph compiler. |
| R18 | Expansion, build evaluation, and shipped execution remain distinct and can recur. | C07 deferred document expressions; T02 capture vs T04/T05 dispatch. |
| R19 | A build interpreter loads a Scheme artifact and invokes a single-shot `build` actor. | G01/C04/T07 build lifecycle and completed output manifests. |
| R20 | Native hosting owns startup, dispatch, IO, and scheduling; Scheme exports handlers. | G01 window callbacks; C03 browser/server hosting. |
| R21 | Rust/native providers and user-written adapters support local, distributed, and serverless deployment. | G04 window/GPU providers, C04 deployment bindings, T04 device provider. No cloud vendor is mandatory. |
| R22 | Runtime control and program behavior use the same actor/connection model with artifacts and effects. | G01/G03 runtime spawn/supervision; C04 service/runtime bindings; T07 build dispatch. |
| R23 | Prefer stateless functional compute and explicit state ownership; globals now live for their actor's lifetime. | G02/G03 pure ephemeral frames; C03 per-instance connection globals; C05 retained native history. |
| R24 | Runtime/library functions expose deliberate retained state services; Scheme stateful actors remain possible. | G04 native world/renderer, C04/C06 database ownership. Mocks do not establish production service guarantees. |
| R25 | Calls progress asynchronously across threads/machines without shared Scheme heaps or an actor-wide waiting lock. | G03 input during a pending frame; C05 slow subscriber isolation; T06 controls during dispatch. |
| R26 | Subordinates have explicit supervision, failure, cancellation, budgets, and restart behavior. | G06 child failures; C06 worker/session ownership. |
| R27 | Connected invocations may return values, futures, or streams; the protocol owns delivery/uncertainty semantics. | G03 frame future, C01/C05 value and stream protocols, C06 endpoint failure. This replaces the earlier universal fire-and-forget rule. |
| R28 | Typed records/variants and method signatures derive schemas/codecs; no duplicate schema definition. | C01 all wire values; T08 shared layout definitions. |
| R29 | S-expression encode/decode at every actor boundary, even local; never transfer a Scheme pointer or evaluate received forms. | C01 transport tests; G04/T04 native commands. |
| R30 | Explicit shared resource references have namespaces, access, lifetime, and versions. | G04 texture/world references, C04 service identity, T09 external/device validation. |
| R31 | Retain GPU buffers/textures/frames; exchange small commands rather than bulk serialization. | G04 renderer ownership; T04 device-resident parameters. |
| R32 | 32-bit Scheme heaps and external data with explicit u64 ranges and binary copying. | G03 bounded heaps; T09 ranges beyond 4 GiB. MNIST alone is insufficient coverage. |
| R33 | Microprocess/isolate lifetimes reclaim bounded temporary heaps wholesale. | G03 frame retirement; T06 bounded step ownership. |
| R34 | Spawn chooses heap/GC policy, debug traps, and explicitly permitted release recovery. | G06 every policy, safepoints, supervision, and queue budgets. |
| R35 | Eventually prove allocation bounds for supported computations with stated inputs/callee costs. | G07 research extension. Dynamic budget checks are an earlier milestone, not proof. |
| R36 | Rebuild shared-source dependencies, validate artifacts, pin in-flight versions, and migrate retained state explicitly. | G05 live rule edits; C06 browser/server compatibility; T06 step replacement. |
| R37 | Pub/sub provides independent recipients; worker sharing within one subscription is a separate policy. | C05 per-browser streams, ordering/replay, and bounded queues. Not every connection is a topic. |
| R38 | Spawning and connecting are separate; pass recipient/service bindings at spawn, with no supervisor-only communication restriction. | G03 frame connection; C04 existing remote service and session creation. |
| R39 | Actors own heaps/globals/resources; connection endpoints own pending exchanges and cleanup. | G03/G04 lifetime table; C06 close/failure cases; T06 cancellation. |
| R40 | Exposed top-level functions and typed signatures define methods; runtime spawns the root actor definition. | G01 root callbacks; C01/C03 method interfaces. No mandatory new class or entry-loop form. |
| R41 | CPS/scheduler handoff should support suspension and closure tasks without choosing an async function color or global pool now. | G03/C06/T06 concurrent progress. Exact `task-run`, `call/cc`, one-shot/multi-shot, and copy-on-write behavior remain later design work. |
| R42 | Build evaluation composes service dependencies/discovery; runtime resolves instances and credentials. | C04 manifest vs live bindings; T07 vendored build configuration. |
| R43 | GPU programming includes graph capture, autodiff, and actual MNIST training, not only shader notation. | T01–T07 numerical checks, device execution, and interactive checkpoint control. |
| R44 | A coherent distributed/heterogeneous platform is demonstrated through tutorial projects that become integration tests. | All three real integration profiles; this suite's source-led teaching and explicit completion criteria. |

## What the examples leave open

There is a home for every requested use case, but the basic demos alone do not
exercise all of them. **C07, G07, and T08 are deliberate extensions** for readers,
allocation proofs, and custom typed kernels. T09 deliberately adds a large-range
storage case because MNIST's size cannot establish 64-bit external addressing.

The extensions specify clients and acceptance evidence for language features;
they do not settle their implementation. The markup grammar, generalized syntax
transformer API, field/union annotation syntax, scheduler/continuation machinery,
first GPU backend, and allocation proof method still need focused design. The
first playable game or working chat should not wait for all of that research.

Track implementation and PRs in the repository's
[TODO issue](https://github.com/tsnl/snail-scheme/issues/11), not a second `TODO.md`.
These requirements belong beside the eventual programs so tests and explanations
can evolve together.
