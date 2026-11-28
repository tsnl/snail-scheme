# Libraries

Every library that ships lives under `src/`, at the path its name gives:
`(snail shell graphics scan)` is `src/snail/shell/graphics/scan.sld`. They
come in layers, each importing only from the layers before it:

- **Core**, `(snail core …)`, imports nothing outside itself. The compiler
  imports only its `base`, `table` and `io`, so it can compile itself.
- **Runtime interfaces**, `(snail runtime …)`, declare one host interface's
  WebAssembly imports and nothing else, so they emit no code of their own.
- **The shell**, `(snail shell …)`, is everything else: written in
  `snail-scheme` over core and the runtime interfaces. The compiler, the
  build and the language server are shell libraries too.
- **Targets**, `(snail target …)`, run a program's `main` and give it the
  capabilities it asks for.
- **Application support**: `(lpc …)` draws Liberated Pixel Cup characters,
  `(datasets …)` links published datasets into programs, and each
  application under `src/apps/` keeps libraries of its own.

There are no `(scheme …)` compatibility libraries and no dynamic numeric
tower.

## Reading a library

A library's header comment, at the top of its file, says what it is for and
how it is used, usually with an example. Sections, each headed
`;; ---- Title ----`, divide the rest, and a compiler module's unit tests
sit in a final `Tests` section. This reference says what each library is
for, names its main entry points, and records what its code does not say:
why it is shaped as it is, what it costs, and how it fits with the others.
For anything finer, read the source, which each section links.

Three conventions run through the shell:

- **A capability is a record of functions** a function is handed, such as
  an `OutputPort`, a `Gpu` or a `Dom`. `host-NAME` makes the host's from a
  `Host`, which only a target holds, and `main` asks its target for what it
  needs by its parameters' types ([capabilities](../snail-scheme/capabilities.md)).
- **A page variant and a test variant.** `(… page)` libraries make a
  capability over the browser page, and `(snail shell dom memory)` and
  `(snail shell gpu record)` make ones that need no page or device, so an
  interface or a graphics library is tested in an ordinary program.
- **Waiting is suspension.** An operation that waits for the host, such as
  reading a file or a buffer, suspends the task that called it and nothing
  else ([task operations](../runtimes/tasks.md)).

## Index

### Core

| Library | For |
| --- | --- |
| [`(snail core forms)`](core.md#snail-core-forms) | The core forms and builtin types, served by the compiler |
| [`(snail core primitive)`](core.md#snail-core-primitive) | The operations the backend implements, with their types |
| [`(snail core base)`](core.md#snail-core-base) | The prelude: forms, numbers, `Option`, `Result`, lists, arrays, strings, prompts |
| [`(snail core io)`](core.md#snail-core-io) | Ports, files and directories, the clock, arguments and environment |
| [`(snail core table)`](core.md#snail-core-table) | Immutable tables from strings to values |

### Text and data

| Library | For |
| --- | --- |
| [`(snail shell math)`](data.md#snail-shell-math) | Elementary functions on `F64`, bit for bit libm's |
| [`(snail shell random)`](data.md#snail-shell-random) | A deterministic generator as a value |
| [`(snail shell text)`](data.md#snail-shell-text) | Unicode properties and case mapping |
| [`(snail shell utf8)`](data.md#snail-shell-utf8) | Strict UTF-8 encoding and decoding |
| [`(snail shell json)`](data.md#snail-shell-json), [`(snail shell json read)`](data.md#snail-shell-json-read) | JSON values, written as `JSON.stringify` writes them, and read back |
| [`(snail shell wire)`](data.md#snail-shell-wire) | Values to bytes and back, checked against their schema |
| [`(snail shell syntax)`](data.md#snail-shell-syntax) | The syntax a `generate-library` recipe returns |
| [`(snail shell inflate)`](data.md#snail-shell-inflate) | DEFLATE streams, decompressed |
| [`(snail shell zip)`](data.md#snail-shell-zip) | Zip archives, read a member at a time from the bytes given |
| [`(snail shell compiler sha256)`](data.md#snail-shell-compiler-sha256) | SHA-256, the same on both hosts |

### Tasks, files, processes and networks

| Library | For |
| --- | --- |
| [`(snail shell task)`](system.md#snail-shell-task) | Cooperative tasks, their scheduler, waits and mailboxes |
| [`(snail shell async-files)`](system.md#snail-shell-async-files) | Whole-file reads that wait as a task |
| [`(snail shell resource)`](system.md#snail-shell-resource) | Files a library links instead of embedding |
| [`(snail shell process)`](system.md#snail-shell-process) | Child processes, commands run to their end, and signals |
| [`(snail shell socket)`](system.md#snail-shell-socket) | TCP and UDP |
| [`(snail shell http)`](system.md#snail-shell-http), [`(snail shell http exchange)`](system.md#snail-shell-http-exchange) | A bounded subset of HTTP/1.1, and one exchange over a connection |
| [`(snail shell web)`](system.md#snail-shell-web) | The length of the file at a URL, and parts of it, on Node |
| [`(snail shell web zip)`](system.md#snail-shell-web-zip) | Zip archives on the web, pinned, their members kept in the machine's cache |
| [`(snail shell wasm)`](system.md#snail-shell-wasm) | Compiling, linking and calling WebAssembly modules |

### Pages, documents and interfaces

| Library | For |
| --- | --- |
| [`(snail shell page)`](pages.md#snail-shell-page) | What every page program shares: its events, its save and its boot |
| [`(snail shell app)`](pages.md#snail-shell-app) | Canvas applications: a scene drawn each frame, and a HUD |
| [`(snail shell ui)`](pages.md#snail-shell-ui), [`(snail shell ui page)`](pages.md#snail-shell-ui-page) | Document interfaces in the shape Elm gave them |
| [`(snail shell dom)`](pages.md#snail-shell-dom), [`(snail shell dom page)`](pages.md#snail-shell-dom-page), [`(snail shell dom memory)`](pages.md#snail-shell-dom-memory) | A document as a capability, over the page or in memory |
| [`(snail shell fetch)`](pages.md#snail-shell-fetch), [`(snail shell fetch page)`](pages.md#snail-shell-fetch-page) | Requests and server-sent events |
| [`(snail shell files)`](pages.md#snail-shell-files), [`(snail shell files page)`](pages.md#snail-shell-files-page) | Files the user drops on the page or picks |
| [`(snail shell base64)`](pages.md#snail-shell-base64) | Encode bytes as a data URL |
| [`(snail shell png)`](pages.md#snail-shell-png) | PNG files and data URLs of RGBA pixels |
| [`(snail shell sprite)`](pages.md#snail-shell-sprite) | Animations on sheets of equal cells |

### The GPU

| Library | For |
| --- | --- |
| [`(snail shell gpu)`](gpu.md#snail-shell-gpu), [`(snail shell gpu record)`](gpu.md#snail-shell-gpu-record) | WebGPU as a capability, and one that records instead of running |
| [`(snail shell graphics pod)`](gpu.md#snail-shell-graphics-pod) | Records laid out as WGSL lays out its structs |
| [`(snail shell graphics wgsl)`](gpu.md#snail-shell-graphics-wgsl) | Shaders as S-expressions, printed to WGSL at build time |
| [`(snail shell graphics kernel)`](gpu.md#snail-shell-graphics-kernel) | What every library of compute kernels needs |
| [`(snail shell graphics scan)`](gpu.md#snail-shell-graphics-scan) | An exclusive prefix sum on the GPU |
| [`(snail shell graphics radix-sort)`](gpu.md#snail-shell-graphics-radix-sort) | A stable radix sort of keys and values on the GPU |

### Rasterized graphics

| Library | For |
| --- | --- |
| [`(snail shell graphics atlas)`](rendering.md#snail-shell-graphics-atlas) | Pictures composed into texture-array pages |
| [`(snail shell graphics quad)`](rendering.md#snail-shell-graphics-quad) | 2D quads from those pages, one instanced draw a run |
| [`(snail shell graphics mesh)`](rendering.md#snail-shell-graphics-mesh) | Meshes as geometry and instance tables |
| [`(snail shell graphics raster)`](rendering.md#snail-shell-graphics-raster) | Batches of mesh instances, lit by the sun as they are drawn |
| [`(snail shell graphics passes)`](rendering.md#snail-shell-graphics-passes) | The sun, tone mapping and FXAA |
| [`(snail shell graphics fly)`](rendering.md#snail-shell-graphics-fly) | A camera that flies |

### Gaussian splats

| Library | For |
| --- | --- |
| [`(snail shell graphics splat)`](splats.md#snail-shell-graphics-splat) | Gaussians drawn as sorted, blended quads |
| [`(snail shell graphics ply)`](splats.md#snail-shell-graphics-ply) | 3D Gaussian Splatting's PLY files, read and written |
| [`(snail shell graphics colmap)`](splats.md#snail-shell-graphics-colmap) | COLMAP's sparse reconstructions |
| [`(snail shell graphics splat-view)`](splats.md#snail-shell-graphics-splat-view) | Gaussians drawn tile by tile, as training draws them |
| [`(snail shell graphics splat-train)`](splats.md#snail-shell-graphics-splat-train) | The differentiable splat renderer, as a tensor graph |
| [`(snail shell graphics splat-fit)`](splats.md#snail-shell-graphics-splat-fit) | Training: a step, densification and the opacity reset |

### Forward rendering

| Library | Responsibility |
| --- | --- |
| `(snail shell graphics gltf)`, `(snail shell graphics gltf animation)` | Parse authored materials, geometry, rigs and clips |
| `(snail shell graphics forward scene)` | Upload material images, vertex ranges and skin bindings |
| `(snail shell graphics forward render)` | Draw shadow cascades, opaque and translucent meshes into an owned texture |
| `(snail shell graphics forward environment)` | Prefiltered sky and directional lighting |
| `(snail shell graphics forward frame)`, `(snail shell graphics compositor)` | Open a color pass and present its output |

### Game simulation

| Library | For |
| --- | --- |
| [`(snail shell game physics)`, `terrain`, `vehicle`, `boarding`](games.md#movement-and-boarding) | CPU movement, vehicle kinematics and riders |
| [`(snail shell game humanoid)`, `pedestrian`](games.md#actors-and-scenery) | Character poses and walking behavior |
| [`(snail shell game scenery)`](games.md#actors-and-scenery) | Mesh shapes placed in a glTF scene |
| [`(snail shell game display)`](games.md#frame-pacing) | Display refresh divisor, pause settings and frame-time graph |

### Tensors

| Library | For |
| --- | --- |
| [`(snail shell tensor)`](tensors.md#snail-shell-tensor) | Tensor graphs of nodes and views |
| [`(snail shell tensor grad)`](tensors.md#snail-shell-tensor-grad) | Reverse-mode gradients, as more graph |
| [`(snail shell tensor adam)`](tensors.md#snail-shell-tensor-adam) | Adam's update, as more graph |
| [`(snail shell tensor fuse)`](tensors.md#snail-shell-tensor-fuse) | Fusing maps into fewer kernels |
| [`(snail shell tensor lower)`](tensors.md#snail-shell-tensor-lower) | A graph lowered to WebGPU buffers and dispatches |
| [`(snail shell tensor eval)`](tensors.md#snail-shell-tensor-eval) | A graph evaluated on the CPU, the kernels' specification |

### Tools

| Library | For |
| --- | --- |
| [`(snail shell compiler)`](tools.md#snail-shell-compiler) and its passes | Source to WebAssembly text, written in `snail-scheme` |
| [`(snail shell assembler)`](tools.md#snail-shell-assembler) | WebAssembly text to a module, and static linking, in-process |
| [`(snail shell project build)`](tools.md#snail-shell-project-build), [`(snail shell project web-app)`](tools.md#snail-shell-project-web-app) | Builds of scripts, and a page's web-app manifest |
| [`(snail shell lsp)`](tools.md#snail-shell-lsp) | The language server |
| [`(snail shell format)`](tools.md#snail-shell-format) | The formatter |
| [`(snail shell highlight)`](tools.md#snail-shell-highlight) | Source text as classified tokens, for coloring |

### Runtime interfaces and targets

| Library | For |
| --- | --- |
| [`(snail runtime browser …)`](runtime.md#the-page) | The page's events, save, document, requests and files |
| [`(snail runtime gpu)`](runtime.md#snail-runtime-gpu) | The host's WebGPU device |
| [`(snail runtime native …)`](runtime.md#nodes-own) | Node's sockets, processes, asynchronous files and the web |
| [`(snail runtime resource)`](runtime.md#snail-runtime-resource), [`(snail runtime wasm)`](runtime.md#snail-runtime-wasm) | Linked files and WebAssembly on every host |
| [`(snail target node)`](runtime.md#snail-target-node), [`(snail target browser)`](runtime.md#snail-target-browser) | The two targets |

### Liberated Pixel Cup art

| Library | For |
| --- | --- |
| [`(lpc layout)`](lpc.md#lpc-layout) | The geometry of LPC character sheets |
| [`(lpc catalog)`](lpc.md#lpc-catalog) | Which LPC bodies, heads, hair and garments the packs draw, and where |
| [`(lpc wardrobe)`](lpc.md#lpc-wardrobe) | Characters dressed from the catalog, as pictures |
| [`(lpc skins)`](lpc.md#lpc-skins) | The skin ramps, read when built |
| [`(lpc credits)`](lpc.md#lpc-credits), [`(lpc embed)`](lpc.md#lpc-embed) | Credits for what a program embeds, and recipes that embed it |

### Datasets

| Library | For |
| --- | --- |
| [`(datasets mipnerf360)`](datasets.md#datasets-mipnerf360) | Mip-NeRF 360's scenes, read from Google's archives when built |
| [`(datasets mipnerf360 bicycle)`](datasets.md#the-scenes), and the other eight scenes | One scene's reconstruction and photographs, at the size 3D Gaussian Splatting trains it |

### Applications' own libraries

Each application keeps its libraries beside its scripts, under
`src/apps/NAME/`:

- `(apps last-mile …)` holds the San Francisco cab shift, GPS and renderer. [Last Mile Taxi](../games/last-mile.md)
- `(apps siegework …)`: the colony game's land, rules, siege, view and HUD
  ([Siegework](../games/siegework.md)).
- `(apps train …)`: 3D Gaussian Splatting training, on a page or on Node
  ([training on photographs](../graphics/tensors.md#training-on-photographs)).
- `(apps splats rings)`: the cloud the splat viewer opens on
  ([gaussian splats](splats.md)).
