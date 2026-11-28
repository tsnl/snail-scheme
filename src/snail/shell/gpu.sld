;; WebGPU as a capability: a `Gpu` mirrors WebGPU's own operations and
;; descriptors, so code that uses it reads like WebGPU, and a `Gpu`
;; parameter says exactly which functions touch the device. A `Gpu` is a
;; record of those operations, so its maker decides what the calls do:
;; `host-gpu`, last below, runs them on the host's device, the page's or
;; Dawn's on Node, and `with-recorded-gpu` in (snail shell gpu record)
;; records them, for testing a library without one.
;;
;; It is WebGPU itself, without bookkeeping: a handle is the id of an
;; object the host holds, made by each `create-...` call and kept as long as
;; the program keeps using it, across frames. `destroy` lets an object go
;; at the next `submit`, after the commands that use it: a buffer's or
;; texture's memory is freed, as WebGPU's `destroy` does, and the host
;; forgets any other kind, as JavaScript's collector would. An
;; encoder, a pass and a command buffer go once used, at `finish`,
;; `end-pass` (or `end-compute-pass`) and `submit`, and the canvas's
;; texture and its views at the
;; next `current-texture`. Misuse is reported by WebGPU's own validation.
;; `work-done` waits until the device has done what was submitted, as
;; `onSubmittedWorkDone` does: a frame loop whose frames cost the device
;; more than a display frame waits on the last one, so frames do not
;; queue up without bound.
;;
;; A descriptor crosses to the host as a list of fields, words and texts in
;; a fixed order per kind ("Descriptors as fields" below), staged as bytes
;; that host/browser/gpu.mjs reads with a DataView into the dictionary
;; WebGPU takes. Every other command crosses as a call with scalar
;; arguments.
(define-library (snail shell gpu)
  (export
   Gpu
   GpuPipelineLayout
   PipelineLayoutObject
   BindingKind
   UniformBinding
   ReadStorage
   FilterSampler
   FloatTexture
   CubeTexture
   DepthArray
   UnfilterableTexture
   layout-binding-fields
   GpuBuffer
   GpuTexture
   GpuTextureView
   GpuSampler
   GpuShaderModule
   GpuRenderPipeline
   GpuComputePipeline
   GpuPipeline
   RenderPipeline
   ComputePipeline
   GpuBindGroup
   GpuCommandEncoder
   GpuRenderPass
   GpuComputePass
   GpuCommandBuffer
   GpuQuerySet
   GpuObject
   BufferObject
   TextureObject
   ViewObject
   SamplerObject
   ModuleObject
   PipelineObject
   ComputePipelineObject
   BindGroupObject
   QuerySetObject
   Image
   DeviceInfo
   BufferUsage
   MapRead
   CopySrc
   CopyDst
   Index
   Vertex
   Uniform
   Storage
   Indirect
   QueryResolve
   BufferDescriptor
   QuerySetDescriptor
   TimestampWrites
   TextureFormat
   R8Unorm
   Rg8Unorm
   Rgba8Unorm
   Rgba8UnormSrgb
   Bgra8Unorm
   Bgra8UnormSrgb
   R32Uint
   Rgba32Uint
   Rg16Float
   R32Float
   Rg32Uint
   Rgba16Float
   Rgba32Float
   Rg11b10Ufloat
   Depth24Plus
   Depth32Float
   texture-format-name
   texture-format-named
   TextureUsage
   TextureCopySrc
   TextureCopyDst
   TextureBinding
   StorageBinding
   RenderAttachment
   TextureDescriptor
   TextureCopy
   whole-texture
   FilterMode
   Nearest
   Linear
   AddressMode
   ClampToEdge
   Repeat
   MirrorRepeat
   SamplerDescriptor
   ShaderModuleDescriptor
   VertexFormat
   Float32
   Float32x2
   Float32x3
   Float32x4
   Uint32
   Uint32x2
   Uint32x3
   Uint32x4
   Sint32
   Sint32x2
   Sint32x4
   Unorm8x4
   VertexAttribute
   VertexStep
   PerVertex
   PerInstance
   VertexBufferLayout
   BlendFactor
   Zero
   One
   Src
   OneMinusSrc
   SrcAlpha
   OneMinusSrcAlpha
   Dst
   OneMinusDst
   DstAlpha
   OneMinusDstAlpha
   BlendOperation
   Add
   Subtract
   ReverseSubtract
   Min
   Max
   BlendComponent
   Blend
   over
   ColorTarget
   FragmentState
   Topology
   PointList
   LineList
   LineStrip
   TriangleList
   TriangleStrip
   CullMode
   CullNone
   CullFront
   CullBack
   CompareFunction
   CompareNever
   CompareLess
   CompareEqual
   CompareLessEqual
   CompareGreater
   CompareNotEqual
   CompareGreaterEqual
   CompareAlways
   DepthState
   RenderPipelineDescriptor
   ComputePipelineDescriptor
   ViewDimension
   View2d
   View2dArray
   ViewCube
   TextureViewDescriptor
   view-of
   layer-view
   array-view
   BindGroupEntry
   BufferEntry
   TextureEntry
   SamplerEntry
   BindGroupDescriptor
   Color
   ColorLoad
   Clear
   Keep
   DepthLoad
   ClearDepth
   KeepDepth
   ReadOnlyDepth
   ColorAttachment
   DepthAttachment
   RenderPassDescriptor
   IndexFormat
   Uint16Index
   Uint32Index
   submit-timed
   elapsed-seconds
   Field
   Word
   Text
   fields-bytes
   fields-text
   buffer-fields
   texture-fields
   view-fields
   sampler-fields
   module-fields
   pipeline-fields
   compute-pipeline-fields
   query-set-fields
   bind-group-fields
   view-dimension-name
   buffer-usage-bits
   texture-usage-bits
   host-gpu)
  (import
   (snail core base)
   (only (snail core io) Host)
   (only (snail shell task) through-host)
   (only (snail shell utf8) string->utf8)
   (prefix (snail runtime gpu) host-))
  (begin

    ;; ---- Handles ----

    ;; Each handle is the id of an object the host holds.

    (record GpuPipelineLayout
      ((id I32)))
    ;; Groups list their bindings in numeric order. Uniform and read-only
    ;; storage buffers may be read by either graphics stage, as a vertex
    ;; stage reads an instance's bones. Sampled textures belong to fragments.
    (enum BindingKind
      (UniformBinding)
      (FilterSampler)
      (FloatTexture)
      (CubeTexture)
      (DepthArray)
      (UnfilterableTexture)
      (ReadStorage))
    (define (binding-code (kind BindingKind)) (→ I32)
      (match kind ((UniformBinding) 0) ((FilterSampler) 1) ((FloatTexture) 2)
             ((CubeTexture) 3) ((DepthArray) 4) ((UnfilterableTexture) 5) ((ReadStorage) 6)))
    (define (layout-binding-fields (label String) (groups (List (List BindingKind))))
      (→ (List Field))
      (Cons (Text label) (counted groups (lambda (bindings)
                                           (counted bindings
                                                    (lambda (binding)
                                                      (list (word (binding-code binding)))))))))
    (record GpuBuffer
      ((id I32)))

    (record GpuTexture
      ((id I32)))

    (record GpuTextureView
      ((id I32)))

    (record GpuSampler
      ((id I32)))

    (record GpuShaderModule
      ((id I32)))

    (record GpuRenderPipeline
      ((id I32)))

    (record GpuComputePipeline
      ((id I32)))

    ;; A pipeline of either kind, whose layout a bind group takes.
    (enum GpuPipeline
      (RenderPipeline ((pipeline GpuRenderPipeline)))
      (ComputePipeline ((pipeline GpuComputePipeline))))

    (record GpuBindGroup
      ((id I32)))

    (record GpuCommandEncoder
      ((id I32)))

    (record GpuRenderPass
      ((id I32)))

    (record GpuComputePass
      ((id I32)))

    (record GpuCommandBuffer
      ((id I32)))

    (record GpuQuerySet
      ((id I32)))

    ;; What `destroy` lets go.
    (enum GpuObject
      (PipelineLayoutObject ((layout GpuPipelineLayout)))
      (BufferObject ((buffer GpuBuffer)))
      (TextureObject ((texture GpuTexture)))
      (ViewObject ((view GpuTextureView)))
      (SamplerObject ((sampler GpuSampler)))
      (ModuleObject ((module GpuShaderModule)))
      (PipelineObject ((pipeline GpuRenderPipeline)))
      (ComputePipelineObject ((pipeline GpuComputePipeline)))
      (BindGroupObject ((group GpuBindGroup)))
      (QuerySetObject ((query-set GpuQuerySet))))

    ;; A decoded image: an rgba8unorm texture of its size.
    (record Image
      ((texture GpuTexture)
       (width I32)
       (height I32)))

    ;; The device a program was given: the canvas's preferred format, and
    ;; the optional features it has beyond the baseline.
    (record DeviceInfo
      ((format TextureFormat)
       (features (List String))
       (storage-binding-size I32)))

    ;; ---- Buffers ----

    (enum BufferUsage
      (MapRead)
      (CopySrc)
      (CopyDst)
      (Index)
      (Vertex)
      (Uniform)
      (Storage)
      (Indirect)
      (QueryResolve))

    ;; A label names an object in WebGPU's messages.
    (record BufferDescriptor
      ((label String)
       (size I32)
       (usage (List BufferUsage))))

    ;; GPUBufferUsage's bits.

    (define (buffer-usage-bit (usage BufferUsage)) (→ I32)
      (match usage
        ((MapRead) 1)
        ((CopySrc) 4)
        ((CopyDst) 8)
        ((Index) 16)
        ((Vertex) 32)
        ((Uniform) 64)
        ((Storage) 128)
        ((Indirect) 256)
        ((QueryResolve) 512)))

    (define (buffer-usage-bits (usages (List BufferUsage))) (→ I32)
      (fold-left i32-or 0 (map buffer-usage-bit usages)))

    ;; ---- Textures ----

    (enum TextureFormat
      (R8Unorm)
      (Rg8Unorm)
      (Rgba8Unorm)
      (Rgba8UnormSrgb)
      (Bgra8Unorm)
      (Bgra8UnormSrgb)
      (R32Uint)
      (Rgba32Uint)
      (Rg16Float)
      (R32Float)
      (Rg32Uint)
      (Rgba16Float)
      (Rgba32Float)
      (Rg11b10Ufloat)
      (Depth24Plus)
      (Depth32Float))

    (define (texture-format-name (format TextureFormat)) (→ String)
      (match format
        ((R8Unorm) "r8unorm")
        ((Rg8Unorm) "rg8unorm")
        ((Rgba8Unorm) "rgba8unorm")
        ((Rgba8UnormSrgb) "rgba8unorm-srgb")
        ((Bgra8Unorm) "bgra8unorm")
        ((Bgra8UnormSrgb) "bgra8unorm-srgb")
        ((R32Uint) "r32uint")
        ((Rgba32Uint) "rgba32uint")
        ((Rg16Float) "rg16float")
        ((R32Float) "r32float")
        ((Rg32Uint) "rg32uint")
        ((Rgba16Float) "rgba16float")
        ((Rgba32Float) "rgba32float")
        ((Rg11b10Ufloat) "rg11b10ufloat")
        ((Depth24Plus) "depth24plus")
        ((Depth32Float) "depth32float")))

    ;; The canvas's preferred format is one of the two WebGPU allows.

    (define (texture-format-named (name String)) (→ TextureFormat)
      (cond ((string=? name "bgra8unorm") (Bgra8Unorm))
            ((string=? name "rgba8unorm") (Rgba8Unorm))
            (else (panic (string-append "gpu: unexpected canvas format " name)))))

    (enum TextureUsage
      (TextureCopySrc)
      (TextureCopyDst)
      (TextureBinding)
      (StorageBinding)
      (RenderAttachment))

    ;; GPUTextureUsage's bits.

    (define (texture-usage-bit (usage TextureUsage)) (→ I32)
      (match usage
        ((TextureCopySrc) 1)
        ((TextureCopyDst) 2)
        ((TextureBinding) 4)
        ((StorageBinding) 8)
        ((RenderAttachment) 16)))

    (define (texture-usage-bits (usages (List TextureUsage))) (→ I32)
      (fold-left i32-or 0 (map texture-usage-bit usages)))

    ;; A 2D texture of `layers` layers, each with `mips` levels.
    (record TextureDescriptor
      ((label String)
       (width I32)
       (height I32)
       (layers I32)
       (mips I32)
       (format TextureFormat)
       (usage (List TextureUsage))))

    ;; Where a copy starts in a texture: a level, a corner and a layer.
    (record TextureCopy
      ((texture GpuTexture)
       (mip I32)
       (x I32)
       (y I32)
       (layer I32)))

    (define (whole-texture (texture GpuTexture)) (→ TextureCopy)
      (new TextureCopy (texture texture) (mip 0) (x 0) (y 0) (layer 0)))

    ;; ---- Samplers and shaders ----

    (enum FilterMode
      (Nearest)
      (Linear))

    (enum AddressMode
      (ClampToEdge)
      (Repeat)
      (MirrorRepeat))

    (record SamplerDescriptor
      ((label String)
       (mag-filter FilterMode)
       (min-filter FilterMode)
       (mipmap-filter FilterMode)
       (address AddressMode)))

    (record ShaderModuleDescriptor
      ((label String)
       (code String)))

    ;; ---- Render pipelines ----

    (enum VertexFormat
      (Float32)
      (Float32x2)
      (Float32x3)
      (Float32x4)
      (Uint32)
      (Uint32x2)
      (Uint32x3)
      (Uint32x4)
      (Sint32)
      (Sint32x2)
      (Sint32x4)
      (Unorm8x4))

    (record VertexAttribute
      ((format VertexFormat)
       (offset I32)
       (location I32)))

    (enum VertexStep
      (PerVertex)
      (PerInstance))

    (record VertexBufferLayout
      ((stride I32)
       (step VertexStep)
       (attributes (List VertexAttribute))))

    (enum BlendFactor
      (Zero)
      (One)
      (Src)
      (OneMinusSrc)
      (SrcAlpha)
      (OneMinusSrcAlpha)
      (Dst)
      (OneMinusDst)
      (DstAlpha)
      (OneMinusDstAlpha))

    (enum BlendOperation
      (Add)
      (Subtract)
      (ReverseSubtract)
      (Min)
      (Max))

    (record BlendComponent
      ((operation BlendOperation)
       (source BlendFactor)
       (destination BlendFactor)))

    (record Blend
      ((color BlendComponent)
       (alpha BlendComponent)))

    ;; The usual blend of a translucent color over what is there.
    (define over
      (new Blend
        (color (new BlendComponent
                 (operation (Add))
                 (source (SrcAlpha))
                 (destination (OneMinusSrcAlpha))))
        (alpha
         (new BlendComponent (operation (Add)) (source (One)) (destination (OneMinusSrcAlpha))))))

    (record ColorTarget
      ((format TextureFormat)
       (blend (Option Blend))))

    ;; A target that is None leaves its location without one, as WebGPU's
    ;; null target does: the shader's output there is dropped.
    (record FragmentState
      ((entry String)
       (targets (List (Option ColorTarget)))))

    (enum Topology
      (PointList)
      (LineList)
      (LineStrip)
      (TriangleList)
      (TriangleStrip))

    (enum CullMode
      (CullNone)
      (CullFront)
      (CullBack))

    (enum CompareFunction
      (CompareNever)
      (CompareLess)
      (CompareEqual)
      (CompareLessEqual)
      (CompareGreater)
      (CompareNotEqual)
      (CompareGreaterEqual)
      (CompareAlways))

    (record DepthState
      ((format TextureFormat)
       (write Bool)
       (compare CompareFunction)))

    ;; A pipeline's layout is WebGPU's "auto": its bind groups are made
    ;; against it, by group index.
    (record RenderPipelineDescriptor
      ((label String)
       (module GpuShaderModule)
       (vertex-entry String)
       (buffers (List VertexBufferLayout))
       (fragment (Option FragmentState))
       (topology Topology)
       (cull CullMode)
       (depth (Option DepthState))))

    ;; A compute pipeline: its module's entry point, with an "auto" layout.
    (record ComputePipelineDescriptor
      ((label String)
       (module GpuShaderModule)
       (entry String)))

    ;; ---- Bind groups ----

    (enum ViewDimension
      (View2d)
      (View2dArray) (ViewCube))

    ;; A view of some of a texture's levels and layers; `layers` 0 is every
    ;; layer from `base-layer` on.
    (record TextureViewDescriptor
      ((dimension ViewDimension)
       (base-mip I32)
       (mips I32)
       (base-layer I32)
       (layers I32)))

    ;; A view of the first `mips` levels of layer 0.

    (define (view-of (gpu Gpu) (texture GpuTexture) (mips I32)) (→ GpuTextureView)
      ((● gpu create-view) texture
       (new TextureViewDescriptor
         (dimension (View2d))
         (base-mip 0)
         (mips mips)
         (base-layer 0)
         (layers 1))))

    ;; A texture's whole array, at its first level.

    (define (array-view (gpu Gpu) (texture GpuTexture)) (→ GpuTextureView)
      ((● gpu create-view) texture
       (new TextureViewDescriptor
         (dimension (View2dArray))
         (base-mip 0)
         (mips 1)
         (base-layer 0)
         (layers 0))))

    (define (layer-view (gpu Gpu) (texture GpuTexture) (layer I32)) (→ GpuTextureView)
      ((● gpu create-view) texture
       (new TextureViewDescriptor
         (dimension (View2d))
         (base-mip 0)
         (mips 1)
         (base-layer layer)
         (layers 1))))

    ;; A buffer's size 0 binds the rest of it.
    (enum BindGroupEntry
      (BufferEntry ((binding I32) (buffer GpuBuffer) (offset I32) (size I32)))
      (TextureEntry ((binding I32) (view GpuTextureView)))
      (SamplerEntry ((binding I32) (sampler GpuSampler))))

    (record BindGroupDescriptor
      ((label String)
       (pipeline GpuPipeline)
       (group I32)
       (entries (List BindGroupEntry))))

    ;; ---- Render passes ----

    (record Color
      ((red F64)
       (green F64)
       (blue F64)
       (alpha F64)))

    (enum ColorLoad
      (Clear ((color Color)))
      (Keep))

    ;; A read-only depth attachment neither loads nor stores, and its
    ;; attachment's `store` is ignored: the pass tests against it and may
    ;; sample it as a texture too.
    (enum DepthLoad
      (ClearDepth ((depth F64)))
      (KeepDepth)
      (ReadOnlyDepth))

    (record ColorAttachment
      ((resolve (Option GpuTextureView))
       (view GpuTextureView)
       (load ColorLoad)
       (store Bool)))

    (record DepthAttachment
      ((view GpuTextureView)
       (load DepthLoad)
       (store Bool)))

    ;; A color attachment that is None leaves its location empty, matching
    ;; a pipeline's None target there.
    (record RenderPassDescriptor
      ((colors (List (Option ColorAttachment)))
       (depth (Option DepthAttachment))))

    (enum IndexFormat
      (Uint16Index)
      (Uint32Index))

    ;; ---- Timestamps ----

    ;; A set of `count` timestamps, WebGPU's query set of type "timestamp",
    ;; which needs the device's `timestamp-query` feature (DeviceInfo's
    ;; `features`). A pass begun with timestamp writes, WebGPU's
    ;; `timestampWrites`, writes the device's time in nanoseconds into
    ;; query `beginning` as it starts and into `end` as it ends;
    ;; `resolve-query-set` copies queries into a buffer made with
    ;; `QueryResolve`, eight bytes each, an unsigned count little-endian.
    ;; Only the difference of two times from one device means anything, and
    ;; a host may round them: browsers do, to 100 microseconds, unless their
    ;; WebGPU developer features are on.
    (record QuerySetDescriptor
      ((label String)
       (count I32)))

    (record TimestampWrites
      ((query-set GpuQuerySet)
       (beginning I32)
       (end I32)))

    ;; Submits the encoder with queries 0 to `count` resolved after its
    ;; commands, and reads their times back, eight bytes each.
    (define (submit-timed (gpu Gpu)
                          (encoder GpuCommandEncoder)
                          (queries GpuQuerySet)
                          (count I32))
      (→ Bytes)
      (let ((resolved ((● gpu create-buffer)
                       (new BufferDescriptor
                         (label "timestamps")
                         (size (* 8 count))
                         (usage (list (QueryResolve) (CopySrc))))))
            (readback ((● gpu create-buffer)
                       (new BufferDescriptor
                         (label "timestamps/readback")
                         (size (* 8 count))
                         (usage (list (MapRead) (CopyDst)))))))
        ((● gpu resolve-query-set) encoder queries 0 count resolved 0)
        ((● gpu copy-buffer-to-buffer) encoder resolved 0 readback 0 (* 8 count))
        ((● gpu submit) (list ((● gpu finish) encoder)))
        (let ((times ((● gpu read-buffer) readback 0 (* 8 count))))
          ((● gpu destroy) (BufferObject resolved))
          ((● gpu destroy) (BufferObject readback))
          times)))

    ;; The seconds from query `beginning` to query `end` of the times read.
    (define (elapsed-seconds (times Bytes) (beginning I32) (end I32)) (→ F64)
      (/ (i64->f64 (- (timestamp-at times end) (timestamp-at times beginning))) 1000000000.0))

    (define (timestamp-at (times Bytes) (query I32)) (→ I64)
      (fold-right (lambda (k total)
                    (+ (* total 256)
                       (i32->i64 (u8->i32 (array-ref times (+ (* 8 (i32->i64 query)) k))))))
                  0
                  (iota 8)))

    ;; ---- The capability ----

    ;; `request-device` asks the page for its device once, and every other
    ;; operation needs it. Offsets and sizes are in bytes. `write-texture`
    ;; takes a copy's start, the bytes of a row, the width and height
    ;; copied, and the texels. `decode-image` decodes an encoded image into
    ;; a texture of its own, or nothing when the bytes are no image the
    ;; host decodes. `read-buffer` waits until the buffer, made with
    ;; `MapRead`, can be read, and answers the bytes asked for.
    ;; `current-texture` is the canvas's texture for this frame, sized to
    ;; the canvas's pixels on the screen, and its size. The timed ways of
    ;; beginning a pass take the timestamp writes WebGPU's pass descriptor
    ;; may hold.
    (record Gpu
      ((request-device (Fn → DeviceInfo))
       (create-buffer (Fn BufferDescriptor → GpuBuffer))
       (write-buffer (Fn GpuBuffer I32 Bytes → Unit))
       (read-buffer (Fn GpuBuffer I32 I32 → Bytes))
       (create-multisample-texture (Fn I32 TextureDescriptor → GpuTexture))
       (create-layout (Fn String (List (List BindingKind)) → GpuPipelineLayout))
       (create-raster-pipeline
        (Fn GpuPipelineLayout I32 RenderPipelineDescriptor → GpuRenderPipeline))
       (create-texture (Fn TextureDescriptor → GpuTexture))
       (create-view (Fn GpuTexture TextureViewDescriptor → GpuTextureView))
       (write-texture (Fn TextureCopy I32 I32 I32 Bytes → Unit))
       (decode-image (Fn Bytes → (Option Image)))
       (create-sampler (Fn SamplerDescriptor → GpuSampler))
       (create-shader-module (Fn ShaderModuleDescriptor → GpuShaderModule))
       (create-render-pipeline (Fn RenderPipelineDescriptor → GpuRenderPipeline))
       (create-bind-group (Fn BindGroupDescriptor → GpuBindGroup))
       (create-command-encoder (Fn → GpuCommandEncoder))
       (copy-buffer-to-buffer (Fn GpuCommandEncoder GpuBuffer I32 GpuBuffer I32 I32 → Unit))
       (copy-texture-to-buffer
        (Fn GpuCommandEncoder TextureCopy GpuBuffer I32 I32 I32 I32 → Unit))
       (copy-texture-to-texture (Fn GpuCommandEncoder TextureCopy TextureCopy I32 I32 → Unit))
       (begin-render-pass (Fn GpuCommandEncoder RenderPassDescriptor → GpuRenderPass))
       (set-pipeline (Fn GpuRenderPass GpuRenderPipeline → Unit))
       (set-bind-group (Fn GpuRenderPass I32 GpuBindGroup → Unit))
       (set-vertex-buffer (Fn GpuRenderPass I32 GpuBuffer I32 → Unit))
       (set-index-buffer (Fn GpuRenderPass GpuBuffer IndexFormat I32 → Unit))
       (set-scissor-rect (Fn GpuRenderPass I32 I32 I32 I32 → Unit))
       (draw (Fn GpuRenderPass I32 I32 I32 I32 → Unit))
       (draw-indexed (Fn GpuRenderPass I32 I32 I32 I32 I32 → Unit))
       (draw-indexed-indirect (Fn GpuRenderPass GpuBuffer I32 → Unit))
       (end-pass (Fn GpuRenderPass → Unit))
       (create-compute-pipeline (Fn ComputePipelineDescriptor → GpuComputePipeline))
       (begin-compute-pass (Fn GpuCommandEncoder → GpuComputePass))
       (begin-timed-compute-pass (Fn GpuCommandEncoder TimestampWrites → GpuComputePass))
       (begin-timed-render-pass
        (Fn GpuCommandEncoder RenderPassDescriptor TimestampWrites → GpuRenderPass))
       (create-query-set (Fn QuerySetDescriptor → GpuQuerySet))
       (resolve-query-set (Fn GpuCommandEncoder GpuQuerySet I32 I32 GpuBuffer I32 → Unit))
       (set-compute-pipeline (Fn GpuComputePass GpuComputePipeline → Unit))
       (set-compute-bind-group (Fn GpuComputePass I32 GpuBindGroup → Unit))
       (dispatch-workgroups (Fn GpuComputePass I32 I32 I32 → Unit))
       (dispatch-workgroups-indirect (Fn GpuComputePass GpuBuffer I32 → Unit))
       (end-compute-pass (Fn GpuComputePass → Unit))
       (finish (Fn GpuCommandEncoder → GpuCommandBuffer))
       (submit (Fn (List GpuCommandBuffer) → Unit))
       (work-done (Fn → Unit))
       (current-texture (Fn → Image))
       (destroy (Fn GpuObject → Unit))))

    ;; ---- Descriptors as fields ----

    ;; A descriptor field: a 32-bit word, or a text. A text crosses as its
    ;; UTF-8 length and bytes, padded to a word; an object a descriptor
    ;; names is its id, a word; an enum value is WebGPU's name for it, a
    ;; text; an optional part is a word, 1 when present, before it. Every
    ;; descriptor but a view's begins with its label.
    (enum Field
      (Word ((value I32)))
      (Text ((value String))))

    ;; The fields as the host reads them: words little-endian.

    (define (fields-bytes (fields (List Field))) (→ Bytes)
      (joined (map field-bytes fields)))

    (define (field-bytes (field Field)) (→ Bytes)
      (match field
        ((Word value) (word-bytes value))
        ((Text value)
         (let ((text (string->utf8 value)))
           (joined (list (word-bytes (i64->i32 (array-length text)))
                         text
                         (make-array (modulo (- 0 (array-length text)) 4) (i32->u8 0))))))))

    ;; Byte arrays end to end, in a fresh array.

    (define (joined (pieces (List Bytes))) (→ Bytes)
      (let ((bytes (make-array
                    (fold-left
                     (lambda (total piece) (+ total (array-length piece)))
                     0
                     pieces)
                    (i32->u8 0))))
        (fold-left (lambda (at piece)
                     (array-copy!
                      bytes
                      at
                      piece
                      0
                      (array-length piece))
                     (+ at (array-length piece)))
                   0
                   pieces)
        bytes))

    (define (word-bytes (value I32)) (→ Bytes)
      (array-generate 4
                      (lambda (index)
                        (i32->u8
                         (i32-and (i32-shift-right/logical value (i64->i32 (* 8 index))) 255)))))

    ;; The fields as words of text, as the recorder notes them.

    (define (fields-text (fields (List Field))) (→ String)
      (string-join (map (lambda (field)
                          (match field
                            ((Word value) (show value))
                            ((Text value) value)))
                        fields)
                   " "))

    (define (word (value I32)) (→ Field) (Word value))

    (define (flag (value Bool)) (→ Field) (Word (if value 1 0)))

    ;; Size, usage.

    (define (buffer-fields (descriptor BufferDescriptor)) (→ (List Field))
      (list (Text (● descriptor label))
            (word (● descriptor size))
            (word (buffer-usage-bits (● descriptor usage)))))

    ;; Width, height, layers, levels, format, usage.

    (define (texture-fields (descriptor TextureDescriptor)) (→ (List Field))
      (list (Text (● descriptor label))
            (word (● descriptor width))
            (word (● descriptor height))
            (word (● descriptor layers))
            (word (● descriptor mips))
            (Text (texture-format-name (● descriptor format)))
            (word (texture-usage-bits (● descriptor usage)))))

    (define (filter-name (mode FilterMode)) (→ String)
      (match mode
        ((Nearest) "nearest")
        ((Linear) "linear")))

    (define (address-name (mode AddressMode)) (→ String)
      (match mode
        ((ClampToEdge) "clamp-to-edge")
        ((Repeat) "repeat")
        ((MirrorRepeat) "mirror-repeat")))

    ;; Magnification, minification and mipmap filters, and the address mode
    ;; across and down.

    (define (sampler-fields (descriptor SamplerDescriptor)) (→ (List Field))
      (list (Text (● descriptor label))
            (Text (filter-name (● descriptor mag-filter)))
            (Text (filter-name (● descriptor min-filter)))
            (Text (filter-name (● descriptor mipmap-filter)))
            (Text (address-name (● descriptor address)))))

    ;; The WGSL code.

    (define (module-fields (descriptor ShaderModuleDescriptor)) (→ (List Field))
      (list (Text (● descriptor label)) (Text (● descriptor code))))

    (define (vertex-format-name (format VertexFormat)) (→ String)
      (match format
        ((Float32) "float32")
        ((Float32x2) "float32x2")
        ((Float32x3) "float32x3")
        ((Float32x4) "float32x4")
        ((Uint32) "uint32")
        ((Uint32x2) "uint32x2")
        ((Uint32x3) "uint32x3")
        ((Uint32x4) "uint32x4")
        ((Sint32) "sint32")
        ((Sint32x2) "sint32x2")
        ((Sint32x4) "sint32x4")
        ((Unorm8x4) "unorm8x4")))

    ;; A count, then each item's fields.

    (define (counted (items (List T)) (fields-of (Fn T → (List Field)))) (→ (List Field)) (∀ (T))
      (Cons (word (i64->i32 (length items))) (concatenate (map fields-of items))))

    ;; Stride, step mode, then each attribute's format, offset and location.

    (define (layout-fields (layout VertexBufferLayout)) (→ (List Field))
      (Cons (word (● layout stride))
            (Cons (Text (match (● layout step)
                          ((PerVertex) "vertex")
                          ((PerInstance) "instance")))
                  (counted (● layout attributes)
                           (lambda (attribute)
                             (list (Text (vertex-format-name (● attribute format)))
                                   (word (● attribute offset))
                                   (word (● attribute location))))))))

    (define (factor-name (factor BlendFactor)) (→ String)
      (match factor
        ((Zero) "zero")
        ((One) "one")
        ((Src) "src")
        ((OneMinusSrc) "one-minus-src")
        ((SrcAlpha) "src-alpha")
        ((OneMinusSrcAlpha) "one-minus-src-alpha")
        ((Dst) "dst")
        ((OneMinusDst) "one-minus-dst")
        ((DstAlpha) "dst-alpha")
        ((OneMinusDstAlpha) "one-minus-dst-alpha")))

    (define (operation-name (operation BlendOperation)) (→ String)
      (match operation
        ((Add) "add")
        ((Subtract) "subtract")
        ((ReverseSubtract) "reverse-subtract")
        ((Min) "min")
        ((Max) "max")))

    ;; Operation, source factor, destination factor.

    (define (component-fields (component BlendComponent)) (→ (List Field))
      (list (Text (operation-name (● component operation)))
            (Text (factor-name (● component source)))
            (Text (factor-name (● component destination)))))

    ;; Format, then the blend's color and alpha components if it has one.

    ;; A target is a word, 1 when present, before its fields.

    (define (optional-target-fields (target (Option ColorTarget))) (→ (List Field))
      (match target
        ((Some target) (Cons (flag #t) (target-fields target)))
        ((None) (list (flag #f)))))

    (define (target-fields (target ColorTarget)) (→ (List Field))
      (Cons (Text (texture-format-name (● target format)))
            (match (● target blend)
              ((Some blend)
               (Cons (flag #t)
                     (append (component-fields (● blend color))
                             (component-fields (● blend alpha)))))
              ((None) (list (flag #f))))))

    (define (topology-name (topology Topology)) (→ String)
      (match topology
        ((PointList) "point-list")
        ((LineList) "line-list")
        ((LineStrip) "line-strip")
        ((TriangleList) "triangle-list")
        ((TriangleStrip) "triangle-strip")))

    (define (cull-name (cull CullMode)) (→ String)
      (match cull
        ((CullNone) "none")
        ((CullFront) "front")
        ((CullBack) "back")))

    (define (compare-name (compare CompareFunction)) (→ String)
      (match compare
        ((CompareNever) "never")
        ((CompareLess) "less")
        ((CompareEqual) "equal")
        ((CompareLessEqual) "less-equal")
        ((CompareGreater) "greater")
        ((CompareNotEqual) "not-equal")
        ((CompareGreaterEqual) "greater-equal")
        ((CompareAlways) "always")))

    ;; The module, the vertex entry and buffers, the fragment stage if any
    ;; (entry, targets), topology, cull mode, and the depth state if any
    ;; (format, whether it writes, compare). Its layout is "auto".

    (define (pipeline-fields (descriptor RenderPipelineDescriptor)) (→ (List Field))
      (concatenate
       (list (list (Text (● descriptor label))
                   (word (● (● descriptor module) id))
                   (Text (● descriptor vertex-entry)))
             (counted (● descriptor buffers) layout-fields)
             (match (● descriptor fragment)
               ((Some fragment)
                (Cons (flag #t)
                      (Cons (Text (● fragment entry))
                            (counted (● fragment targets) optional-target-fields))))
               ((None) (list (flag #f))))
             (list (Text (topology-name (● descriptor topology)))
                   (Text (cull-name (● descriptor cull))))
             (match (● descriptor depth)
               ((Some depth)
                (list (flag #t)
                      (Text (texture-format-name (● depth format)))
                      (flag (● depth write))
                      (Text (compare-name (● depth compare)))))
               ((None) (list (flag #f)))))))

    ;; The module and its entry point.

    (define (compute-pipeline-fields (descriptor ComputePipelineDescriptor)) (→ (List Field))
      (list (Text (● descriptor label))
            (word (● (● descriptor module) id))
            (Text (● descriptor entry))))

    (define (query-set-fields (descriptor QuerySetDescriptor)) (→ (List Field))
      (list (Text (● descriptor label)) (word (● descriptor count))))

    (define (view-dimension-name (dimension ViewDimension)) (→ String)
      (match dimension
        ((View2d) "2d")
        ((View2dArray) "2d-array") ((ViewCube) "cube")))

    ;; Dimension, first level and count, first layer and count (0 for the
    ;; rest). A view has no label.

    (define (view-fields (descriptor TextureViewDescriptor)) (→ (List Field))
      (list (Text (view-dimension-name (● descriptor dimension)))
            (word (● descriptor base-mip))
            (word (● descriptor mips))
            (word (● descriptor base-layer))
            (word (● descriptor layers))))

    ;; Binding, then 0 with buffer, offset and size (0 for the rest), 1 with
    ;; a view, or 2 with a sampler.

    (define (entry-fields (entry BindGroupEntry)) (→ (List Field))
      (match entry
        ((BufferEntry binding buffer offset size)
         (list (word binding) (word 0) (word (● buffer id)) (word offset) (word size)))
        ((TextureEntry binding view) (list (word binding) (word 1) (word (● view id))))
        ((SamplerEntry binding sampler) (list (word binding) (word 2) (word (● sampler id))))))

    ;; The pipeline whose layout it takes, the group's index, and its
    ;; entries.

    (define (bind-group-fields (descriptor BindGroupDescriptor)) (→ (List Field))
      (Cons (Text (● descriptor label))
            (Cons (word (match (● descriptor pipeline)
                          ((RenderPipeline pipeline) (● pipeline id))
                          ((ComputePipeline pipeline) (● pipeline id))))
                  (Cons (word (● descriptor group))
                        (counted (● descriptor entries) entry-fields)))))

    ;; ---- On the host's device ----

    ;; `host-gpu` runs each operation on the device host/browser/gpu.mjs
    ;; holds, through (snail runtime gpu), and host/browser/gpu.mjs knows each
    ;; object by the id it gave it. The browser target provides it to a
    ;; page's main. A program on Node makes it itself, where it uses the
    ;; device, as a page makes its `Fetch`, so a Node program that draws
    ;; nothing links none of it. Node's device is Dawn's
    ;; (host/native/gpu.mjs); it has no screen, so there `current-texture`
    ;; fails, and it decodes images as a page does.
    ;;
    ;;   (let* ((gpu (host-gpu host)) (info (request-device gpu))) ...)

    (define (host-gpu (host Host)) (→ Gpu)
      (new Gpu
        (request-device requested)
        (create-buffer
         (lambda (descriptor) (new GpuBuffer (id (made 0 (buffer-fields descriptor))))))
        (write-buffer
         (lambda (buffer offset bytes) (host-write-buffer (● buffer id) offset bytes)))
        (read-buffer (lambda (buffer offset size) (read-bytes (● buffer id) offset size)))
        (create-multisample-texture (lambda (samples desc)
                                      (new GpuTexture
                                        (id (made 8 (Cons (word samples) (texture-fields desc)))))))
        (create-layout (lambda (label groups)
                         (new GpuPipelineLayout
                           (id (made 9 (layout-binding-fields label groups))))))
        (create-raster-pipeline (lambda (layout samples desc)
                                  (new GpuRenderPipeline (id (made 10 (Cons (word (● layout id))
                                                                            (Cons (word samples)
                                                                                  (pipeline-fields
                                                                                   desc))))))))
        (create-texture
         (lambda (descriptor) (new GpuTexture (id (made 1 (texture-fields descriptor))))))
        (create-view
         (lambda (texture descriptor)
           (new GpuTextureView
             (id (host-create-view (● texture id) (fields-bytes (view-fields descriptor)))))))
        (write-texture
         (lambda (copy bytes-per-row width height bytes)
           (host-write-texture (● (● copy texture) id)
                               (● copy mip)
                               (● copy x)
                               (● copy y)
                               (● copy layer)
                               bytes-per-row
                               width
                               height
                               bytes)))
        (decode-image decoded)
        (create-sampler
         (lambda (descriptor) (new GpuSampler (id (made 2 (sampler-fields descriptor))))))
        (create-shader-module
         (lambda (descriptor) (new GpuShaderModule (id (made 3 (module-fields descriptor))))))
        (create-render-pipeline
         (lambda (descriptor)
           (new GpuRenderPipeline (id (made 4 (pipeline-fields descriptor))))))
        (create-bind-group
         (lambda (descriptor) (new GpuBindGroup (id (made 5 (bind-group-fields descriptor))))))
        (create-command-encoder (lambda () (new GpuCommandEncoder (id (host-encoder)))))
        (copy-buffer-to-buffer
         (lambda (encoder source source-offset destination destination-offset size)
           (host-copy-buffer (● encoder id)
                             (● source id)
                             source-offset
                             (● destination id)
                             destination-offset
                             size)))
        (copy-texture-to-buffer
         (lambda (encoder copy buffer offset bytes-per-row width height)
           (host-copy-texture-to-buffer (● encoder id)
                                        (● (● copy texture) id)
                                        (● copy mip)
                                        (● copy x)
                                        (● copy y)
                                        (● copy layer)
                                        (● buffer id)
                                        offset
                                        bytes-per-row
                                        width
                                        height)))
        (copy-texture-to-texture
         (lambda (encoder source destination width height)
           (host-copy-texture (● encoder id)
                              (● (● source texture) id)
                              (● source mip)
                              (● source x)
                              (● source y)
                              (● source layer)
                              (● (● destination texture) id)
                              (● destination mip)
                              (● destination x)
                              (● destination y)
                              (● destination layer)
                              width
                              height)))
        (begin-render-pass
         (lambda (encoder descriptor)
           (attachments descriptor)
           (new GpuRenderPass (id (host-begin-pass (● encoder id))))))
        (set-pipeline
         (lambda (pass pipeline) (host-set-pipeline (● pass id) (● pipeline id))))
        (set-bind-group
         (lambda (pass index group) (host-set-bind-group (● pass id) index (● group id))))
        (set-vertex-buffer
         (lambda (pass slot buffer offset)
           (host-set-vertex-buffer (● pass id) slot (● buffer id) offset)))
        (set-index-buffer
         (lambda (pass buffer format offset)
           (host-set-index-buffer (● pass id)
                                  (● buffer id)
                                  (match format
                                    ((Uint16Index) 0)
                                    ((Uint32Index) 1))
                                  offset)))
        (set-scissor-rect
         (lambda (pass x y width height) (host-set-scissor (● pass id) x y width height)))
        (draw
         (lambda (pass vertices instances first-vertex first-instance)
           (host-draw (● pass id) vertices instances first-vertex first-instance)))
        (draw-indexed
         (lambda (pass indices instances first-index base-vertex first-instance)
           (host-draw-indexed (● pass id)
                              indices
                              instances
                              first-index
                              base-vertex
                              first-instance)))
        (draw-indexed-indirect
         (lambda (pass buffer offset)
           (host-draw-indexed-indirect (● pass id) (● buffer id) offset)))
        (end-pass (lambda (pass) (host-end-pass (● pass id))))
        (create-compute-pipeline
         (lambda (descriptor)
           (new GpuComputePipeline (id (made 6 (compute-pipeline-fields descriptor))))))
        (begin-compute-pass
         (lambda (encoder) (new GpuComputePass (id (host-begin-compute (● encoder id))))))
        (begin-timed-compute-pass
         (lambda (encoder writes)
           (timestamp-writes writes)
           (new GpuComputePass (id (host-begin-compute (● encoder id))))))
        (begin-timed-render-pass
         (lambda (encoder descriptor writes)
           (attachments descriptor)
           (timestamp-writes writes)
           (new GpuRenderPass (id (host-begin-pass (● encoder id))))))
        (create-query-set
         (lambda (descriptor) (new GpuQuerySet (id (made 7 (query-set-fields descriptor))))))
        (resolve-query-set
         (lambda (encoder query-set first count buffer offset)
           (host-resolve-queries (● encoder id)
                                 (● query-set id)
                                 first
                                 count
                                 (● buffer id)
                                 offset)))
        (set-compute-pipeline
         (lambda (pass pipeline) (host-set-compute-pipeline (● pass id) (● pipeline id))))
        (set-compute-bind-group
         (lambda (pass index group)
           (host-set-compute-bind-group (● pass id) index (● group id))))
        (dispatch-workgroups (lambda (pass x y z) (host-dispatch (● pass id) x y z)))
        (dispatch-workgroups-indirect
         (lambda (pass buffer offset) (host-dispatch-indirect (● pass id) (● buffer id) offset)))
        (end-compute-pass (lambda (pass) (host-end-compute (● pass id))))
        (finish
         (lambda (encoder) (new GpuCommandBuffer (id (host-finish (● encoder id))))))
        (submit submitted)
        (work-done (lambda () (through-host host-start-done host-finish-done) (unit)))
        (current-texture
         (lambda ()
           (let ((id (host-current-texture)))
             (new Image
               (texture (new GpuTexture (id id)))
               (width (host-current-width))
               (height (host-current-height))))))
        (destroy (lambda (object) (host-destroy (object-id object))))))

    ;; ---- The host's objects ----

    ;; An object of the host's kind `kind`, in the order of `made` in
    ;; host/browser/gpu.mjs, from its descriptor's fields.

    (define (made (kind I32) (fields (List Field))) (→ I32)
      (host-create kind (fields-bytes fields)))

    (define (object-id (object GpuObject)) (→ I32)
      (match object
        ((PipelineLayoutObject layout) (● layout id))
        ((BufferObject buffer) (● buffer id))
        ((TextureObject texture) (● texture id))
        ((ViewObject view) (● view id))
        ((SamplerObject sampler) (● sampler id))
        ((ModuleObject module) (● module id))
        ((PipelineObject pipeline) (● pipeline id))
        ((ComputePipelineObject pipeline) (● pipeline id))
        ((BindGroupObject group) (● group id))
        ((QuerySetObject query-set) (● query-set id))))

    ;; Each command buffer is queued, then the queue submitted.

    (define (submitted (buffers (List GpuCommandBuffer))) (→ Unit)
      (for-each (lambda (buffer) (host-queue-buffer (● buffer id))) buffers)
      (host-submit))

    ;; ---- The host's passes ----

    ;; Each attachment is its view, its load and its store, in one call.

    (define (attachments (descriptor RenderPassDescriptor)) (→ Unit)
      (for-each (lambda (attachment)
                  (match attachment
                    ((Some attachment) (color-attachment attachment))
                    ((None) (host-pass-no-color))))
                (● descriptor colors))
      (match (● descriptor depth)
        ((Some attachment) (depth-attachment attachment))
        ((None) (unit))))

    (define (color-attachment (attachment ColorAttachment)) (→ Unit)
      (let ((view (● attachment view id)) (store (store-flag (● attachment store)))
            (resolve (match (● attachment resolve) ((Some v) (● v id)) ((None) 0))))
        (match (● attachment load)
          ((Clear color)
           (host-pass-color view
                            1
                            (● color red)
                            (● color green)
                            (● color blue)
                            (● color alpha)
                            store resolve))
          ((Keep) (host-pass-color view 0 0.0 0.0 0.0 0.0 store resolve)))))

    (define (depth-attachment (attachment DepthAttachment)) (→ Unit)
      (let ((view (● attachment view id)) (store (store-flag (● attachment store))))
        (match (● attachment load)
          ((ClearDepth depth) (host-pass-depth view 1 depth store))
          ((KeepDepth) (host-pass-depth view 0 0.0 store))
          ((ReadOnlyDepth) (host-pass-depth view 2 0.0 store)))))

    (define (store-flag (store Bool)) (→ I32) (if store 1 0))

    ;; A pass's timestamp writes, in one call before it begins.
    (define (timestamp-writes (writes TimestampWrites)) (→ Unit)
      (host-pass-timestamps (● writes query-set id) (● writes beginning) (● writes end)))

    ;; ---- Requesting the device ----

    ;; The host asks its adapter for the baseline features, and for the
    ;; optional ones it has (host/browser/gpu.mjs); it has told why it has
    ;; no device.

    (define (requested) (→ DeviceInfo)
      (let ((status (through-host host-start-device host-finish-device)))
        (unless (= status 0)
          (panic "gpu: this host has no WebGPU device with the baseline features"))
        (new DeviceInfo
          (format (texture-format-named (reply (host-device-format))))
          (features (words (reply (host-device-features))))
          (storage-binding-size (host-storage-binding-size)))))

    (define (reply (count I32)) (→ String)
      (string-generate (i32->i64 count)
                       (lambda (index)
                         (integer->char (i32->i64 (host-reply-scalar (i64->i32 index)))))))

    ;; The words of a text separated by single spaces.

    (define (words (text String)) (→ (List String))
      (if (string=? text "")
          (Nil)
          (match (string-index text #\space)
            ((Some at)
             (Cons (substring text 0 at) (words (substring text (+ at 1) (string-length text)))))
            ((None) (list text)))))

    ;; ---- Waiting on the host ----

    (define (read-bytes (buffer I32) (offset I32) (size I32)) (→ Bytes)
      (let ((count (through-host (lambda (ticket) (host-start-read ticket buffer offset size))
                                 host-finish-read)))
        (array-generate (i32->i64 count) (lambda (index) (host-read-byte (i64->i32 index))))))

    ;; The host decodes the image and holds its texture until it is kept.

    ;; The host answers a width of 0 for bytes it does not decode.
    (define (decoded (bytes Bytes)) (→ (Option Image))
      (let ((width (through-host (lambda (ticket)
                                   (host-start-decode ticket
                                                      (texture-usage-bits (list (TextureBinding)
                                                                                (TextureCopySrc)
                                                                                (TextureCopyDst)
                                                                                (RenderAttachment)))
                                                      bytes))
                                 host-finish-decode)))
        (if (= width 0)
            (None)
            (let ((height (host-decoded-height)))
              (Some (new Image
                      (texture (new GpuTexture (id (host-keep-decoded))))
                      (width width)
                      (height height)))))))

    ))
