# Development toolchain

Lofi can link a program statically or link its libraries when it starts.
Static builds compile the whole program, optimize it and merge the Rust runtime
into one module. `--release` increases optimization; it does not select linking
mode. Development builds keep each library as its own module, with the runtime
as a separate instance.

| Command | Build |
| --- | --- |
| `lofi run`, `lofi compile`, `lofi build`, `make site` | Static; `--release` requests full optimization |
| `lofi serve`, `lofi watch`, `make ide` (current commands) | Separate development modules |

`lofi compile -o DIRECTORY SOURCE` publishes `DIRECTORY/program.wasm`.
The output is a directory, even for a single-file program. Compiler and linker
intermediates stay private; a failed rebuild keeps the previous successful
program, and unrelated files in the directory remain untouched.
`lofi run -o DIRECTORY SOURCE` also retains its program there; without `-o`,
`run` removes its private build when execution ends. To run a published artifact
directly, use `node --no-warnings scripts/run-lofi.mjs DIRECTORY/program.wasm`.

Projects describe named builds in inert `project.datum`:

```text
./lofi build --release apps/siegework site
python3 -m http.server 4191 --directory apps/siegework/build/site
```

`build` takes an explicit project directory and target name. It publishes that
target at `PROJECT/build/TARGET`, a link to a completed directory containing
`program.wasm` and, for a browser build, the shared host and its `public` files.
Put the page in `public/index.html`. Builds retain prior generations and reject
unmanaged entries at the output path. The [project format](https://github.com/tsnl/snail-scheme/blob/stack/project-builds-20261024/doc/project-format.md)
documents publication and public-file rules.

The native project builder keeps one Wasm compiler alive throughout an invocation.
It also supports resident callers with a successful compiler Session per target.
Changing a target's entry or library roots starts a fresh Session; an edit within
those inputs uses the compiler's existing incremental checks. Generated-library
producers run again each attempt because they may read files outside their recipe.

Builds return completed private directories before publication. A failed parent
changes none of its dependencies' public outputs. A caller can discard a completed
candidate and still reuse the compiler's successful work: caches retain evidence,
not paths into that candidate. Development directories contain their modules,
manifest and runtime, so they are self-contained. The new watcher/IDE integration
will use this same builder; the existing commands below still use their old loop.

## Builds in proportion to the edit

`lofi serve` and `lofi watch` run a development loop that is itself a
Lofi program, `(lofi develop)`, and keeps the compiler running between
builds. It remembers every library's **interface**: everything importers
depend on, which is every declaration but the bodies of functions with
monomorphic signatures. An edit to such a body recompiles one library; an
edit to an interface recompiles the libraries that import it too.

The native loop and its Wasm compiler now run in one persistent Node worker.
The parent owns file watches, timers, HTTP connections and application children,
so it can receive an external edit or answer a request while compilation runs.
Synchronous filesystem and assembler operations stay with the compiler. Five
existing commands cross to the parent; compiler entries remain serial and keep
the same session after a reported compile error. The first build is scheduled
only after watches are installed. The loop writes HTML, manifests and module
binaries beside their destination, then renames them into place, so concurrent
reads see complete files. Stopping the host closes its resources and
the worker, and stops its current application child.

This establishes the execution boundary for the proposed project development
session. The current loop still has the old command, publication and watcher
policies; shared project subscriptions and attempt-scoped diagnostics follow.

```text
$ ./lofi serve apps/siegework
built siegework in 457 ms: 14 of 14 modules compiled
serving siegework at http://127.0.0.1:8000/
built siegework in 106 ms: 1 of 14 modules compiled
```

A page relinks the modules that changed and every module after them, which
are the only ones that can import from them, and keeps the application's
state ([hot reload](applications.md#hot-reload)). Because the loop
checks each library before the libraries that import it, a definition
gets its type from its own library: give constants a signature where a
literal could have more than one type, as `(lofi app)` gives its key codes
`I32`.

## The browser IDE

The following describes the current implementation. The
[project and development proposal](https://github.com/tsnl/snail-scheme/blob/design/desktop-ide-tasks-20261024/doc/proposals/desktop-ide.md)
will replace its temporary browser backend with `lofi dev` and make the editor
a client of the running development session. The integrated preview has been
removed; the commands below have not changed.

`make ide` packages an IDE as a static site in `build/ide`, with nothing to
install and no server beyond one for static files:

```text
$ make ide
$ python3 -m http.server --directory build/ide
```

It opens Siegework until you open a project directory of your own; files stay
in the browser's storage, and saving writes each file back to its directory
where the browser allows it. The toolbar along the top toggles the file
browser on the left and splits the editor panes. Code is highlighted as you type; Tab and Enter indent as
Emacs's Scheme mode does, and saving formats the file as `make check`
expects. Each edit, saved or not,
goes to the development loop running in a worker, compiler included: a
build that fails puts a squiggle under what the compiler points at; a
successful build clears the diagnostic. The editor does not run the application.

## Proposed project workflow

The [project-description parser](https://github.com/tsnl/snail-scheme/blob/stack/project-forms-20261024/doc/project-format.md)
is implemented as `(lofi project)` for Chibi and Wasm. It returns typed build
descriptions and resolves run targets to program builds, retaining error locations.
The one-shot CLI builder consumes these descriptions. The development workflow
below remains proposed.

`project.datum` uses explicit `build-target` and `run-target` forms. It now
replaces the application packaging script for the CLI; IDE integration follows.
The compiler now supports the `(lofi artifact)` library's `artifact-bundle`
macro and checks recorded file dependencies before reusing cached compilation.
`lofi build` resolves these requests to browser targets in the same project,
including requests inside generated-library producers. Repeated requests reuse
one completed generation during a build; cycles report their target path.
A server can reference several frontend targets while compiling; their files
become ordinary embedded bytes. Standalone commands and the old development
loop still reject project artifact requests. The
[artifact contract](https://github.com/tsnl/snail-scheme/blob/stack/project-target-dependencies-20261024/doc/artifact-bundles.md)
describes the compiler boundary and cache rules. The native driver
now uses typed request/reply datums for generated libraries and artifact inputs,
with exclusive scratch ownership across compiler restarts. Stderr is only
diagnostic text.

`lofi dev PROJECT` would keep the incremental compiler alive and share one
file watcher with the editor. Saving only writes disk; the watcher starts
compilation regardless of whether the writer was this editor, another tool
or an agent. Each build attempt publishes a fresh diagnostic collection while
retaining valid compiler caches. Unsaved buffers stay in the editor.

Applications run as ordinary subprocesses. Today's `watch` restarts them
after a successful build. The proposal requires preserving server records
in durable typed tables and deriving working data through cached views.
Views recompute on demand, with no application `resume` method. The detailed
state API remains under review; durable writes and view recomputation must
be measured independently of incremental compilation.
The proposed `serve` command is for production, without development watching;
`build` remains a one-shot command. See the [terms](terms.md#toolchain-terms)
for the distinction between incremental compilation, restart and hot reload.

## Loading code while a program runs

`(lofi wasm)` loads a WebAssembly module from a file, linked against the
program's own modules, and takes the functions it exports. They arrive
untyped, as a `Funcref`, and `unsafe-cast` makes one a function of the
type its context expects:

```scheme
(import
 (lofi base)
 (lofi io)
 (lofi wasm))

(let* ((module (load-module "adder" "adder.wasm"))
       (add (ann (unsafe-cast (module-export module "add")) (-> I64 I64 I64))))
  (display (add 40 2)))
```

Nothing checks the Lofi type. WebAssembly traps if the function's own
type differs from the one Lofi gives `(-> I64 I64 I64)`, and the program
ends. The Node runner provides the `wasm` effect; browser hosts do not
yet.

[The toolchain design](https://github.com/tsnl/snail-scheme/blob/main/doc/toolchain.md)
explains separate compilation, the recursion groups that let WebAssembly
types match across modules, and what is left to build.
