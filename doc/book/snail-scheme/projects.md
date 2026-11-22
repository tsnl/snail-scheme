# Workspaces and builds

A workspace is a folder that holds `src/`. Every library lives under `src/`,
at the path its name gives, and every import resolves there, then in the
standard libraries. A script is a source file anywhere in a workspace;
`snail-scheme build --target TARGET FILE` builds it for `node` or
`browser`, and `snail-scheme run` builds it and becomes its program
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
being the script's path in its workspace without its extension. It holds
one module, `NAME.wasm`, NAME being the script's file name without its
extension: the whole program compiled as one and fused with its runtime.

Each file the program links ([linked files](types.md#linked-files)) is an
object of the workspace's store,
`WORKSPACE/build/.snail-store/sha256/AB/DIGEST`, named for the SHA-256 of
its bytes and sharded by its first two hex digits. Every build of every
script shares the store: an object is written once and never rewritten.
The program reads its files from `store/` beside its module, at the same
paths, where each is another name for the store's object, a hard link (a
copy where the two lie on different file systems). A program's bulky files
are then on disk once, and its directory still holds them itself, so it
can be served or shipped on its own. Nothing reclaims the store: delete
`build/` and rebuild from time to time. On Node the native runner,
`host/native/run-snail.mjs`, runs the module, which a Node build packages
with it ([a Node package](#a-node-package)), and a page links it through
`linkModule` in `load.mjs`.

A release build, `--release`, differs in one thing: the module is then
optimized by Binaryen's `wasm-opt -O2`, which can inline the runtime's
functions into the program. `wasm-opt` is found on `PATH`.

A browser build adds the shared browser host and recursively copies the
`public/` folder beside the script, if there is one. Supply `index.html`
there; no page is generated. The builder names the program's module in
the page, with a
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

### A Node package

A Node build's directory is an npm package around its module, which runs
wherever it is copied:

```text
build/apps/hello/main/
  package.json      {"name": "main", "private": true,
                     "scripts": {"start": "node main.mjs"}, "bin": {"main": "main.mjs"}}
  main.mjs          runs main.wasm with its arguments
  main.wasm
  store/            the files the program links, if any
  host/native/      the Node host, as the repository keeps it
  host/browser/     the three files of the browser host it shares
```

npm runs it as Cargo runs a crate:

```sh
cd build/apps/hello/main
npm install                    # fetches its dependencies, if it has any
npm start -- ARGUMENT ...      # runs it, as `cargo run -- ARGUMENT ...` does
npm install -g .               # installs its command, `main`, as `cargo install --path .` does
```

npm prints the command it starts before the program's output; `npm start
--silent` leaves the output the program's alone. npm runs a script in the
package's folder, where Cargo stays in the caller's. `node main.mjs
ARGUMENT ...` runs the program in the caller's directory, as `snail-scheme
run` does, with nothing to install. A program that holds
`(snail runtime gpu)` may ask for a device and decode an image, so its
package depends on npm's `webgpu` and `@napi-rs/canvas` packages, at the versions
the repository's `package.json` pins, and loads each when it is first
needed, at the program's first `request-device` and its first
`decode-image` ([WebGPU on Node](../graphics/plan.md#webgpu-on-node)).
Inside the repository, Node finds the copies `make fetch` installed;
elsewhere, `npm install` in the package fetches them. Other programs
depend on nothing.

The package is private, so npm will not publish it until its author gives
it a name and a version of their own. What becomes of it after that is
the Node ecosystem's work, not the builder's: `npm publish` ships it, and
any bundler or packager that takes an npm package takes it. Nothing
installs a dependency but npm, so a package is installed before it is
packed. A single executable application, for one,
is Node's own binary with a script built into it
([SEA](https://nodejs.org/api/single-executable-applications.html)). The
script can load only Node's built-in modules, so it loads the package
beside the executable through `createRequire`. `main.mjs` and the host
avoid top-level `await`, so `require` can load them. The output is a link
to its generation, which the copy follows:

```sh
mkdir -p dist && cp -RL build/apps/hello/main dist/hello && (cd dist/hello && npm install)
echo "require('node:module').createRequire(__filename)('./hello/main.mjs');" > sea-main.cjs
echo '{"main": "sea-main.cjs", "output": "dist/hello-run"}' > sea-config.json
node --build-sea sea-config.json
dist/hello-run ARGUMENT ...
```

The executable runs with `dist/hello/` beside it. Node 26.9 and later can
also serve the package from inside the executable, as one file, with
`"useVfs": true` and the package zipped as its `"vfsArchive"`.

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
                   (embedded linking)
                   (only (snail core io) Arguments ProcessEnvironment Fs Clock)
                   (only (snail shell process) Processes))
                  (lambda ((mut Mut)
                           (arguments Arguments)
                           (environment ProcessEnvironment)
                           (processes Processes)
                           (fs Fs)
                           (clock Clock))
                    (files-library fs (list "embedded" "client")
                                   "client-files"
                                   (build-script mut processes fs clock (producer-tools arguments)
                                                 (script-at fs environment "client/main.scm")
                                                 (Browser)
                                                 (Debug)))))
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
