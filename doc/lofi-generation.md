# Source recipes and dependency preparation

The Chibi [`source-driver.sld`](../src/lofi/compiler/source-driver.sld) reads Lofi
source and assembles an explicit map for the compiler. It accepts ordinary
`define-library` files and generation recipes:

```scheme
(generate-library (demo answer)
                  (import
                   (producer helpers))
                  (make-answer-library-text))
```

The body is one ordinary Lofi expression of type `String`. Its imports belong
to the producer. The driver compiles a zero-argument function containing that
expression to Wasm and runs it. The result is the source text of one
`define-library` form whose name matches the recipe key. The driver parses that
text exactly like a file, so generated code can use macros and `(scheme base)`.
An identity-bound private function and a separate adapter keep driver names out
of the expression's lexical environment.

The resulting library has its own imports. These are collected independently
for the application. A producer's imports never implicitly enter the returned
application map.

## Try the example

[`demo/answer.sld`](../examples/generation/demo/answer.sld) builds the text of a
library whose `main` returns I32 `42`. A source command imports that result:

```sh
./lofi run -I examples/generation examples/generation/main.sld
```

Execution exits with status `42`. The producer and generated application both
run as compiled Wasm through the same source driver.

## Text transport

The adapter streams the produced string to the runner one Unicode scalar per
call through the reserved `lofi:generator/character` import.
[`run-lofi-generator.mjs`](../scripts/run-lofi-generator.mjs) collects those
scalars and writes the text for the driver. Diagnostics in generated code name
the recipe path followed by `#generated`, with lines and columns in the
generated text. Text containing anything other than one `define-library` form,
or a library with a different name, is rejected.

## Selection, identities and separate preparation

Search paths map `(demo answer)` to `demo/answer.sld`. The first matching path
wins, including when its contents are malformed. A selected file's declared
name must match the requested key. Diagnostics retain that chosen path.

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

`runner-path` normally names `scripts/run-lofi-generator.mjs`.
`initial-libraries` is an explicit association list of keys and unresolved
library values, including `(lofi primitive)` when required. Search directories
are explicit; direct API calls add no implicit directory. Source CLI commands
append the repository's `src` after the supplied `-I` directories.

`prepare-library` produces only the requested value. It obtains a generator's
producer closure, but does not obtain imports of its returned library.
`collect-libraries` returns the entry library and its complete application
dependency closure. `collect-source-file` returns two values: the root key and
that map. It also accepts the anonymous source-script syntax. With a false
context, encountering a generation recipe is an error.

The driver copies the initial association list while preserving library object
identity and aliases. A prepared value can be supplied to a later collection
under one or several keys. Independently repeated preparation operations create
fresh values; there is no global generation cache. Failure ends the operation;
partially prepared state is not published.

## Explicit foreign services and source context

Other foreign services come from an explicitly selected ES module:

```sh
./lofi run --generation-provider ./build-providers.mjs -I generated main.sld
```

The same option is supported by both build scripts. The module exports:

```javascript
export function createProviders(sourceContext) {
  // Acquire caller-defined services using sourceContext.sourceDirectory.
  return {providers: new Map(), close() { /* Release those services. */ }};
}
```

The factory may be asynchronous. Its frozen context contains `sourcePath`,
`sourceDirectory`, and a frozen `libraryKey` array. Paths are absolute. A new
process and provider scope serve each recipe.

`providers` must map foreign module names to genuine `WebAssembly.Instance`
objects, whose function signatures the execution adapter checks. The reserved
`lofi:generator` module cannot be supplied. Once the factory returns a valid
scope, the runner calls `close` exactly once after success or failure, awaiting
it when necessary, before writing the generated text. Both execution and
cleanup errors are retained when both fail. Already performed provider effects
are not rolled back.

## Verification

`scripts/test-lofi-generation` compiles and executes nested producers and their
generated applications. It checks distinct producer and consumer imports,
independent preparation, explicit aliases, initialization through diamond
imports, descriptor-relative input, name hygiene, wrong result types, generated
checking locations, malformed and misnamed output, missing dependencies,
preparation cycles, first-path selection, and provider cleanup on failure.
