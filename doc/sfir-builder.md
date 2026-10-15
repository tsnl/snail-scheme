# Constructing and transferring library values

The compiler remains Scheme hosted by Chibi. An SFIR producer can now construct
a limited set of structured library declarations, execute as Wasm, and transfer
its result to that compiler. This uses neither a Scheme product frontend nor
source text as a substitute for declarations. The
[source driver](sfir-generation.md) can execute `generate-library` recipes using
this boundary. General compiler calls from SFIR remain future work.

## Constructive SFIR interface

[`(sfir compiler-builder)`](../lib/sfir/compiler-builder.sfir) provides nominal
types with private constructors and scalar handle fields. Its public functions
compose immutable syntax nodes owned by an explicitly supplied builder provider.
There is no mutable current library. Lists passed to constructors are ordinary
SFIR lists; their contents are copied into immutable host sequences.

| Values | Constructors |
| --- | --- |
| `Name`, `SourceSpan` | `builder-name`, `source-span` |
| `ScopeId`, `BindingId` | `library-scope`, `nested-scope`, `binding` |
| `BindingReference` | `local-reference`, `import-reference` |
| `TypeSyntax` | `type-i32`, `type-i64`, `type-f32`, `type-f64`, `type-bool`, `type-char`, `type-unit`, `function-type` |
| `Expression` | `literal-i32`/`i64`/`f32`/`f64`/`bool`/`char`, `reference-expression`, `lambda-expression`, `application-expression`, `conditional-expression` |
| `Declaration` | `definition` |
| `ImportSelection`, `ImportRename` | `all-imports`, `only-imports`, `import-rename`, `rename-imports` |
| `Import`, `Export`, `SfirLibrary` | `library-import`, `library-export`, `sfir-library` |

Each binding has an explicit scope and identity. Lambda scopes name their
lexical parent. A local reference carries a binding identity; an imported
reference carries the library's import scope and a name. An export accepts a
`BindingReference`, while `reference-expression` converts a reference into an
expression. Function bodies can refer to private bindings with the same spelling
as their parameters without confusing those identities.

The current declaration constructor defines a binding with an explicit scalar
or function type and an expression initializer. It does not yet construct
polymorphic signatures, local blocks, datatypes, classes, instances, overloads
or foreign declarations. The interface constructs values; it does not yet
provide general AST inspection. `SourceSpan` currently records a source name and
one-based line and column, matching the compiler's existing located nodes.

Library keys are descriptive name lists. They do not determine library identity
or authorize source lookup. The caller can register one received library under
several keys in the compilation map. Imports and export renames remain
descriptions until ordinary map resolution finds their supplied providers.

## Execution and ownership

[`library-builder.mjs`](../src/snail-sfir/library-builder.mjs) supplies the fixed
scalar constructor protocol as a typed `WebAssembly.Instance` provider. Its I64
handles contain an invocation tag and local node ID. Every operation checks the
origin, node category and referenced nodes. The receiver performs the remaining
lexical, declaration and graph checks before publishing a library value.

The normal driver operation is:

```javascript
const transfer = invokeLibraryGenerator(producerCode, producerProviders, inputs);
const packet = libraryTransferJSON(transfer);
```

`producerCode` comes from `loadWasm`. The selected scalar entry calls an SFIR
function returning `SfirLibrary`, then uses `library-token` to return its I64
transport token. `invokeLibraryGenerator` creates an invocation-owned
`sfir.builder` provider, instantiates the producer, invokes that entry and copies
the returned library's reachable syntax graph into an owned transfer. It closes
the instance and builder on success or failure. Caller-owned foreign providers
and their effects retain their usual lifetime; the adapter does not roll them
back or close them.

`openLibraryBuilder` exposes the same lifecycle for explicit driver composition:
its `provider` supplies constructors, `finish(token)` produces a transfer while
the arena is live, and `close()` invalidates all arena handles. Repeated finishing
of the same library returns the same owned transfer. A closed arena rejects
further operations; the transfer's copied data remains available.

The JSON packet has exactly `version`, `root` and `nodes` fields. Nodes have
closed tags and explicit references into that packet's node table. Numeric
literal spellings preserve I64 precision and floating special values. Integers
use decimal digits with an optional minus sign. Floats use decimal notation with
a fraction or lowercase `e` exponent (or both), or explicit `+inf.0`, `-inf.0`
and `+nan.0`. Scheme exactness/radix prefixes, rational, complex and polar
spellings are rejected. Bare integer text such as `"1"` is not a float spelling;
the provider emits `"1.0"`. Finite floats round from the exact decimal value.
Strings are names or literal data, never code to evaluate. There are no producer
heap pointers, live closures, checked types, filesystem paths to follow, or
authoritative origin strings in the packet.

## Receiving and compiling

The Chibi module [`library-transfer.sld`](../src/snail-sfir/library-transfer.sld)
accepts the packet through an explicit port:

```scheme
(define context (make-library-transfer-context))
(define transfer (call-with-input-file packet-path read-library-transfer))
(define generated (receive-library-transfer context transfer))
(define artifact
  (compile (cons (cons generated-key generated) output-dependencies)
           (make-entry generated-key 'run) wasm-target))
```

`read-library-transfer` parses a closed schema, checks reference kinds and
structural cycles, and owns the resulting data under a fresh opaque origin.
`receive-library-transfer` checks lexical ownership, duplicate declarations and
names, literal representations, imports and exports, then constructs the same
unresolved `SfirLibrary` graph as the frontend. Recursive code refers to binding
IDs; syntax itself must be acyclic. Normal resolution and type checking still
run, so a producer cannot forge evidence that a declaration has been checked.

Receiving the same owned transfer again in one context returns the same library
and binding identities. Reading the same bytes again creates a separate origin.
Keep the `transfer` value above when repeated reception should preserve identity;
calling `read-library-transfer` again starts another identity namespace.
Raw packets cannot select an existing origin or replace its syntax. Contexts
have no global cache or hidden file lookup. Producer dependencies and
`output-dependencies` are independent supplied maps, even when their keys overlap.

## Exact build and run example

[`examples/library-builder.sfir`](../examples/library-builder.sfir) constructs a
private zero-argument function returning I32 `42`, exports it as `run`, and
returns that library from its SFIR `produce` function. Its `build` function is
the scalar wrapper used by the driver. Run the complete example and boundary
checks from the repository root:

```sh
scripts/test-sfir-builder
```

The runner compiles `build` with its explicit producer map, executes the Wasm
producer, writes `build/sfir-builder/example.json`, receives it in a separate
Chibi process, and compiles it under `(generated answer)`. It then loads
`example-result.wasm` and verifies that invoking its `run` Entry returns `42`.
The [four small driver files](../tests/sfir-builder/) show the exact compilation,
transfer, reception and execution calls. Source reads and artifact writes occur
in these drivers, outside resolution and compilation.

Remaining work includes the complete declaration/accessor API, general compiler
services callable from SFIR, and native loading with independent state. The
[source driver](sfir-generation.md) now supplies recipe collection and
preparation-cycle diagnostics around the checked builder boundary.
