# Why Snail-Scheme?

Snail makes real world systems easier to describe in code.

An ordinary Scheme script builds **artifacts**: Wasm, JavaScript, shaders, or data.
**Runtimes** use those artifacts to run **nodes** with their own state and IO.
Nodes exchange **messages** over **connections**.

The distinction is simple: **spawn** creates a node from an artifact;
**connect** reaches a node that is already running. Runtimes handle the
serialization and communication together, so nodes in different runtimes use
the same connection abstraction. The [node chapter](nodes.md) explains each term
with a counter shared by two browsers.

## How to read this book

For the proposed language, start with [SFIR](sfir/index.md). Its chapters move
from examples and language rules to imports, library values and programmable
builds. They specify a design independently of the current compiler's syntax.

For the application model, read [nodes and runtimes](nodes.md),
[runtime contracts](runtime-contracts.md), and [build scripts](builds.md).
These chapters describe the existing Scheme APIs and the wider runtime design.
The [examples](tutorials/index.md) apply
these ideas to a game, chat, and tensor training. Game and chat use pseudocode; the tensor tutorial includes a runnable prototype.

Optional type annotations support checking, inference, and
[static typeclasses](typeclasses.md). User-defined overloads select checked
implementations from static types. Constrained generic functions specialize
before code generation. The [tensor tutorial](tutorials/tensors.md) uses this
interface to run one algorithm on concrete arrays or construct a symbolic graph.

The [runtime pages](platforms/index.md) document the implementations in this
checkout: the Wasm command and its Node.js host. They state which parts of
the model each runtime supports and provide commands you can run. Runtimes
without an implementation have stub pages. The [ABI](abi.md) explains local calls
and value ownership inside a running instance.

## Read and develop the book

From the checkout:

```sh
nix-shell
scripts/book serve --hostname 127.0.0.1 --port 8000
```

Open <http://127.0.0.1:8000>. mdBook
watches the sources and reloads changed pages. `scripts/book build` writes
`build/book/`; `MDBOOK` selects an installed mdBook executable.
[mdBook's serve documentation](https://rust-lang.github.io/mdBook/cli/serve.html)
describes the preview options.

Sources live in `doc/book/`. The ABI and command pages include WAT reference files whose
comments explain each function. Bodies marked `unreachable` are documentation
stubs, even where the corresponding runtime operation is implemented.
