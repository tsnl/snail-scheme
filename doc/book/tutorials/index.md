# Examples

Game and chat explain the node model through state, artifacts, messages, and
lifetimes. The tensor tutorial provides a runnable CPU prototype with concrete
arrays, static typeclasses, symbolic graphs, and an interpreter. Use the
[runtime pages](../platforms/index.md) for supported operations and run commands.

| Example | What it explains |
| --- | --- |
| [Game](game.md) | Temporary frame nodes, retained resources, and replacing an artifact. |
| [Chat](chat.md) | Separate browser state, connections across runtimes, and shared history. |
| [Tensors](tensors.md) | One static operation interface for eager arrays and symbolic graphs. |

Each application uses an ordinary `build.scm`. Compiler and runtime libraries
supply reusable operations; application code defines its messages and
workflow/session rules. A build can share source between artifacts without
sharing the state of their running nodes.
