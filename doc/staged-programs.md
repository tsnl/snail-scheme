# One source, several execution targets

This is a design scope, not an implemented language extension. It extends the
[generated-library proposal](generate-library.md) toward applications containing
server code, browser code, and typed GPU programs in the same source file.
The surface forms below are sketches; their names and import syntax are open.

## Separate phase from execution target

Two questions apply to every binding: when does it run, and where does it run?

| Code | When | Where | Result |
| --- | --- | --- | --- |
| Reader or syntax transformer | Generation/expansion | Compiler host, initially Chibi | Located syntax and declared artifacts |
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

Each target block needs its own imports and lexical bindings. `shared` makes
selected source definitions available to both Scheme targets, with separately
compiled code and separately initialized state. It does not create shared mutable
memory or implicitly make those definitions shader-compatible. Reject imports
that cannot run on the selected target. Explicitly typed, portable numeric code
could later opt into GPU compilation as well.

Sharing code is an authoring convenience; a large application can put these
blocks in several explicitly named files. There is no requirement to put every
part of an application into one monolithic file.

## Crossings are explicit operations

| Boundary | What crosses | Required operation |
| --- | --- | --- |
| Generator to runtime | Syntax, literal constants, artifact references | Quote/build syntax; deliberately lift supported constants |
| Server to browser | Initial model or response data | Schema and encoder/decoder |
| Browser to server | Request message and response | Explicit asynchronous request, with success/failure messages |
| CPU to GPU | Packed buffer bytes, textures, resource bindings | Generated packing and host API calls |
| GPU to CPU | Copied/mapped result buffers | Explicit asynchronous readback |

A runtime closure, file port, database connection, DOM node, or GPU handle must
not leak across one of these boundaries by lexical capture. A transformer can
capture compiler-host helpers while it runs, but it must emit bindings valid in
the destination. Errors should name the reference, declaration, phase, and target.

For a server/browser exchange, use a declared data schema and a versioned endpoint
contract. Calling an ordinary server procedure from client code should fail
expansion unless an explicit remote interface supplies a stub. That stub represents
latency and failure. In the reducer API, a request produces a command and its
completion delivers another message; it must not make the pure reducer perform IO.
This command protocol is future work, not part of the current counter prototype.

Initial HTML and browser startup must agree on a model snapshot and build version.
Serialize data with a real codec rather than inserting Scheme text into scripts.
The first browser host can replace a designated root and attach handlers. Preserving
server-created DOM nodes through hydration, user input, focus, and selection is a
separate milestone; sharing a `view` function does not implement it automatically.

Browser WASM also needs host imports for DOM, events, timers, fetch, and WebGPU.
WASM code does not gain these APIs from being compiled successfully. An initial
JavaScript adapter can translate handles and copy strings/byte buffers across the
runtime boundary. Define callback lifetimes and root Scheme callbacks while the
host retains them. Memory views must be refreshed after WASM memory growth.
[WebAssembly's web embedding](https://webassembly.org/docs/web/) describes its
integration with the browser environment.

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
