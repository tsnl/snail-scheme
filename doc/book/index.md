# Why Snail-Scheme?

Snail-Scheme is a Scheme compiler and a platform in development for distributed,
heterogeneous computation. Compilers are libraries. A Scheme program can build
other programs, compose their dependencies, and select where the artifacts go.
The same approach should serve a document, an interactive application, or a
computation spread across CPUs and GPUs.

**Actors are the key programming model we are working toward.** An actor owns an
isolated heap, globals, and resources; its exported Scheme procedures are message
handlers. A platform starts it and dispatches messages. Spawning establishes
lifetime ownership, while connecting establishes communication with a particular
recipient. Connections serialize S-expressions, including between local actors.
Native runtime services own retained resources such as files and GPU buffers.

Prefer pure functions and short-lived actors for computation, with long-lived
state in explicit services. A frame actor can finish its work and release its
entire temporary heap. A connection may produce a value, future, or stream;
closing it and retiring an actor are different operations. These are design
requirements, not claims about the current scheduler or collector.

## What runs today

The compiler runs in Chibi. It emits WasmGC, links the Rust runtime, and executes
the result under Node/V8 with WASI. Scheme build scripts choose inputs, output
paths, and execution. The book documents this [build workflow](builds.md) and the
implemented [Node platform](platforms/node.md).

The [native ABI](platforms/native.md), self-hosted interpreter, actor scheduling,
browser runtime, and [three integration tutorials](tutorials/index.md) are planned.
Each page separates existing behavior from the work needed to reach that design.
The book is the documentation foundation for those prototypes.

## Read and develop the book

From the checkout, enter the development shell and start the preview:

```sh
nix-shell
scripts/book serve --hostname 127.0.0.1 --port 3000
```

Open <http://127.0.0.1:3000>. mdBook watches the sources and reloads changed pages.
`scripts/book build` writes the static site to `build/book/`. `MDBOOK` can select
an installed mdBook executable; no Node package manager or custom preprocessor
is needed. [mdBook's serve documentation](https://rust-lang.github.io/mdBook/cli/serve.html)
describes the preview options.

Book sources live under `doc/book/`. Each platform gets one page, with its WAT
interface included from a `.wat` file and a linked symbol reference. The module
bodies marked `unreachable` are interface stubs, not runnable implementations.
