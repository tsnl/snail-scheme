# Tutorials: the integration milestones

**Planned.** These are specifications for the three prototype PRs above the book
foundation. They are not runnable tutorials yet. First finish self-hosting and
the runtime ABI needed by build scripts; then build the prototypes in this order.

| Order | Project | Functionality it adds |
| --- | --- | --- |
| 1 | [Game](game.md) | Runtime-dispatched handlers, isolated frame jobs, retained resources, reload and supervision. |
| 2 | [Chat](chat.md) | Browser/native targets, typed S-expression connections, reducers and DOM views, discovery and streams. |
| 3 | [Tensor training](tensors.md) | Graph capture, typed IR, autodiff, GPU compilation, retained data and an interactive workbook. |

Each finished tutorial gets one webpage and ideally two or three complete source
files, including its `build.scm`. Show one included code block per file, with
explanations beside it. Separate reusable libraries from application policy.
Include exact run commands and expected output only after executing them.

The small host tests and the real integration profile serve different purposes.
A headless test does not prove a window works; a generated Wasm file does not
prove the UI ran in the browser; a toy tensor fixture does not prove MNIST trained
on a GPU. Missing hardware or capabilities remain explicit missing coverage.

## Requirements that need deliberate extensions

The basic demos exercise the platform's core model. Several earlier requirements
need more than those demos: chat's generated document tests reader staging;
the game needs separate GC-policy and allocation-bound cases; tensor training
needs a typed-kernel extension and external offsets beyond 4 GiB. The following
pages retain those requirements without making them prerequisites for the first
small runnable checkpoint.

Track implementation in the [TODO issue](https://github.com/tsnl/snail-scheme/issues/11).
