# Development toolchain

Lofi can link a program statically or link its libraries when it starts.
Static builds compile the whole program, optimize it and merge the Rust runtime
into one module. `--release` increases optimization; it does not select linking
mode. Development builds keep each library as its own module, with the runtime
as a separate instance.

| Command | Build |
| --- | --- |
| `lofi build`, `make site`, internal source compile/run | Static; `--release` requests full optimization |
| `lofi dev`, `./scripts/lofi-tool serve`, `./scripts/lofi-tool watch`, `make ide` | Separate development modules |

The public commands operate on projects. Compiler contributors can use
`./scripts/lofi-tool run SOURCE`, `wat SOURCE`, `schema SOURCE` or `bootstrap`.
`./scripts/lofi-tool compile -o FILE SOURCE` writes a raw Wasm file and linker
intermediates; it does not provide project publication guarantees.
Source-level `run` uses a private build directory by default and removes it when
the process finishes.

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
`lofi build` calls it directly and releases its scratch files on completion or
failure. Only development puts the compiler in a worker, to keep its HTTP service
and disk observer responsive during compilation.
It also supports resident callers with a successful compiler Session per target.
Changing a target's entry or library roots starts a fresh Session; an edit within
those inputs uses the compiler's existing incremental checks. Generated-library
producers run again each attempt because they may read files outside their recipe.

Builds return completed private directories before publication. A failed parent
changes none of its dependencies' public outputs. A caller can discard a completed
candidate and still reuse the compiler's successful work: caches retain evidence,
not paths into that candidate. Development directories contain their modules,
manifest and runtime, so they are self-contained. The native project development API now uses this builder in a persistent worker,
shares one disk observer with the file service, and publishes only attempts not
superseded by observed changes. Its loopback HTTP boundary offers file reads and
conditional saves, manual Build and current build/file-change subscriptions.
Save only writes disk; compiler attempts come from observation. The editor uses this service through `lofi dev`; `serve` and `watch` still use
their old application loop until launch/reload integration.

## Builds in proportion to the edit

`./scripts/lofi-tool serve` and `./scripts/lofi-tool watch` run a development loop that is itself a
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

The project development session uses the same execution boundary with shared
file subscriptions, attempt-scoped diagnostics and generation publication.
`serve` and `watch` still have their older publication and watcher policies.

```text
$ ./scripts/lofi-tool serve apps/siegework
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

## The project editor

```text
$ ./lofi dev apps/siegework
editing /path/to/apps/siegework at http://127.0.0.1:8000/
```

Open the printed URL. `--port PORT` selects another port; 0 chooses a free port.
`make ide` starts the same service for Siegework. The native process owns the
compiler and disk files. The browser keeps only open buffers and unsaved edits,
with highlighting, Scheme indentation, format-on-save and split panes.

Save writes disk. One watcher informs both the compiler and editor, so edits made
by agents and other applications take the same path. Clean buffers update;
unsaved buffers retain their text and report a conflict. Reload discards a draft
explicitly. Saving while typing preserves the later typing as unsaved text.
Deleted dirty files remain available to copy, and an empty project is supported.

Every compilation starts with fresh diagnostic messages while keeping valid
compiler caches. Compiler-provided locations open the matching project file and
mark the source point in saved buffers without conflicts. Unsaved drafts suppress
these marks. Generated source and external libraries keep their actual locations
in the message panel. The compiler still stops at its first error. Build requests
compilation explicitly; unsaved edits are never sent to the compiler.

`dev` currently builds and edits. Use existing `serve`/`watch` for application
execution and reload until those move into this service. The editor has no
integrated preview, browser compiler or persistent copy of the project.

## Projects and the remaining application workflow

The [project-description parser](https://github.com/tsnl/snail-scheme/blob/stack/project-forms-20261024/doc/project-format.md)
is implemented as `(lofi project)` for Chibi and Wasm. It returns typed build
descriptions and resolves run targets to program builds, retaining error locations.
Both the one-shot CLI builder and `dev` consume these descriptions. Application
launch/reload integration and the state API below remain proposed.

`project.datum` uses explicit `build-target` and `run-target` forms. It now
replaces the application packaging script for both CLI and IDE builds.
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
now uses typed missing-input records and immutable artifact tables,
with exclusive scratch ownership across retries. Stderr is only
diagnostic text.

`lofi dev PROJECT` keeps the incremental compiler alive and shares one
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
