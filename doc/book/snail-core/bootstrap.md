# Bootstrap and self-hosting

The compiler is a Snail Scheme program that compiles itself. Chez Scheme
runs that same source for stage zero through a deliberately small host
adapter. This does not make Snail Scheme an R6RS or R7RS implementation:
only the compiler's explicit source closure has an erased host equivalent.

## The stage-zero boundary

`host/chez/load.scm` loads the compiler's `.sld` library envelopes as native
Chez libraries. `host/chez/` supplies `(snail core base)`, `(snail core table)`,
`(snail core io)` and the typed-form adapter, plus the build driver. Compiler
modules come from `src/snail/shell/compiler/`. An application library outside
that closure is rejected. Test mode additionally admits the test support and
project parser/planner fixtures.

| Snail Scheme source | Chez execution |
| --- | --- |
| Typed `define` headers | Parameter names and function bodies, with type/effect clauses erased. |
| `struct` and `enum` | Distinct constructor identities with mutable fields; pure replacement copies the outer object. |
| `(● object field ...)`, `set!`, `replace!` | Registered field slots, with ordinary object aliasing. |
| `match` | Case tests and field bindings. |
| Types, quantifiers and constraints | Erased after the host adapter has recognized their syntax. |
| Compiler failure effects | Host handlers with a delimited escape to the compiler's error boundary. |
| Compiler tables | Host tables whose externally visible traversal order agrees with the typed library. |

Chez's host control facilities are implementation details of this adapter.
They do not expose `call/cc`, `dynamic-wind`, a borrow checker or a numeric
tower to Snail programs. The adapter need only execute the effects used by
the compiler; arbitrary source handlers are compiled by the compiler itself.
All top-level definitions are functions. Runtime values are constructed by
those functions; Chez needs no separate scalar evaluator bridge.

The compiler must not depend on differences in host integer overflow,
argument evaluation order or table iteration. Stateful sibling operations
are explicitly sequenced; generated identifiers and declaration order are
deterministic. The bootstrap checks the resulting text, not just whether
both outputs run.

## Stages and checks

1. A working previous compiled compiler produces stage one. For a clean
   bootstrap, Chez executes the source to produce it instead.
2. Stage one compiles the source to stage two.
3. Stage two compiles the source again to stage three.
4. Stages two and three must have exactly identical Wasm text.
5. When Chez produced stage one, stages one and two must also have exactly
   identical text: the source host and compiled compiler ran the same input.

`make bootstrap` removes the old compiler output and starts from Chez.
`./scripts/snail-tool bootstrap` can reuse a working compiled compiler.
Ordinary tool invocations rebuild stale compiler sources automatically.
Set `CHEZ` to the Chez `scheme` executable when it is not on `PATH`.

`make test` exercises compiler units and linked programs with the compiled
compiler. `make test-chez` compiles the suite from source on Chez.
`make test-wasmtime` uses Wasmtime for supported compiles and executions and
checks agreement with V8. `make check` verifies source formatting. There is
no Chibi test or bootstrap path.

## The native executable

`crates/snail` builds `build/snail`, a native executable that embeds
[wasmtime](https://wasmtime.dev) 48 and runs compiled programs without
Node, the compiled compiler among them. The compiler needs nothing else:
the Rust runtime is merged into `snailc.wasm`, so its only imports are 21
`wasi_snapshot_preview1` functions. It is an ordinary program,
`bootstrap/compile.sld`, which makes one compile from its command line. A
compile that fails exits with status 1, and so does one that needs an
input, having written its `request.datum` first.

`build/snail run-wasm PROGRAM ARGUMENT ...` runs a compiled program as
`host/native/run-snail.mjs` does on Node, for one that needs of its host
only WASI, the files it links and loading modules
(`crates/snail/src/program.rs`).
PROGRAM is one linked module, or the `modules.json` of a per-library build,
which the engine runs: `(snail shell engine)`, a Snail Scheme program stage 0
builds to `build/engine/engine.wasm` (`bootstrap/engine.sld`), which both
hosts start with the manifest in `SNAIL_MANIFEST`, or at
`SNAIL_ENGINE_MODULE`. The engine reads the runtime and each module from
the store the manifest names, by digest, through its `linked-content-store`
effect, which this entry handles by reading files. It links them through
the Wasm primitives of `(snail shell wasm)`, the runtime first and each
library's module after those it imports from, names the runtime
`snail.core.support` so the host stages Bytes in its memory, calls the root program
`main`, and serves the files the program links, each
read in a task of its own that wakes the reading task's ticket. Linking is
the engine's first task: the host turns the engine once after its `main`,
which links the program and calls its entry, and then reads
`engine:status`. The engine's own scheduler and the program's are turned
as one through its `engine:turn`, `engine:wake`, `engine:close-tasks`,
`engine:running` and `engine:live`, which the host calls in place of
`tasks:*`. A file a
linked module links is an object of `store/` beside it, read by the host
when a task first asks for it, which wakes the task's ticket between turns
(`links.rs`).
WASI gets PROGRAM and the arguments, the environment with `SNAIL_CWD`
naming the working directory, and the host's `/` preopened; then
`_initialize`, and
`main`, and then the program's tasks, driven until none is live
([driving the scheduler](../runtimes/scheduling.md)).
The `main`'s result, the engine's `engine:status` for a manifest, is the
status when it is 0 to 255, and 1 otherwise, and 1 when a task trapped or
exited; a WASI exit in a `main` is its own status, and ends the program
before its tasks run.
`close-resources`, or the runtime's `snail:io/close-all`, runs whatever
happened, and a nonzero answer fails a run that succeeded. A trap or a
failure of the host is status 2, with V8's message after `snail: ` and the
Wasm frames after it, and so is a run whose tasks all wait on tickets,
since this host completes no host operations. Node's runner gives the
same statuses. A module that imports
`snail.runtime.native.socket`, `snail.runtime.native.process` or
`snail.runtime.native.files` is refused before it is compiled: a program
that uses sockets, processes, file modes or watches runs on Node.

Node is still the default engine. `SNAIL_ENGINE=wasmtime` runs every compile
on `build/snail` instead, the bootstrap's stages included, and every program
the driver runs that imports neither of those modules: `program-command`
in `host/chez/snail/stage0/build.sld` asks `build/snail imports PROGRAM`,
which reads the import sections without compiling them, and runs the rest
on Node. Stage 0 also uses this executable for assembly and static linking,
so the driver builds it with Cargo when stale regardless of the selected
engine, and `make bootstrap` builds it first.

`build/snail precompile MODULE OUTPUT` writes Cranelift's machine code for
a module as a `.cwasm` file, which `run-wasm` loads in place of compiling
the module: the driver keeps `build/compiler/snailc.cwasm` beside the
compiler, which saves each compile about 0.7 s. The file belongs to one
wasmtime version, configuration and CPU, so it is a build output and is
never committed.

Node remains the default for compiler execution. Wasmtime provides an
independent engine and is exercised by `make test-wasmtime`. Performance
comparisons must identify the compiler revision and distinguish engine
startup, compilation of Wasm to native code, and execution; the language's
boxed records and counted ownership change those costs substantially.

The standalone executable and its embedded project tooling remain the
subject of [#562](https://github.com/tsnl/snail-scheme/issues/562). Chez is
needed for a clean source bootstrap, not to execute a compiled program.
