# Source recipes and dependency preparation

The Chibi [`source-driver.sld`](../src/snail-sfir/source-driver.sld) reads SFIR
source and assembles an explicit map for the compiler. It accepts ordinary
`define-library` files and the book's exact recipe grammar:

```scheme
(generate-library (demo answer)
  (import (producer helpers))
  (make-answer-library))
```

The body is one ordinary SFIR expression. Its imports belong to the producer.
The driver compiles a zero-argument function containing that expression to
Wasm, checks that its result has the nominal `SfirLibrary` type, executes it,
and receives an owned structured library through the
[builder protocol](sfir-builder.md). An I64 builder token or a live function
cannot substitute for that result. An identity-bound private function and a
separate adapter keep driver names out of the expression's lexical environment.

The resulting library has its own imports. These are collected independently
for the application. A producer's imports never implicitly enter the returned
application map. Producer compilation currently uses Wasm; the application can
use either existing target. [`compile`](book/sfir/compilers.md) continues to
consume supplied library values without discovering source or running recipes.

## Try the example

[`demo/answer.sfir`](../examples/generation/demo/answer.sfir) constructs a
zero-argument function returning I32 `42`. A source command imports that result:

```sh
./snail-sfir run -I examples/generation examples/generation/main.sfir
./snail-sfir run --target native -I examples/generation examples/generation/main.sfir
```

Both commands exit with status `42`. The producer runs as compiled Wasm in
either case. The second command executes its generated application natively.
`scripts/build-sfir` and `scripts/build-native` use the same source driver.

## Selection, identities and separate preparation

Search paths map `(demo answer)` to `demo/answer.sfir`. The first matching path
wins, including when its contents are malformed. A selected file's declared
name must match the requested key. Diagnostics retain that chosen path. The
generated value's descriptive name may differ: the driver registers the value
under the recipe's requested key, as an explicit map caller can do.

One preparation operation keeps one selected value for each key. Every
compilation gets its own dependency map, while its traversal shares the active
preparation chain. A source library already parsed for an enclosing request
does not conceal a cycle through a generator. Cycle errors include the key
chain and selected paths. Missing dependencies include the request chain.
The driver rejects ordinary import cycles too.

The host API is:

```scheme
(make-generation-context runner-path provider-module-or-false)
(prepare-library key search-directories initial-libraries context-or-false)
(collect-libraries entry search-directories initial-libraries context-or-false)
(collect-source-file path search-directories initial-libraries context-or-false)
```

`runner-path` normally names `scripts/run-sfir-generator.mjs`.
`initial-libraries` is an explicit association list of keys and unresolved
`SfirLibrary` values, including `(sfir primitive)` when required. Search
directories are explicit; direct API calls add no implicit `lib` directory.
Source CLI commands append the repository's `lib` after the supplied `-I`
directories. Reading uses the existing explicit `with-chromium-trace-to` scope.

`prepare-library` produces only the requested value. It obtains a generator's
producer closure, but does not obtain imports of its returned library.
`collect-libraries` returns the entry library and its complete application
dependency closure. `collect-source-file` returns two values: the root key and
that map. It also accepts the existing anonymous source-script syntax.
With a false context, encountering a generation recipe is an error.

The driver copies the initial association list while preserving library object
identity and aliases. A prepared value can be supplied to a later collection
under one or several keys. Independently repeated preparation operations create
fresh values; there is no global generation or running-instance cache. Ordinary
compilation and instantiation preserve the existing per-library initialization
rules. Failure ends the operation; partially prepared state is not published.

## Explicit foreign services and source context

Recipes have the builder service automatically. Other foreign services come
from an explicitly selected ES module:

```sh
./snail-sfir run --generation-provider ./build-providers.mjs -I lib main.sfir
```

The same option is supported by both build scripts. The module exports:

```javascript
export function createProviders(sourceContext) {
  // Acquire caller-defined services using sourceContext.sourceDirectory.
  return {providers: new Map(), close() { /* Release those services. */ }};
}
```

The factory may be asynchronous. Its frozen context contains `sourcePath`,
`sourceDirectory`, and a frozen `libraryKey` array. Paths are absolute and
normalized against the caller's working directory. The runner preserves the
selected descriptor path it receives; source CLI commands first canonicalize
explicit source paths and search directories. A relative source operation can
explicitly resolve against `sourceDirectory`. A new process and provider
scope serve each recipe. An external shared service requires explicit handles
or transport supplied by the factory.

`providers` must map foreign module names to genuine `WebAssembly.Instance`
objects, whose function signatures the execution adapter checks. The reserved
`sfir.builder` provider cannot be replaced. The factory retains responsibility
for cleaning up if acquisition fails before it returns. Once it returns a valid
scope, the runner calls `close` exactly once after success or failure, awaiting
it when necessary. It closes the producer and builder arena before writing the
owned transfer. Both execution and cleanup errors are retained when both fail.
Already performed provider effects are not rolled back.

There is no built-in `read-source`, Scheme frontend, macro expansion or
auxiliary-artifact protocol in this driver. The separate
[SFIR compiler service](sfir-compiler-service.md) exposes explicit compilation
and Wasm execution calls; this recipe runner does not automatically install it.
The book's
`read-source` example assumes an imported service; this driver supplies the
explicit source context such a service needs. The
[constructive syntax API](sfir-builder.md) covers the book's complete library
syntax and exposes typed inspection views. Runtime traps identify the recipe and
preserve the execution error; generated syntax locations survive transfer and
subsequent type checking.

## Verification

`scripts/test-sfir-generation` compiles and executes nested producers and their
generated applications. It checks distinct producer and consumer imports,
independent preparation, explicit aliases, initialization through diamond
imports, fresh instances, descriptor-relative input, name hygiene, both command
targets, wrong results, generated checking locations, missing dependencies,
preparation cycles, first-path selection, and provider cleanup on failure.
