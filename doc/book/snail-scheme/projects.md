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

`snail-scheme` uses one root `project.datum` for the whole repository, whose
one target builds the book's highlighter. The applications are scripts
([application model](applications.md)), built without it:

```sh
./snail-scheme build --release --target browser src/apps/siegework/main.scm
python3 -m http.server 4191 --directory build/src/apps/siegework/main
```

An editor opening the root runs `snail-scheme lsp` over the same project
([editors](toolchain.md#editors)). Test fixtures retain their own projects.

A single script needs no project:
`snail-scheme build --target node FILE` builds it ([scripts](scripts.md)).
`snail-scheme build [--release] PROJECT BUILD-TARGET` publishes one selected target and
its required artifacts. `snail-scheme run PROJECT RUN-TARGET [ARGUMENT ...]` builds and
runs a named program, and `snail-scheme lsp` answers an editor for the project it
opens. The [toolchain](toolchain.md) describes command lifetimes. Durable
application data remains in progress.

## Description format

The file contains exactly one proper list of explicit `build-target` and
`run-target` forms. Every field is exactly `(key value)`, including list values
such as `(library-roots ("src" "shared"))` and `(args ())`.

Both build kinds require one `entry`, a source path string.

Both kinds accept an optional `library-roots` list. Browser builds also accept an optional `public` directory.
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

`(snail shell project)` uses the compiler's located reader on Chez and Wasm.
`parse-project` takes text and its filename and returns ordered typed build and
run lists. A resolved `RunTarget` contains a `ProgramBuild`; callers need not
recheck its existence or kind. Builds are collected before runs are resolved,
without a separate pending syntax tree. Paths and declarations retain locations;
duplicate target errors identify both declarations, duplicate fields the second.

## Output directories

Each build target produces one directory at `PROJECT/build/TARGET`. In a
debug build every library is compiled to a module of its own. The modules,
the runtime they link with and each file the program links
([linked files](types.md#linked-files)) are objects of the project's
store, `PROJECT/build/.snail-store/sha256/AB/DIGEST`, named for the SHA-256
of their bytes and sharded by its first two hex digits. A build adds only the
objects whose bytes are new; an object is written once and never rewritten,
and nothing reclaims the store: delete it and rebuild from time to time.

A debug directory holds the program's manifest, `TARGET.manifest.datum`, and
a view of the objects it names at the same paths under its own `store/`,
links into the project's store. The manifest is one list of entries:

```scheme
((runtime "DIGEST" SIZE)
 (module "snail.core.base" "DIGEST" SIZE)
 ...
 (file "DIGEST" SIZE))
```

the runtime, each library's module in program order, then each file the
program links. Every host links the program from it: Node and
`build/snail run-wasm` through the engine the command line holds, a page
through `load.mjs`.

A release directory, `--release`, holds one module instead, `TARGET.wasm`:
the whole program compiled as one, fused with its runtime, then optimized
by Binaryen's `wasm-opt -O2`, which can inline the runtime's functions into
the program. Each file the program links is copied into its `store/`, at
the same path, so the directory can be served or shipped on its own. Node
and `build/snail run-wasm` run the module directly, and a page through
`linkModule` in `load.mjs`. `wasm-opt` is found on `PATH`.

A browser build adds the shared browser host and
recursively copies `public`, if specified. Supply `index.html` there; no
page is generated. The builder names the program, the manifest or the
module, in the page, with a
`snail-modules` meta element, which `host.mjs`, or `ui.mjs` for a
[document interface](applications.md#document-interfaces), links the
program from; a linked file is fetched when the program first reads it.

Public files cannot overwrite generated files. At the root, every name the
build generates is reserved: the manifest, the release module, `store`, the browser host's files
and the `.snail-target` ownership marker. `.snail-publish` is reserved at
every depth. Public trees must
contain only regular files and directories, include no project build output,
and have no symlink components, including in the path to the public directory.

The public output is a relative symlink to a completed generation beside it.
Rebuilds replace that link atomically after compilation and packaging succeed.
Previous generations remain available to readers: `snail-scheme build` reclaims none. Resolve the link once before reading several files as one artifact.
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

A build that embeds a generation ([artifact bundles](#artifact-bundles)) gets
its files with the objects of its `store/` view read in, so the embedded
page is complete wherever it is served from.

## Artifact bundles

```scheme
(import
 (snail core base)
 (snail shell artifact))


(define (frontend) (→ ArtifactBundle) (artifact-bundle "client"))

;; A lookup in embedded data, without file IO or a runtime build.
(artifact-ref (frontend) "index.html")
```

The name must be a literal string naming a browser target in the same project.
The macro constructs an ordinary `ArtifactBundle` containing `ArtifactFile`
records with relative `path` and immutable `bytes`. `artifact-ref` returns
`Option Bytes`; field paths expose the file list. MIME types, routes and
transport policy belong to serving code. No special backend representation or
runtime artifact service is involved.

Uses arise during expression expansion, including macro uses, generated
libraries and the programs of their producers. An unused macro template makes
no use. Constructor names retain their definition scope, so importing only
the macro, renaming it or shadowing constructors does not change its meaning.

The project planner orders a build before running any of it
(`src/snail/shell/project/plan.sld`): a walk of each program's import closure
finds the producers it needs, and a discovery expansion, the expander itself
supplied no files, finds the targets it embeds. There is no source scanner
that a macro could hide a use from. Each target is built once per invocation,
before the first phase that embeds it, and a cycle, such as
`client -> admin -> client`, fails before any phase runs. Generated syntax can
embed a target that only its producer's output names, so a phase that waits
for a producer is planned again once the producer has run, and a cycle it
closes fails then, before anything after it runs. Missing or non-browser
targets fail at the using source point. Standalone source commands cannot
resolve project artifacts; use a project build.

Packaging and enumeration finish before a generation can supply an artifact.
The inventory contains canonical relative paths sorted by path, including hidden
and nested files but excluding the root `.snail-target` marker. Unreadable
directories, symlinks and nonregular entries are rejected. Inventories name files
in the completed generation directly, never through the replaceable public link.
Repeated uses therefore see the same bytes throughout one invocation.

The compiler takes snapshots of those bytes through its
[input boundary](compilers.md#compiler-inputs); expansion never rereads backing
files. Each project attempt regenerates producer output, obtains current
artifacts, and checks and emits the complete dependency closure. A discarded
candidate contributes no state to the next compilation.
