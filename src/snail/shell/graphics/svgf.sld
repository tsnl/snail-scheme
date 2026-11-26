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
;; four more levels, in half floats, and the light. The two histories
;; change places each frame.
(define-library (snail shell graphics svgf)
  (export
   SvgfInputs
   Svgf
   make-svgf
   resize-svgf
   svgf-moments
   release-svgf
   filter-svgf filter-svgf-frame)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics kernel)
   (snail shell graphics raster)
   (snail shell graphics shaders))
  (begin

    ;; What a frame is filtered from: the noisy radiance, the G-buffer's
    ;; octahedral normals (shading and geometric), emission, albedo and
    ;; screen motion, its depth, and the uniform of the camera it was seen
    ;; with, whose `previous` is last frame's.
    ;; A negative noisy alpha holds the observation at the same still pixel.
    (record SvgfInputs
      ((noisy GpuTextureView)
       (normals GpuTextureView)
       (emission GpuTextureView)
       (albedo GpuTextureView)
       (motion GpuTextureView)
       (triangles GpuTextureView)
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
       (atrous-half GpuComputePipeline)
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

    (define (make-svgf (gpu Gpu)
                       (inputs SvgfInputs)
                       (light GpuTextureView)
                       (width I32)
                       (height I32))
      (→ Svgf)
      (let ((module ((● gpu create-shader-module) (new ShaderModuleDescriptor
                                                    (label "svgf")
                                                    (code (string-append (declarations camera-shape)
                                                                         (declarations
                                                                          filtering-shape)
                                                                         svgf-shader))))))
        (planned gpu (new Kernels
                       (temporal (compute-kernel gpu module "svgf" "temporal"))
                       (variance (compute-kernel gpu module "svgf" "variance"))
                       (atrous (compute-kernel gpu module "svgf" "atrous"))
                       (atrous-half (compute-kernel gpu module "svgf" "atrous_half"))
                       (remodulate (compute-kernel gpu module "svgf" "remodulate"))
                       (filtering
                        (uniform-buffer gpu "svgf/filtering" (filtering-bytes #t 1.0 #t))))
                 inputs
                 light
                 width
                 height)))

    ;; New planes and groups when the inputs or the size change; the
    ;; history starts again.
    (define (resize-svgf (gpu Gpu) (svgf Svgf)
                         (inputs SvgfInputs)
                         (light GpuTextureView)
                         (width I32)
                         (height I32))
      (→ Svgf)
      (release-svgf gpu svgf)
      (planned gpu (● svgf kernels) inputs light width height))

    ;; The planes and groups let go; the kernels, which hold no size, stay.
    (define (release-svgf (gpu Gpu) (svgf Svgf)) (→ Unit)
      (for-each (lambda (group) ((● gpu destroy) (BindGroupObject group)))
                (Cons (● svgf remodulate-group)
                      (concatenate (list (● svgf temporal-groups)
                                         (● svgf variance-groups)
                                         (● svgf atrous-groups)))))
      (for-each (lambda (plane) (release-plane gpu plane)) (● svgf planes)))

    ;; ---- A frame ----

    ;; Motion keeps at most four observations and gives the current one at
    ;; least 40% weight. A still frame keeps averaging.
    (define (filter-svgf (gpu Gpu)
                         (encoder GpuCommandEncoder)
                         (svgf Svgf)
                         (moved Bool)
                         (exposure F32))
      (→ Svgf)
      (filter-svgf-frame gpu encoder svgf moved exposure #f))
    (define (filter-svgf-frame (gpu Gpu) (encoder GpuCommandEncoder) (svgf Svgf)
                               (moved Bool) (exposure F32) (cut Bool)) (→ Svgf)
                               (let ((kernels (● svgf kernels)) (parity (● svgf parity)))
                                 ((● gpu write-buffer)
                                  (● kernels filtering)
                                  0
                                  (filtering-bytes moved exposure cut))
                                 (let ((first ((● gpu begin-compute-pass) encoder)))
                                   (over-screen gpu
                                                first
                                                svgf
                                                (● kernels temporal)
                                                (list-ref (● svgf temporal-groups) parity))
                                   (over-screen gpu
                                                first
                                                svgf
                                                (● kernels variance)
                                                (list-ref (● svgf variance-groups) parity))
                                   (over-screen gpu
                                                first
                                                svgf
                                                (● kernels atrous)
                                                (list-ref (● svgf atrous-groups) 0))
                                   ((● gpu end-compute-pass) first))
                                 ((● gpu copy-texture-to-texture) encoder
                                  (whole-texture (● (plane (● svgf planes) "pong") texture))
                                  (whole-texture
                                   (● (history (● svgf planes) "color" parity) texture))
                                  (● svgf width)
                                  (● svgf height))
                                 (let ((rest ((● gpu begin-compute-pass) encoder)))
                                   (for-each (lambda (level)
                                               (over-screen gpu rest
                                                            svgf
                                                            (● kernels atrous-half)
                                                            (list-ref (● svgf atrous-groups)
                                                                      level)))
                                             (list 1 2 3 4))
                                   (over-screen gpu
                                                rest
                                                svgf
                                                (● kernels remodulate)
                                                (● svgf remodulate-group))
                                   ((● gpu end-compute-pass) rest))
                                 (Svgf-parity-set svgf (- 1 parity))))

    (define (over-screen (gpu Gpu) (pass GpuComputePass)
                         (svgf Svgf)
                         (pipeline GpuComputePipeline)
                         (group GpuBindGroup))
      (→ Unit)
      ((● gpu set-compute-pipeline) pass pipeline)
      ((● gpu set-compute-bind-group) pass 0 group)
      (dispatch-texels gpu pass (● svgf width) (● svgf height)))

    ;; Slot 0 for the temporal filter and the light, slots 1 to 5 for the
    ;; à-trous levels' steps.
    (define (filtering-bytes (moved Bool) (exposure F32) (cut Bool)) (→ Bytes)
      (uniform-slots filtering-shape
                     (map (lambda (limits) (new Filtering (limits limits)))
                          (Cons (cond (cut (new Vec4f (x 1.0) (y 1.0) (z 0.0) (w exposure)))
                                      (moved (new Vec4f (x 4.0) (y 0.40) (z 0.0) (w exposure)))
                                      (else (new Vec4f (x 4096.0) (y 0.0) (z 0.0) (w exposure))))
                                (map (lambda (stride)
                                       (new Vec4f (x 0.0) (y 0.0) (z stride) (w 0.0)))
                                     (list 1.0 2.0 4.0 8.0 16.0))))))

    ;; ---- Planes ----

    ;; The planes in order: integrated, ping, pong, then two histories
    ;; each of colors, moments and places; the guide; and the half-float
    ;; pair the later à-trous levels take turns in. The first levels'
    ;; planes are rgba32float: a still camera's history is a running
    ;; average, which a frame moves by as little as 1/4096 of the
    ;; difference. Half floats keep 11 bits, so such a step rounds away in
    ;; each of the three writes on the way to the next history (temporal,
    ;; variance, the first à-trous level), and a still image drifted darker
    ;; the longer it held still: a third darker after 30 seconds. The later
    ;; levels' output reaches only this frame's light.
    (define plane-names
      (→ (List String))
      (list "integrated" "ping" "pong" "color" "color" "moments" "moments" "place" "place"
            "guide" "ping-half" "pong-half"))

    (define (plane-format (name String)) (→ TextureFormat)
      (cond ((string=? name "guide") (Rgba32Uint))
            ((or (string=? name "ping-half") (string=? name "pong-half")) (Rgba16Float))
            (else (Rgba32Float))))

    ;; The completed frame stores its two luminance moments and observation
    ;; count in RGB. The other parity is the next draw's destination.
    (define (svgf-moments (s Svgf)) (→ GpuTextureView)
      (● (history (● s planes) "moments" (- 1 (● s parity))) view))

    (define (plane (planes (List Plane)) (name String)) (→ Plane) (history planes name 0))

    ;; History `parity` of colors, moments or places; the first plane of
    ;; that name is history 0.
    (define (history (planes (List Plane)) (name String) (parity I64)) (→ Plane)
      (list-ref planes (+ parity (fold-left (lambda (found index)
                                              (if (and (< found 0)
                                                       (string=? (list-ref plane-names index) name))
                                                  index
                                                  found))
                                            -1
                                            (iota (length plane-names))))))

    (define (planned (gpu Gpu) (kernels Kernels)
                     (inputs SvgfInputs)
                     (light GpuTextureView)
                     (width I32)
                     (height I32))
      (→ Svgf)
      (let ((planes (map (lambda (name)
                           (make-plane gpu (string-append "svgf/" name)
                                       width
                                       height
                                       (plane-format name)
                                       (list (StorageBinding)
                                             (TextureBinding)
                                             (TextureCopySrc)
                                             (TextureCopyDst))))
                         plane-names)))
        (new Svgf
          (kernels kernels)
          (width width)
          (height height)
          (planes planes)
          (temporal-groups (map (lambda (index)
                                  (group gpu (● kernels temporal)
                                         (temporal-entries planes
                                                           inputs
                                                           (● kernels filtering)
                                                           index)))
                                (iota 2)))
          (variance-groups
           (map
            (lambda (index) (group gpu (● kernels variance) (variance-entries planes inputs index)))
            (iota 2)))
          (atrous-groups (map (lambda (level)
                                (group gpu
                                       (if (= level 0) (● kernels atrous) (● kernels atrous-half))
                                       (atrous-entries planes inputs (● kernels filtering) level)))
                              (iota 5)))
          (remodulate-group (group gpu (● kernels remodulate)
                                   (remodulate-entries planes inputs light (● kernels filtering))))
          (parity 0))))



    ;; ---- Groups ----

    (define (group (gpu Gpu) (pipeline GpuComputePipeline) (entries (List BindGroupEntry)))
      (→ GpuBindGroup)
      (kernel-group gpu pipeline 0 "svgf" entries))

    (define (temporal-entries (planes (List Plane))
                              (inputs SvgfInputs)
                              (filtering GpuBuffer)
                              (index I64))
      (→ (List BindGroupEntry))
      (list (TextureEntry 0 (● inputs noisy))
            (TextureEntry 1 (● inputs albedo))
            (TextureEntry 2 (● inputs emission))
            (TextureEntry 3 (● inputs normals))
            (TextureEntry 4 (● inputs depth))
            (TextureEntry 5 (● inputs motion))
            (TextureEntry 18 (● inputs triangles))
            (TextureEntry 6 (● (history planes "color" (- 1 index)) view))
            (TextureEntry 7 (● (history planes "moments" (- 1 index)) view))
            (TextureEntry 8 (● (history planes "place" (- 1 index)) view))
            (TextureEntry 9 (● (plane planes "integrated") view))
            (TextureEntry 10 (● (history planes "moments" index) view))
            (TextureEntry 11 (● (history planes "place" index) view))
            (TextureEntry 19 (● (plane planes "guide") view))
            (BufferEntry 16 (● inputs camera) 0 0)
            (slot-entry 17 filtering 0)))

    (define (variance-entries (planes (List Plane)) (inputs SvgfInputs) (index I64))
      (→ (List BindGroupEntry))
      (list (TextureEntry 0 (● inputs noisy))
            (TextureEntry 12 (● (plane planes "integrated") view))
            (TextureEntry 13 (● (plane planes "ping") view))
            (TextureEntry 14 (● (history planes "moments" index) view))
            (BufferEntry 16 (● inputs camera) 0 0)
            (TextureEntry 20 (● (plane planes "guide") view))))

    ;; The first level reads ping and writes pong, which the history keeps;
    ;; the rest read pong and take turns in the half-float pair, so the
    ;; fifth ends in pong-half.
    (define (atrous-entries (planes (List Plane))
                            (inputs SvgfInputs)
                            (filtering GpuBuffer)
                            (level I64))
      (→ (List BindGroupEntry))
      (let ((from (plane planes (list-ref (list "ping" "pong" "ping-half" "pong-half" "ping-half")
                                          level)))
            (to
             (plane planes (list-ref (list "pong" "ping-half" "pong-half" "ping-half" "pong-half")
                                     level))))
        (list (TextureEntry 0 (● inputs noisy))
              (TextureEntry 12 (● from view))
              (TextureEntry (if (= level 0) 13 21) (● to view))
              (BufferEntry 16 (● inputs camera) 0 0)
              (slot-entry 17 filtering (+ level 1))
              (TextureEntry 20 (● (plane planes "guide") view)))))

    (define (remodulate-entries (planes (List Plane))
                                (inputs SvgfInputs)
                                (light GpuTextureView)
                                (filtering GpuBuffer))
      (→ (List BindGroupEntry))
      (list (TextureEntry 0 (● inputs noisy))
            (TextureEntry 1 (● inputs albedo))
            (TextureEntry 2 (● inputs emission))
            (TextureEntry 4 (● inputs depth))
            (TextureEntry 12 (● (plane planes "pong-half") view))
            (TextureEntry 15 light)
            (slot-entry 17 filtering 0)))

    ))
