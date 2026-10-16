# Compiler calls from SFIR

[`(sfir compiler)`](../lib/sfir/compiler.sfir) exposes compilation, Wasm loading,
instantiation and scalar entry calls to ordinary compiled SFIR programs. Its
explicit foreign service keeps the compiler implementation in Scheme hosted by
Chibi. The caller supplies an immutable library map and a public entry;
compilation does not search directories, read source files or run generators.

The service currently runs in Node on Linux with Chibi, the existing Binaryen
tools, `mkfifo` and GNU `ps` available. Compilation always returns a Wasm artifact.
Native builds use ordinary Chibi scripts that pass Wasm to the separate native
package; independent native instances use the
[Scheme native adapter](sfir-native-loading.md). This is a correctness
implementation, with no claim about compile-service latency or clean benchmark
timings.

## Values and errors

Every fallible public operation returns `(CompilerResult T)`:

```scheme
(match (compile libraries (entry application-key "main"))
  ((compiler-success artifact) (use-artifact artifact))
  ((compiler-failure message) (report-error message)))
```

The example assumes supplied `libraries`, `application-key`, and result handlers.
`CompilerResult`, `compiler-success` and `compiler-failure` are ordinary generic
SFIR datatype definitions. Diagnostic messages are copied into ordinary SFIR
strings. Parser and checker errors preserve source names and locations.

`LibraryMap`, `Artifact`, `Code` and `Instance` are nominal service handles. They
belong to the host scope that created them; they contain no managed heap pointer.
The service checks ownership, resource category and lifetime on every operation.
Result values require an open scope; calling its foreign provider after scope
closure fails at the host boundary because its result storage has been released.
`Entry` contains a nonempty list of string key components and a public export
string. `(provider-set name)` selects a provider map explicitly installed by the
host. The service snapshots these maps when opened; their Wasm instances remain
borrowed services that the host may deliberately share.

## Parsing inspectable library values

`(parse-library source-name source-text)` returns `(CompilerResult SfirLibrary)`.
It reads exactly one `define-library` using the existing Chibi frontend and copies
its unresolved declarations into the same immutable [syntax API](sfir-builder.md)
used by generators. The result supports every builder inspection view and can be
rebuilt or transformed before `library-map-insert`.

```scheme
(let original (require (parse-library "math.sfir" source-text)))
(let changed
  (match (inspect-library original)
    ((view-library key scope imports exports declarations span)
      (sfir-library replacement-key scope imports exports declarations span))))
(let libraries (require (library-map-insert dependencies application-key changed)))
(let artifact (require (compile libraries (entry application-key "run"))))
```

The example assumes supplied text, name lists, dependencies and a `require`
function that handles `CompilerResult`. Source names provide diagnostic locations;
parsing does not read files, obtain imports, execute initializers, infer types or
optimize. Numeric syntax retains its original spelling until the ordinary checker
selects a representation. Attached quantified identities remain visible in their
initializers. Forward definitions and sequential lets retain their distinct scope
rules and original declaration order.

Fresh parsing creates fresh scope and binding identities. Aliasing or reinserting
the same returned value preserves its library identity within the service scope.
Constructing a replacement library creates a new library value. Source strings
and mutable data obtained from views are copied, so changing them cannot change
an existing library. All values retain the service's builder lifetime.

## Supplying libraries

| Operation | Arguments | Success value |
| --- | --- | --- |
| `empty-library-map` | none | `LibraryMap` |
| `library-map-primitives` | map | map containing `(sfir primitive)` |
| `library-map-parse` | map, key, source name, source string | map containing the parsed library |
| `library-map-insert` | map, key, parsed or constructed `SfirLibrary` | map containing the received library |
| `library-map-alias` | map, existing key, new key | map with another key for the same library |

All operations return a new map and preserve the prior map. Insertion replaces
an existing key. A supplied key is an explicit lookup choice and need not match
the library's descriptive name. Keys use `(List String)` in this adapter.

Source insertion requires exactly one `define-library`. It parses the supplied
text once into an owned unresolved library in Chibi. The source name provides
diagnostic locations; it is not a file read. Changing the caller's source string
after insertion cannot change the stored library. Parsing identical text again
creates fresh local identities. The primitive library is added only by the
explicit `library-map-primitives` call.

Syntax-value insertion uses the existing [builder protocol](sfir-builder.md).
The builder checks its invocation handle, copies reachable immutable syntax into
an owned packet, and Chibi checks and receives that packet. Repeated insertion
of the same parsed or constructed library preserves identity within this service scope.
The receiver caches only the unresolved library; resolution and checking still
use each supplied map. Aliases preserve identity for both construction paths.
Imports in either kind of library must be supplied separately.

`library-map-parse` retains its combined source-to-map operation for callers that
need no intermediate syntax value. Both parsing operations use the same frontend.
The first-class path transfers the parser's syntax graph into the builder arena;
its checked token conversion verifies builder ownership and the library category.
Full reception checks lexical ownership again before inserting the library. The
packet contains declared syntax and identities, never inferred checking evidence.

## Artifacts and independently initialized instances

| Operation | Arguments | Success value |
| --- | --- | --- |
| `compile` | map, `Entry` | Wasm `Artifact` |
| `write-artifact` | artifact, explicit path string | `Unit` |
| `load` | artifact | `Code` |
| `instantiate` | code, `(provider-set name)` | `Instance` |
| `invoke-entry` | instance, `(List ScalarValue)` | `ScalarValue` |
| `close-instance` | instance | `Unit` |

Compilation retains the existing monomorphic scalar entry restriction. Loading
copies the owned artifact into the [Wasm execution adapter](../src/snail-sfir/execute.mjs).
Provider linking happens during instantiation, after compilation. The engine
checks actual provider and entry function signatures before initializers run.
Every instantiation has separate library state. Aliases initialize one library
identity once within that instance; separate loads do not share mutable state.

`ScalarValue` has `scalar-i32`, `scalar-i64`, `scalar-f32`, `scalar-f64`,
`scalar-bool`, `scalar-char` and `scalar-unit` constructors. Calls check the
complete saved semantic argument signature before execution, including the
distinction between I32, Bool and Char despite their common physical Wasm type.
Unit is supported as a result, not as an entry parameter. Results are checked
and decoded with their saved semantic type. The adapter preserves I64 precision,
Unicode scalar characters, floating signed zero, infinities and NaNs according
to its existing scalar transport contract.

Failed initialization returns `compiler-failure` and publishes no instance.
Effects already performed by providers remain. A failed invocation also returns
`compiler-failure`; the instance remains usable, and preceding state changes and
external effects remain. Closing an instance is idempotent. Later calls on that
instance fail. A callback cannot close an actively executing instance or the
whole service scope; these checks happen before any resource is released.

## Explicit host ownership

The host compiles the build program using the existing compiler and opens its
services explicitly:

```javascript
import {readFileSync} from 'node:fs';
import {openCompilerService} from './src/snail-sfir/compiler-service.mjs';
import {loadWasm, instantiate, invokeEntry, closeInstance}
  from './src/snail-sfir/execute.mjs';

const service = openCompilerService({
  providerSets: new Map([['empty', new Map()]])
});
let program;
try {
  program = instantiate(loadWasm(readFileSync('build-program.wasm')), service.providers);
  invokeEntry(program, []);
} finally {
  if (program) closeInstance(program);
  service.close();
}
```

The returned provider map contains `sfir.compiler` and the matching
`sfir.builder`. Additional build-program providers can be added explicitly.
Provider sets selected by the build program are separate from that provider map.
There is no automatic compiler-service installation in the source CLI or recipe
runner. Source discovery, source reads, dependency preparation and provider
acquisition remain explicit host or driver operations.

One service owns one Chibi process, its unresolved values and immutable maps,
copied artifacts, loaded code, instances and builder arena. Handles and transport
buffers remain owned until `service.close()`; `close-instance` releases instance
state earlier. Scope close invalidates all handles, kills the owned process group
and checks within two seconds that no group member is running. Node reaps its
direct child when its event loop resumes. Closure also closes FIFO descriptors
and removes temporary files, including when termination checking reports an error.
It does not close
borrowed foreign providers or delete explicitly saved artifacts.

Requests use a fixed local JSON command protocol, not Scheme evaluation. Chibi
and Node exchange owned syntax packets and artifact bytes. A request timeout or
broken protocol closes the compiler connection and retains its diagnostic for
later map operations. Previously copied artifacts, code and instances remain
usable until scope close. Ordinary parser or compiler diagnostics leave the
connection usable. `openCompilerService` accepts an explicit `chibi` executable
and a positive `timeout` in milliseconds; the default request timeout is 120000.
The deadline is checked while output continues arriving as well as while waiting.
Startup uses the same owned group and deadline, with no separate preflight process.

## Verification

Run `scripts/test-sfir-compiler-service`. Its linked
[SFIR build program](../tests/sfir-compiler-service/program.sfir) exercises every
public operation, source and constructed imports, alias initialization, missing
dependencies, copied source ownership, separate state, provider mismatches,
semantic signature rejection, all seven result types, failed initialization,
recoverable invocation traps and saved artifacts after scope close. Separate
boundary tests reject foreign and wrong-category handles, stop an explicitly
owned Chibi process, execute its already copied artifact, and check reentrant
closure and temporary-file cleanup. Noisy and stalled hosts test deadlines;
a host and descendant that ignore SIGTERM test bounded group shutdown and reaping.
Command records are retained under
`build/sfir-compiler-service/`; they are correctness diagnostics, not timings.

`scripts/test-sfir-parsed-library` executes an ordinary compiled SFIR program that
parses source, inspects and rebuilds its syntax, changes its public export,
compiles explicit maps and invokes the results. It checks fresh parse identities,
repeated insertion aliases, source-string ownership, original-library reuse, and
errors deferred until map resolution or type checking. The builder suite also
reconstructs a complete parsed library through SFIR views, compares linked Wasm
and native behavior, and checks exact numeric precision and diagnostic locations.
The parsing runner retains bounded command records and artifacts under
`build/sfir-parsed-library/attempt-*/`.
