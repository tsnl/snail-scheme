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
| `(runtime toolchain)` | `--target`, checked against the script's capability effects |
| `artifact-bundle`, the planner (`project/plan.sld`) | A `generate-library` producer that calls the compiler |
| `snail-scheme watch`, the reload client, relinking | Nothing, for now |
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
There is no marker effect for a platform as a whole. A target provides a set of
capabilities. The effect row the checker infers for the script must fit within
that set, or the build fails and names each capability the target lacks. A script
whose row uses the assembler's services links with the toolchain runtime.

Code meant for several targets asks only for the capabilities it uses. A library
that writes text needs `output-port`, not "Node", so any target that provides an
output port can run it. The exact set of capability effects, and which target
provides which, are still to be decided.

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

Every build has the same shape, debug or release:

- **One module per library.** Debug and release both keep a module for each
  library. Caching then works the same way in both. A release ships several
  files in any case.
- **A manifest**, `main.manifest.datum`, naming every file the program needs:
  its modules in link order, the runtime, and each linked file. Each entry gives
  a path and the object's digest.
- **One store**, `build/store/sha256/ab/abcdef…`, shared by every build in the
  workspace. An object is named for the SHA-256 of its bytes and sharded by the
  first two hex digits. It is written once and never rewritten.

Nothing reclaims the store. Delete `build/` and rebuild from time to time. A
`snail-scheme gc` command can come later if it is needed.

The output folder holds the manifest and a view of it: each path the manifest
names is a relative symbolic link to its object in the store, or, for a debug
build's linked file, to the file itself. The folder can therefore be served or
run as it is, as `python3 -m http.server --directory build/src/apps/siegework/main`
serves a browser program. The manifest is the record; the links are derived
from it and rewritten by each build.

## Linked files

`link-file` loses its path restrictions. A path may leave the library's
directory, including into a producer's output.

- In a release build, the linked file is copied into the store, and the manifest
  names its digest.
- In a debug build, the manifest gives the file's own path. A copy-on-write copy
  would be better, later.

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
- `snail-scheme watch` and live reload. They come back only if they are needed.
- Reclaiming the store.

## Delivery

Each step is a pull request that passes every check on its own.

1. **Drop `watch`.** Remove the development service, `development.sld`,
   `(snail shell project bundle)`, the reload client and `relinkProgram`, with
   their tests and chapters.
2. **The store and manifests.**
   - Every build keeps a module per library, and the `Debug` and `Development`
     modes merge.
   - All builds share the sharded `build/store/`, and each writes its
     `.manifest.datum`.
   - Targets still come from `project.datum`.
3. **Scripts and `run`/`build FILE`.**
   - Top-level statements, and resolution under `src/`.
   - The shared build flags, with `--target` checked against the capability
     effects the script uses.
   - The output path comes from the script's path.
   - `snailc` and `-o` go.
4. **Applications become scripts.**
   - Prototype the page's top level as a task.
   - Move Siegework and Hearsay to `src/apps/NAME/main.scm`, with a winit-style
     helper.
   - Remove the `Application` class.
5. **Embedding, then no project file.**
   - Producers call the compiler, and `link-file` is loosened.
   - Port the `artifact-bundle` tests, then delete `artifact.sld`, `plan.sld`,
     `project.sld` and the root `project.datum`.
   - The language server uses the workspace.
