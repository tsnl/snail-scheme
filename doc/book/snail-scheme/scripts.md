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
| `(entry ((lib) Type))` and the `Application` class | Top-level statements in the script |
| `(runtime toolchain)` | The `assembler` capability, handled by the target |
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

A script is a `.scm` file. It imports libraries and runs its statements in order.
It has no `main` function and declares no entry type.

```scheme
(import (snail core base) (snail core io) (apps fibonacci))
(write-string (number->string (fibonacci 30)))
(newline)
```

The script's statements are checked like a function body. Their inferred effect
row is the program's: nothing is declared. Libraries keep their rule that loading
runs no initializer. Only a script has statements.

A GUI program is an ordinary script that hands control to a library's event loop,
in the style of Rust's [winit](https://github.com/rust-windowing/winit): it
builds a handler, a record of functions, and calls `(run-scene handler)` as a
statement. Such libraries are conveniences, not part of the language or the
toolchain.

On the page a statement cannot block, so the script's top level runs as the
scheduler's first task, and `run-scene` waits for events through the task
effect ([application model](applications.md)).

## Targets and capabilities

Each build names its runtime target explicitly, with `--target`, such as
`--target node` or `--target browser`. Nothing infers a target.

What a platform offers is split into capability effects, one for each service,
such as `output-port`, `input-port`, the page's document, sockets or processes.
There is no marker effect for a platform as a whole.

An entry's inferred effect row, the script's or an exposed function's, is
what it requires, as a dependency-injection interface: nothing in the program
handles those effects. A target is a library of handlers, one for each
capability it provides, `(snail target node)` for instance, and the build
injects them into every entry, as evidence passed to it, so the script
performs `write-string` and the target's `output-port` handler answers. Any
effect left in the row after those handlers is a build error naming each
capability the target lacks. An effect the program handles itself, such as
the compiler's `compile`, never reaches the target.

The handlers answer by calling the host through `extern` imports. An
extern's type is its library author's claim, trusted as written, and calling
one needs no effect: a file or socket extern is declared as a plain function,
and its library keeps it behind the capability's handler, so code outside
sees only `fs` or `tcp`. Building a sensible abstraction over its externs is
the library's job. The foreign functions that were pure, the math functions,
Unicode tables and float printing, have moved into `snail-scheme` code.

Code meant for several targets asks only for the capabilities it uses. A library
that writes text needs `output-port`, not "Node", so any target whose handlers
include an output port can run it. A capability's library declares only the
effect and its operations; how a target answers them belongs to the target's
handlers, not to a `default` in the library.

There are three hosts' targets, and one they share, each a library under
`src/snail/target/`:

- `portable`, the capabilities every host has, on which the others build;
- `node`, the program on Node (`host/native`), the `wasmtime` target's
  capabilities and Node's own;
- `wasmtime`, the program on the native executable `build/snail run-wasm`
  (`crates/snail`), the portable ones and the local machine's;
- `browser`, the program in a page (`host/browser`), the portable ones and
  the page's.

A target exports `provide`, which runs a thunk under its handlers, and
`start`, which runs `main` as the first task of the host's scheduler inside
`provide`. A capability's library exports the handler that answers it on
the host, such as `provide-fs` in `(snail core io)`, and a target's
`provide` installs those it has.

| Capability | Library | `portable` | `node` | `wasmtime` | `browser` |
| --- | --- | --- | --- | --- | --- |
| `output-port` | `(snail core io)` | stdout | stdout | stdout | the console |
| `clock` | `(snail core io)` | ✓ | ✓ | ✓ | ✓ |
| `resource` | `(snail shell resource)` | ✓ | ✓ | ✓ | ✓ |
| `wasm` | `(snail shell wasm)` | ✓ | ✓ | ✓ | ✓ |
| `tasks` | `(snail shell task)` | ✓ | ✓ | ✓ | ✓ |
| `input-port` | `(snail core io)` | — | stdin | stdin | — |
| `fs` | `(snail core io)` | — | ✓ | ✓ | — |
| `files` | `(snail shell async-files)` | — | ✓ | ✓ | — |
| `process`, `signals` | `(snail shell process)` | — | ✓ | — | — |
| `tcp`, `udp` | `(snail shell socket)` | — | ✓ | — | — |
| `dom` | `(snail shell dom)` | — | — | — | ✓ |
| `page`, `events`, `storage` | `(snail shell page)` | — | — | — | ✓ |
| `fetch` | `(snail shell fetch)` | — | — | — | ✓ |
| `screen` | `(snail shell app)` | — | — | — | ✓ |
| `assembler` | `(snail shell assembler)` | — | ✓ | ✓ | — |

Every capability in the table but `dom`, `fetch` and `assembler` is
answered by its target's handlers. The page's interface installs `dom` and
`fetch` itself, with `with-page-dom` and `with-page-fetch`
(`(snail shell ui page)`), and a tool installs its assembler.

The table states the rule the build checks, so changing what a host provides
means changing this table and the target's handlers together. It replaces
today's trapping stand-ins: a program that uses `tcp` fails to build for
`wasmtime` instead of trapping when it connects.

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
  does, then runs it. Its output stays on disk, so a failure can be diagnosed, and
  future caching needs no new path.
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
Node, `build/snail run-wasm` and a page each run it directly. The output
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

Each step is a pull request that passes every check on its own.

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
     Under `SNAIL_ENGINE=wasmtime` a test program builds for `wasmtime`
     unless stage 0's `node-programs` names it.
   - The page's capabilities move into `browser`: done. `events`,
     `storage` and `screen` have no `default`, and `browser` installs
     `provide-events`, `provide-storage` and `provide-screen`. Stage 0's
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
