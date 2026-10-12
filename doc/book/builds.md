# Programs that build programs

`snail-scheme [-I DIRECTORY ...] [--] SCRIPT [ARGUMENT ...]` evaluates an ordinary
Scheme script. The native CLI compiles that script through Wasm datums and LLVM into a
temporary executable, runs it, and returns its status. Script statements execute
in order. Compilation, artifact paths, and execution policy are procedures in
Scheme libraries.

## Bootstrap and rebuild

The checkout's complete `build.scm` chooses the interpreter's output filename:

```scheme
{{#include ../../build.scm}}
```

Bootstrap with Chibi, then run the same script with the resulting interpreter:

```sh
chibi-scheme -h512M -I src build.scm
build/snail-scheme -Isrc build.scm
build/snail-scheme build.scm build/another-snail-scheme
```

Both `-Isrc` and `-I src` prepend `src` to the library search path, as in Chibi.
Repeat `-I` to add directories; the last supplied directory is searched first.
Paths are relative to the current working directory. `--` permits a script
filename beginning with `-`. After the script filename, all arguments belong to
the script, including any `-I` tokens.

The CLI uses the public `(snail-scheme options)` library. Its `parse-options`
procedure reads argument strings using an `<args-spec>` record, constructed from
a quoted list of typed declarations, a program name, and optional help text.
The library generates usage and help from that record. An `<args>` record holds
positionals and typed option values:
flags, counters, single values, or repeated values. `--` switches permanently to
positional-only mode. The CLI uses `parse-options-prefix` to preserve the script's
argument suffix and provides generated help with `-h` or `--help`.

This first native platform targets **x86-64 Linux**. Enter `nix-shell` for Chibi,
Rust, Binaryen, Clang/LLD, BDWGC, and mdBook. Cargo's dependencies and Rust target
must be available before the offline build. `BDWGC_INCLUDE` and `BDWGC_LIB` can
select a collector installation outside the compiler's normal search paths.

The build script generates its installation library and compiles `main.scm`,
selecting its `main` handler explicitly:

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
the initial bootstrap. The CLI verifies its selected Binaryen tools before
compilation; `--help` works without them. See the [tool installation instructions](../backend.md).
`scripts/test-self-host` verifies the installed path by blocking Chibi and Python,
rebuilding the interpreter, and executing scripts with the replacement.

## Build policy belongs to libraries

`(snail-scheme compiler)` constructs Wasm datums and optionally writes unlinked
WAT. `(snail-scheme build)` uses Binaryen to assemble and link portable Wasm.
`(snail-scheme native)` lowers Binaryen's optimized Scheme module to LLVM and
runs ordinary scripts. Its `build-native` procedure publishes an executable
atomically. `compile-native` is the composition stage used by the
build script above: it writes a private candidate into the caller's workspace,
without reserving another directory or publishing anything. Importing these
libraries performs no build.

The CLI links Rust's native archive directly through the AWI. Rust provides file
IO, binary input, process arguments, environment access, subprocesses, and artifact
publication. The bootstrap build host implements the same operations using Chibi.
The [native CLI interface](platforms/native-cli.md) documents every platform
operation and the application's required handler inline.

Build scripts choose every artifact path. A successful build publishes a
completed file or switches a relative symlink to a complete executable generation
with its dependency artifacts. A failed build preserves the previous output and
reports retained intermediates. See [generation and packaging](../build-artifacts.md).
`call-with-build-output` owns one workspace and checks the declared input paths
both before building and before publication. The second check also protects a
runtime archive created during this build. `native-runtime-path` selects that
archive's filename without building it.

Tool arguments are literal strings. Build tools receive EOF on stdin, leaving
the invoking script's input intact.
Scripts inherit stdin/stdout/stderr, environment, working directory, and arguments.

## Stages are ordinary computations with explicit outputs

1. **Expansion** transforms located syntax. `generate-library` has
   one generator `begin`; its imports apply to generator code, and generated
   code declares its own imports. Explicit source paths select the reader.
2. **Build evaluation** calls compiler libraries, captures graphs, or composes
   applications. Completed artifacts and dependency descriptions cross the stage.
3. **Shipped execution** loads those artifacts and performs their runtime effects.

Running a reader does not run the document's embedded Scheme. Capturing a tensor
graph does not train it. Build-time heaps and live connections do not become
deployment state. General reader generators, graph capture, hot reload, and actor
connections remain planned. Ordinary Scheme compiler calls and isolated library
generators implement the current build stages.
