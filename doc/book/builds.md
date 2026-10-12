# Programs that build programs

`build.scm` is an ordinary Scheme script. It calls compiler libraries and other
tools, chooses output paths, and can build several artifacts from shared source.
Script arguments can select tests, linting, or release packaging. Importing a
compiler library performs no build; the script's calls determine what happens.

Building produces code or data. Runtimes later load the artifacts. A shared
library compiled into a server artifact and a browser artifact gives each node
its own state. See the [counter example](nodes.md#an-example-one-counter-two-browsers).

## One script, several artifacts

A 3D game's `build.scm` can arrange its output like this:

```text
out/
  game-server.wasm  command code for Node.js
  game.wasm         browser code, including embedded WGSL
  game.js           browser loader and bindings
  world.glb         cooked 3D assets
```

The script calls the project's chosen compilers and asset tools in the order
their inputs require. A shader DSL implemented in Scheme can produce WGSL for
embedding in Wasm or for a separate file. The asset tool can turn source models
into GLB. They are all ordinary build operations producing artifacts.

The script decides which source is shared across artifacts and which libraries
belong to each runtime. A release argument can package the completed output
directory as a tarball. Test and lint arguments can run different operations
without introducing another build language.

## Compiler libraries

These libraries are implemented in this checkout:

| Library | What its calls produce |
| --- | --- |
| `(snail-scheme compiler)` | Unlinked WAT through `source-file->wat-file` |
| `(snail-scheme build)` | Assembled and linked Wasm through `build-wasm`, or `build-runtime` and `link-wasm` for separate stages |
| `(snail-scheme effects)` | Interface definitions and platform selection for linked Wasm |

Compiler and build calls run inside a `with-chromium-trace-to` scope from
`(snail-scheme chromium-trace)`. The script chooses the trace output as well as
the artifacts. The [command page](platforms/native-cli.md) includes a complete
`build.scm`; the [Node.js page](platforms/nodejs.md) shows a linked Wasm build.

`build-wasm` publishes one linked module atomically. `compile-wasm` writes a
candidate in the caller's workspace and returns its dependency artifact, so a
script can compose more work before publication. `run-script` compiles and runs
an ordinary script as Wasm through Node.js.

Tools receive literal argument strings and EOF on stdin. Executed scripts
inherit stdin/stdout/stderr, environment, working directory, and arguments.
Node.js supplies subprocess and publication effects for compiled commands;
Chibi supplies the bootstrap adapter.

## Publishing artifacts

`call-with-build-output` owns a workspace and checks declared inputs before
building and before publication, including a runtime module created during the
build. A failed build preserves that artifact's previous output and reports
retained intermediates. **This guarantee is per artifact.** If A publishes and B
then fails, A is not rolled back. A release script can build all outputs in a
fresh directory and make that release visible only after every step succeeds.

## Building and running are separate

Generating a shader writes code; loading it and dispatching work uses a runtime.
Compiling a tensor graph produces an artifact; training executes that artifact
with data. Generated Scheme is also source for a later stage, unless the build
script explicitly evaluates it.

Build-time heaps and live connections do not become deployment state. A runtime
loads the files selected by its configuration and initializes each node's state.
The build script controls how those files are produced and placed.
