;; WebGPU as an effect: `gpu` mirrors WebGPU's own operations and
;; descriptors, so code that uses it reads like WebGPU, and a `! gpu` row
;; says exactly which functions touch the device. A handler decides what
;; the calls do: `provide-gpu` in (snail shell gpu page) runs them on the
;; page's device, and `with-recorded-gpu` in (snail shell gpu record)
;; records them, for testing a library without one.
;;
;; Both handlers keep the same books on the objects a program makes
;; ("Objects" below):
;;
;; - A long-lived object is made by its resource path. The same path and
;;   descriptor answer the object already made, which is how a module that
;;   starts again finds what the last one made. A handle says whether its
;;   object is `fresh`, made by this call, so its contents are still to be
;;   written.
;; - An object made without a path lives until the frame ends, at the next
;;   `submit`: command encoders, passes and transient buffers.
;; - Each frame marks the objects it uses. When making an object would go
;;   over the budget, the least recently used unmarked ones are evicted;
;;   if the marked ones alone are over it, the program panics, naming the
;;   largest. An evicted object is made afresh when its path is next asked
;;   for.
;; - A handle carries its object's generation, the count of objects made
;;   by its path, so using a handle whose object is gone panics with what
;;   it was, rather than leaving WebGPU to report an invalid object.
;;
;; A descriptor is a list of fields, words and texts in a fixed order per
;; kind ("Descriptors as fields" below). The books compare those lists to
;; find an object by its path, encoding nothing; only an object being made
;; crosses to the host, as staged bytes that host/browser/gpu.mjs reads
;; with a DataView into the dictionary WebGPU takes. Render passes and
;; every other command cross as calls with scalar arguments.
(define-library (snail shell gpu)
  (export
   gpu
   request-device
   create-buffer
   write-buffer
   read-buffer
   create-texture
   write-texture
   decode-image
   create-sampler
   create-shader-module
   create-render-pipeline
   create-bind-group
   create-command-encoder
   copy-buffer-to-buffer
   copy-texture-to-buffer
   copy-texture-to-texture
   begin-render-pass
   set-pipeline
   set-bind-group
   set-vertex-buffer
   set-index-buffer
   set-scissor-rect
   draw
   draw-indexed
   draw-indexed-indirect
   end-pass
   finish
   submit
   current-texture
   destroy
   GpuBuffer
   GpuTexture
   GpuSampler
   GpuShaderModule
   GpuRenderPipeline
   GpuBindGroup
   GpuCommandEncoder
   GpuRenderPass
   GpuCommandBuffer
   GpuObject
   BufferObject
   TextureObject
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
   BufferDescriptor
   TextureFormat
   R8Unorm
   Rg8Unorm
   Rgba8Unorm
   Rgba8UnormSrgb
   Bgra8Unorm
   Bgra8UnormSrgb
   R32Uint
   R32Float
   Rg32Uint
   Rgba16Float
   Rgba32Float
   Rg11b10Ufloat
   Depth24Plus
   Depth32Float
   texture-format-name
   texture-format-named
   texel-bytes
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
   ViewDimension
   View2d
   View2dArray
   TextureView
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
   ColorAttachment
   DepthAttachment
   RenderPassDescriptor
   IndexFormat
   Uint16Index
   Uint32Index
   Objects
   make-objects
   Request
   Claim
   Existing
   Create
   Entry
   claim!
   known!
   use!
   all-used!
   retire!
   end-frame!
   object-entry
   path-name
   buffer-handle
   texture-handle
   sampler-handle
   module-handle
   pipeline-handle
   bind-group-handle
   buffer-request
   texture-request
   image-request
   sampler-request
   module-request
   pipeline-request
   bind-group-request
   Field
   Word
   Text
   fields-bytes
   fields-text
   view-dimension-name
   buffer-usage-bits
   texture-usage-bits)
  (import
   (snail core base)
   (snail core table)
   (only (snail shell task) tasks)
   (only (snail shell utf8) string->utf8))
  (begin

    ;; ---- Handles ----

    ;; A long-lived object's handle: its id on the host, its generation,
    ;; and whether this call made it. Encoders, passes and command buffers
    ;; last a frame and carry only their id.

    (record GpuBuffer
      ((id I32)
       (generation I32)
       (fresh Bool)))

    (record GpuTexture
      ((id I32)
       (generation I32)
       (fresh Bool)))

    (record GpuSampler
      ((id I32)
       (generation I32)
       (fresh Bool)))

    (record GpuShaderModule
      ((id I32)
       (generation I32)
       (fresh Bool)))

    (record GpuRenderPipeline
      ((id I32)
       (generation I32)
       (fresh Bool)))

    (record GpuBindGroup
      ((id I32)
       (generation I32)
       (fresh Bool)))

    (record GpuCommandEncoder
      ((id I32)))

    (record GpuRenderPass
      ((id I32)))

    (record GpuCommandBuffer
      ((id I32)))

    ;; What `destroy` takes: the objects that hold memory.
    (enum GpuObject
      (BufferObject ((buffer GpuBuffer)))
      (TextureObject ((texture GpuTexture))))

    ;; A decoded image: an rgba8unorm texture of its size.
    (record Image
      ((texture GpuTexture)
       (width I32)
       (height I32)))

    ;; The device a program was given: the canvas's preferred format, and
    ;; the optional features it has beyond the baseline.
    (record DeviceInfo
      ((format TextureFormat)
       (features (List String))))

    ;; ---- Buffers ----

    (enum BufferUsage
      (MapRead)
      (CopySrc)
      (CopyDst)
      (Index)
      (Vertex)
      (Uniform)
      (Storage)
      (Indirect))

    ;; A path names a long-lived buffer; without one, the buffer lasts the
    ;; frame.
    (record BufferDescriptor
      ((path (Option (List String)))
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
        ((Indirect) 256)))

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

    ;; The bytes a texel takes, for the memory budget.

    (define (texel-bytes (format TextureFormat)) (→ I64)
      (match format
        ((R8Unorm) 1)
        ((Rg8Unorm) 2)
        ((Rgba16Float) 8)
        ((Rg32Uint) 8)
        ((Rgba32Float) 16)
        (_ 4)))

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
      ((path (Option (List String)))
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
      ((path (Option (List String)))
       (mag-filter FilterMode)
       (min-filter FilterMode)
       (mipmap-filter FilterMode)
       (address AddressMode)))

    (record ShaderModuleDescriptor
      ((path (Option (List String)))
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

    (record FragmentState
      ((entry String)
       (targets (List ColorTarget))))

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
      ((path (Option (List String)))
       (module GpuShaderModule)
       (vertex-entry String)
       (buffers (List VertexBufferLayout))
       (fragment (Option FragmentState))
       (topology Topology)
       (cull CullMode)
       (depth (Option DepthState))))

    ;; ---- Bind groups ----

    (enum ViewDimension
      (View2d)
      (View2dArray))

    ;; A view of some of a texture's levels and layers; `layers` 0 is every
    ;; layer from `base-layer` on.
    (record TextureView
      ((texture GpuTexture)
       (dimension ViewDimension)
       (base-mip I32)
       (mips I32)
       (base-layer I32)
       (layers I32)))

    ;; A view of the first `mips` levels of layer 0.

    (define (view-of (texture GpuTexture) (mips I32)) (→ TextureView)
      (new TextureView
        (texture texture)
        (dimension (View2d))
        (base-mip 0)
        (mips mips)
        (base-layer 0)
        (layers 1)))

    ;; A texture's whole array, at its first level.

    (define (array-view (texture GpuTexture)) (→ TextureView)
      (new TextureView
        (texture texture)
        (dimension (View2dArray))
        (base-mip 0)
        (mips 1)
        (base-layer 0)
        (layers 0)))

    (define (layer-view (texture GpuTexture) (layer I32)) (→ TextureView)
      (new TextureView
        (texture texture)
        (dimension (View2d))
        (base-mip 0)
        (mips 1)
        (base-layer layer)
        (layers 1)))

    ;; A buffer's size 0 binds the rest of it.
    (enum BindGroupEntry
      (BufferEntry ((binding I32) (buffer GpuBuffer) (offset I32) (size I32)))
      (TextureEntry ((binding I32) (view TextureView)))
      (SamplerEntry ((binding I32) (sampler GpuSampler))))

    (record BindGroupDescriptor
      ((path (Option (List String)))
       (pipeline GpuRenderPipeline)
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

    (enum DepthLoad
      (ClearDepth ((depth F64)))
      (KeepDepth))

    (record ColorAttachment
      ((view TextureView)
       (load ColorLoad)
       (store Bool)))

    (record DepthAttachment
      ((view TextureView)
       (load DepthLoad)
       (store Bool)))

    (record RenderPassDescriptor
      ((colors (List ColorAttachment))
       (depth (Option DepthAttachment))))

    (enum IndexFormat
      (Uint16Index)
      (Uint32Index))

    ;; ---- The effect ----

    ;; `request-device` asks the page for its device once, with a memory
    ;; budget in bytes, and every other operation needs it. Offsets and
    ;; sizes are in bytes. `write-texture` takes a copy's start, the bytes
    ;; of a row, the width and height copied, and the texels. `decode-image`
    ;; decodes an encoded image into a texture of its own, made by `path`,
    ;; which names the image's bytes: the same path answers the texture
    ;; already decoded. `read-buffer` waits until the buffer, made with
    ;; `MapRead`, can be read, and answers the bytes asked for.
    ;; `current-texture` is the canvas's texture for this frame, sized to
    ;; the canvas's pixels on the screen, and its size. `submit` ends the
    ;; frame.
    (effect gpu
      ((request-device (Fn I64 → DeviceInfo ! tasks))
       (create-buffer (Fn BufferDescriptor → GpuBuffer))
       (write-buffer (Fn GpuBuffer I32 Bytes → Unit))
       (read-buffer (Fn GpuBuffer I32 I32 → Bytes ! tasks))
       (create-texture (Fn TextureDescriptor → GpuTexture))
       (write-texture (Fn TextureCopy I32 I32 I32 Bytes → Unit))
       (decode-image (Fn (List String) Bytes → Image ! tasks))
       (create-sampler (Fn SamplerDescriptor → GpuSampler))
       (create-shader-module (Fn ShaderModuleDescriptor → GpuShaderModule))
       (create-render-pipeline (Fn RenderPipelineDescriptor → GpuRenderPipeline))
       (create-bind-group (Fn BindGroupDescriptor → GpuBindGroup))
       (create-command-encoder (Fn → GpuCommandEncoder))
       (copy-buffer-to-buffer (Fn GpuCommandEncoder GpuBuffer I32 GpuBuffer I32 I32 → Unit))
       (copy-texture-to-buffer (Fn GpuCommandEncoder TextureCopy GpuBuffer I32 I32 I32 I32 → Unit))
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
       (finish (Fn GpuCommandEncoder → GpuCommandBuffer))
       (submit (Fn (List GpuCommandBuffer) → Unit))
       (current-texture (Fn → Image))
       (destroy (Fn GpuObject → Unit))))

    ;; ---- Objects ----

    ;; What the books know of a live object: its id, its kind, its path ("" for
    ;; one that lasts the frame), its generation, the descriptor it was
    ;; made with, the bytes it holds, the last frame that used it, the
    ;; objects its descriptor names, and an image's size.
    (record Entry
      ((id I32)
       (kind String)
       (path String)
       (generation I32)
       (descriptor (List Field))
       (bytes I64)
       (frame I64)
       (depends (List I32))
       (width I32)
       (height I32)))

    ;; The books: the frame's number, the next id, the budget and the bytes
    ;; live objects hold, the live objects by id, the ids of long-lived ones
    ;; by path, the last generation of each path, the frame's own objects,
    ;; and what each gone long-lived object was. One handler owns them.
    (record Objects
      ((frame I64)
       (next I32)
       (budget I64)
       (used I64)
       (live (Table Entry))
       (paths (Table I32))
       (generations (Table I32))
       (transients (List I32))
       (gone (Table String))))

    (define (make-objects (budget I64)) (→ Objects)
      (new Objects
        (frame 0)
        (next 1)
        (budget budget)
        (used 0)
        (live (empty-table))
        (paths (empty-table))
        (generations (empty-table))
        (transients (Nil))
        (gone (empty-table))))

    (define (path-name (path (List String))) (→ String)
      (string-join path "/"))

    ;; What making an object asks: its kind, its path, its descriptor's
    ;; text, its bytes, the ids its descriptor names and an image's size.
    (record Request
      ((kind String)
       (path (Option (List String)))
       (descriptor (List Field))
       (bytes I64)
       (depends (List I32))
       (width I32)
       (height I32)))

    ;; The object a request answers: one already made, or one to make now,
    ;; after destroying those it replaces or evicts.
    (enum Claim
      (Existing ((entry Entry)))
      (Create ((entry Entry) (retired (List Entry)))))

    ;; An object by its path when its descriptor is unchanged; otherwise a
    ;; new one, under the next id, with room made for it.

    (define (claim! (objects Objects) (request Request)) (→ Claim) (! mut)
      (match (found objects request)
        ((Some entry) (mark! objects entry) (Existing entry))
        ((None)
         (let* ((replaced (replaced! objects request))
                (evicted (make-room! objects (● request bytes))))
           (Create (register! objects request) (append replaced evicted))))))

    ;; The object a request names, if the books have it, marked for use.

    (define (known! (objects Objects) (request Request)) (→ (Option Entry)) (! mut)
      (match (found objects request)
        ((Some entry) (mark! objects entry) (Some entry))
        ((None) (None))))

    (define (found (objects Objects) (request Request)) (→ (Option Entry))
      (match (● request path)
        ((Some path)
         (match (table-ref (● objects paths) (path-key (● request kind) (path-name path)))
           ((Some id)
            (let ((entry (object-entry objects id)))
              (if (and (string=? (● entry kind) (● request kind))
                       (same-fields? (● entry descriptor) (● request descriptor)))
                  (Some entry)
                  (None))))
           ((None) (None))))
        ((None) (None))))

    ;; The object a path named before, now that its descriptor changed, and
    ;; those that named it.

    (define (replaced! (objects Objects) (request Request)) (→ (List Entry)) (! mut)
      (match (● request path)
        ((Some path)
         (match (table-ref (● objects paths) (path-key (● request kind) (path-name path)))
           ((Some id) (Cons (retire! objects id "replaced") (dependents! objects id)))
           ((None) (Nil))))
        ((None) (Nil))))

    (define (register! (objects Objects) (request Request)) (→ Entry) (! mut)
      (let* ((path (match (● request path)
                     ((Some path) (path-name path))
                     ((None) "")))
             (key (path-key (● request kind) path))
             (generation (if (string=? path "") 1 (+ 1 (generation-of objects key))))
             (entry (new Entry
                      (id (● objects next))
                      (kind (● request kind))
                      (path path)
                      (generation generation)
                      (descriptor (● request descriptor))
                      (bytes (● request bytes))
                      (frame (● objects frame))
                      (depends (● request depends))
                      (width (● request width))
                      (height (● request height)))))
        (set! (● objects next) (+ 1 (● objects next)))
        (set! (● objects used) (+ (● objects used) (● request bytes)))
        (set! (● objects live) (table-set (● objects live) (show (● entry id)) entry))
        (if (string=? path "")
            (set! (● objects transients) (Cons (● entry id) (● objects transients)))
            (begin
              (set! (● objects paths) (table-set (● objects paths) key (● entry id)))
              (set! (● objects generations) (table-set (● objects generations) key generation))))
        entry))

    ;; A path names one object of each kind: a pipeline and its bind group
    ;; may share one.

    (define (path-key (kind String) (path String)) (→ String)
      (string-append kind " " path))

    (define (generation-of (objects Objects) (key String)) (→ I32)
      (match (table-ref (● objects generations) key)
        ((Some generation) generation)
        ((None) 0)))

    ;; A live object, or a panic saying why it is gone.

    (define (object-entry (objects Objects) (id I32)) (→ Entry)
      (match (table-ref (● objects live) (show id))
        ((Some entry) entry)
        ((None)
         (panic (match (table-ref (● objects gone) (show id))
                  ((Some why) (string-append "gpu: object " (show id) ", " why))
                  ((None)
                   (string-append "gpu: object " (show id) " lasted a frame that has ended")))))))

    ;; A use marks an object, and those its descriptor names, for this frame.

    (define (use! (objects Objects) (id I32)) (→ Entry) (! mut)
      (let ((entry (object-entry objects id)))
        (mark! objects entry)
        entry))

    (define (all-used! (objects Objects) (ids (List I32))) (→ Unit) (! mut)
      (for-each (lambda (id) (use! objects id) (unit)) ids))

    (define (mark! (objects Objects) (entry Entry)) (→ Unit) (! mut)
      (set! (● entry frame) (● objects frame))
      (for-each (lambda (id)
                  (match (table-ref (● objects live) (show id))
                    ((Some depended) (set! (● depended frame) (● objects frame)))
                    ((None) (unit))))
                (● entry depends)))

    ;; An object taken off the books, and what it was remembered as.

    (define (retire! (objects Objects) (id I32) (why String)) (→ Entry) (! mut)
      (let ((entry (object-entry objects id)))
        (set! (● objects live) (table-remove (● objects live) (show id)))
        (set! (● objects used) (- (● objects used) (● entry bytes)))
        (unless (string=? (● entry path) "")
          (set! (● objects paths)
                (table-remove (● objects paths) (path-key (● entry kind) (● entry path))))
          (set! (● objects gone)
                (table-set (● objects gone)
                           (show id)
                           (string-append (● entry kind)
                                          " "
                                          (● entry path)
                                          " generation "
                                          (show (● entry generation))
                                          ", was "
                                          why))))
        entry))

    ;; ---- Eviction ----

    ;; Room for `bytes` more: the least recently used long-lived objects
    ;; that hold memory and this frame has not used are evicted, and with
    ;; them any object whose descriptor names one. If those this frame uses are over the budget
    ;; alone, the program panics.

    (define (make-room! (objects Objects) (bytes I64)) (→ (List Entry)) (! mut)
      (if (<= (+ (● objects used) bytes) (● objects budget))
          (Nil)
          (let ((victims (list-sort (lambda (a b) (< (● a frame) (● b frame)))
                                    (filter (lambda (entry)
                                              (and (not (string=? (● entry path) ""))
                                                   (> (● entry bytes) 0)
                                                   (< (● entry frame) (● objects frame))))
                                            (table-values (● objects live))))))
            (evicting! objects bytes victims (Nil)))))

    (define (evicting! (objects Objects) (bytes I64) (victims (List Entry)) (evicted (List Entry)))
      (→ (List Entry))
      (! mut)
      (cond ((<= (+ (● objects used) bytes) (● objects budget)) (reverse evicted))
            (else
             (match victims
               ((Nil) (panic (over-budget objects bytes)))
               ((Cons victim rest)
                (let ((gone (Cons (retire! objects (● victim id) "evicted")
                                  (dependents! objects (● victim id)))))
                  (evicting! objects
                             bytes
                             (filter (lambda (entry)
                                       (not (any? (lambda (g) (= (● g id) (● entry id))) gone)))
                                     rest)
                             (append (reverse gone) evicted))))))))

    (define (dependents! (objects Objects) (id I32)) (→ (List Entry)) (! mut)
      (map (lambda (entry) (retire! objects (● entry id) "gone with an object it named"))
           (filter (lambda (entry) (member? id (● entry depends)))
                   (table-values (● objects live)))))

    (define (over-budget (objects Objects) (bytes I64)) (→ String)
      (string-append "gpu: this frame needs "
                     (show (+ (● objects used) bytes))
                     " bytes, over the budget of "
                     (show (● objects budget))
                     "; the largest objects it uses: "
                     (string-join (map (lambda (entry)
                                         (string-append (if (string=? (● entry path) "")
                                                            (● entry kind)
                                                            (● entry path))
                                                        " "
                                                        (show (● entry bytes))))
                                       (take (list-sort (lambda (a b) (> (● a bytes) (● b bytes)))
                                                        (table-values (● objects live)))
                                             (min 3 (length (table-values (● objects live))))))
                                  ", ")))

    ;; ---- Frames ----

    ;; The frame's own objects, taken off the books, and the next frame begun.

    (define (end-frame! (objects Objects)) (→ (List Entry)) (! mut)
      (let ((ended
             (map (lambda (id) (retire! objects id "ended")) (reverse (● objects transients)))))
        (set! (● objects transients) (Nil))
        (set! (● objects frame) (+ 1 (● objects frame)))
        ended))

    ;; ---- Handles from entries ----

    (define (buffer-handle (entry Entry) (fresh Bool)) (→ GpuBuffer)
      (new GpuBuffer (id (● entry id)) (generation (● entry generation)) (fresh fresh)))

    (define (texture-handle (entry Entry) (fresh Bool)) (→ GpuTexture)
      (new GpuTexture (id (● entry id)) (generation (● entry generation)) (fresh fresh)))

    (define (sampler-handle (entry Entry) (fresh Bool)) (→ GpuSampler)
      (new GpuSampler (id (● entry id)) (generation (● entry generation)) (fresh fresh)))

    (define (module-handle (entry Entry) (fresh Bool)) (→ GpuShaderModule)
      (new GpuShaderModule (id (● entry id)) (generation (● entry generation)) (fresh fresh)))

    (define (pipeline-handle (entry Entry) (fresh Bool)) (→ GpuRenderPipeline)
      (new GpuRenderPipeline (id (● entry id)) (generation (● entry generation)) (fresh fresh)))

    (define (bind-group-handle (entry Entry) (fresh Bool)) (→ GpuBindGroup)
      (new GpuBindGroup (id (● entry id)) (generation (● entry generation)) (fresh fresh)))

    ;; ---- Descriptors as fields ----

    ;; A descriptor field: a 32-bit word, or a text. A text crosses as its
    ;; UTF-8 length and bytes, padded to a word; an object a descriptor
    ;; names is its id, a word; an enum value is WebGPU's name for it, a
    ;; text; an optional part is a word, 1 when present, before it.
    (enum Field
      (Word ((value I32)))
      (Text ((value String))))

    (define (same-fields? (a (List Field)) (b (List Field))) (→ Bool)
      (match (new Pair (first a) (second b))
        ((Pair (Nil) (Nil)) #t)
        ((Pair (Cons x a) (Cons y b)) (and (same-field? x y) (same-fields? a b)))
        (_ #f)))

    (define (same-field? (a Field) (b Field)) (→ Bool)
      (match (new Pair (first a) (second b))
        ((Pair (Word x) (Word y)) (= x y))
        ((Pair (Text x) (Text y)) (string=? x y))
        (_ #f)))

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
      (unsafe-total
       (lambda ()
         (let ((bytes (make-array
                       (fold-left (lambda (total piece) (+ total (array-length piece))) 0 pieces)
                       (i32->u8 0))))
           (fold-left (lambda (at piece)
                        (array-copy! bytes at piece 0 (array-length piece))
                        (+ at (array-length piece)))
                      0
                      pieces)
           bytes))))

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

    ;; A request for an object of `kind` at `path`.

    (define (request (kind String)
                     (path (Option (List String)))
                     (fields (List Field))
                     (bytes I64)
                     (depends (List I32)))
      (→ Request)
      (new Request
        (kind kind)
        (path path)
        (descriptor fields)
        (bytes bytes)
        (depends depends)
        (width 0)
        (height 0)))

    ;; Size, usage.

    (define (buffer-request (descriptor BufferDescriptor)) (→ Request)
      (request "buffer"
               (● descriptor path)
               (list (word (● descriptor size)) (word (buffer-usage-bits (● descriptor usage))))
               (i32->i64 (● descriptor size))
               (Nil)))

    ;; Width, height, layers, levels, format, usage. A texture's bytes count
    ;; a third more when it has levels below its first.

    (define (texture-request (descriptor TextureDescriptor)) (→ Request)
      (let ((base (* (texel-bytes (● descriptor format))
                     (* (i32->i64 (● descriptor width))
                        (* (i32->i64 (● descriptor height)) (i32->i64 (● descriptor layers)))))))
        (request "texture"
                 (● descriptor path)
                 (list (word (● descriptor width))
                       (word (● descriptor height))
                       (word (● descriptor layers))
                       (word (● descriptor mips))
                       (Text (texture-format-name (● descriptor format)))
                       (word (texture-usage-bits (● descriptor usage))))
                 (if (> (● descriptor mips) 1) (quotient (* base 4) 3) base)
                 (Nil))))

    ;; An image is known by its path alone; its size comes from decoding.

    (define (image-request (path (List String)) (width I32) (height I32)) (→ Request)
      (new Request
        (kind "image")
        (path (Some path))
        (descriptor (Nil))
        (bytes (* 4 (* (i32->i64 width) (i32->i64 height))))
        (depends (Nil))
        (width width)
        (height height)))

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

    (define (sampler-request (descriptor SamplerDescriptor)) (→ Request)
      (request "sampler"
               (● descriptor path)
               (list (Text (filter-name (● descriptor mag-filter)))
                     (Text (filter-name (● descriptor min-filter)))
                     (Text (filter-name (● descriptor mipmap-filter)))
                     (Text (address-name (● descriptor address))))
               0
               (Nil)))

    ;; The WGSL code.

    (define (module-request (descriptor ShaderModuleDescriptor)) (→ Request)
      (request "shader" (● descriptor path) (list (Text (● descriptor code))) 0 (Nil)))

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

    (define (pipeline-request (descriptor RenderPipelineDescriptor)) (→ Request)
      (request "render-pipeline"
               (● descriptor path)
               (concatenate
                (list (list (word (● (● descriptor module) id)) (Text (● descriptor vertex-entry)))
                      (counted (● descriptor buffers) layout-fields)
                      (match (● descriptor fragment)
                        ((Some fragment)
                         (Cons (flag #t)
                               (Cons (Text (● fragment entry))
                                     (counted (● fragment targets) target-fields))))
                        ((None) (list (flag #f))))
                      (list (Text (topology-name (● descriptor topology)))
                            (Text (cull-name (● descriptor cull))))
                      (match (● descriptor depth)
                        ((Some depth)
                         (list (flag #t)
                               (Text (texture-format-name (● depth format)))
                               (flag (● depth write))
                               (Text (compare-name (● depth compare)))))
                        ((None) (list (flag #f))))))
               0
               (list (● (● descriptor module) id))))

    (define (view-dimension-name (dimension ViewDimension)) (→ String)
      (match dimension
        ((View2d) "2d")
        ((View2dArray) "2d-array")))

    ;; Texture, dimension, first level and count, first layer and count (0
    ;; for the rest).

    (define (view-fields (view TextureView)) (→ (List Field))
      (list (word (● (● view texture) id))
            (Text (view-dimension-name (● view dimension)))
            (word (● view base-mip))
            (word (● view mips))
            (word (● view base-layer))
            (word (● view layers))))

    ;; Binding, then 0 with buffer, offset and size (0 for the rest), 1 with
    ;; a view, or 2 with a sampler.

    (define (entry-fields (entry BindGroupEntry)) (→ (List Field))
      (match entry
        ((BufferEntry binding buffer offset size)
         (list (word binding) (word 0) (word (● buffer id)) (word offset) (word size)))
        ((TextureEntry binding view) (append (list (word binding) (word 1)) (view-fields view)))
        ((SamplerEntry binding sampler) (list (word binding) (word 2) (word (● sampler id))))))

    (define (entry-object (entry BindGroupEntry)) (→ I32)
      (match entry
        ((BufferEntry _ buffer _ _) (● buffer id))
        ((TextureEntry _ view) (● (● view texture) id))
        ((SamplerEntry _ sampler) (● sampler id))))

    ;; The pipeline whose layout it takes, the group's index, and its
    ;; entries.

    (define (bind-group-request (descriptor BindGroupDescriptor)) (→ Request)
      (request "bind-group"
               (● descriptor path)
               (Cons (word (● (● descriptor pipeline) id))
                     (Cons (word (● descriptor group))
                           (counted (● descriptor entries) entry-fields)))
               0
               (Cons (● (● descriptor pipeline) id) (map entry-object (● descriptor entries)))))

    ))
