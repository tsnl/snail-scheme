# Project descriptions

`project.datum` describes one project with inert data. The parser is implemented
in `src/lofi/project.sld` as `(lofi project)` and runs on Chibi and compiled Wasm.
CLI building and development integration are subsequent changes; current
commands do not consume this file yet.

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

Each build target will produce one output directory, potentially containing
multiple files. Artifact dependencies are discovered later during expansion,
including generated libraries. The parser does not scan source, build a second
dependency graph, detect artifact cycles or invoke a build.

See the [implementation plan](proposals/desktop-ide.md) for output directories,
project builds, `lofi dev` and the editor service.
