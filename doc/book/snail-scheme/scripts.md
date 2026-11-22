# Scripts and builds without `project.datum`

**Implemented, but for the steps still open below.** The
[builds chapter](projects.md) describes what ships. This chapter took the
cheapest path to the end state: `snail-scheme` behaves like an interpreter
first and a compiler second.

```sh
./snail-scheme run --target node src/apps/fibonacci/main.scm
./snail-scheme build --target browser --release src/apps/siegework/main.scm
```

There is no project file, no target registry, no planner and no development
service. Performance work, such as reuse between builds, waits until
measurements ask for it.

## What goes

| Today | Replaced by |
| --- | --- |
| `project.datum`, `(snail shell project)` | A script's path on the command line |
| Build and run targets, `args` | The script, and arguments on the command line |
| `library-roots` | The workspace's `src/` |
| `(entry ((lib) Type))` and the `Application` class | The script's `main` |
| `(runtime toolchain)` | The runtime a script that imports `(snail shell assembler)` links with |
| `artifact-bundle`, the planner (`project/plan.sld`) | A `generate-library` producer that builds a script (removed) |
| `snail-scheme watch`, the reload client, relinking | Nothing, for now (removed) |
| `snailc`, `-o` | `snail-scheme run FILE` and `build FILE` |

## The workspace

A workspace is a folder that contains `src/`. Every library lives under `src/`,
at the path its name gives, and every import resolves there. That is the whole
rule. It is built for this repository's monorepo and nothing more. The editor's
open folder is the workspace the language server uses.

A script may sit anywhere in the workspace. Since imports resolve under `src/`,
an application keeps its script beside its libraries:
`src/apps/siegework/main.scm` imports most of its code from
`(apps siegework ...)`.

## Scripts

A script is a `.scm` file. It imports libraries and defines `main`, its
entry, whose parameters are the capabilities it asks its target for:

```scheme
(import (snail core base) (snail core io) (apps fibonacci))

(define (main (out OutputPort)) (→ Unit)
  (write-line out (number->string (fibonacci 30))))
```

A top level holds definitions alone, a script's as a library's: nothing
runs when a library loads, and what runs when a program starts is its
`main`. A script once ran its top-level statements instead; a statement
has nothing to write to, now that a program is handed each capability it
uses, so the parameters of `main` are where a program says what it needs.

A GUI program is an ordinary script that hands control to a library's event
loop, in the style of Rust's [winit](https://github.com/rust-windowing/winit):
its `main` builds a handler, a record of functions, and calls
`(run-scene gpu events storage clock handler)`. Such libraries are
conveniences, not part of the language or the toolchain.

On the page a program cannot block, so `main` runs as the scheduler's first
task, and `run-scene` waits for events as a task does
([application model](applications.md)).

## Targets and capabilities

Each build names its runtime target explicitly, with `--target`, such as
`--target node` or `--target browser`. Nothing infers a target.

What a platform offers is split into capabilities, one value for each
service: an output port, an input port, the page's document, sockets,
processes. There is no marker for a platform as a whole, and no object
that holds everything a host has.

An entry's parameters, `main`'s or an exposed function's, are what it
requires, as a dependency-injection interface. A target is a library,
`(snail target node)` for instance, and provides a type by exporting a
function of no parameters that answers it. The build calls each entry with
what the providers of its parameters' types answer. A parameter of `main`
whose type the target does not provide is a build error naming it
([capabilities](capabilities.md#main-asks-its-target)).

The host's capabilities answer by calling the host through `extern`
imports. An extern's type is its library author's claim, trusted as
written: a file or socket extern is declared as a plain function, and its
library keeps it behind the capability, so code outside reaches the host's
files only through an `Fs`. Building a sensible abstraction over its
externs is the library's job. The foreign functions that were pure, the
math functions, Unicode tables and float printing, have moved into
`snail-scheme` code.

Code meant for several targets asks only for the capabilities it uses. A
library that writes text takes an `OutputPort`, not "Node", so any target
that provides one can run it. A capability's library declares the type and
the function that makes the host's; whether a target provides it belongs to
the target.

There are two targets, each a library under `src/snail/target/`:

- `node`, the program on Node (`host/native`);
- `browser`, the program in a page (`host/browser`).

A target exports its providers and `start`, which runs `main` as the first
task of the host's scheduler.

Capabilities fall into three groups. The portable subset is what both
targets provide, and what a target for another host, such as
[workerd](https://github.com/cloudflare/workerd), would provide too; a
library that asks only for these runs anywhere.

| Portable capability | Library | On Node | In a page |
| --- | --- | --- | --- |
| `Host` | `(snail core io)` | makes any capability below | makes any capability below |
| `Arguments`, `ProcessEnvironment` | `(snail core io)` | the command line, variables and working directory | none, and no working directory |
| `OutputPort` | `(snail core io)` | standard output | the console |
| `Clock` | `(snail core io)` | the monotonic clock | the monotonic clock |
| `Resources` | `(snail shell resource)` | files beside the module | files fetched beside the module |
| `Wasm` | `(snail shell wasm)` | Node's WebAssembly | the page's WebAssembly |

Tasks need no capability: any code may wait
([suspension](suspension.md), [tasks](../runtimes/tasks.md)).

Node adds the local machine:

| Node's capability | Library |
| --- | --- |
| `InputPort` | `(snail core io)`, standard input |
| `Fs` | `(snail core io)` |
| `Files` | `(snail shell async-files)` |
| `Processes`, `Signals` | `(snail shell process)` |
| `Tcp`, `Udp` | `(snail shell socket)` |

A page adds itself:

| The page's capability | Library |
| --- | --- |
| `Events`, `PageStorage` | `(snail shell page)` |
| `Gpu` | `(snail shell gpu)` |
| `Dom` | `(snail shell dom)` |
| `Fetch` | `(snail shell fetch)` |
| `FilePicker` | `(snail shell files)` |

A program on Node that draws asks for the `Host` and makes its `Gpu` from
it, with `host-gpu`, so one that draws nothing links no device
([`Host`](capabilities.md#host)).

The tables state the rule the build checks, so changing what a host
provides means changing them and the target together: a program that asks
for `Tcp` fails to build for `browser` instead of trapping when it
connects.

A script that imports `(snail shell assembler)` links with the runtime that
includes the assembler's services, and any other links with the smaller one.
Assembling is deterministic, so it is no capability.

## Commands

Every command that builds takes the same build flags, parsed in one place and
documented once:

- `--target TARGET`, required: the runtime target.
- `--release`: a release build. Without it, the build is a debug build.

The commands:

- `snail-scheme build FLAGS FILE` builds `FILE`.
- `snail-scheme run FLAGS FILE [ARGUMENT ...]` builds `FILE` exactly as `build`
  does, then runs it on Node. Its output stays on disk, so a failure can be
  diagnosed, and future caching needs no new path.
- `snail-scheme lsp` and `snail-scheme format` are unchanged.

A producer that calls the compiler passes the same flags, as a record, so a
build embedded through a generated library is configured the way the command
line configures one.

No command takes an output path. A build of `src/apps/siegework/main.scm` writes
under `build/src/apps/siegework/main`, the script's path without its extension.
That path cannot collide, and it is stable, which is what future caching needs.

## Output: one linked module

Every build is fully linked: the whole program compiled as one module and
fused with the runtime, `main.wasm`, with the files it links under
`store/sha256/ab/abcdef…`, each named for the SHA-256 of its bytes. Each
is a hard link to the one copy in the workspace's store,
`build/.snail-store`, which every build of every script shares.
Node and a page each run it directly. The output
folder can be served or run as it is, as `python3 -m http.server
--directory build/src/apps/siegework/main` serves a browser program.

A release build, `--release`, also optimizes the module with Binaryen's
`wasm-opt -O2`, which can inline the runtime's functions into the program.
That is the modes' one difference: a debug build was once a module per
library with a manifest, kept for relinking a running page, and went when
reload did.

## Linked files

`link-file` loses its path restrictions. A path may leave the library's
directory, including into a producer's output.

- Every build places the linked file in the store, and the manifest names its
  digest; a debug build's view links to it, a release build's copies it.

## Embedding another build

A program that serves another, such as a server shipping a browser client,
embeds it through a generated library:

1. The `generate-library` producer calls the compiler as an ordinary function,
   `(snail shell compiler)` linked into the producer.
2. The producer arranges the outputs it wants. Marshaling a page's `public`
   files is the consumer's job, done here.
3. The generated library `link-file`s those outputs and exports accessors to them.

Each call of the compiler function prints a line to stderr naming what it
compiles. A producer that embeds itself, directly or not, recurses, and that line
makes the loop evident to whoever runs the build. Detecting the cycle needs
shared state across these processes, which is future work.

A producer that imports the compiler compiles the compiler on every build.
That is accepted for now.

## Deferred

- Reuse between builds, and sharing work between a producer and its consumer.
- `snail-scheme watch` and live reload, removed. They come back only if they are needed.
- Reclaiming the store.

## Delivery

Each step is a pull request that passes every check on its own. The steps
record how the build got here, in the terms of their time: a script then
ran its top-level statements, and a target was a library of effect
handlers. A script's entry is now its `main`, a target provides
capabilities as values, and rows are gone
([#877](https://github.com/tsnl/snail-scheme/issues/877),
[capabilities](capabilities.md#capabilities)).

1. **Drop `watch`.** Done: the development service, `development.sld`,
   `(snail shell project bundle)`, the reload client, relinking and file
   watching (`(snail shell watch)`) are gone, with their tests and chapters.
2. **The store and manifests.** Done, and since replaced: every build is
   one linked module, and the engine that linked per-library programs is
   gone.
   - Every build kept a module per library, and the `Debug` and `Development`
     modes merged.
   - All builds shared the sharded `build/.snail-store/`, and each wrote its
     `.manifest.datum`.
   - Targets still come from `project.datum`.
3. **Scripts and `run`/`build FILE`.** Done, but for targets' handlers:
   - Top-level statements, and resolution under the workspace's `src/`.
   - The shared build flags, `--target` and `--release`.
   - The output path comes from the script's path, and the toolchain
     runtime from linking `(snail shell assembler)`.
   - `snailc` and `-o` go; `snail-scheme wat --target TARGET FILE` prints a script's text.
   - Each `--target` supplying its handlers comes in step 5.
4. **Constant arrays, then pure foreign functions in `snail-scheme`.** Done:
   - Constant arrays: done, `(constant-array TYPE (VALUE ...))`, a table of
     integer-like scalars built once per module from a data segment
     ([types](types.md#constant-arrays)).
   - The Unicode tables: done, `(snail shell text unicode)`, generated by
     `make unicode-tables`.
   - The math functions: done, `(snail shell math)`, ported from fdlibm.
   - Float printing: done, in `(snail core base)`. Nothing parsed reals at
     run time, so the runtime's parser is gone.
5. **Targets as handler libraries.**
   - The target reaches every compile: done. `--target NAME` names the
     library `(snail target NAME)`, and the program's entry starts `main`
     under its `provide`, which handles nothing yet. A `project.datum`
     program builds for `node`, a browser target for `browser`, and stage 0
     compiles for `node`.
   - Tasks from the target: done. The entry's start takes the host's
     scheduler and calls the target's `start`, which runs `main` as its
     first task inside `provide`. Every host calls `main(scheduler)` and
     then turns; `around-main`, `tasks:start-main` and `engine:status` are
     gone, and `main`'s result is no longer a status.
   - The portable capabilities move into the targets: done. `output-port`,
     `input-port`, `fs`, `clock`, `files`, `resource` and `wasm` have no
     `default`; their libraries export `provide-NAME` handlers, and the
     targets install them. The root program's exposed functions run inside
     `provide` too, through a wrapper, unless a signature shows only `mut`
     and `host`; a library's own exposures run unwrapped. Stage 0 builds a
     test for another target with `program->wat-for`.
   - Node's capabilities move into `node`: done. `process`, `signals`,
     `tcp` and `udp` have no `default`, and `node` installs
     `provide-process`, `provide-signals`, `provide-tcp` and `provide-udp`.
   - The page's capabilities move into `browser`: done. `events`,
     `storage` and `gpu` have no `default`, and `browser` installs
     `provide-events`, `provide-storage` and `provide-gpu`. Stage 0's
     `browser-programs` names the tests that build for it.
   - `default` goes, and a capability left unhandled fails the build: done.
     An effect declares only its operations. What a host calls, `main`'s
     start and each exposed function, may leave only `mut` and `host`
     unhandled, and anything else is an error naming the effect; an
     operation that reaches no handler at run time panics.
   - Externs keep the types their libraries declare: no `unsafe-extern`.
     A capability's handler is the abstraction around its externs, and
     `host` stays the builtin row of the entry and the scheduler.
6. **Release builds fully linked,** with `wasm-opt` from Binaryen: done.
   `--release` writes `NAME.wasm` and copies of its linked files. The
   page's `load.mjs` links such a module with `linkModule`, and producers
   share the linking. Siegework's release module is 190 KB.
7. **Applications become scripts.**
   - Siegework and Hearsay move to `src/apps/NAME/`: done. Their libraries
     are `(apps NAME ...)` and their tests are in `tests/NAME/`.
   - Each becomes `src/apps/NAME/main.scm`, with a winit-style helper:
     done. A script hands `run-scene` a `SceneHandler`, or `run-interface`
     an `InterfaceHandler`, and the page calls its `main` like every host.
   - The `Application` class goes: done, with `(entry ((lib) Type))`,
     `define-page-entry` and the page's in-memory checkpoint. A trap ends
     the page, which keeps its last save.
8. **Embedding, then no project file.**
   - Producers build scripts, and `link-file` takes `..` and absolute
     paths: done. A producer calls `build-script` and links the files of
     the generation it answers; a build runs each producer its compile
     asks for and compiles again. `artifact.sld`, `plan.sld` and the
     compiler's `Inputs` are gone.
   - `project.sld` and the root `project.datum` go: done, with the
     project forms of `build` and `run`; highlight-book is a script.
   - The language server uses the workspace: done. It checks each open
     script, a page when a `public/` folder is beside it and Node
     otherwise, and each open library as the program that imports it.
