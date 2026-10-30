# Projects and targets

A project is one directory described by an inert `project.datum`. The file
contains data, not Scheme code. Parsing it performs no file access or build;
the command chooses when to compile and run its named targets.

```scheme
((build-target client
   (browser
    (entry "client/main.sld")
    (library-roots ("client/src"))
    (public "client/public")))
 (build-target server
   (program
    (entry "server/main.sld")
    (library-roots ("server/src" "shared"))))
 (run-target dev
   (run server
    (args ("--port" "8080")))))
```

Build targets describe programs or browser bundles. Run targets name program
builds and their arguments. One server can embed several browser bundles; a
browser bundle is a dependency, not a directly launched process. Applications
supply the server and routes; project metadata does not infer them.

```sh
./snail build --release apps/siegework site
python3 -m http.server 4191 --directory apps/siegework/build/site
./snail dev apps/siegework
```

`snail build [--release] PROJECT BUILD-TARGET` publishes one selected target and
its required artifacts. `snail run PROJECT RUN-TARGET [ARGUMENT ...]` builds and
runs a named program. `snail dev [--port PORT] PROJECT` retains compiler
sessions, serves the editor, and serves each browser target's latest builds
on an origin of their own.
The [toolchain](toolchain.md) describes command lifetimes and development,
including the editor's application controls and the pages' reload. Durable
application data remains in progress.

## Description format

The file contains exactly one proper list of explicit `build-target` and
`run-target` forms. Every field is exactly `(key value)`, including list values
such as `(library-roots ("src" "shared"))` and `(args ())`.

Both build kinds require one literal `entry` path and accept an optional
`library-roots` list. Browser builds also accept an optional `public` directory.
Omitted roots mean an empty list; the toolchain supplies its standard library.
Run targets name a program build and accept an optional `args` list of literal
strings, preserving order and empty strings. Runs may precede their builds.
Configured arguments precede arguments supplied on the command line.

Names use the compiler reader's identifier syntax and must fit one path
component: no separators, colon, NUL, `..` or reserved `.snail-*` names.
Unicode and punctuation such as `café.v2` are allowed. Build and run names have
separate namespaces. Duplicate names within a namespace and duplicate fields
are errors, including repeated empty lists. Unknown forms, unknown fields and
executable metadata are rejected. An empty project list is valid.

Paths are nonempty strings relative to the project directory. They use `/`
separators and reject absolute paths, empty components, `.`/`..` components,
backslashes, colons and NUL. The whole spelling `"."` may name a directory but
cannot be an entry file. This lexical rule is not a filesystem sandbox: parsing
does not resolve symlinks, check existence or read source files.

`(snail shell project)` uses the compiler's located reader on Chibi and Wasm.
`parse-project` takes text and its filename and returns ordered typed build and
run lists. A resolved `RunTarget` contains a `ProgramBuild`; callers need not
recheck its existence or kind. Builds are collected before runs are resolved,
without a separate pending syntax tree. Paths and declarations retain locations;
duplicate target errors identify both declarations, duplicate fields the second.

## Output directories

Each build target produces one directory at `PROJECT/build/TARGET`. A static
program contains `program.wasm`, and each file its libraries link at
`resources/NAME` ([linked files](types.md#linked-files)). A browser build adds the shared browser host
and recursively copies `public`, if specified. Supply `index.html` there; no page
is generated. Browser pages load `./program.wasm` through `host.mjs`, which
fetches the linked files beside it before the program starts, or through
`ui.mjs` for a [document interface](applications.md#document-interfaces).

Public files cannot overwrite generated files. At the root, every name some
build generates is reserved, whether or not this build writes it:
`program.wasm`, `modules`, `modules.json`, `runtime.wasm`, `resources`, the
browser host's files and the `.snail-target` ownership marker. A public tree
that builds in one mode, or with one set of linked files, therefore builds in
every other. `.snail-publish` is reserved at every depth. Public trees must
contain only regular files and directories, include no project build output,
and have no symlink components, including in the path to the public directory.

The public output is a relative symlink to a completed generation beside it.
Rebuilds replace that link atomically after compilation and packaging succeed.
Previous generations remain available to readers: `snail build` reclaims none,
and `snail dev` only those it published once nothing needs them
([observation and acceptance](toolchain.md#observation-and-acceptance)). Resolve the link once before reading several files as one artifact.
An ordinary file, directory or unrelated link at the output path is rejected
and never removed by the builder.

The builder, `(snail shell project build)`, completes every selected target before
returning a private candidate.
Compilation or packaging failure changes no public outputs, including dependencies
already built. Publication checks all destinations and prepares temporary links
before renaming any. Each rename is atomic; several links are not one transaction.
A later rename failure retains the published prefix and removes only unpublished
generations. Publication consumes the candidate even on failure; callers must
not discard it again. These guarantees concern complete outputs, not an atomic
source snapshot or power-loss durability.

Development builds contain per-library modules, `modules.json` and `runtime.wasm`
instead of linked `program.wasm`, with the same `resources/`. Each generation is
self-contained: a linked file is copied into every generation, so editing one
compiles nothing again, yet the next generation holds and reads its new bytes. Existing
browser pages receive the module-manifest meta tag understood by `host.mjs`;
the builder still does not invent a page.

## Artifact bundles

```scheme
(import
 (snail core base)
 (snail shell artifact))

(: frontend ArtifactBundle)
(define frontend (artifact-bundle "client"))

;; A lookup in embedded data, without file IO or a runtime build.
(artifact-ref frontend "index.html")
```

The name must be a literal string naming a browser target in the same project.
The macro constructs an ordinary `ArtifactBundle` containing `ArtifactFile`
records with relative `path` and immutable `bytes`. `artifact-ref` returns
`Option Bytes`; record accessors expose the file list. MIME types, routes and
transport policy belong to serving code. No special backend representation or
runtime artifact service is involved.

Uses arise during expression expansion, including macro uses, generated
libraries and the programs of their producers. An unused macro template makes
no use. Constructor names retain their definition scope, so importing only
the macro, renaming it or shadowing constructors does not change its meaning.

The compiler plans a build before running any of it
(`src/snail/shell/compiler/plan.sld`): a walk of each program's import closure
finds the producers it needs, and a discovery expansion, the expander itself
supplied no files, finds the targets it embeds. There is no source scanner
that a macro could hide a use from. Each target is built once per invocation,
before the first phase that embeds it, and a cycle, such as
`client -> admin -> client`, fails before any phase runs. Generated syntax can
embed a target that only its producer's output names, so a phase that waits
for a producer is planned again once the producer has run, and a cycle it
closes fails then, before anything after it runs. Missing or non-browser
targets fail at the using source point. Standalone source commands and the
older development loop cannot resolve project artifacts.

Packaging and enumeration finish before a generation can supply an artifact.
The inventory contains canonical relative paths sorted by path, including hidden
and nested files but excluding the root `.snail-target` marker. Unreadable
directories, symlinks and nonregular entries are rejected. Inventories name files
in the completed generation directly, never through the replaceable public link.
Repeated uses therefore see the same bytes throughout one invocation.

The compiler takes immutable snapshots of those bytes. Its
[input and cache boundary](compilers.md#compiler-inputs) compares exact evidence
before reusing an expansion; it never rereads backing files during expansion.
Each new project attempt regenerates producer output and obtains current
artifacts. Successful compiler caches may survive a discarded candidate because
they retain evidence rather than paths into its output directory.
