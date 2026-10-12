# Model examples

These examples explain the node model through three applications. They describe
state, artifacts, messages, and lifetimes; they are not executable tutorials.
Use the [runtime pages](../platforms/index.md) for supported operations and run
commands.

| Example | What it explains |
| --- | --- |
| [Game](game.md) | Temporary frame nodes, retained resources, and replacing an artifact. |
| [Chat](chat.md) | Separate browser state, connections across runtimes, and shared history. |
| [Tensor training](tensors.md) | Building domain-specific artifacts and running them with retained data. |

Each application uses an ordinary `build.scm`. Compiler and runtime libraries
supply reusable operations; application code defines its messages and
workflow/session rules. A build can share source between artifacts without
sharing the state of their running nodes.
