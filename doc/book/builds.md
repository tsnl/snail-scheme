# Programs that build programs

**Implemented:** ordinary Scheme build scripts hosted by Chibi. **Planned:**
running those same scripts with a self-hosted `snail-scheme` interpreter.

The script owns build policy, including output paths. Importing the compiler
library does not build anything; calling its procedures does.

This is the repository's current complete `build.scm`:

```scheme
{{#include ../../build.scm}}
```

Run it from the checkout:

```sh
chibi-scheme -I src build.scm
```

It builds and runs Fibonacci through the Rust/Wasm runtime. Chibi supplies process
creation while Cargo and Binaryen remain external build tools. The existing
`build-wasm`, `build-runtime`, `link-wasm`, and `run-wasm` procedures are in
[`build.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-scheme/build.sld).
The compiler itself is independently callable through
`(snail-scheme compiler)` and `source-file->wat-file`.

## The self-hosting milestone

The intended command is `snail-scheme SCRIPT [ARGUMENT ...]`: compile the script
to temporary Wasm and execute it, evaluating its statements in order. Compilation,
hot reload, output selection, and application composition remain library calls.
A future root `build.scm` will build this interpreter and specify its artifacts.
The resulting interpreter must then run `build.scm` and rebuild itself.

This needs runtime support for the build's effects, including subprocesses while
the tools are external. WASIp1 does not provide `std::process::Command` support;
the current Node launcher has no process-spawn import. A process operation must
therefore be specified and implemented before claiming self-hosting works.
[Rust's WASIp1 documentation](https://doc.rust-lang.org/rustc/platform-support/wasm32-wasip1.html#requirements)
records that limitation. Native IO belongs in the Rust runtime; an eventual
native executable should not depend on Node.

## Stages are ordinary computations with explicit outputs

1. **Expansion** transforms located syntax. A planned `generate-library` has
   one generator `begin`; its imports apply to generator code, and generated
   code declares its own imports. Explicit source paths select the reader.
2. **Build evaluation** calls compiler libraries, captures graphs, or composes
   applications. Completed artifacts and dependency descriptions cross the stage.
3. **Shipped execution** loads those artifacts and performs their runtime effects.

Running a reader does not run the document's embedded Scheme. Capturing a tensor
graph does not train it. Build-time heaps and live connections do not become
deployment state. A compiler is an ordinary library call unless the application
deliberately places it behind an actor connection.
