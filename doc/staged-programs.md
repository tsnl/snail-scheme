# One source, several execution targets

This is a design scope, not an implemented language extension. It extends the
[generated-library proposal](generate-library.md) toward applications containing
server code, browser code, and typed GPU programs in the same source file.
The surface forms below are sketches; their names and import syntax are open.

This is a supporting staging proposal for the current
[platform design](why-snail-scheme.md). Actors own their heaps and globals;
connections can carry invocations returning values, futures, or streams. Every
actor crossing serializes even locally. Native providers own scheduling and IO,
so script-owned event loops are unnecessary. The
[chat](tutorials/02-chat/README.md) and [tensor](tutorials/03-tensors/README.md)
projects are the intended integration targets. Older counter-workbook and target
syntax sketches below remain illustrations, not additional settled APIs.

## Separate phase from execution target

Two questions apply to every binding: when does it run, and where does it run?

| Code | When | Where | Result |
| --- | --- | --- | --- |
| Reader or syntax transformer | Generation/expansion | Compiler host, initially Chibi | Located syntax and declared artifacts |
| Application builder or graph tracer | Build evaluation | Build actor, initially hosted by Chibi | Application descriptions, typed graphs, artifacts, or compiler requests |
| Server procedure | Application runtime | Server Scheme runtime | HTML, responses, model snapshots |
| Browser procedure | Application runtime | Snail-Scheme WASM runtime | Model changes and DOM operations |
| Shader generator | Generation/expansion | Compiler host | Typed shader IR, WGSL, interface metadata |
| Shader entry point | Draw or dispatch | GPU | Vertex, fragment, or compute results |

Server and browser are separate runtime targets, not successive macro phases.
Likewise, a vertex shader's pipeline stage is distinct from a compiler phase.
A compiler can generate programs for several targets without running any of
their application bodies. WGSL constants and pipeline specialization parameters
introduce additional evaluation times; they should retain their own meanings.

A static document evaluates a view once. An interactive application evaluates it
after model changes. The model/update/view interface can serve both. Placement
still matters: a server-only database operation cannot become a browser-local
procedure merely because both are written next to the view.

## Build evaluation is an actor invocation

In the [actor model](why-snail-scheme.md#building-is-another-use-of-the-platform),
the build runtime loads a Scheme artifact, spawns its build actor, and invokes
`build`. A single-shot build actor retires after the job, reclaiming its heap.
Compiler and storage services can expose connections too; compilers remain ordinary
libraries that can also be called locally. Artifacts are the code/data consumed
and produced. Native runtime adapters implement loading and dispatch.

Use the same actor model for building and for running the resulting application.
The initial `build-interpreter` accepts a Scheme source artifact, prepares its
libraries, and dispatches one build request to an exported `build` procedure.
The source artifact includes its explicit entry library, dependency mappings,
and source origins. It need not already be a compiled binary. Loading the source
uses the Scheme reader and expander; it does not discover a language from a prefix
or extension. The build contract can later also be implemented by a host loading
compiled build code, without changing what a build request means.

There are three useful operations, with different input and output values:

| Operation | Consumes | Produces |
| --- | --- | --- |
| Expand | Located syntax and transformer bindings. | Expanded syntax or IR retaining lexical meaning and source origins. |
| Evaluate a builder | A prepared Scheme build module and build inputs. | An application description, generated data/IR, and requested compilation work. |
| Run a shipped artifact | Compatible code/data artifacts and an actor's incoming messages. | Results, outgoing messages, effects, and possibly further artifacts. |

These are relative stages, not three globally fixed times. Running a builder is
ordinary Scheme evaluation. That evaluation can generate another Scheme module,
whose compilation expands more macros, or construct a tensor graph that is
compiled directly from IR. A deployed actor can also produce later artifacts if
its contract provides that capability. The dependency graph records which inputs
each evaluation needs, and diagnoses actual stage/dependency cycles.

An application object is a result of evaluation. Scheme functions can compose
it, choose components from configuration, calculate constants, and construct
graphs. A compiler implemented as a pure procedure can consume a graph and return
artifact bytes during the same invocation. Compilation requiring an external
tool or another actor is an explicit effect, supplied through runtime functions
or returned commands. No special compiler meaning is attached to every procedure
that happens to construct an application.

Single-shot means one build request and one terminal success or failure. It does
not require one uninterrupted invocation stack. A builder composes an application
plan containing target recipes; native services can resolve dependencies and run
compiler jobs. A pending artifact reference identifies a dependency, not bytes
already available to load. The build handler can suspend for a future or resume
orchestration through subsequent messages, according to its connection contract.
Its globals and continuations stay in its actor until the build is finished.

On success, the build actor publishes an application manifest and references to
completed artifacts. The manifest records selected actor contracts, profiles,
connections, and required runtime bindings. The build result must not report
success while required compilation work remains pending. A failed job returns
diagnostics without publishing an incomplete application as the new usable build.
Scheduling compilation, storing outputs, and dispatching completion messages are
runtime and service-actor operations; the Scheme build handler owns application
composition.

The [actor model](why-snail-scheme.md#building-is-another-use-of-the-platform)
uses artifacts as loadable code/data and typed messages for requests, completions,
and effects. A graph, source bundle, executable, or static document can be an
artifact, with an explicit format and interface. Actor implementations interpret
their supported formats. Sharing a protocol does not make their instruction sets,
host APIs, or scheduling guarantees interchangeable.

Only deliberately represented values cross to a later actor: syntax with its
required context, typed IR, encoded data, or artifact references. Build-time
closures and live host objects can be used locally while constructing a graph;
they do not travel with the builder's heap. Generated code captures supported
constants explicitly. Durable application data belongs to an explicit service,
independent of an actor that may be replaced. Globals persist within an actor's
lifetime, not across its destruction. All actor deliveries encode and decode,
including local service messages; ordinary calls within a job stay local.

Source reads, configuration, compiler/tool versions, and any other effect inputs
belong in the build's dependency accounting. Controlled randomness requires an
explicit seed. Running arbitrary Scheme does not establish reproducibility or
make an untracked computation cacheable. The first build actor can rebuild each
time; the shared effect boundary lets later caching observe dependencies.

The compiler remains hosted by Chibi. A first build interpreter can execute
host-compatible build libraries there and invoke the existing compiler as a tool.
Evaluating these builders with Snail's own runtime depends on the embedding and
library support milestones. It does not require the compiler itself to move into
that runtime. General procedural transformers and phase-qualified imports remain
separate missing capabilities; naming a build actor does not implement them.

## Tracing constructs a later program

[JAX tracing](https://docs.jax.dev/en/latest/tracing.html) runs a function with
tracer values carrying information such as input shapes and element types, and
records supported operations as an intermediate program. Static host operations
execute while tracing; recorded operations execute later. Snail can adopt this
separation with an ordinary library of graph-building procedures.

For example, a Scheme builder can compose neural-network layers using lists,
higher-order functions, and configuration. Tensor primitives operating on symbolic
inputs construct a typed graph. A graph compiler validates that graph and produces
an artifact for a compatible graph-execution actor. Input signatures and graph types
constrain the later program, while the Scheme builder can remain dynamically typed.
Model weights can be explicit artifact data or later runtime inputs; the build
must choose which and include that choice in its dependencies and interface.

Start with explicit tensor primitives and graph control-flow operations. Ordinary
Scheme `if` treats every value except `#f` as true; a symbolic predicate represented
by a record would therefore select a host branch instead of emitting a graph
branch. A tracing dialect needs explicit graph conditionals or transformed,
checked conditionals that distinguish static and symbolic tests. Overloading
arithmetic alone cannot trace arbitrary Scheme control flow.
[R7RS booleans](https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-8.html#TAG:__tex2page_sec_6.3)
specifies that truth convention. Side effects performed while constructing a graph
likewise do not become effects of the shipped graph automatically.

Shader syntax transformers and tensor tracing can thus share artifact production
and actor dispatch while retaining their own language semantics and validation.
Neither requires every graph-building operation to become a syntax transformer.
The actor and typed-graph APIs described here are planned, not implemented.

Large graph data and model weights use the
[external-storage model](why-snail-scheme.md#resource-lifetimes-are-a-programming-tool):
the intended policy bounds Scheme working memory while explicit 64-bit ranges
identify external binary data. Current WasmGC references do not establish a
32-bit Scheme heap layout or enforce that policy. Graph and compiler actors can
eventually work on bounded windows or ask native
storage/device actors to transfer data directly. This does not make tracing,
compilation, and graph execution the same operation or require an actor per tensor
element. Actors delimit independently scheduled work and ownership.

## Build targets, artifacts, and applications

Use `define-target` as the working name for a declaration that produces one
primary compiled artifact for a selected configuration. `define-build-target`
is the more explicit alternative. An application description assembles several
targets and their required actor services, and can itself be an exported library
binding. Reserve `define-application` for shorthand defining that description,
if it needs its own syntax. These names and clauses remain proposals. A target is
an artifact-producing recipe in a library, not a separate execution primitive.
Its output can instantiate a message handler or supply code/data to a service.

| Name | Meaning |
| --- | --- |
| `define-library` | Reusable Scheme bindings with an import/export interface. |
| `generate-library` | Generation-time code producing a library implementation. |
| `define-target` | A named unit to compile and package under a host contract. |
| Artifact | Code or data with a declared format and interface; building a configured target produces one primary output artifact. |
| `define-application` | Possible shorthand for binding a composable application description. |

`define-program` suggests an executable program more readily than an actor
module or shader. `define-artifact` names the output, whereas `define-target`
names the source declaration from which different configured outputs can be
built. The build graph can select several targets without requiring an
application declaration in the first implementation.

[R7RS program structure](https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-7.html)
does define a program as imports followed by definitions and expressions, with
outer expressions executed in order. It does not provide this kind of named
artifact declaration or actor dispatch contract. Ordinary Scheme programs
can continue to use that existing execution model.

A Scheme target can reuse library-style imports, exports, and an optional
`begin` body. The additional contract describes how a host invokes the exported
behavior. For example:

```scheme
;; browser.target.scm -- proposed declarations, not executable today
(define-target (workbook browser)
  (import (workbook contracts)
          (workbook browser-behavior))
  (contract (message-handler <browser-message>))
  (export handle))

;; server.target.scm
(define-target (workbook server)
  (import (workbook contracts)
          (workbook server-behavior))
  (contract (message-handler <server-message>))
  (export handle))
```

The illustrative `(workbook contracts)` library supplies function/dispatch
contracts. Each target specializes its interface with message types from
its own imports; the shared interface library need not import both behaviors.
The behavior libraries supply the exported procedures. Exact contract syntax
and how its metadata is made available to the build driver remain open. Message
and model declarations supply their schemas. Models arrive as explicit message
data or through state-service requests; the contract does not retain them as
Scheme actor fields. A handler can call ordinary `update` and `view` helpers.
Contract metadata must be available without executing the application's runtime
bodies during compilation.

The build produces one artifact for each configured target. The `export` clause
above describes the interface inside that artifact; producing one artifact does
not restrict it to one exported procedure or imply a Scheme-owned `main`.
The runtime owns dispatch. A native executable can link the selected Rust runtime
with the behavior, while a module can be loaded by a compatible existing host.

In a `define-target` body, definitions and initialization expressions retain
runtime semantics, including the selected actor contract's invocation lifetime rules.
They are not generator code. `generate-library` remains the explicit mechanism
for running Scheme to produce library syntax at generation time. A Scheme target
should reuse ordinary library expansion and add a compilation root and contract
adapter, rather than introduce another interpretation of procedure bodies.

Keep three choices visible: the logical target, the host contract, and the build
profile. A profile chooses supported platform/ABI, output format, runtime adapter,
and optimization settings. It must satisfy the declared contract. `wasm` alone
does not distinguish a WASI command from a browser behavior module. Likewise,
a native executable and a native loadable module have different host interfaces.
The current CLI already uses `--target` for a platform; a future CLI must make
logical target selection distinct from that existing option.

A typed shader target could produce WGSL or SPIR-V through suitable backends.
Its declared shader interface and dialect constrain the valid profiles. Selecting
SPIR-V must not silently reinterpret arbitrary dynamic Scheme as shader code.
Shader entry points and resource layouts also differ from actor methods and
message schemas. The artifact abstraction can cover both kinds of interface
without pretending they share one execution ABI.

An artifact reference should retain its logical target, configuration, format,
host interface, and produced location. A filesystem path is one materialization
of that reference. One primary payload may have supporting source maps, interface
metadata, or browser loader assets; WGSL itself is text. The build driver owns
output paths and publishes the related outputs coherently.

Source and artifact dependencies have different meanings. Importing shared
Scheme definitions compiles them for the consuming target. Declaring a dependency
on `./browser.target.scm` requests its browser artifact as an asset and does not
execute or link its Scheme behavior into the server. Source paths remain explicit;
the driver does not select a reader through a prefix or filename extension.
The exact artifact-dependency clause is still to be designed.

## Vendoring a multi-target application

A vendored library can export an application description: a value describing
targets, their connections, and the services they require. A consuming project
composes that value with other applications and supplies compatible profiles and
host bindings. The same description can be the root of a standalone application
or a member of a larger one. Being the root is a choice made by the build driver.
Building the application produces a set of configured target artifacts. Each
target still produces its one primary payload and supporting files.

Keep the build interface in an ordinary Scheme library, evaluated on the compiler
host. Its exports are descriptions or functions constructing descriptions. The
target source files contain the separate runtime imports and behavior exports.
For example, this proposed API describes target membership:

```scheme
;; vendor/workbook/build.sld -- illustrative compiler-host library
(define-library (acme workbook build)
  (export workbook)
  (import (scheme base) (snail-scheme build))
  (begin
    (define workbook
      (application
        (component 'server
          (target-source "./server.target.scm"))
        (component 'browser
          (target-source "./browser.target.scm"))))))
```

`application` and `component` here are proposed build-data constructors, separate
from the UI prototype's runtime `application` procedure. A component gives a
target or nested application a local name. `target-source` records an explicit
source file and its declaration-site origin; it does not compile the target.
It needs a source-aware form or an explicit origin argument. An ordinary procedure
receiving only a relative string cannot infer the caller's source location.
The files still contain the library-shaped `define-target` declarations above.

The consuming build module can reuse the description twice:

```scheme
;; site.build.sld -- source artifact selected for the build interpreter
(define-library (site build)
  (export build)
  (import (scheme base)
          (snail-scheme build)
          (acme workbook build))
  (begin
    (define (build)
      (application
        (component 'lessons workbook)
        (component 'playground workbook)))))
```

This sketch shows composition, not a complete deployment. It still needs profiles,
service connections, and host bindings. Those clauses remain to be designed.
`define-application` could abbreviate such a definition, but ordinary records and
procedures are sufficient to prototype the description API in Chibi. No special
package declaration or global target-registration side effect is needed.

The build interpreter dispatches its request to `build`, then resolves the
selected reachable targets. Importing a well-behaved build library only makes its
descriptions available; constructing them does not launch servers, create actors,
or execute target initialization. Build libraries can still run ordinary Scheme
code on import, so this is an API discipline, not a claim of enforced purity.
Keep dependencies and tracked source reads explicit before caching their results.
Runtime behavior libraries import their target's code and message types, without
depending on the compiler-host build library.

The public application interface should expose only the connections a consumer
needs. For the workbook, the browser requires a counter service channel; the
server behavior implements the corresponding message contract. A default assembly
connects these internally and exposes a browser mount plus its host requirements.
A factory could instead accept an existing counter service. In either case, the
runtime supplies the actual channel binding. A vendored browser target
does not hard-code a server URL or capture a build-host connection object.

Contracts already name their accepted message types. Connection metadata refers
to those types; it does not repeat their fields in an application schema. Derive
S-expression encoders and decoders from the shared record and union declarations,
compiled independently for browser and server. Validate connected interfaces when
building a closed graph, and validate boundary values at runtime. Independently
deployed peers also need an explicit compatibility check. Matching schema shapes
alone cannot establish compatible delivery or state semantics.

Keep runtime connections separate from build dependencies. Browser and server
actors can exchange messages in both directions while compiling independently
against a shared message library. A server's packaging dependency on a browser
artifact is a build edge; the browser's counter channel is not a reverse
dependency on the server binary.

Assign responsibilities explicitly:

| Library author supplies | Consuming application supplies |
| --- | --- |
| Behavior libraries, target declarations, message types, assets, and internal connections. | Which descriptions and optional parts to include. |
| Required actor contracts and supported target configurations. | Compatible profiles, runtimes, and service actors, such as browser WASM and a native HTTP host. |
| Required services and state guarantees. | Channel bindings, resource namespaces, storage, routes, and DOM mounts. |
| Source and artifact dependencies relative to their defining files. | Vendored source mappings and final output locations. |

Names such as `lessons/server` and `playground/server` distinguish members of the
composed graph. They do not require separate binaries or one actor per member.
Identical source and compile-time configuration may share a built artifact;
different runtime configurations and worker pools can use that same code.
For two independent workbooks, supply distinct counter model keys or state-service
namespaces. Their requests may use the same stateless workers. Sharing a counter
is an explicit binding/data choice. Stable resource identities and migration must
not depend on incidental build paths or temporary worker identities.
Library-qualified message type identity likewise remains unchanged when a
consumer renames an import or includes the application under a different name.

Application composition also does not require a process or WASM module for every
reusable widget. The vendor can export ordinary model/update/view libraries for
composition into an existing target, alongside the optional standalone target
assembly. Combining compatible behavior into one target is an explicit source
composition choice. Including two independently declared targets does not
silently merge their heaps, runtime adapters, or actor lifetimes. Shader artifacts can be
members of the same graph without acquiring actor semantics.

Vendor the sources and build descriptions first. Configure the mapping from
`(acme workbook ...)` to the vendored files explicitly. Resolve target sources and
assets relative to the defining library or target, so moving the vendor directory
does not make them relative to the consumer's working directory. This requires
loader work: the current compiler maps library names under fixed `src/` and
`bootstrap/` roots. It has no general vendored-source mapping or build-description
API. Shipping prebuilt artifacts can follow once profiles and host interfaces can
be checked; a path to an arbitrary binary is insufficient to establish compatibility.

This does not change `generate-library`'s stages. A generator may produce a build
library whose exports describe targets, or a runtime library whose exports are
behavior. Its outer exports still belong to the generated implementation. Merely
exporting a description does not execute the described application.

## A possible source shape

All of this can use the existing Scheme reader. No prefix, reader lookup, or
filename-extension dispatch is necessary.

```scheme
;; scene.scm -- illustrative, not executable today
(shared
  (define (update message model) (+ model message))
  (define (view model)
    (element 'output '() model)))

(server
  (define (serve request)
    (respond-with-application request 0 view (client-entry browser-entry))))

(client
  (define (browser-entry root initial-model)
    (mount! root (application initial-model update view))))

(shader tint
  (uniform color (vec4 f32) (group 0) (binding 0))
  (fragment (shade) (result (vec4 f32) (location 0))
    color))
```

`respond-with-application`, `client-entry`, `mount!`, and the enclosing forms are
proposed operations. `client-entry` denotes an exported browser artifact entry,
not a callable server closure. The response contains initial HTML, an explicitly encoded model,
and a reference to the browser artifact. It does not serialize Scheme procedures.
The `shader` form declares code and an interface; it does not draw anything.
A browser or native host would create a pipeline and submit rendering commands.

`browser-entry` above is a host-invoked startup hook. An actor contract can
instead expose initialization, update, and view methods directly. Neither shape
requires Scheme to own the process or browser event loop.

Each target block needs its own imports and lexical bindings. `shared` makes
selected source definitions available to both Scheme targets, with separately
compiled code and separately initialized state. It does not create shared mutable
memory or implicitly make those definitions shader-compatible. Reject imports
that cannot run on the selected target. Explicitly typed, portable numeric code
could later opt into GPU compilation as well.

Sharing code is an authoring convenience; a large application can put these
blocks in several explicitly named files. There is no requirement to put every
part of an application into one monolithic file.

These blocks could contribute named targets to the build graph. The source file
is an authoring unit, while the target and its interface determine compilation
and reload boundaries. The exact lowering from block syntax to target
declarations remains open.

## Crossings are explicit operations

| Boundary | What crosses | Required operation |
| --- | --- | --- |
| Generator to runtime | Syntax, literal constants, artifact references | Quote/build syntax; deliberately lift supported constants |
| Server to browser | Initial model or response data | Type-derived schema and S-expression encoder/decoder |
| Browser to server | Request message and response | Explicit asynchronous request, with success/failure messages |
| Local actor to actor | Typed request/event/reply | The same derived S-expression encoding and receiving-heap decoding |
| CPU to GPU | Packed buffer bytes, textures, resource bindings | Generated packing and host API calls |
| GPU to CPU | Copied/mapped result buffers | Explicit asynchronous readback |

A runtime closure, file port, database connection, DOM node, or raw GPU handle must
not leak across one of these boundaries by lexical capture. Explicit encoded
resource references are allowed where both sides share a compatible provider or
namespace. A transformer can capture compiler-host helpers while it runs, but it
must emit bindings valid in
the destination. Errors should name the reference, declaration, phase, and target.

For a server/browser exchange, derive the data schema entirely from the message
and model types and encode values as S-expressions. The actor contract selects
the accepted types; a separate schema declaration is unnecessary. The
[message-type design](why-snail-scheme.md#messages-cross-heaps-pointers-do-not)
describes type-derived reconstruction; the [chat specification](tutorials/02-chat/README.md)
exercises variants and compatibility. Calling an ordinary
server procedure from client code should fail expansion unless an explicit remote
interface supplies a stub. That stub represents latency and failure. In the
reducer API, a request produces a command and its completion delivers another
message; it must not make the pure reducer perform IO.
This command protocol is future work, not part of the current counter prototype.

Initial HTML and browser startup must agree on a model snapshot and build version.
The browser decodes S-expression data against the derived types before using it;
received datums are never evaluated as Scheme code.
The first browser host can replace a designated root and attach handlers. Preserving
server-created DOM nodes through hydration, user input, focus, and selection is a
separate milestone; sharing a `view` function does not implement it automatically.

Browser WASM also needs host imports for DOM, events, timers, fetch, and WebGPU.
WASM code does not gain these APIs from being compiled successfully. An initial
JavaScript adapter can own DOM/network resources and dispatch encoded events into
a browser actor. Retain endpoint/handler identifiers and explicit data rather than
unrooted callback pointers; never retain a closure into a retired actor. Scoped
native imports require borrows confined to their call. Memory views must be
refreshed after WASM memory growth.
[WebAssembly's web embedding](https://webassembly.org/docs/web/) describes its
integration with the browser environment.

## First browser/server workbook

This counter was the earlier split-application sketch. The
[chat tutorial](tutorials/02-chat/README.md) is now the full-stack integration goal.
Its browser actor may retain its local model; using a separate native model store
below is an application choice rather than a required actor-state policy.

The first split should have observable behavior on both sides. Keep the count
in an explicit server state service and explanation visibility in a browser-local
host state service. Scheme handlers receive snapshots or request them through
channels. A local explanation toggle should update the DOM without a network request.
Increasing the count should send a message to the server and render the returned
count without navigating to a new page. Initially use a reply from the server
before displaying a count change; optimistic updates add reconciliation work.

Separate the source responsibilities before introducing a combined-file reader:

| Source | Responsibility |
| --- | --- |
| `messages.sld` | Shared request/reply records and their unions; the complete source of their serialization schemas. |
| `server-behavior.sld` | Stateless handlers and pure count reducers; explicit requests to the state service. |
| `browser-behavior.sld` | Stateless event/reply handlers and view composition using browser-host snapshots. |
| `contracts.sld` | Handler/channel protocols and shared message/model types, with state/resource assumptions. |
| `server.target.scm` | Server behavior exports and host contract. |
| `browser.target.scm` | Browser behavior exports and host contract. |

These are proposed source roles, not files already present in the prototype.
Shared message definitions compile independently for each target. Sending a
record encodes its value; receiving reconstructs it with the receiving target's
record types. Neither target shares Scheme objects or type-descriptor addresses
with the other. The type-derived codec belongs below application dispatch, so a
reducer does not manually assemble S-expression lists for each network request.

An Increase click follows this proposed sequence:

1. The browser handler returns a command to send an adjustment record to the
   workbook's counter channel.
2. The browser runtime encodes the record according to the accepted message type
   and sends S-expression data over the transport.
3. The server dispatches isolated work. A state-service request supplies a snapshot;
   a fresh reducer invocation proposes a new value and expected version. Local
   channel crossings also encode and decode.
4. The state service accepts the proposal under a conditional-update or transaction
   rule. A conflict follows the explicit retry policy rather than losing an update.
5. After commit, send a count/revision reply. The browser host updates its local
   model through its service and supplies a snapshot to view computation; the
   rendered data is delivered to the DOM host.

Use an ordinary HTTP POST and S-expression response for the first transport.
The response delivers data through the connection. A handler can suspend locally
while awaiting it; its Scheme stack never crosses the transport. Service references
keep HTTP routing out of reducers. The connector owns its routing, correlation,
and pending-exchange state. Request identities, revision
checks, and retry policy must specify how duplicates and old replies are handled.

The Chibi host can exercise both reducers and independent codec instances before
the browser runtime is ready. A genuine browser demonstration additionally needs
a repeatedly callable Snail WASM module and DOM/network host imports. The current
native/WASIp1 executable path does not yet provide those facilities; see the
[embedding plan](rust-interop.md#reusable-embedding-and-targets). JavaScript glue
can supply browser APIs while the reducers and message definitions remain Scheme.
It should not duplicate the message schema in a second handwritten implementation.

Acceptance should cover a local DOM update without network traffic, an encoded
server round trip without navigation, rejection of malformed or incompatible
messages before dispatch, and deterministic handling of duplicate or old replies.
First prove reconstruction with independently instantiated record types. Actor
isolation, durable storage, and reload remain separate runtime milestones.

## How this relates to generate-library

Keep `generate-library`'s existing proposed contract: imports belong to generator
code, exports belong to the resulting library, and its single `begin` is a
function body that returns generated implementation declarations.

A wrapper could select this source processor explicitly:

```scheme
;; scene.sld -- proposed generator use
(generate-library (demo scene)
  (export serve browser-artifact shader-artifacts)
  (import (scheme base) (demo staged-source))
  (begin
    (generate-application "./scene.scm")))
```

The primary result is an ordinary server library with separate generated imports.
Its exported artifact descriptors refer to the separately compiled browser module
and shader data. This preserves one wrapper's library identity. It also exposes a
missing build-system capability: recording additional outputs and dependencies.

Prefer a declared artifact graph to generators writing arbitrary output paths.
Each artifact needs a logical identity, target/profile, source origins, dependency
edges, output kind, and exported interface. The driver chooses output paths and
publishes a coherent build. A sidecar artifact API versus a structured generator
result containing artifacts remains an open design choice. Do not quietly change
`generate-library` into several unrelated library definitions.

Named targets can supply those artifact nodes. A generated library may refer to
their outputs, while `define-target` selects the implementation and host contract
to compile. Generating syntax, compiling each target, and executing its actors are
distinct operations. The first driver can rebuild each requested target before
adding caching keyed by the complete source, dependency, and profile inputs.

A future ordinary Scheme library could import procedural declaration transformers
and use `client` or `shader` forms directly in its body. That route and the explicit
wrapper route should use the same artifact model. Reading a nested shader block
must preserve it as syntax until its dialect expander handles it; the ordinary
Scheme expander must not first interpret shader forms as runtime function calls.

## Generalized syntax transformers

The current compiler already has located syntax, binding-aware `syntax-rules`,
and resolved Scheme HIR. It does not have a general compile-time evaluator,
phase-qualified library instances, a typed shader IR, or an artifact-producing
transformer interface. See [syntax.sld](../src/snail-scheme/syntax.sld),
[expand.sld](../src/snail-scheme/expand.sld), and [HIR](hir.md).

Extend that foundation with a procedural transformer protocol receiving located,
lexically contextual syntax and returning contextual syntax. Provide identifier
comparison, intentional syntax construction, fresh bindings, source-preserving
errors, and controlled local expansion. Existing source locations alone are not
hygiene. Preserve the expander's definition-site/use-site binding distinctions
rather than passing plain datums to a host `eval` and trying to recover scopes.

Macro helpers run in a distinct host environment. An explicit phase import loads
the transformer dependency there; runtime imports stay with their targets. Cache
and cycle keys must include phase and target, as well as module identity. Record
tracked source reads and tool/profile inputs for generated artifacts. Initially,
rerunning generators on every build is preferable to an unsound cache.

A declaration transformer may contribute an artifact through the compiler's
artifact interface. An expression transformer still expands an expression. This
keeps ordinary macros comprehensible while making module-producing constructs
possible. Mere procedural macro evaluation does not supply multi-output builds,
network semantics, or GPU validation.

## A Scheme shader dialect

Start with a typed subset whose emitted language is WGSL. Reuse Scheme reading,
syntax matching, hygiene infrastructure, and generation-time computation; use a
separate shader IR for shader semantics. The existing dynamic Scheme HIR and GC
runtime are not the representation of a GPU invocation.

A first subset should include explicit scalar/vector types, structures, fixed
arrays, local variables, arithmetic, conditionals, loops, direct function calls,
and vertex/fragment entry points. Add storage arrays, textures, samplers, and
compute entry points as the Resin port reaches them. Require annotations on entry
interfaces and resources; infer local expressions where straightforward.

WGSL constrains resource address spaces, interfaces, memory layout, and some
operations' control flow. Recursive functions are prohibited. These restrictions
need validation in addition to types. Consult the [WGSL specification](https://www.w3.org/TR/WGSL/).

Full Scheme remains available to the generator: it can recursively build a shader
or specialize a higher-order helper into first-order code. The resulting shader
must satisfy the target rules. Dynamic pairs, closures, continuations, exceptions,
and allocation in the Scheme runtime are outside the initial GPU subset. Numeric
conversion and overflow behavior need an explicit shader contract; host Scheme
arithmetic is not an automatic reference implementation for f32/i32/u32 code.

Emit WGSL plus generated-line-to-Scheme-source mappings, entry-point metadata,
resource layout, and required feature information. Validate emitted WGSL using
an actual WebGPU/WGSL implementation, then execute a small draw or dispatch.
Readable emitted source remains useful for debugging. GLSL output can follow as a
separate profile; language features and resource conventions do not map merely by
changing spelling. Snail's WASM work handles browser CPU code; shaders are a
separate output consumed by WebGPU.

## What Resin makes concrete

The relevant Python branch is
[`archive/main-v3`](https://github.com/tsnl/resin/tree/archive/main-v3), inspected
at `aa1e3612843297e94cc98102f44f6524b4528b6c`. Its
[`draw_2d.py`](https://github.com/tsnl/resin/blob/aa1e3612843297e94cc98102f44f6524b4528b6c/src/resin/draw_2d.py)
defines a NumPy `POD_QUAD_DTYPE` and bind-group layout, while
[`draw_2d.wgsl`](https://github.com/tsnl/resin/blob/aa1e3612843297e94cc98102f44f6524b4528b6c/src/resin/draw_2d.wgsl)
repeats the structure and binding declarations. One typed Scheme schema should
generate all three, including buffer writers and explicit padding.

The current `PodQuad` has four vec2 fields followed by four vec4 fields. Applying
WGSL layout rules gives offsets `0, 8, 16, 24, 32, 48, 64, 80`, size/array stride
96 bytes, and alignment 16. This is a derived porting test, not a new layout.
A useful contrasting fixture is vec3: its f32 payload has size 12 but alignment
16, so an array element occupies a 16-byte stride.
[WGSL memory layout](https://www.w3.org/TR/WGSL/#memory-layout) defines these rules.

A buffer schema should specify its address-space/profile, integer widths,
float encoding, matrix orientation, offsets, strides, and padding. A Scheme
record or vector in WASM memory is not automatically GPU buffer data. Generate
packing from the schema rather than exposing runtime object layout to the GPU.

Start with Resin's small
[`gpu.wgsl` blit shader](https://github.com/tsnl/resin/blob/aa1e3612843297e94cc98102f44f6524b4528b6c/src/resin/gpu.wgsl),
then port the 2D quad shader and its schema. The much larger 3D renderer introduces
additional resource and feature requirements and should follow. Keep the DOM host
for documents and controls; a canvas/WebGPU view can host Resin graphics beside
them. Layout, font shaping, clipping, input routing, GPU resources, and device
lifecycle remain real parts of a Resin port beyond its shader language.

## Small milestones with observable results

1. **Host the current UI in browser WASM.** Run the reducer locally, initially
   replacing a root with DOM output. Keep the same model/view used for initial
   HTML. Verify a button works with networking disabled after startup.
2. **Generate two targets from one located source.** An explicit Chibi-hosted
   processor separates server/shared/client blocks and records the browser
   artifact. Verify server bindings are absent from browser output, invalid
   cross-target references fail at their source location, and generator effects
   stay distinct from runtime effects. This can precede general procedural macros.
3. **Expose that processor through staging and transformer APIs.** Implement
   phase imports, contextual syntax construction, and declared artifact output;
   reuse them for `generate-library` and embedded declarations. Test capture,
   shadowing, stage cycles, tracked includes, and an edit rebuilding all outputs.
4. **Compile the blit shader dialect to WGSL.** Validate and draw a known texture;
   reject bad types, recursion, and invalid interface declarations with mapped
   diagnostics. Do not equate successful text generation with a working shader.
5. **Port the quad schema and renderer.** Compare generated offsets/packing with
   Resin's existing bytes, then draw textured bordered quads and compare pixels.
   Check device features before adding the 3D/compute path.

The immediate design decisions are target/phase import syntax, how generators
report additional artifacts, how initial models and remote messages are encoded,
and the first shader type/resource schema. A full distributed language, automatic
hydration, complete Scheme-on-GPU semantics, and two shader backends can wait.
