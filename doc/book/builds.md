# Programs that build programs

`snail-scheme SCRIPT [ARGUMENT ...]` evaluates an ordinary Scheme script. The
native CLI compiles that script through Wasm and LLVM into a temporary executable,
runs it, and returns its status. Script statements execute in order. Compilation,
artifact paths, and execution policy are procedures in Scheme libraries.

## Bootstrap and rebuild

The checkout's complete `build.scm` chooses the interpreter's output filename:

```scheme
{{#include ../../build.scm}}
```

Bootstrap with Chibi, then run the same script with the resulting interpreter:

```sh
chibi-scheme -I src build.scm
build/snail-scheme build.scm
build/snail-scheme build.scm build/another-snail-scheme
```

This first native platform targets **x86-64 Linux**. Enter `nix-shell` for Chibi,
Rust, Binaryen, Clang/LLD, BDWGC, and mdBook. Cargo's dependencies and Rust target
must be available before the offline build. `BDWGC_INCLUDE` and `BDWGC_LIB` can
select a collector installation outside the compiler's normal search paths.

`build-interpreter` compiles `main.scm`, selecting its `main` handler explicitly:

```scheme
{{#include ../../main.scm}}
```

The platform initializes one instance and calls this zero-argument handler once.
Its returned integer is the command's exit status. The generated script adapter
instead evaluates top-level statements and returns zero on normal completion;
a helper named `main` inside a script does not become an entry point.

The interpreter embeds its source checkout's absolute path. `SNAIL_ROOT` can
select a compatible checkout. It still needs those compiler/runtime sources and
external Cargo, Binaryen, Clang/LLD, and BDWGC tools; this is a self-hosting build
interpreter, not a standalone compiler distribution. It does not need Chibi after
the initial bootstrap. `scripts/test-self-host` verifies that by blocking Chibi,
rebuilding the interpreter, and executing scripts with the replacement.

## Build policy belongs to libraries

`(snail-scheme compiler)` emits unlinked WAT. `(snail-scheme build)` assembles and
links portable Wasm. `(snail-scheme native)` translates binary Wasm to LLVM and
invokes the native linker. `(snail-scheme cli)` composes these operations with the
native Rust runtime and a CLI entry adapter. Importing them performs no build.

The CLI links Rust's native archive directly through the AWI. Rust provides file
IO, binary input, process arguments, environment access, subprocesses, and artifact
publication. The bootstrap build host implements the same operations using Chibi.
The [native CLI interface](platforms/native-cli.md) documents every platform
operation and the application's required handler inline.

Build scripts choose every artifact path. A successful build atomically renames
a completed artifact over the destination; a failed build preserves the previous
output and reports retained intermediates. Tool arguments are literal strings.
Build tools receive EOF on stdin, leaving the invoking script's input intact.
Scripts inherit stdin/stdout/stderr, environment, working directory, and arguments.

## Stages are ordinary computations with explicit outputs

1. **Expansion** transforms located syntax. A planned `generate-library` has
   one generator `begin`; its imports apply to generator code, and generated
   code declares its own imports. Explicit source paths select the reader.
2. **Build evaluation** calls compiler libraries, captures graphs, or composes
   applications. Completed artifacts and dependency descriptions cross the stage.
3. **Shipped execution** loads those artifacts and performs their runtime effects.

Running a reader does not run the document's embedded Scheme. Capturing a tensor
graph does not train it. Build-time heaps and live connections do not become
deployment state. General reader generators, graph capture, hot reload, and actor
connections remain planned; ordinary Scheme compiler calls are the first working
stage of this design.
