# Bootstrap and self-hosting

The compiler is a `snail-scheme` program that compiles itself, inside the
command line, `bootstrap/cli.sld`, the one program stage zero builds, which
also holds the engine that runs per-library programs. Everything else,
scripts and the book's highlighter among them, the command line builds, as
`clang` builds `lli`. Chez Scheme
runs that same source for stage zero through a deliberately small host
adapter. This does not make `snail-scheme` an R6RS or R7RS implementation:
only the compiler's explicit source closure has an erased host equivalent.

## The stage-zero boundary

`host/chez/load.scm` loads the compiler's `.sld` library envelopes as native
Chez libraries. `host/chez/` supplies `(snail core base)`, `(snail core table)`,
`(snail core io)` and the typed-form adapter, plus the build driver. Compiler
modules come from `src/snail/shell/compiler/`. An application library outside
that closure is rejected. Test mode additionally admits the test support and
project parser fixture.

| `snail-scheme` source | Chez execution |
| --- | --- |
| Typed `define` and `lambda` headers | Parameter names and function bodies, with type/effect clauses erased. |
| Top-level values | Ordinary Chez definitions, evaluated when their library loads; the compiler's own source defines none whose order could matter. |
| `record` and `enum` | Distinct constructor identities with mutable fields; pure replacement copies the outer object. |
| `(new Name (field expression) ...)` | Compile-time field selection and sequential initializer bindings, followed by the private constructor. |
| `(● object field ...)`, `set!` | Registered field slots, with ordinary object aliasing. |
| `match` | Case tests and field bindings. |
| Types, quantifiers and constraints | Erased after the host adapter has recognized their syntax. |
| Compiler failure effects | Host handlers with a delimited escape to the compiler's error boundary. |
| Compiler tables | Host tables whose externally visible traversal order agrees with the typed library. |

Chez's host control facilities are implementation details of this adapter.
They do not expose `call/cc`, `dynamic-wind`, a borrow checker or a numeric
tower to `snail-scheme` programs. The adapter need only execute the effects used by
the compiler; arbitrary source handlers are compiled by the compiler itself.
All top-level definitions are functions. Runtime values are constructed by
those functions; Chez needs no separate scalar evaluator bridge.

The compiler must not depend on differences in host integer overflow,
argument evaluation order or table iteration. Stateful sibling operations
are explicitly sequenced; generated identifiers and declaration order are
deterministic. The bootstrap checks the resulting text, not just whether
both outputs run.

## Stages and checks

`scripts/bootstrap` builds the command line into
`build/bootstrap/snail-scheme.wasm`, linked with the toolchain runtime, whose
services include the assembler, and prints it and the two runtimes, plain
and the toolchain's, a line each, which `./snail-scheme` caches in
`build/tools.txt`.

1. A working previous command line produces stage one. For a clean
   bootstrap, Chez executes the compiler's source to produce it instead.
2. Stage one compiles the command line's source to stage two.
3. Stage two compiles it again to stage three.
4. Stages two and three must have exactly identical Wasm text.
5. When Chez produced stage one, stages one and two must also have exactly
   identical text: the source host and compiled compiler ran the same input.

`make bootstrap` removes the old command line and starts from Chez.
`./scripts/bootstrap` can reuse a working one: when the compiler's own
sources are older than it, an edit elsewhere under `src/` or `bootstrap/`
cannot change the compiler inside it, so one compile by it is the
fixpoint's output; an edit to the compiler runs the whole fixpoint.
Set `CHEZ` to the Chez `scheme` executable when it is not on `PATH`.

`make test` runs the compiler's unit tests from source on Chez
(`tests/unit.scm`), then builds every test program with the command line,
as a user's is built, and runs it (`tests/run.mjs`). Stage 0 compiles
nothing but the command line: that Chez and the compiled compiler agree is
the fixpoint's check, on the compiler's own source. `make test-wasmtime`
builds each program for wasmtime, runs it on the native executable, and
checks that the command line emits the same text on both engines. `make check` verifies source formatting. There is
no Chibi test or bootstrap path.

## The native executable

`crates/snail` builds `build/snail`, a native executable that embeds
[wasmtime](https://wasmtime.dev) 48 and runs compiled programs without
Node, the command line among them. A compile is the command line's
`compile` action, which stage 0 runs for the bootstrap and the test
harness: one that fails exits with status 1, and so does one that needs an
input, having written its `request.datum` first.

`build/snail run-wasm PROGRAM ARGUMENT ...` runs a compiled program as
`host/native/run-snail.mjs` does on Node, for one that needs of its host
only WASI, the files it links and loading modules
(`crates/snail/src/program.rs`).
PROGRAM is one linked module, as every `snail-scheme build` writes, or the
`NAME.manifest.datum` of a per-library build, which only stage 0's test
harness makes now and the engine runs: `(snail shell engine)`, which the command line
holds ("The engine" in `bootstrap/cli.sld`), so the program stage 0 builds is
also what runs every per-library program. Both hosts start it, from
`build/bootstrap/snail-scheme.wasm` or `SNAIL_ENGINE_MODULE`, with the
manifest in `SNAIL_MANIFEST`, and call its `engine:` exports in place of its
`main`; a host decides by being given a manifest. The engine reads the
manifest with the compiler's reader, and the runtime and each module from
`store/` beside it, by digest, through its `linked-content-store` effect,
which the command line handles by reading files. It links them through
the Wasm primitives of `(snail shell wasm)`, the runtime first and each
library's module after those it imports from, names the runtime
`snail.core.support` so the host stages Bytes in its memory, calls the root program
`main`, and serves the files the program links, each
read in a task of its own that wakes the reading task's ticket. Linking is
the engine's first task: the host turns the engine once after its `main`,
which links the program and calls its entry's start, `main:body`, with
the engine's scheduler. The engine's own scheduler and the program's are turned
as one through its `engine:turn`, `engine:wake`, `engine:close-tasks`,
`engine:running` and `engine:live`, which the host calls in place of
`tasks:*`. A file a
linked module links is an object of `store/` beside it, at
`sha256/AB/DIGEST`, read by the host
when a task first asks for it, which wakes the task's ticket between turns
(`links.rs`).
WASI gets PROGRAM and the arguments, the environment with `SNAIL_CWD`
naming the working directory, and the host's `/` preopened; then
`_initialize`; then `main` with a new scheduler, which starts the
program's `main` as its first task, or the engine's `engine:start`; then
the first turn; and then the program's tasks, driven until none is live
([driving the scheduler](../runtimes/scheduling.md)).
The status is 0, or 1 when a task trapped or exited after the first turn;
a WASI exit in the first turn is its own status, and ends the program
before its other tasks run.
`close-resources`, or the runtime's `snail:io/close-all`, runs whatever
happened, and a nonzero answer fails a run that succeeded. A trap or a
failure of the host is status 2, with V8's message after `snail: ` and the
Wasm frames after it, and so is a run whose tasks all wait on tickets,
since this host completes no host operations. Node's runner gives the
same statuses. What a module imports of
`snail.runtime.native.socket` or `snail.runtime.native.process` is linked to
a function that traps when it is called, saying the operation runs on Node:
the command line imports processes for `run`, and its `compile` calls none,
so it compiles here, while a program that uses sockets or processes runs on
Node.

Node is still the default engine. `SNAIL_ENGINE=wasmtime` runs every compile
on `build/snail` instead, the bootstrap's stages included, and every program
the driver runs that imports neither of those modules. A test program builds
for the engine that runs it: for `(snail target wasmtime)` under
`SNAIL_ENGINE=wasmtime`, unless `node-programs` in
`host/chez/snail/stage0/build.sld` names it as one that needs Node's
processes, signals or sockets, and for `(snail target node)` otherwise.
A program built for Node imports those modules, since its target installs
their handlers, so `program-command` asks `build/snail imports PROGRAM`,
which reads the import sections without compiling them, and runs it on
Node. Stage 0 also uses this executable for assembly and static linking,
so the driver builds it with Cargo when stale regardless of the selected
engine, and `make bootstrap` builds it first.

`build/snail precompile MODULE OUTPUT` writes Cranelift's machine code for
a module as a `.cwasm` file, which `run-wasm` loads in place of compiling
the module: the driver keeps `build/bootstrap/snail-scheme.cwasm` beside the
command line, which saves each compile most of a second. The file belongs to one
wasmtime version, configuration and CPU, so it is a build output and is
never committed.

Node remains the default for compiler execution. Wasmtime provides an
independent engine and is exercised by `make test-wasmtime`. Performance
comparisons must identify the compiler revision and distinguish engine
startup, compilation of Wasm to native code, and execution; the language's
boxed records change those costs substantially.

The standalone executable and its embedded project tooling remain the
subject of [#562](https://github.com/tsnl/snail-scheme/issues/562). Chez is
needed for a clean source bootstrap, not to execute a compiled program.
