# Tutorials: the integration milestones

**Planned applications.** Build scripts and the Wasm command work today. These
tutorials specify the actor and GUI behavior still to implement. Start with a
small observable checkpoint in each application, then add the remaining checks.

| Order | Project | Functionality it adds |
| --- | --- | --- |
| 1 | [Game](game.md) | Runtime handlers, temporary frame actors, retained resources, and artifact reload. |
| 2 | [Chat](chat.md) | Browser/server actors, typed messages, DOM views, discovery, and streams. |
| 3 | [Tensor training](tensors.md) | Graph capture, typed IR, autodiff, GPU compilation, retained data and an interactive workbook. |

Each tutorial should have one page and two or three application source files,
including `build.scm`. Keep reusable compiler/runtime libraries separate from
application rules. Include each complete file once, with explanations beside it.
Add run commands and expected output after executing them.

Match each claim to its evidence:

| Claim | Required execution |
| --- | --- |
| Pure rules, codecs, or derivatives are correct for the fixture | Host tests against independent expected values |
| Actors and resources have the intended lifetimes | Headless startup, failure, and cleanup tests |
| A window, browser UI, or GPU workload works | The actual runtime and device |

Record missing hardware or capabilities as missing coverage.

## Requirements that need deliberate extensions

Later checks cover document generation in chat, collection controls and static
allocation bounds in the game, and typed kernels and storage beyond 4 GiB in
tensor training. Each needs its own example and evidence; the first small
checkpoint does not establish those guarantees.

Track implementation in the [TODO issue](https://github.com/tsnl/snail-scheme/issues/11).
