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
./lofi build --release apps/siegework site
python3 -m http.server 4191 --directory apps/siegework/build/site
./lofi check apps/siegework
./lofi dev apps/siegework
```

`lofi build [--release] PROJECT BUILD-TARGET` publishes one selected target and
its required artifacts. `lofi run PROJECT RUN-TARGET [ARGUMENT ...]` builds and
runs a named program. `lofi check PROJECT` checks all declared entries.
`lofi dev [--port PORT] PROJECT` retains compiler sessions and serves the editor.
The [toolchain](toolchain.md) describes command lifetimes, checking and development,
including the HTTP run controls. Editor controls, durable application data and
browser reload integration remain in progress.

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
component: no separators, colon, NUL, `..` or reserved `.lofi-*` names.
Unicode and punctuation such as `café.v2` are allowed. Build and run names have
separate namespaces. Duplicate names within a namespace and duplicate fields
are errors, including repeated empty lists. Unknown forms, unknown fields and
executable metadata are rejected. An empty project list is valid.

Paths are nonempty strings relative to the project directory. They use `/`
separators and reject absolute paths, empty components, `.`/`..` components,
backslashes, colons and NUL. The whole spelling `"."` may name a directory but
cannot be an entry file. This lexical rule is not a filesystem sandbox: parsing
does not resolve symlinks, check existence or read source files.

`(lofi project)` uses the compiler's located reader on Chibi and Wasm.
`parse-project` takes text and its filename and returns ordered typed build and
run lists. A resolved `RunTarget` contains a `ProgramBuild`; callers need not
recheck its existence or kind. Builds are collected before runs are resolved,
without a separate pending syntax tree. Paths and declarations retain locations;
duplicate target errors identify both declarations, duplicate fields the second.

## Output directories

Each build target produces one directory at `PROJECT/build/TARGET`. A static
program contains `program.wasm`. A browser build adds the shared browser host
and recursively copies `public`, if specified. Supply `index.html` there; no page
is generated. Browser pages load `./program.wasm` through `host.mjs`.

Public files cannot overwrite generated files or the root `.lofi-target`
ownership marker. `.lofi-publish` is reserved at every depth. Public trees must
contain only regular files and directories, include no project build output,
and have no symlink components, including in the path to the public directory.

The public output is a relative symlink to a completed generation beside it.
Rebuilds replace that link atomically after compilation and packaging succeed.
Previous generations remain available to readers; automatic reclamation is not
implemented. Resolve the link once before reading several files as one artifact.
An ordinary file, directory or unrelated link at the output path is rejected
and never removed by the builder.

The builder completes every selected target before returning a private candidate.
Compilation or packaging failure changes no public outputs, including dependencies
already built. Publication checks all destinations and prepares temporary links
before renaming any. Each rename is atomic; several links are not one transaction.
A later rename failure retains the published prefix and removes only unpublished
generations. Publication consumes the candidate even on failure; callers must
not discard it again. These guarantees concern complete outputs, not an atomic
source snapshot or power-loss durability.

Development builds contain per-library modules, `modules.json` and `runtime.wasm`
instead of linked `program.wasm`. Each generation is self-contained. Existing
browser pages receive the module-manifest meta tag understood by `host.mjs`;
the builder still does not invent a page.

## Artifact bundles

```scheme
(import
 (lofi base)
 (lofi artifact))

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

Requests arise during expression expansion, including macro uses, generated
libraries and compilation of their producers. An unused macro template makes
no request. Constructor names retain their definition scope, so importing only
the macro, renaming it or shadowing constructors does not change its meaning.

The builder discovers dependencies from these requests. It traverses serially,
reuses completed targets within one invocation and reports an active target as
a cycle, such as `client -> admin -> client`. Missing or non-browser targets
fail at the requesting source point. There is no source scanner or second
dependency graph. Standalone source commands and the older development loop
cannot resolve project artifacts.

Packaging and enumeration finish before a generation can supply an artifact.
The inventory contains canonical relative paths sorted by path, including hidden
and nested files but excluding the root `.lofi-target` marker. Unreadable
directories, symlinks and nonregular entries are rejected. Inventories name files
in the completed generation directly, never through the replaceable public link.
Repeated requests therefore use the same bytes throughout one invocation.

The compiler takes immutable snapshots of those bytes. Its
[input and cache boundary](compilers.md#compiler-inputs) compares exact evidence
before reusing an expansion; it never rereads backing files during expansion.
Each new project attempt regenerates producer output and obtains current
artifacts. Successful compiler caches may survive a discarded candidate because
they retain evidence rather than paths into its output directory.
