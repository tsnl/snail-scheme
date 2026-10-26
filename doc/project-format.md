# Project descriptions

`project.datum` describes one project with inert data. The parser is implemented
in `src/lofi/project.sld` as `(lofi project)` and runs on Chibi and compiled Wasm.
`lofi build [--release] PROJECT TARGET` consumes it and builds one named target.
The same native builder also supports persistent incremental sessions; watcher,
launch and IDE integration follow separately.

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

The file contains exactly one proper list. A build target is a `program` or
`browser` form. Both require one literal `entry` path and accept one optional
`library-roots` list. Browser builds also accept one optional `public` directory.
Omitted roots mean an empty list; the toolchain supplies its standard library.
The description does not execute Scheme or infer application-specific roots.

A run target names a program build and accepts one optional `args` list.
Arguments are literal strings, preserving order and empty strings. Runs may
precede their build declarations. A browser bundle is a dependency served by a
program, not a directly launched process. Environment and working-directory
policies belong to launch integration, not this parser.

Each field is exactly `(key value)`, including list values such as
`(library-roots ("src" "shared"))` and `(args ())`.

Names use the compiler reader's identifier syntax and must fit one path
component: no separators, colon, NUL, `..` or reserved `.lofi-*` names.
Unicode and punctuation such as `café.v2` are allowed. Build and run names occupy
separate namespaces, so a build and run may both be named `dev`. Duplicate names within a namespace and duplicate
options are errors, including repeated empty `args` or `library-roots` lists.
Unknown forms/options and executable metadata are rejected. An empty project
list is valid.

Paths are nonempty strings relative to the project directory. They use `/`
separators and reject absolute paths, empty components, `.`/`..` components,
backslashes, colons and NUL. The whole spelling `"."` may name a directory but
cannot be an entry file. This is a lexical format rule, not a filesystem sandbox:
the parser does not resolve symlinks, check existence or read source files.

`parse-project` takes the description text and its filename. It uses the
compiler's located reader, which is available on both hosts, and returns a
`Project` with ordered typed build and run lists. A resolved `RunTarget`
contains a `ProgramBuild`; downstream code need not rediscover whether its
reference exists or points to a program. Paths and declarations retain their
locations. Build declarations are collected before runs are resolved. No separate
pending declaration tree is needed. Duplicate target diagnostics identify both
declarations; duplicate fields identify the second field.

Each build target produces one output directory at `PROJECT/build/TARGET`.
Programs contain `program.wasm`. Browsers add the shared browser host and a
recursive copy of `public`, if specified. Supply `index.html` in `public`;
no page is generated. Browser pages load `./program.wasm` through `host.mjs`.
Public files cannot overwrite generated files, the ownership marker
`.lofi-target`. The publication name `.lofi-publish` is reserved at every depth.
Public trees
must contain regular files/directories, with no symlinks, and cannot include
the project's build output. Public path components cannot be symlinks either.

The output is a relative symlink to a completed generation beside it. Rebuilds
atomically replace that link after compilation and packaging succeed. Previous
generations remain available to readers; no automatic reclamation occurs yet.
Resolve the link once before reading several files as one artifact. This
guarantees complete publication, not a transaction across changing source files
or durability after power loss. An ordinary directory, file or unrelated link
at the target's output path is rejected. The builder never removes it.

`scripts/project.mjs` owns traversal and packaging for both cold builds and
resident callers. It finishes all selected targets before returning a candidate;
the CLI publishes it immediately. Compilation or packaging failure changes no
public output, including outputs of already compiled dependencies. Publication
of several links is not globally atomic; if a later rename fails, already
published complete generations remain and unpublished candidates are removed.

The builder's development mode uses per-library modules, `modules.json` and
`runtime.wasm` instead of a linked `program.wasm`. Every directory remains
self-contained. An existing browser page receives the module-manifest meta
tag understood by `host.mjs`; the builder does not invent a page. It retains
compiler Sessions across calls but regenerates producer results each attempt.
The current `serve`/`watch` commands still use their old loop until `dev`
integration is complete.

`(artifact-bundle "NAME")` embeds the complete output of a browser build in
this project. Requests arise during expansion, including macros, generated
libraries and compilation of their producers. The builder resolves targets
serially, reuses each completed generation during the invocation, and reports
an active target as a cycle. The [artifact contract](artifact-bundles.md)
describes file ordering and publication. The project parser does not scan
source, construct a second dependency graph or invoke builds.

See the [implementation plan](proposals/desktop-ide.md) for output directories,
project builds, `lofi dev` and the editor service.
