# `snail-scheme`

**`snail-scheme` is a statically-typed Scheme successor**, for building
applications, compiling to WebAssembly with garbage collection. Its compiler
is written in the language and compiles itself; programs run on Node and in
the browser.

## What is here

- **The language**: S-expressions, hygienic macros and explicit types;
  records as mutable heap objects any number of names may share;
  capabilities passed as values, so a function can do only what it was
  handed; and one-shot suspension, from which exceptions, generators and
  tasks are built ([the language](snail-scheme/index.md)).
- **Libraries**, all written in `snail-scheme`: a prelude, files, processes
  and sockets, pages, document interfaces and canvas applications, WebGPU as
  a capability with rasterizing, Gaussian splatting and path tracing on top
  of it, and GPU tensor graphs with gradients ([library reference](libraries/index.md)).
- **Tools**: one command, `snail-scheme`, that builds and runs scripts, a
  language server with editor support for Zed and VS Code, and a formatter
  ([development toolchain](snail-scheme/toolchain.md)).
- **Runtimes**: tasks scheduled in `snail-scheme`, with Node and the
  browser completing what they wait on ([runtimes](runtimes/index.md)).
- **Applications**, in `src/apps/`: [Siegework](games/siegework.md), a
  colony game; Hearsay's two prototypes; a path-traced glTF viewer; a
  Gaussian splat viewer; and a trainer that fits splats to photographs
  ([tensors and training](graphics/tensors.md)).

## Where to start

- **To learn the language**, read [`snail-scheme` in ten minutes](snail-scheme/tutorials/tour.md),
  then the [tutorials](snail-scheme/tutorials/index.md).
- **To find a library**, start at the [library reference](libraries/index.md),
  which lists every one and links its source.
- **To build something**, read [getting started](https://github.com/tsnl/snail-scheme/blob/main/doc/getting-started.md),
  then [workspaces and builds](snail-scheme/projects.md) and the
  [application model](snail-scheme/applications.md).
- **To work on the compiler**, read the [compiler architecture](snail-scheme/compilers.md)
  and [bootstrap](snail-scheme/bootstrap.md).

## Try it in a browser with WebGPU

- **[Play Siegework](play/siegework/)**: explore a seeded map, wire an
  energy network across it, and destroy three nests.
- **[Play If You’re Going That Way](play/iygtw/)** and explore a farming village by bicycle with Moss. [Rider’s guide](games/iygtw.md).
- **[Open the viewer](play/viewer/)** and drop a `.glb` on it, or pick a
  sample, to see it path traced ([the path tracer](graphics/tracer.md)).
- **[Open Splats](play/splats/)** and drop a trained scene's `.ply` on it.
- **[Play Hearsay](play/hearsay/)**: the rumor mill and the favor ledger.

The book describes what is implemented and marks proposals explicitly.
Source lives in the [repository](https://github.com/tsnl/snail-scheme), and
[GitHub issues](https://github.com/tsnl/snail-scheme/issues) track open work.
