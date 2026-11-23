# Development toolchain

Every build compiles the whole program to one module and fuses it with the
runtime ([output directories](projects.md#output-directories)). A release
build, `--release`, also optimizes it with Binaryen's `wasm-opt`. Stage 0
links a single program into one module the same way.

| Command | Build |
| --- | --- |
| `snail-scheme build`, `snail-scheme run` | Debug: one linked module |
| `snail-scheme build --release`, `make site` | Release: the same module, optimized |

A script, a single source file, is built and run with an explicit target,
`node` or `browser`
([scripts](scripts.md)): `./snail-scheme run --target node FILE [ARGUMENT ...]`
builds it into `build/PATH`, PATH being its path in its workspace without
the extension, and runs it, and `./snail-scheme wat --target TARGET FILE` prints its whole
program's text. Its `main` is its entry, whose parameters are the
capabilities it asks its target for. A program links with the toolchain runtime, whose services
include the assembler, exactly when it links `(snail shell assembler)`.
`wat` runs no producer, so a script that reaches a `generate-library`
recipe must be built instead.

Node runs the command line and every program it builds
(`host/native/run-snail.mjs`). Stage 0 links the command line with
`snail-link`, a small native program in `crates/snail-scheme-support`
([running and linking](bootstrap.md#running-and-linking)). One native
`snail-scheme` that replaces the launcher is proposed in
[#562](https://github.com/tsnl/snail-scheme/issues/562).

The [builds chapter](projects.md) defines workspaces, output directories and
embedding one build in another.

`snail-scheme run --target node FILE [ARGUMENT ...]` builds the script and
runs that exact completed generation on Node, passing the arguments after
the script unchanged. The program inherits the caller's working directory,
environment and terminal IO.

After compiler and scratch cleanup, the native command replaces itself with the
runtime using [Node's process replacement](https://nodejs.org/api/process.html#processexecvefile-args-env).
Its PID, exit status and signals therefore belong to the application. This uses
the existing Node 26 POSIX host. Compilation and generator execution retain
the cold builder's synchronous behavior.

## Contributor checks

`make test` runs the compiler's unit tests on Chez (`tests/unit.scm`), then
`tests/run.mjs`: every program fixture, built by `./snail-scheme build` as a
user's is and run on its host, and the host, build and application checks.
A fixture `NAME.sld` must print `NAME.out`, or fail to build with each line
of `NAME.err`. Each build has private scratch and its own output, so eight
run at once. A fixture folder with libraries of its own, as
`tests/programs`, is a workspace: they live under its `src/`.

CI reports formatting, both Rust crates, tool building and the `snail-scheme` suite
as separate steps under the required `Complete correctness checks` job. It
caches Cargo's test targets and the driver's native and WASI target
directories; Cargo checks their freshness on every build. Test debug symbols
and incremental compilation are disabled there to keep these caches small.
The bootstrapped compiler has a separate exact cache key covering its source,
bootstrap hosts, Rust runtime and pinned tools. On an exact hit, CI refreshes
its timestamp to account for checkout's new source timestamps. A changed
input rebuilds the bootstrap, and test outputs are rebuilt on every run.

## Assembly, linking and optional optimization

`(snail shell assembler)` offers `assemble` for an independent module and
`link` for a standalone program, taking program text and runtime bytes and
returning a `Result` of bytes or an error message. The toolchain runtime's
`assembler` feature provides `wat` and `wasm-fuse`; plain program runtimes
carry neither. Stage 0 calls the same Rust functions through `snail-link`.
No Binaryen installation is required.

Linking resolves the program, runtime and diagnostics/cleanup adapter before
removing `snail:*` and `diagnostics/*` exports. All other exports survive,
including GC globals and dynamic functions. A second `wasm-fuse` pass prunes
unreachable definitions and remaps debug names. Function bodies are not
optimized here; a release build then runs `wasm-opt -O2` over the linked
module ([output directories](projects.md#output-directories)). The internal
source driver also continues to accept `--release`.

Optimization can be a separate user-owned step, with Binaryen installed
independently:

```sh
wasm-opt program.wasm -o program.optimized.wasm -O3 \
  --enable-gc --enable-reference-types --enable-tail-call --enable-bulk-memory \
  --enable-nontrapping-float-to-int --enable-sign-ext --enable-mutable-globals \
  --always-inline-max-function-size=40 --converge
```

Optimize a copy, outside a published generation and its cache. Avoid
`--closed-world`: hosts and separately linked libraries can retain function
references and access each other's GC values.

## Editors

`snail-scheme` has no editor of its own. An editor gets what it needs from two
pieces in the repository: a [tree-sitter](https://tree-sitter.github.io/)
grammar for what it can tell from the text alone, and `snail-scheme lsp`, a
[Language Server Protocol](https://microsoft.github.io/language-server-protocol/)
server, for what takes the compiler. `editors/zed` is the extension that puts
them together for [Zed](https://zed.dev/).

### The grammar

`editors/tree-sitter-snail-scheme` parses the reader's data: lists in `()` or `[]`,
`#u8(` byte arrays, quotes, strings, and the comments the reader discards,
`;` lines, nested `#| |#` blocks and `#;` datum comments. Its external scanner,
`src/scanner.c`, reads every other token to a delimiter and classifies it as
`token-kind` in `src/snail/shell/compiler/read.sld` does: a boolean, a number,
a character or a symbol. A token the reader rejects, such as `.` or `#x1F`, is
a symbol to the grammar, so Chez's own files still parse. The grammar is for
editors alone; the compiler keeps its reader. The generated parser is
committed, and `tests/tree-sitter.mjs` (in `make test`) checks that
`grammar.js` still generates it, runs its corpus tests and parses every
tracked Scheme file without an error.

The grammar colours nothing: the server does. Zed requires a grammar for a
language, and its queries live with the extension, under
`editors/zed/languages/snail-scheme/`: `brackets.scm`, `indents.scm` and
`outline.scm`, which lists a library by its name and then its definitions.

### The language server

`snail-scheme lsp` is the command line's `lsp`, `(snail shell lsp)`. It reads
Content-Length framed JSON-RPC on standard input, answers on standard output,
and serves the workspace at the root folder the editor opens, which holds
`src/`. It offers:

- **Diagnostics.** When a file is opened and on each save, it checks each
  open document as a build would, producers and all, with scratch under
  `build/snail-run/`, writing no output (`check-script` and
  `check-library`). A `.scm` file is a script, checked as a page when a
  `public/` folder is beside it and for Node otherwise; an `.sld` file
  under `src/` is checked as the program that imports it. Each failure is
  reported on its file, once however many documents meet it, over the
  range `(snail shell highlight)` derives for its point: the token there,
  or the datum that starts there. A file is cleared once it checks. A
  failure with no point, or in a file that does not exist, is reported on
  the document checked. A check reads the disk, so diagnostics follow what
  was saved.
- **Formatting.** The open text, formatted by `(snail shell format)`, as one
  edit of the whole document.
- **Hover and definition.** The last checks' programs give each
  variable's use its type and the binding that introduces it: a top-level
  definition, perhaps in an imported library, a `let` binding or a lambda's
  parameter. Hover shows the name, its type and the library it comes from;
  definition goes to the name in its binding form.
- **Colours.** Semantic tokens for the whole open text, from
  `(snail shell highlight)`'s classes: comments, strings and characters,
  numbers, keywords and booleans, type names, and the name a definition
  introduces, as a `function` with the `declaration` modifier. Other names
  and punctuation are left to the editor. A token that spans lines is split
  at each line's end, since a client need not accept one that does not.

Positions are counted in UTF-16 code units, as the protocol's default
encoding is. `tests/lsp.mjs` (in `make test`) drives the server through
each of these on a workspace of its own.

### Zed

`editors/zed` is a Zed extension: `extension.toml` names the grammar, by
repository and revision, and the language server, and `languages/snail-scheme/`
holds the language's configuration and queries. Zed runs extensions in a
wasmtime without its garbage-collection feature and loads only Rust, so the
extension is a small Rust crate, `src/snail_scheme.rs`, compiled to
`wasm32-wasip2`. It only finds the command: the binary path the user's
settings give under `lsp.snail-scheme`, then a `snail-scheme` on the
worktree's `PATH`, then the repository's own `./snail-scheme` launcher. To try it, choose
**Install Dev Extension** in Zed's extensions page and pick `editors/zed`.
Zed colours with the server's semantic tokens once a setting asks:

```json
"languages": {"snail-scheme": {"semantic_tokens": "full"}}
```

### VS Code

`editors/vscode` is a VS Code extension of a few lines of JavaScript,
`extension.js`, on `vscode-languageclient`. It contributes the
`snail-scheme` language for the files Zed's extension claims, with
`language-configuration.json` for comments and brackets, and no TextMate
grammar: the server's semantic tokens colour the text. It starts the
command the `snail-scheme.path` setting names, else the workspace's
`./snail-scheme` launcher, else `snail-scheme` on `PATH`, with `lsp`. To try
it, run `npm ci --prefix editors/vscode`, then choose **Developer: Install
Extension from Location…** and pick `editors/vscode`. `tests/vscode.mjs`
(in `make test`) loads it with stand-ins for both modules.

### The formatter

The command-line formatter, `snail-scheme format` (and `scripts/format-scheme`,
which runs it), runs the same library as the language server, in the same
program. With no arguments it formats
stdin to stdout; optional `--width COLUMNS` selects a positive width instead of
100. `--check FILE ...` reports every file needing formatting on stderr and
exits with status 1; `--write FILE ...` updates only changed files.
`make check`, `make format` and `snail-scheme lsp` all use this implementation.

Binding forms are recognized by name: `let`, `let*`, and any name ending in
`-let` or `-let*`. A user-defined `result-let*` or `retry-let` needs no formatter
registration. Bindings align with each other, and the body is indented two
spaces from the form's opening parenthesis. Forms ending in `-let` also use
named-let layout when a loop name precedes the bindings. This is a formatting
convention; the formatter does not expand macros or inspect their definitions.

## Browser packaging

Packaging has three steps: copy host and public assets, generate the default
manifest only when the public folder has none, and add typed page metadata. The
manifest is a normal bundled file. `(snail shell project web-app)` renders
metadata constructors with HTML attribute escaping and inserts them at the
page's head boundary, preserving the supplied HTML, head attributes, comments
and doctype. A module manifest's `snail-scheme` datum text travels in a `meta` element's
`content` attribute; browser decoding precedes datum parsing. Scheme fixtures
cover this encoding and page construction; Chromium checks the browser's
resolved URLs and standards mode.

Browser bundles expose a web-app manifest by default. The
manifest gives a standalone window, the application name, theme colors, and
192/512-pixel icons. A browser target can provide `public/manifest.webmanifest`
to replace the default entirely, including its icons and display mode; it is
served unchanged. The builder links the manifest from UTF-8 `index.html` pages.

The web manifest's relative `start_url` and `scope` resolve at the output
directory, and the default identity is that resolved start URL (no explicit
`id` is emitted). A bundle's relative manifest link works under a deployment
subdirectory. HTTPS or a loopback origin is needed for browser installation.
These manifests do not add offline caching or a service worker.

## Code highlighting

The book colors code with `(snail shell highlight)`, and so do editors,
through the [language server](#the-language-server).
It walks text with the compiler reader's own lexical rules, the "Lexemes"
section of `src/snail/shell/compiler/read.sld`: what starts at an index, where
it ends, and what a token's text is to the reader, a boolean, a number, a name
or an error. The reader is built on the same functions, so a highlighter
cannot disagree with it about where a string, a character such as `#\(`, a
comment or a token ends. The classifier adds what a reader discards, the
comments and whitespace between data, and it never fails: a string the text
ends inside is a string to the end, and a token the reader rejects, such as
`.`, is classed invalid. Its tokens tile the text. The core forms it colors
as keywords are the compiler's own list, `core-keywords` in `core.sld`; the
derived forms and declaration words are listed once in the classifier. It
also marks the name a `define`, `define-syntax` or `:` introduces, and colors
what `#;` comments out as a comment.

mdbook runs `scripts/highlight-book` as a preprocessor, which `book.toml`
registers after the `links` preprocessor has included the examples. It is a
`snail-scheme` script, `tools/highlight-book.scm`, which reads the book as mdbook
writes it, JSON on its standard input, and writes it back. It replaces each fenced block whose language is `scheme` with a
`<pre><code class="nohighlight">` of `tok-` spans, one per token but
whitespace, which `doc/highlight.css` colors for mdbook's light and dark
themes; highlight.js skips code of class `nohighlight`, and still highlights
the book's other blocks. `scripts/highlight-book` runs it with
`snail-scheme run --target node`, so `mdbook build` works from a fresh checkout
that can build the compiler. `tests/highlight-book.mjs` runs the preprocessor on a small book.

Proposed: once the book is itself built by a `snail-scheme` script, the classifier can run
in a `generate-library` recipe that writes the highlighted pages, and the mdbook
preprocessor goes away.

## Application and networking integration

A program target runs with `snail-scheme run`. A browser target's output is a
static directory any HTTP server can serve. Durable
state remains [proposed work](applications.md#proposed-application-processes).
Production `serve` and package installation still need their own contracts;
neither is a current public command.

The concrete [socket capabilities](../runtimes/networking.md) provide TCP streams and
UDP datagrams to native CLI programs, and a test makes its own. Their
native owners define bounded buffering, cancellation and close behavior. UDP
keeps message boundaries without guaranteeing delivery or order.

The [HTTP library](http.md) provides bounded parsing, response framing and one
complete exchange over TCP.
Wait on the host by ticket, as the runtime's sockets do, and test real sockets as well as
intercepted operations. [Networking work](https://github.com/tsnl/snail-scheme/issues/457)
tracks this boundary. No transport hierarchy or generic provider framework
is needed. TLS, HTTP/2 and deployment infrastructure are separate work.

## Traces

Measure performance from a trace: a file in Chrome's JSON trace format,
which [Perfetto](https://ui.perfetto.dev) opens and `chrome://tracing`
reads. A trace shows where a run's time goes among the program, the host
and the device, and it measures every run the same way, so compare two
runs by their traces, not with a timer added for the occasion.

- A program on Node writes one as it ends when `SNAIL_TRACE` names the
  file: `SNAIL_TRACE=run.json node build/.../main.mjs ARGUMENT ...`.
  Node keeps every span until then, so trace a short run, such as a few
  hundred of the trainer's steps.
- A page traces when its URL's query has `trace`. `TRACE=page.json node
  tests/browser/page.mjs URL SCREENSHOT SECONDS` opens the page so and
  records Chromium's own trace of the visit: the page's spans beside its
  main thread's tasks, V8's work and the GPU process's. `startTrace` and
  `stopTrace` in `tests/browser/chromium.mjs` do the same for any test.

The spans are the host's, in `host/browser/trace.mjs`, and they stay in
the checked-in code, costing one test of a flag in a run that is not
traced. On the `main` track, each `turn` is a turn of the scheduler, the
time the program's own code ran, and each `gpu submit` is a submission;
a `wait` is a host operation that a task waits on, such as `gpu read`,
`gpu done` or `decode image`. On a device with `timestamp-query`, a
traced run times every pass, and the `gpu` track shows each pass for as
long as the device ran it, named for the pipelines it set. A pass the
program times itself keeps its own queries. WebGPU puts timestamps only
at the ends of passes, so a pass is the finest span the trace has, and
the queries cost the device a little. The device's clock has an origin
of its own, and a pass cannot start before its submit, so the host puts
the device's clock as early as it can be with no pass before its submit.
Durations are exact, and starts are exact once the device has been idle
at some submit. A browser
rounds the device's times to 100 μs unless its WebGPU developer features
are on, as they are in `tests/browser/chromium.mjs`. On a page, a span is
a `performance.measure`, which Chromium's trace records under
`blink.user_timing`. Node's traces do not record measures, so Node's host
writes its file itself, a thread for each track.

A span marks a boundary where time passes from one party to another. When
measuring something calls for a new one, add it with `span` or `traced`
and keep it, so that later measurements see it too.
`(profile-program gpu program)` (`(snail shell tensor lower)`) is the
finer tool for a tensor program: it times each step in a pass of its own.

## Process boundaries and future debugging

| Boundary | Information crossing it |
| --- | --- |
| Editor ↔ language server | LSP over standard streams: open text, saves, diagnostics, formatting edits, hovers and definitions. |
| Browser ↔ application server | Ordinary HTTP. |

A future debugger attaches to a program's process and build. Its inspector
endpoint expires with that process. `run-snail.mjs` executes Wasm on the process's main
thread, so attachment reaches the program itself. Debug commands use the inspector
connection rather than compiler requests or parsed stdout. The editor
stays responsive while an application is paused. Source mappings and
breakpoints require a separate compiler/assembler proof; debugger support is
not implemented. [Editor and debugger work](https://github.com/tsnl/snail-scheme/issues/461)
tracks these extensions.

[Build-tooling and package decisions](https://github.com/tsnl/snail-scheme/issues/462)
track complete rebuilds, producer-input observation and package installation.
