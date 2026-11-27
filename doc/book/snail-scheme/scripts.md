# Scripts and targets

A script is a source file that defines `main`, and a target is what runs
it. `snail-scheme` behaves like an interpreter first and a compiler second:

```sh
./snail-scheme run --target node examples/fibonacci.sld
./snail-scheme build --target browser --release src/apps/siegework/main.scm
```

The command line names the script and target platform.
[Workspaces and builds](projects.md) describes the output and how one build
embeds another.

## The workspace

The nearest ancestor with `snail-scheme-workspace.datum` is the script's
workspace. Each workspace may extend one local base. Their `src/` directories
form a single library tree for builds and editor checks. Standalone trees
without a declaration use the nearest `src/` and the standard libraries.

A script may sit anywhere in the workspace. Since imports resolve under `src/`,
an application keeps its script beside its libraries:
`src/apps/siegework/main.scm` imports most of its code from
`(apps siegework ...)`.

## Scripts

A script is a source file anywhere in the workspace. It imports libraries
and defines `main`, its entry, whose parameters are the capabilities it
asks its target for, as `examples/fibonacci.sld` does:

```scheme
{{#include ../../../examples/fibonacci.sld}}
```

A top level holds definitions alone, a script's as a library's: nothing
runs when a library loads, and what runs when a program starts is its
`main`. A top-level statement would have nothing to write to, since a
program is handed each capability it uses, so the parameters of `main` are
where a program says what it needs.

A GUI program is an ordinary script that hands control to a library's event
loop, in the style of Rust's [winit](https://github.com/rust-windowing/winit):
its `main` builds a handler, a record of functions, and calls
`(run-scene dom events storage handler)`. Such libraries are
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
| `Web` | `(snail shell web)` |

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
- `snail-scheme lsp` serves an editor ([the language server](toolchain.md#the-language-server)),
  and `snail-scheme format` formats standard input onto standard output.

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
That is the modes' one difference.

## Linked files

`link-file` takes a path relative to its library, `..` included, or an
absolute one, so a library may link a producer's output. Every build
places each linked file in the workspace's store, named by its digest, and
the generation's `store/` holds another name for it, as above
([linked files](types.md#linked-files)). Browser programs reuse the linked bytes from an origin-wide Cache Storage cache keyed by SHA-256. A fresh build can reuse every digest it shares with a previous build. HTML and the executable still load on navigation so the page can discover the current build.

A program that serves another, such as a server shipping its browser
client, embeds that build through a generated library whose producer builds
it ([embedding a build](projects.md#embedding-a-build)). A producer that
imports the compiler compiles the compiler on every build; that is accepted
for now.

## Static resource catalogs

Put the files a script publishes in a directory beside it with the same stem, for example `main.resources/maps/city.bin` beside `main.scm`. Both browser and Node builds publish `resources.json` and `store/sha256/AB/DIGEST`. The catalog maps each relative name to its SHA-256 and byte length. Files with identical contents share one object. The directory may contain regular files and subdirectories. Changes to its contents update the catalog without adding imports to the client’s Wasm.

Serve the generation under any URL prefix. Keep the catalog revalidatable and give the digest URLs a long immutable cache lifetime. A Snail server can link the generation using `(snail shell project embed)` and mount its catalog with `(snail shell static-resource serve)`. A browser uses `(snail shell static-resource)` to request the catalog and acquire files. [Resource libraries](../libraries/system.md#snail-shell-static-resource)

## Not yet

- Reuse between builds, and sharing work between a producer and its consumer.
- `snail-scheme watch` and live reload, removed; they come back only if they
  are needed.
- Reclaiming the store.
