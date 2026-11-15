# Proposed scripts and builds without `project.datum`

**Design proposal for review; not implemented.** The [project chapter](projects.md)
describes what ships today. This chapter takes the cheapest path to the end
state: `snail-scheme` behaves like an interpreter first and a compiler second.

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
| `artifact-bundle`, the planner (`project/plan.sld`) | A `generate-library` producer that calls the compiler |
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
builds a handler, a record of functions, and calls `(run-app handler)` as a
statement. Such libraries are conveniences, not part of the language or the
toolchain.

**To prototype first:** on the page a statement cannot block. The browser host
already drives the application's loop as a task, so the script's top level runs
as a task, and `run-app` waits for events through the task effect. Siegework is
the prototype.

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

The handlers answer by calling the host: every `extern` declares
`unsafe-extern`, a marker effect with no operations, in its type, so no
foreign call looks pure. It is the one effect the runtime itself provides.
The handful of foreign functions that are pure today, the math functions,
Unicode tables and float printing, move into `snail-scheme` code first, so no
declaration claims purity across the boundary.

Code meant for several targets asks only for the capabilities it uses. A library
that writes text needs `output-port`, not "Node", so any target whose handlers
include an output port can run it. A capability's library declares only the
effect and its operations; how a target answers them belongs to the target's
handlers, not to a `default` in the library.

There are three targets:

- `node`, the program on Node (`host/native`);
- `wasmtime`, the program on the native executable `build/snail run-wasm`
  (`crates/snail`);
- `browser`, the program in a page (`host/browser`).

| Capability | Library | `node` | `wasmtime` | `browser` |
| --- | --- | --- | --- | --- |
| `output-port` | `(snail core io)` | stdout | stdout | the console |
| `input-port` | `(snail core io)` | stdin | stdin | — |
| `fs` | `(snail core io)` | ✓ | ✓ | — |
| `clock` | `(snail core io)` | ✓ | ✓ | ✓ |
| `tasks` | `(snail shell task)` | ✓ | ✓ | ✓ |
| `resource` | `(snail shell resource)` | ✓ | ✓ | ✓ |
| `wasm` | `(snail shell wasm)` | ✓ | ✓ | ✓ |
| `files` | `(snail shell async-files)` | ✓ | ✓ | — |
| `process`, `signals` | `(snail shell process)` | ✓ | — | — |
| `tcp`, `udp` | `(snail shell socket)` | ✓ | — | — |
| `dom` | `(snail shell dom)` | — | — | ✓ |
| `page`, `events`, `storage` | `(snail shell page)` | — | — | ✓ |
| `fetch` | `(snail shell fetch)` | — | — | ✓ |
| `screen` | `(snail shell app)` | — | — | ✓ |
| `assembler` | `(snail shell assembler)` | ✓ | ✓ | — |

The table states the rule the build checks, so changing what a host provides
means changing this table and the target's handlers together. It replaces
today's trapping stand-ins: a program that uses `tcp` fails to build for
`wasmtime` instead of trapping when it connects.

The assembler is a capability too, `assembler`, which `node` and `wasmtime`
provide. Its handler lives in the runtime that includes the assembler's services,
so a script whose row has `assembler` links with that runtime, and any other
links with the smaller one.

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

## Output: modules, a manifest and the store

- **A debug build keeps one module per library,** linked when the program
  starts, with the runtime as an instance of its own.
- **A release build is fully linked:** the runtime and every library fused
  into one module, then optimized with Binaryen's `wasm-opt`, which can
  inline the runtime's functions into the program. Calls into the runtime
  are then ordinary calls.
- **A manifest**, `main.manifest.datum`, names every object the program
  needs by digest and size: `(runtime "DIGEST" SIZE)`, `(module "LIBRARY"
  "DIGEST" SIZE)` for each library in link order, `(file "DIGEST" SIZE)`
  for each linked file.
- **One store**, `build/.snail-store/sha256/ab/abcdef…`, shared by every
  build in the workspace. An object is named for the SHA-256 of its bytes and
  sharded by the first two hex digits. It is written once and never rewritten.

Nothing reclaims the store. Delete `build/` and rebuild from time to time. A
`snail-scheme gc` command can come later if it is needed.

The output folder holds the manifest and a view of the objects it names at
the same paths under its own `store/`: relative links into the store in a debug
build, copies in a release build. The folder can therefore be served or run as
it is, as `python3 -m http.server --directory build/src/apps/siegework/main`
serves a browser program.

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
- Cycle detection across producers.
- `snail-scheme watch` and live reload, removed. They come back only if they are needed.
- Reclaiming the store.

## Delivery

Each step is a pull request that passes every check on its own.

1. **Drop `watch`.** Done: the development service, `development.sld`,
   `(snail shell project bundle)`, the reload client, relinking and file
   watching (`(snail shell watch)`) are gone, with their tests and chapters.
2. **The store and manifests.** Done, with the engine moved into the command
   line, since every program is now linked one library at a time:
   - Every build keeps a module per library, and the `Debug` and `Development`
     modes merge.
   - All builds share the sharded `build/.snail-store/`, and each writes its
     `.manifest.datum`.
   - Targets still come from `project.datum`.
3. **Scripts and `run`/`build FILE`.** Done, but for targets' handlers:
   - Top-level statements, and resolution under the workspace's `src/`.
   - The shared build flags, `--target` and `--release`.
   - The output path comes from the script's path, and the toolchain
     runtime from linking `(snail shell assembler)`.
   - `snailc` and `-o` go; `snail-scheme wat FILE` prints a script's text.
   - Each `--target` supplying its handlers comes in step 5.
4. **Constant arrays, then pure foreign functions in `snail-scheme`.**
   - Constant vectors: done, `(constant-vector TYPE (VALUE ...))`, a table of
     integer-like scalars built once per module from a data segment
     ([types](types.md#constant-vectors)).
   - The math functions, Unicode tables and float printing in `snail-scheme`.
5. **Targets as handler libraries.**
   - `host` becomes `unsafe-extern`, which every `extern` declares.
   - A handler library per target, injected into every entry; a capability
     left unhandled fails the build.
   - `default` and `around-main` go.
6. **Release builds fully linked,** with `wasm-opt` from Binaryen.
7. **Applications become scripts.**
   - Prototype the page's top level as a task.
   - Move Siegework and Hearsay to `src/apps/NAME/main.scm`, with a winit-style
     helper.
   - Remove the `Application` class.
8. **Embedding, then no project file.**
   - Producers call the compiler, and `link-file` is loosened.
   - Port the `artifact-bundle` tests, then delete `artifact.sld`, `plan.sld`,
     `project.sld` and the root `project.datum`.
   - The language server uses the workspace.
