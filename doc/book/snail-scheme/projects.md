# Workspaces and builds

A workspace is a folder that holds `src/`. Every library lives under `src/`,
at the path its name gives, and every import resolves there, then in the
standard libraries. A script is a source file anywhere in a workspace;
`snail-scheme build --target TARGET FILE` builds it for `node`, `wasmtime`
or `browser`, and `snail-scheme run` builds it and becomes its program
([scripts](scripts.md)). A script's workspace is the nearest folder above it
that holds `src/`. There is no project file: what is built, and for which
platform, is on the command line.

This repository is one workspace. The applications are scripts
([application model](applications.md)):

```sh
./snail-scheme build --release --target browser src/apps/siegework/main.scm
python3 -m http.server 4191 --directory build/src/apps/siegework/main
```

An editor opening a workspace runs `snail-scheme lsp`, which checks each
open script and library ([editors](toolchain.md#editors)). The
[toolchain](toolchain.md) describes command lifetimes.

## Output directories

A script's build produces one directory at `WORKSPACE/build/PATH`, PATH
being the script's path in its workspace without its extension. In a
debug build every library is compiled to a module of its own. The modules,
the runtime they link with and each file the program links
([linked files](types.md#linked-files)) are objects of the workspace's
store, `WORKSPACE/build/.snail-store/sha256/AB/DIGEST`, named for the SHA-256
of their bytes and sharded by its first two hex digits. A build adds only the
objects whose bytes are new; an object is written once and never rewritten,
and nothing reclaims the store: delete it and rebuild from time to time.

A debug directory holds the program's manifest, `NAME.manifest.datum`, NAME
being the script's file name without its extension, and
a view of the objects it names at the same paths under its own `store/`,
links into the workspace's store. The manifest is one list of entries:

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

A release directory, `--release`, holds one module instead, `NAME.wasm`:
the whole program compiled as one, fused with its runtime, then optimized
by Binaryen's `wasm-opt -O2`, which can inline the runtime's functions into
the program. Each file the program links is copied into its `store/`, at
the same path, so the directory can be served or shipped on its own. Node
and `build/snail run-wasm` run the module directly, and a page through
`linkModule` in `load.mjs`. `wasm-opt` is found on `PATH`.

A browser build adds the shared browser host and recursively copies the
`public/` folder beside the script, if there is one. Supply `index.html`
there; no page is generated. The builder names the program, the manifest or the
module, in the page, with a
`snail-modules` meta element, which `host.mjs`, or `ui.mjs` for a
[document interface](applications.md#document-interfaces), links the
program from; a linked file is fetched when the program first reads it.

Public files cannot overwrite generated files. At the root, every name the
build generates is reserved: the manifest, the release module, `store`, the browser host's files
and the `.snail-target` ownership marker. `.snail-publish` is reserved at
every depth. Public trees must
contain only regular files and directories, include no build output,
and have no symlink components, including in the path to the public directory.

The public output is a relative symlink to a completed generation beside it.
Rebuilds replace that link atomically after compilation and packaging succeed.
Previous generations remain available to readers: `snail-scheme build` reclaims none. Resolve the link once before reading several files as one artifact.
An ordinary file, directory or unrelated link at the output path is rejected
and never removed by the builder.

The builder, `(snail shell project build)`, builds the script's generation
in private scratch before publishing it. A compile or packaging failure
removes the generation and changes no published output. Publication checks
the destination, makes a temporary link beside the generation and renames it
into place, which is atomic. These guarantees concern complete outputs, not
an atomic source snapshot or power-loss durability.

## Embedding a build

A build embeds another through a `generate-library` recipe whose producer
builds it. `build-script` in `(snail shell project build)` builds and
publishes a script as `snail-scheme build` does, and answers its
generation's directory; `producer-tools` reads the tools the build ran the
producer with from its command line. The library the recipe returns links
each file of that generation, so the embedding program reads them as
resources, and the files ship with it:

```scheme
(generate-library (embedded client)
                  (import
                   (snail core base)
                   (snail shell project build)
                   (embedded linking))
                  (files-library (list "embedded" "client")
                                 "client-files"
                                 (build-script (producer-tools)
                                               (script-at "client/main.scm")
                                               (Browser)
                                               (Debug))))
```

`files-library`, in the test's own `(embedded linking)`, lists the generation
and links each file by its absolute path (`tests/embedding/`). `link-file`
takes a path relative to the recipe, `..` included, or an absolute one. A
debug generation's `store/` view is links into the workspace's store, and a
linked file is read through its link, so the embedded page is complete
wherever it is served from.

A producer runs in its workspace's directory, in every build that reaches
it, so a changed client file reaches the next build of the server. A build
that compiles a generated library whose output it has not yet produced
prints the producer into its scratch, compiles, links and runs it, and
compiles again (`producing` in `build.sld`). The producer's own compile does
the same, and the libraries loading when it was reached begin its source,
so a producer that needs the library it generates, at once or once another
producer has run, is an import cycle and never runs. A producer is also
handed the scripts whose builds it is part of, after the tools on its
command line, and `build-script` refuses one of them: a script that embeds
its own build fails with the chain of scripts, where it would otherwise
build without end.
