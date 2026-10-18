# Applications

An application owns a runnable product and the recipe that assembles it from
libraries. Reusable languages, compilers and frameworks belong in the repository's
top-level [`src/`](../src/). An app demonstrates how those tools compose.

| Application | Purpose | Status |
| --- | --- | --- |
| [Siegework](siegework/README.md) | Single-player runs of automated extraction, logistics and siege defense. | Scheme/WebGPU prototype with local IndexedDB saves and state-preserving module reload. |

## Ownership and layout

Each app owns its `build.scm`, entry points, rules, assets, settings and tests.
App-owned libraries may live under `apps/<app>/src/` and use the app's namespace;
for example, `(siegework game)` resolves to
`apps/siegework/src/siegework/game.sld`. The build explicitly supplies that source
root alongside the repository's `src/`. App libraries must not shadow shared
library identities.

Shared shader syntax, GPU ASTs and compilers, browser/WebGPU bindings, server and
network transports, serialization, and stream utilities belong under top-level
`src/`. They should not need to import `(siegework ...)` or know
about mines, monsters or matches. Siegework owns its shader programs, resource
rules, message schema and use of those libraries. Build only the shared surface
needed for the next working example; this is a placement rule, not a request to
implement a framework in advance.

Snail library source uses `.sld`; imports select the available language bindings.
Foreign host adapters retain their host's source format beside the libraries they
serve. Executable Scheme orchestration uses `.scm`, so an app's `build.scm` remains
an explicit recipe. The [compiler tour](../TOUR.md) explains the shared source and
bootstrap layout. Current builds use the Chibi-hosted compiler; this organization
does not require a self-hosted compiler or compilation inside the browser.

A future Wasm-to-native CLI can likewise have its command and build recipe under
`apps/`, importing its reusable implementation from `src/`. The existing
[`src/native/`](../src/native/README.md) package is not moved by this app draft.

## Build contract

Each implemented app recipe should name its source roots, compiler and foreign
providers, inputs, and output directory. It should assemble those inputs through
library APIs, report missing dependencies, and leave reproducible artifacts that
can be run independently of the build process. The repository's existing
[`build.scm`](../build.scm) is a working native composition example, not a browser
app build command.

Siegework has a real [build recipe](siegework/build.scm) and
[run instructions](siegework/README.md#build-and-play). Its browser host and shader
compiler are reusable libraries under `src/`. The
[application chapter](../doc/book/lofi/applications.md) explains their public API.

The goal is an app whose composition is understandable in a few files. That
counts the app-specific work, not all the shared tools underneath it, and never
justifies compressing code or hiding substantial framework work in an app.
