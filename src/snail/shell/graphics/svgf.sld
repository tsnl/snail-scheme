;; A denoiser for one-path-a-pixel light: spatiotemporal variance-guided
;; filtering (Schied et al. 2017), as svgf.wgsl.scm explains. It reads a
;; frame's noisy radiance and the G-buffer planes it was traced from,
;; keeps a history across frames, and writes the filtered light, scaled
;; by an exposure, into a plane the program gives it, such as Post's.
;;
;;   (let ((svgf (filter-svgf encoder (resize-svgf svgf inputs light w h) moved exposure))) ...)
;;
;; A frame is one compute pass of temporal, variance and the first
;; à-trous level, whose output is copied into the history, then a pass of
;; four more levels and the light. The two histories change places each
;; frame.
(define-library (snail shell graphics svgf)
  (export
   SvgfInputs
   Svgf
   make-svgf
   resize-svgf
   filter-svgf)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics raster)
   (snail shell graphics shaders))
  (begin

    ;; What a frame is filtered from: the noisy radiance, the G-buffer's
    ;; octahedral normals (shading and geometric), emission, albedo and
    ;; screen motion, its depth, and the uniform of the camera it was seen
    ;; with, whose `previous` is last frame's.
    (record SvgfInputs
      ((noisy GpuTextureView)
       (normals GpuTextureView)
       (emission GpuTextureView)
       (albedo GpuTextureView)
       (motion GpuTextureView)
       (depth GpuTextureView)
       (camera GpuBuffer)))

    ;; The filters' uniform, one slot each: the longest history, the least
    ;; weight a frame gets and the exposure, then an à-trous level's step.
    (record Filtering
      ((limits Vec4f))
      (deriving Pod))

    (define filtering-shape (→ (Shape Filtering)) (shape))
    (define camera-shape (→ (Shape Camera3D)) (shape))

    (record Kernels
      ((temporal GpuComputePipeline)
       (variance GpuComputePipeline)
       (atrous GpuComputePipeline)
       (remodulate GpuComputePipeline)
       (filtering GpuBuffer)))

    ;; The kernels, the planes for a size and the groups over them, and
    ;; which history is this frame's.
    (record Svgf
      ((kernels Kernels)
       (width I32)
       (height I32)
       (planes (List Plane))
       (temporal-groups (List GpuBindGroup))
       (variance-groups (List GpuBindGroup))
       (atrous-groups (List GpuBindGroup))
       (remodulate-group GpuBindGroup)
       (parity I64)))

    (define (make-svgf (inputs SvgfInputs) (light GpuTextureView) (width I32) (height I32)) (→ Svgf) (! gpu)
      (let ((module (create-shader-module (new ShaderModuleDescriptor
                                            (label "svgf")
                                            (code (string-append (declarations camera-shape)
                                                                 (string-append (declarations filtering-shape) svgf-shader)))))))
        (planned (new Kernels
                   (temporal (kernel module "temporal"))
                   (variance (kernel module "variance"))
                   (atrous (kernel module "atrous"))
                   (remodulate (kernel module "remodulate"))
                   (filtering (create-buffer (new BufferDescriptor
                                               (label "svgf/filtering")
                                               (size (* 6 256))
                                               (usage (list (Uniform) (CopyDst)))))))
                 inputs
                 light
                 width
                 height)))

    (define (kernel (module GpuShaderModule) (entry String)) (→ GpuComputePipeline) (! gpu)
      (create-compute-pipeline (new ComputePipelineDescriptor (label (string-append "svgf/" entry)) (module module) (entry entry))))

    ;; New planes and groups when the inputs or the size change; the
    ;; history starts again.
    (define (resize-svgf (svgf Svgf) (inputs SvgfInputs) (light GpuTextureView) (width I32) (height I32)) (→ Svgf) (! gpu)
      (release svgf)
      (planned (● svgf kernels) inputs light width height))

    (define (release (svgf Svgf)) (→ Unit) (! gpu)
      (for-each (lambda (group) (destroy (BindGroupObject group)))
                (Cons (● svgf remodulate-group)
                      (concatenate (list (● svgf temporal-groups) (● svgf variance-groups) (● svgf atrous-groups)))))
      (for-each (lambda (plane)
                  (destroy (ViewObject (● plane view)))
                  (destroy (TextureObject (● plane texture))))
                (● svgf planes)))

    ;; ---- A frame ----

    ;; `moved` when the camera moved since the last frame: a moving
    ;; camera keeps 32 frames at most and gives each at least a fifth, a
    ;; still one keeps averaging.
    (define (filter-svgf (encoder GpuCommandEncoder) (svgf Svgf) (moved Bool) (exposure F32)) (→ Svgf) (! gpu)
      (let ((kernels (● svgf kernels)) (parity (● svgf parity)))
        (write-buffer (● kernels filtering) 0 (filtering-bytes moved exposure))
        (let ((first (begin-compute-pass encoder)))
          (over-screen first svgf (● kernels temporal) (list-ref (● svgf temporal-groups) parity))
          (over-screen first svgf (● kernels variance) (list-ref (● svgf variance-groups) parity))
          (over-screen first svgf (● kernels atrous) (list-ref (● svgf atrous-groups) 0))
          (end-compute-pass first))
        (copy-texture-to-texture encoder
                                 (whole-texture (● (plane (● svgf planes) "pong") texture))
                                 (whole-texture (● (history (● svgf planes) "color" parity) texture))
                                 (● svgf width)
                                 (● svgf height))
        (let ((rest (begin-compute-pass encoder)))
          (for-each (lambda (level) (over-screen rest svgf (● kernels atrous) (list-ref (● svgf atrous-groups) level)))
                    (list 1 2 3 4))
          (over-screen rest svgf (● kernels remodulate) (● svgf remodulate-group))
          (end-compute-pass rest))
        (Svgf-parity-set svgf (- 1 parity))))

    (define (over-screen (pass GpuComputePass) (svgf Svgf) (pipeline GpuComputePipeline) (group GpuBindGroup)) (→ Unit) (! gpu)
      (set-compute-pipeline pass pipeline)
      (set-compute-bind-group pass 0 group)
      (dispatch-workgroups pass (quotient (+ (● svgf width) 7) 8) (quotient (+ (● svgf height) 7) 8) 1))

    ;; Slot 0 for the temporal filter and the light, slots 1 to 5 for the
    ;; à-trous levels' steps.
    (define (filtering-bytes (moved Bool) (exposure F32)) (→ Bytes)
      (fold-left array-append
                 (make-array 0 (i32->u8 0))
                 (map (lambda (limits)
                        (let ((bytes (pod-bytes filtering-shape (new Filtering (limits limits)))))
                          (array-append bytes (make-array (- 256 (array-length bytes)) (i32->u8 0)))))
                      (Cons (if moved
                                (new Vec4f (x 32.0) (y 0.2) (z 0.0) (w exposure))
                                (new Vec4f (x 4096.0) (y 0.0) (z 0.0) (w exposure)))
                            (map (lambda (stride) (new Vec4f (x 0.0) (y 0.0) (z stride) (w 0.0)))
                                 (list 1.0 2.0 4.0 8.0 16.0))))))

    ;; ---- Planes ----

    ;; The planes in order: integrated, ping, pong, then two histories
    ;; each of colors, moments and places.
    (define plane-names
      (→ (List String))
      (list "integrated" "ping" "pong" "color" "color" "moments" "moments" "place" "place"))

    (define (plane (planes (List Plane)) (name String)) (→ Plane) (history planes name 0))

    ;; History `parity` of colors, moments or places; the first plane of
    ;; that name is history 0.
    (define (history (planes (List Plane)) (name String) (parity I64)) (→ Plane)
      (list-ref planes (+ parity (fold-left (lambda (found index)
                                              (if (and (< found 0) (string=? (list-ref plane-names index) name)) index found))
                                            -1
                                            (iota (length plane-names))))))

    (define (planned (kernels Kernels) (inputs SvgfInputs) (light GpuTextureView) (width I32) (height I32)) (→ Svgf) (! gpu)
      (let ((planes (map (lambda (name)
                           (filter-plane (string-append "svgf/" name)
                                         width
                                         height
                                         (if (string=? name "place") (Rgba32Float) (Rgba16Float))))
                         plane-names)))
        (new Svgf
          (kernels kernels)
          (width width)
          (height height)
          (planes planes)
          (temporal-groups (map (lambda (index) (group (● kernels temporal) (temporal-entries planes inputs (● kernels filtering) index)))
                                (iota 2)))
          (variance-groups (map (lambda (index) (group (● kernels variance) (variance-entries planes inputs index))) (iota 2)))
          (atrous-groups (map (lambda (level) (group (● kernels atrous) (atrous-entries planes inputs (● kernels filtering) level)))
                              (iota 5)))
          (remodulate-group (group (● kernels remodulate) (remodulate-entries planes inputs light (● kernels filtering))))
          (parity 0))))

    (define (filter-plane (label String) (width I32) (height I32) (format TextureFormat)) (→ Plane) (! gpu)
      (let ((texture (create-texture (new TextureDescriptor
                                       (label label)
                                       (width (max 1 width))
                                       (height (max 1 height))
                                       (layers 1)
                                       (mips 1)
                                       (format format)
                                       (usage (list (StorageBinding) (TextureBinding) (TextureCopySrc) (TextureCopyDst)))))))
        (new Plane (texture texture) (view (view-of texture 1)))))

    ;; ---- Groups ----

    (define (group (pipeline GpuComputePipeline) (entries (List BindGroupEntry))) (→ GpuBindGroup) (! gpu)
      (create-bind-group (new BindGroupDescriptor (label "svgf") (pipeline (ComputePipeline pipeline)) (group 0) (entries entries))))

    (define (temporal-entries (planes (List Plane)) (inputs SvgfInputs) (filtering GpuBuffer) (index I64)) (→ (List BindGroupEntry))
      (list (TextureEntry 0 (● inputs noisy))
            (TextureEntry 1 (● inputs albedo))
            (TextureEntry 2 (● inputs emission))
            (TextureEntry 3 (● inputs normals))
            (TextureEntry 4 (● inputs depth))
            (TextureEntry 5 (● inputs motion))
            (TextureEntry 6 (● (history planes "color" (- 1 index)) view))
            (TextureEntry 7 (● (history planes "moments" (- 1 index)) view))
            (TextureEntry 8 (● (history planes "place" (- 1 index)) view))
            (TextureEntry 9 (● (plane planes "integrated") view))
            (TextureEntry 10 (● (history planes "moments" index) view))
            (TextureEntry 11 (● (history planes "place" index) view))
            (BufferEntry 16 (● inputs camera) 0 0)
            (BufferEntry 17 filtering 0 256)))

    (define (variance-entries (planes (List Plane)) (inputs SvgfInputs) (index I64)) (→ (List BindGroupEntry))
      (list (TextureEntry 0 (● inputs noisy))
            (TextureEntry 3 (● inputs normals))
            (TextureEntry 4 (● inputs depth))
            (TextureEntry 12 (● (plane planes "integrated") view))
            (TextureEntry 13 (● (plane planes "ping") view))
            (TextureEntry 14 (● (history planes "moments" index) view))
            (BufferEntry 16 (● inputs camera) 0 0)))

    ;; Levels read ping and write pong, then the other way, so the fifth
    ;; ends in pong.
    (define (atrous-entries (planes (List Plane)) (inputs SvgfInputs) (filtering GpuBuffer) (level I64)) (→ (List BindGroupEntry))
      (let ((from (plane planes (if (= (remainder level 2) 0) "ping" "pong")))
            (to (plane planes (if (= (remainder level 2) 0) "pong" "ping"))))
        (list (TextureEntry 0 (● inputs noisy))
              (TextureEntry 3 (● inputs normals))
              (TextureEntry 4 (● inputs depth))
              (TextureEntry 12 (● from view))
              (TextureEntry 13 (● to view))
              (BufferEntry 16 (● inputs camera) 0 0)
              (BufferEntry 17 filtering (i64->i32 (* 256 (+ level 1))) 256))))

    (define (remodulate-entries (planes (List Plane)) (inputs SvgfInputs) (light GpuTextureView) (filtering GpuBuffer))
      (→ (List BindGroupEntry))
      (list (TextureEntry 0 (● inputs noisy))
            (TextureEntry 1 (● inputs albedo))
            (TextureEntry 2 (● inputs emission))
            (TextureEntry 4 (● inputs depth))
            (TextureEntry 12 (● (plane planes "pong") view))
            (TextureEntry 15 light)
            (BufferEntry 17 filtering 0 256)))

    ))
