;; Trace a stationary camera into an offscreen RGBA texture. The caller owns
;; the tracer, so another view can reuse the pipelines, geometry and BVH.
(define-library (snail shell graphics still)
  (export render-still read-rgba read-plane read-traced-radiance trace-reference)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics kernel)
   (snail shell graphics raster)
   (only (snail shell graphics trace shaders) reference-shader)
   (snail shell graphics trace render))
  (begin
    (define (read-rgba (gpu Gpu) (target Plane) (width I32) (height I32)) (→ Bytes)
      (read-plane gpu target width height 4))

    ;; Native texture bytes in top-to-bottom rows, without WebGPU pitch padding.
    (define (read-plane (gpu Gpu) (target Plane) (width I32) (height I32) (texel-size I64))
      (→ Bytes)
      (let* ((row (* texel-size (i32->i64 width))) (h (i32->i64 height))
             (pitch (* 256 (quotient (+ row 255) 256))) (size (i64->i32 (* pitch h)))
             (buffer
              ((● gpu create-buffer) (new BufferDescriptor (label "still/readback") (size size)
                                          (usage (list (CopyDst) (MapRead))))))
             (encoder ((● gpu create-command-encoder))))
        ((● gpu copy-texture-to-buffer)
         encoder
         (whole-texture (● target texture))
         buffer
         0
         (i64->i32 pitch)
         width
         height)
        ((● gpu submit) (list ((● gpu finish) encoder)))
        (let* ((padded ((● gpu read-buffer) buffer 0 size))
               (pixels (make-array (* row h) (i32->u8 0))))
          ((● gpu destroy) (BufferObject buffer))
          (for-each (lambda (y) (array-copy! pixels (* y row) padded (* y pitch) row)) (iota h))
          pixels)))

    ;; ---- Linear reference images ----

    (define (observations (t Tracer)) (→ I64)
      (* (* (i32->i64 (● t targets width)) (i32->i64 (● t targets height)))
         (match (● t targets blended) ((Some _) 2) (_ 1))))

    (define (read-radiance-buffer (gpu Gpu) (source GpuBuffer) (pixels I64)) (→ Bytes)
      (let* ((size (i64->i32 (* 16 pixels)))
             (back
              ((● gpu create-buffer) (new BufferDescriptor (label "reference/readback") (size size)
                                          (usage (list (MapRead) (CopyDst))))))
             (encoder ((● gpu create-command-encoder))))
        ((● gpu copy-buffer-to-buffer) encoder source 0 back 0 size)
        ((● gpu submit) (list ((● gpu finish) encoder)))
        (let ((bytes ((● gpu read-buffer) back 0 size)))
          ((● gpu destroy) (BufferObject back))
          bytes)))

    (define (read-traced-radiance (gpu Gpu) (t Tracer)) (→ Bytes)
      (read-radiance-buffer gpu (● t targets radiance) (observations t)))

    (define f32-shape (→ (Shape F32)) (shape))

    ;; Average disjoint seeds on the GPU, before filtering, exposure and tone
    ;; mapping. The blended first-hit layer, when present, follows the opaque layer.
    (define (trace-reference (gpu Gpu) (t Tracer) (camera Camera3D) (spread F32)
                             (bounces I64) (seed I32) (samples I64)) (→ Bytes)
                             (unless (and (> samples 0) (<= samples 4096))
                               (panic "reference samples must be in 1..4096"))
                             (let* ((n (observations t))
                                    (sum (storage-buffer gpu
                                                         "reference/mean"
                                                         (* 16 n)
                                                         (list (CopySrc))))
                                    (scale (uniform-buffer gpu
                                                           "reference/scale"
                                                           (pod-bytes f32-shape
                                                                      (/ 1.0 (i64->f32 samples)))))
                                    (module
                                     ((● gpu create-shader-module) (new ShaderModuleDescriptor
                                                                     (label "reference")
                                                                     (code reference-shader))))
                                    (add (compute-kernel gpu module "reference" "accumulate"))
                                    (group (kernel-group gpu
                                                         add
                                                         0
                                                         "reference"
                                                         (list
                                                          (BufferEntry 0 (● t targets radiance) 0 0)
                                                          (BufferEntry 1 sum 0 0)
                                                          (BufferEntry 2 scale 0 0)))))
                               (for-each (lambda (i)
                                           (let ((encoder ((● gpu create-command-encoder))))
                                             (encode-trace-observation gpu
                                                                       encoder
                                                                       t
                                                                       camera
                                                                       spread
                                                                       bounces
                                                                       (+ seed (i64->i32 i)))
                                             (let ((pass ((● gpu begin-compute-pass) encoder)))
                                               ((● gpu set-compute-pipeline) pass add)
                                               ((● gpu set-compute-bind-group) pass 0 group)
                                               (dispatch-items gpu pass n 64)
                                               ((● gpu end-compute-pass) pass))
                                             ((● gpu submit) (list ((● gpu finish) encoder)))
                                             (when (= (modulo i 8) 7) ((● gpu work-done)))))
                                         (iota samples))
                               (let ((bytes (read-radiance-buffer gpu sum n)))
                                 (for-each (lambda (o) ((● gpu destroy) o))
                                           (list (BufferObject sum)
                                                 (BufferObject scale)
                                                 (BindGroupObject group)
                                                 (ComputePipelineObject add) (ModuleObject module)))
                                 bytes)))

    (define (render-still (gpu Gpu) (tracer Tracer) (camera Camera3D) (samples I64)
                          (bounces I64) (exposure F32)) (→ (Pair Tracer Bytes))
                          (unless (and (> samples 0) (<= samples 4096))
                            (panic "still samples must be in 1..4096"))
                          (let* ((width (● tracer targets width)) (height (● tracer targets height))
                                 (target (make-plane gpu
                                                     "still"
                                                     width
                                                     height
                                                     (Rgba8Unorm)
                                                     (list (RenderAttachment) (TextureCopySrc)))))
                            (let loop ((frame (discard-trace-history tracer)) (i 0))
                              (if (= i samples)
                                  (let ((pixels (read-rgba gpu target width height)))
                                    (release-plane gpu target)
                                    (new Pair (first frame) (second pixels)))
                                  (let ((next (draw-traced gpu frame (● target view) camera
                                                           (/ 1.0 (i32->f32 height))
                                                           exposure
                                                           bounces
                                                           #f
                                                           (new TraceSettings
                                                             (display-width width)
                                                             (display-height height)))))
                                    ;; Bound the queued frames for large offline sample counts.
                                    (when (= (modulo i 8) 7) ((● gpu work-done)))
                                    (loop next (+ i 1)))))))))
