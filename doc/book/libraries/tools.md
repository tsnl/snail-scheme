# Tools

The compiler, the build and the editor support are `snail-scheme` libraries
too, which `bootstrap/cli.sld`, the `snail-scheme` command line, puts
together ([development toolchain](../snail-scheme/toolchain.md)).

## `(snail shell compiler)`

The compiler's passes in order, from a program's source path to
WebAssembly text: `source->checked` reads, expands and checks a program, and
`checked->wat` specializes, prepares and emits it; `source->wat` does both.
Every invocation reads, checks and emits the whole program afresh. Chez
runs this source as stage 0, and Node runs it compiled to WebAssembly, so
it imports only `(snail core base)`, `(snail core table)` and
`(snail core io)` and avoids what the two hosts would disagree on, such as
integer overflow and the order of a table's keys
([compiler architecture](../snail-scheme/compilers.md)).

Its passes and supporting modules, each `(snail shell compiler NAME)`:

| Module | Does |
| --- | --- |
| `read` | Text to located syntax, by recursive descent; its lexical rules are exported for highlighting; how any pass stops a compile with a diagnostic |
| `library` | Where a library's file is, and what it declares before it is expanded: a `define-library`, or a `generate-library`'s producer |
| `inputs` | The requests a compile makes for what it was not given, such as a producer's output |
| `expand` | Located syntax to the core program: libraries loaded, every identifier resolved, macros run, entities recorded |
| `core` | The core language every pass after expansion shares: types, expressions and the program's tables |
| `check` | Hindley-Milner checking with typeclass evidence, each expression rebuilt with its type |
| `specialize` | Each definition reached copied once for each set of types it is used at |
| `prepare` | Fixed declarations and normalized items, with what each call may suspend to |
| `wasm` | Prepared code to WasmGC: representations, closures, tail calls and the frames a suspension saves |
| `driver` | One invocation, shared by stage 0's entry and the command line's `compile` |
| `sha256` | The digest linked files are named by ([text and data](data.md#snail-shell-compiler-sha256)) |

The [compiler tour](../snail-scheme/compilers.md#the-passes) follows a
program through them.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler.sld)

## `(snail shell assembler)`

`assemble`, WebAssembly text to a binary module, and `link`, static linking
of modules into one, in-process. Only a tool linked with the toolchain's
runtime can use it: the plain runtime leaves the text parser out, so a
program that imports this library links with the toolchain's instead
([assembly and linking](../snail-scheme/toolchain.md#assembly-linking-and-optional-optimization)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/assembler.sld)

## `(snail shell project build)`

A script's build, which `snail-scheme build` and `run` run: `build-script`
compiles, links and packages a script into a generation of its own, then
publishes it by replacing the script's link in its workspace's `build/` at
once. A compile that reaches a generated library runs its producer first,
then compiles again. A build that fails removes every generation it made,
and only those, so earlier outputs stay published. `check-script` and
`check-library` compile as a build does and write nothing, for the language
server. A build's `Mode` is `Debug` or `Release`, which also optimizes the
module with `wasm-opt`; its `Platform` is `Node` or `Browser`
([workspaces and builds](../snail-scheme/workspaces.md)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/project/build.sld)

## `(snail shell project web-app)`

A browser build's installable web-app manifest and the page's links to it:
`web-app-manifest` is the default manifest, and `with-web-app` inserts into
a page the manifest's link and the name of the program's module, keeping
the rest of the page byte for byte. A project's own
`public/manifest.webmanifest` replaces the default whole
([browser packaging](../snail-scheme/toolchain.md#browser-packaging)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/project/web-app.sld)

## `(snail shell lsp)`

`serve-language`, `snail-scheme lsp`: the Language Server Protocol over
standard input and output for one workspace, the folder an editor opened.
It checks each open document in this process, as a build would, whenever
the editor opens or saves it, and answers diagnostics, hover (a name's type
where it is used), definitions, formatting and semantic colors. A check
reads the disk, so it reports what was saved. Zed and VS Code start it
through `editors/`
([the language server](../snail-scheme/toolchain.md#the-language-server)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/lsp.sld)

## `(snail shell format)`

The repository's formatter, which `scripts/format-scheme` and the language
server share: `format-source` puts each import specification and field on
its own line, indents every line under its call's first argument or two in
for a special form's body, and breaks a line whose code runs past
`format-width` (100 columns), never joining lines. `make check` holds every
tracked Scheme file to it ([the formatter](../snail-scheme/toolchain.md#the-formatter)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/format.sld)

## `(snail shell highlight)`

`highlight-tokens`, source text as tokens that tile it, each of a `Class`
for coloring, by the compiler reader's own lexical rules, adding only the
comments and whitespace a reader discards. Text the reader would reject
still classifies. The book's code blocks, the language server's semantic
tokens and the range it marks for a diagnostic all come from it
([code highlighting](../snail-scheme/toolchain.md#code-highlighting)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/highlight.sld)
