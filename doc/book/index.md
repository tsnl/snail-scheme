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

Chibi bootstraps the native `snail-scheme` interpreter. That executable runs
Scheme scripts and can rebuild itself through the [build libraries](builds.md).
Scheme compiles through WasmGC and LLVM; the native CLI links the Rust runtime
directly. Scripts choose inputs, output paths, and execution.

The first platform contracts are [native CLI](platforms/native-cli.md),
[native GUI](platforms/native-gui.md), and [browser GUI](platforms/browser-gui.md).
They build on the [AWI extension](awi.md). The native CLI entry and linkage are
implemented; GUI services and actor scheduling remain planned. The
[three integration tutorials](tutorials/index.md) will exercise that design.

## Read and develop the book

From the checkout, enter the development shell and start the preview:

```sh
nix-shell
scripts/book serve --hostname 0.0.0.0 --port 8000
```

Open <http://127.0.0.1:8000> locally, or port 8000 on the machine’s LAN address. mdBook watches the sources and reloads changed pages.
`scripts/book build` writes the static site to `build/book/`. `MDBOOK` can select
an installed mdBook executable. [mdBook's serve documentation](https://rust-lang.github.io/mdBook/cli/serve.html)
describes the preview options.

Book sources live under `doc/book/`. Each platform gets one page rendering its
`.wat` interface. Function documentation lives inline in that file. Bodies marked
`unreachable` are interface stubs, not runnable implementations.
