# Constructing and transferring library values

The compiler remains Scheme hosted by Chibi. An Lofi producer can construct the
complete book library syntax, inspect and transform that syntax, execute as Wasm,
and transfer its result to that compiler. This uses neither a Scheme product
frontend nor source text as a substitute for declarations. The
[source driver](lofi-generation.md) can execute `generate-library` recipes using
this boundary. The [compiler service](lofi-compiler-service.md) also returns
ordinary parsed libraries through this same syntax API.

## Constructive Lofi interface

[`(lofi compiler-builder)`](../lib/lofi/compiler-builder.lofi) provides nominal
types with private constructors and scalar handle fields. Its public functions
compose immutable syntax nodes owned by an explicitly supplied builder provider.
There is no mutable current library. Lists passed to constructors are ordinary
Lofi lists; their contents are copied into immutable host sequences.

| Values | Constructors |
| --- | --- |
| `Name`, `SourceSpan` | `builder-name`, `source-span` |
| `ScopeId`, `BindingId`, `TypeVariableId` | `library-scope`, `nested-scope`, `binding`, `type-variable` |
| `BindingReference` | `local-reference`, `import-reference` |
| `TypeSyntax` | `type-i32`/`i64`/`f32`/`f64`/`bool`/`char`/`unit`/`string`/`bytevector`/`never`/`any`, `reference-type`, `list-type`, `vector-type`, `rest-type`, `function-type`, `rest-function-type`, `nominal-type`, `variable-type` |
| `Signature`, `ConstraintSyntax` | `binding-signature`, `all-signature`, `constraint` |
| `KindSyntax` | `kind-type`, `kind-constraint`, `function-kind`, `evidence-kind` |
| `Expression` | `literal-i32`/`i64`/`f32`/`f64`/`bool`/`char`/`string`/`bytevector`, `literal-number`, `reference-expression`, `lambda-expression`, `rest-lambda-expression`, `application-expression`, `conditional-expression`, `block-expression`, `annotation-expression`, `instantiation-expression`, `match-expression` |
| `MatchArm` | `match-arm` |
| `Declaration` (body statements) | `definition`, `signature-definition`, `inferred-definition`, `local-binding`, `inferred-local-binding`, `expression-statement` |
| `DataField`, `DataCase`, static `Declaration` | `data-field`, `accessor-field`, `data-constructor`, `datatype-definition` |
| `ClassMethod`, `MethodImplementation`, static `Declaration` | `class-method`, `typeclass-definition`, `method-implementation`, `instance-definition`, `kind-annotated-definition` |
| Extension `Declaration` | `extern-definition`, `overload-definition` |
| `ImportSelection`, `ImportRename` | `all-imports`, `only-imports`, `import-rename`, `rename-imports` |
| `Import`, `Export`, `LofiLibrary` | `library-import`, `library-export`, `lofi-library` |

“Complete book syntax” refers to the declaration, expression and type forms.
The signatures in the linked Lofi module are the implemented API reference;
the book's schematic records and compiler operations are not a second callable
interface. In particular, the book's opaque `LibraryId` corresponds here to an
invocation's library handle and the owned transfer's identity. There is no
public `LibraryId` field or constructor argument that can select a receiving
identity. Reusing an owned transfer in one receiving context preserves its
library identity; independently reading identical bytes does not.

The signatures distinguish syntax categories explicitly. The
original `definition` accepts a monomorphic `TypeSyntax`; `signature-definition`
and `local-binding` accept a `Signature`. `binding-signature` wraps a monomorphic
type, while `all-signature` supplies explicit type parameters, requirements and
a result type. `inferred-definition` and `inferred-local-binding` omit the
signature and let the ordinary checker infer it. Every `overload-definition`
requires an explicit `Signature`; there is no inferred overload constructor or
inspection variant. Transferred overload declarations follow the same rule.
Numeric scalar constructors select their width.
`literal-number` instead accepts a copied original source spelling and returns
unresolved numeric syntax; `view-number-literal` exposes that spelling. Its
numeric grammar and final representation are checked in Chibi. This preserves
source precision, exactness/radix prefixes and delayed range diagnostics without
choosing I32 or F64 at parsing time. `rest-type` exposes the source `Rest` type
form; ordinary checking still determines where it is permitted. `Unit` is constructed by an application of the imported `unit` operation.

Every binding has an explicit scope and identity. A local reference carries
that identity; an imported reference carries the library's import scope and a
name. `nominal-type` and `constraint` use the same reference values in their
respective static roles. An export accepts a `BindingReference`, while
`reference-expression` converts a reference into an expression. References can
intentionally distinguish visible bindings with the same spelling. The source
grammar's reserved names remain invalid for binders, public exports and import
rename destinations.

Each lambda, block and match arm owns a fresh `nested-scope` whose parent is its
enclosing lexical scope. Fixed parameters and the optional rest binding belong
to that scope. `block-expression` takes an ordered list of declarations followed
by a separate final expression. Its `def` bindings are visible throughout the
block; a `let` becomes visible only after its initializer. Repeated `let` names
have distinct identities. Datatypes, classes, instances and overloads require
library scope; foreign declarations also work inside blocks. A repeated overload
row uses the same family `BindingId`. A family whose name matches an imported
family extends that imported identity, including after import renaming.

Each `all-signature`, datatype and class owns another fresh `nested-scope` for
its `TypeVariableId` values. That scope's parent is the enclosing lexical scope.
The signature's parameters are visible in its signature and initializer;
datatype and class parameters scope their fields and method signatures.
Quantification does not create a runtime lexical scope: a lambda initializer
still names the surrounding lexical scope as its parent. Separate quantified
identities can share a spelling, while duplicate names in one parameter list
are rejected. Reuse of a scope by two binding owners is rejected. Shared
reference/type syntax is checked at each occurrence against that occurrence's
visible identities, even when the same node was valid elsewhere.

Kind annotations describe expected static kinds. A producer cannot manufacture
checked types, inferred schemes or instance evidence. Constructor arities,
nominal identities, class membership, exhaustiveness, foreign ABIs and overload
selection remain the ordinary resolver and checker's responsibility.
`SourceSpan` records a source name and one-based line and column, matching the
compiler's existing located nodes. Annotated value declarations can also retain
the attached signature's distinct source span. `signature-location` queries it;
`with-signature-location` returns a copied declaration with a replacement span.
Both operations require an annotated definition, local binding or overload.
Constructed declarations without that optional field use their declaration span.

## Inspecting and transforming syntax

`inspect-type`, `inspect-signature`, `inspect-kind`, `inspect-expression` and
`inspect-declaration` return their corresponding public `…View` datatypes.
Their variants expose every constructor's fields and can be matched normally.
`inspect-library`, `inspect-import`, `inspect-export`, `inspect-import-selection`
and `inspect-import-rename` expose library structure. `inspect-binding`,
`inspect-reference`, `inspect-scope`, `inspect-type-variable`, `inspect-span`,
`inspect-constraint`, `inspect-match-arm`, `inspect-data-field`,
`inspect-data-constructor`, `inspect-class-method` and
`inspect-method-implementation` cover the remaining structured values.

For example, this changes a library's descriptive key while preserving its
binding graph:

```scheme
(match (inspect-library original)
  ((view-library key scope imports exports declarations span)
    (lofi-library replacement-key scope imports exports declarations span)))
```

Views contain ordinary Lofi values and references to existing immutable syntax
nodes. They retain their invocation ownership. `same-binding?`, `same-scope?`
and `same-type-variable?` compare identities, independent of names.
`builder-name-text` returns a copied String. String and bytevector literal views
also return copies, so mutating those copies cannot change the inspected node.
A view constructor creates ordinary view data; only a checked syntax constructor
creates a syntax handle. [`rebuild.lofi`](../tests/lofi-builder/rebuild.lofi)
shows a compiled transformation that rebuilds a library through these views,
retaining every binding identity.

Library keys are descriptive name lists. They do not determine library identity
or authorize source lookup. The caller can register one received library under
several keys in the compilation map. Imports and export renames remain
descriptions until ordinary map resolution finds their supplied providers.

## Execution and ownership

[`library-builder.mjs`](../src/snail-lofi/library-builder.mjs) supplies the fixed
scalar constructor protocol as a typed `WebAssembly.Instance` provider. Its I64
handles contain an invocation tag and local node ID. Every operation checks the
origin, node category and referenced nodes. The receiver performs the remaining
lexical, declaration and graph checks before publishing a library value.

The normal driver operation is:

```javascript
const transfer = invokeLibraryGenerator(producerCode, producerProviders, inputs);
const packet = libraryTransferJSON(transfer);
```

`producerCode` comes from `loadWasm`. The selected scalar entry calls a Lofi
function returning `LofiLibrary`, then uses `library-token` to return its I64
transport token. `invokeLibraryGenerator` creates an invocation-owned
`lofi.builder` provider, instantiates the producer, invokes that entry and copies
the returned library's reachable syntax graph into an owned transfer. It closes
the instance and builder on success or failure. Caller-owned foreign providers
and their effects retain their usual lifetime; the adapter does not roll them
back or close them.

`openLibraryBuilder` exposes the same lifecycle for explicit driver composition:
its `provider` supplies constructors, `receive(packet)` copies a structurally checked
packet into fresh arena identities, and `finish(token)` produces a transfer while
the arena is live, and `close()` invalidates all arena handles. Repeated finishing
of the same library returns the same owned transfer. A closed arena rejects
further operations; the transfer's copied data remains available.

`checked-library` checks that an I64 transport token belongs to this live builder
and names a library node before producing the nominal Lofi value. Private record
constructors remain private. This is the service's entry from copied parse data;
provider code cannot silently reinterpret an arbitrary compiler descriptor.

The JSON packet has exactly `version`, `root` and `nodes` fields. Nodes have
closed tags and explicit references into that packet's node table. Numeric
literal spellings preserve I64 precision and floating special values. Integers
use decimal digits with an optional minus sign. Floats use decimal notation with
a fraction or lowercase `e` exponent (or both), or explicit `+inf.0`, `-inf.0`
and `+nan.0`. Scheme exactness/radix prefixes, rational, complex and polar
spellings are rejected for concrete scalar literals. Unresolved `number-literal`
nodes carry source spelling separately and use the existing source numeric reader.
Bare integer text such as `"1"` is not a float spelling;
the provider emits `"1.0"`. Finite floats round from the exact decimal value.
All transferred text must contain Unicode scalar values; lone surrogate escapes
are rejected. Strings are names or literal data, never code to evaluate. There
are no producer heap pointers, live closures, checked types, filesystem paths to
follow, or authoritative origin strings in the packet.

## Receiving and compiling

The Chibi module [`library-transfer.sld`](../src/snail-lofi/library-transfer.sld)
accepts one complete packet through an explicit, bounded port (a file or an
already framed message). It preserves all JSON control escapes and rejects
trailing input:

```scheme
(define context (make-library-transfer-context))
(define transfer (call-with-input-file packet-path read-library-transfer))
(define generated (receive-library-transfer context transfer))
(define artifact
  (compile (cons (cons generated-key generated) output-dependencies)
           (make-entry generated-key 'run)))
```

`read-library-transfer` parses a closed schema, checks reference kinds and
structural cycles, and owns the resulting data under a fresh opaque origin.
`receive-library-transfer` checks lexical ownership, duplicate declarations and
names, literal representations, imports and exports, then constructs the same
unresolved `LofiLibrary` graph as the frontend. Recursive code refers to binding
IDs; syntax itself must be acyclic. Normal resolution and type checking still
run, so a producer cannot forge evidence that a declaration has been checked.

Receiving the same owned transfer again in one context returns the same library
and binding identities. Reading the same bytes again creates a separate origin.
Keep the `transfer` value above when repeated reception should preserve identity;
calling `read-library-transfer` again starts another identity namespace.
Raw packets cannot select an existing origin or replace its syntax. Contexts
have no global cache or hidden file lookup. Producer dependencies and
`output-dependencies` are independent supplied maps, even when their keys overlap.

`write-library-transfer` copies a parsed, named library to this same packet. Its
identity maps use the parser's binder and type-variable objects, and lexical
structure supplies the scope owners. The retained `def`/`let` source former
preserves sequential shadowing. Existing source locations, including distinct
attached-signature spans, survive the copy. No source grammar is parsed again.

## Exact build and run example

[`examples/library-builder.lofi`](../examples/library-builder.lofi) constructs a
private zero-argument function returning I32 `42`, exports it as `run`, and
returns that library from its Lofi `produce` function. Its `build` function is
the scalar wrapper used by the driver. Run the complete example and boundary
checks from the repository root:

```sh
scripts/test-lofi-builder
```

The runner compiles `build` with its explicit producer map, executes the Wasm
producer, writes `build/lofi-builder/example.json`, receives it in a separate
Chibi process, and compiles it under `(generated answer)`. It then loads
`example-result.wasm` and verifies that invoking its `run` Entry returns `42`.
The [four small driver files](../tests/lofi-builder/) show the exact compilation,
transfer, reception and execution calls. Source reads and artifact writes occur
in these drivers, outside resolution and compilation.

The same runner builds a producer covering datatypes, classes, instances,
quantified signatures, nested generic scopes, rest functions, inferred and
annotated blocks, matches, overloads extended through renamed imports, local
foreign declarations, and string/bytevector literals. It rebuilds the result
through typed inspection views and compares it with ordinary Lofi source on
linked Wasm and actual native execution, including collection at every native
allocation. Malicious packets exercise lexical escape in both traversal orders,
wrong static roles, invalid Unicode, byte ranges, reserved names, duplicate
quantifiers and attempts to claim checking evidence.

The runner also transfers ordinary parsed source into the builder, rebuilds it
through compiled Lofi views and compares that result with the other two routes.
Precision probes cover I64 boundaries, F32 double-rounding and subnormal cases,
signed zero and computed conversions. Negative probes compare source and received
diagnostics. These checks are correctness evidence, not clean measurements.

The [compiler service](lofi-compiler-service.md) exposes parsing, explicit maps,
compilation and Wasm execution to Lofi. [Native loading](lofi-native-loading.md)
is separately available through its host adapter, which consumes a Wasm artifact.
Scheme elaboration and macro staging remain deferred.
