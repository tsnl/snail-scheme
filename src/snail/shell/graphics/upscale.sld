;; Resolve a jittered first hit on the stable display grid, before tone mapping.
(define-library (snail shell graphics upscale)
  (export Upscaler make-upscaler release-upscaler resolve-upscaled jitter-camera sample-phase)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics kernel)
   (snail shell graphics raster)
   (snail shell graphics passes)
   (only (snail shell graphics animation) unit-matrix matrix-product v4)
   (only (snail shell graphics shaders) upscale-shader))
  (begin
    ;; Eight centered subpixel locations. Positive y is down in image space.
    (define (sample-phase (frame I32)) (→ Vec2f)
      (let* ((i (i32->i64 (i32-and frame 7))) (j (list-ref (list 0 4 2 6 1 5 3 7) i)))
        (new Vec2f (x (- (* 0.125 (+ (i64->f32 i) 0.5)) 0.5))
             (y (- (* 0.125 (+ (i64->f32 j) 0.5)) 0.5)))))
    (define (jitter-camera (c Camera3D) (j Vec2f) (width I32) (height I32)) (→ Camera3D)
      (let* ((x (/ (* -2.0 (● j x)) (i32->f32 width))) (y (/ (* 2.0 (● j y)) (i32->f32 height)))
             (shift (lambda (a b) (Mat4x4f-w-set unit-matrix (v4 a b 0.0 1.0)))))
        (Camera3D-inverse-set
         (Camera3D-view-projection-set c (matrix-product (shift x y) (● c view-projection)))
         (matrix-product (● c inverse) (shift (negate x) (negate y))))))
    (record Upscaler
      ((width I32)
       (height I32)
       (kernel GpuComputePipeline)
       (uniform GpuBuffer)
       (colors (List Plane))
       (ids (List Plane))
       (toned Plane)
       (groups (List GpuBindGroup))
       (tone-groups (List GpuBindGroup))
       (fxaa-group GpuBindGroup)))
    (define shift-shape (→ (Shape Vec4f)) (shape))
    (define camera-shape (→ (Shape Camera3D)) (shape))
    (define (make-upscaler (gpu Gpu) (post Post) (camera GpuBuffer) (depth Plane) (front Plane)
                           (planes (List Plane)) (w I32) (h I32)) (→ Upscaler)
                           (let* ((kernel (compute-kernel gpu ((● gpu create-shader-module)
                                                               (new ShaderModuleDescriptor
                                                                 (label "upscale")
                                                                 (code (string-append
                                                                        (declarations camera-shape)
                                                                        upscale-shader))))
                                                          "upscale" "resolve"))
                                  (uniform (uniform-buffer gpu
                                                           "upscale/jitter"
                                                           (pod-bytes shift-shape
                                                                      (v4 0.0 0.0 2.0 2.0))))
                                  (history (lambda (label format)
                                             (map (lambda (_)
                                                    (make-plane gpu
                                                                label
                                                                w
                                                                h
                                                                format
                                                                (list (TextureBinding)
                                                                      (StorageBinding))))
                                                  (iota 2))))
                                  (colors (history "upscale/color" (Rgba16Float)))
                                  (ids (history "upscale/triangle" (R32Uint)))
                                  (toned (make-plane gpu
                                                     "upscale/toned"
                                                     w
                                                     h
                                                     (Rgba8Unorm)
                                                     (list (RenderAttachment) (TextureBinding))))
                                  (inputs
                                   (list (BufferEntry 0 camera 0 0) (BufferEntry 1 uniform 0 0)
                                         (TextureEntry 2 (● post targets light-view))
                                         (TextureEntry 3 (● depth view))
                                         (TextureEntry 4 (● (list-ref planes 4) view))
                                         (TextureEntry 5 (● (list-ref planes 1) view))
                                         (TextureEntry 6 (● (list-ref planes 5) view))
                                         (TextureEntry 11 (● front view)))))
                             (new Upscaler
                               (width w)
                               (height h)
                               (kernel kernel)
                               (uniform uniform)
                               (colors colors)
                               (ids ids)
                               (toned toned)
                               (groups (map (lambda (i) (let ((old (- 1 i)))
                                                          (kernel-group gpu
                                                                        kernel
                                                                        0
                                                                        "upscale"
                                                                        (append inputs
                                                                                (list
                                                                                 (TextureEntry 7
                                                                                               (●
                                                                                                (list-ref
                                                                                                 colors
                                                                                                 old)
                                                                                                view))
                                                                                 (TextureEntry 8
                                                                                               (●
                                                                                                (list-ref
                                                                                                 ids
                                                                                                 old)
                                                                                                view))
                                                                                 (TextureEntry 9
                                                                                               (●
                                                                                                (list-ref
                                                                                                 colors
                                                                                                 i)
                                                                                                view))
                                                                                 (TextureEntry 10
                                                                                               (●
                                                                                                (list-ref
                                                                                                 ids
                                                                                                 i)
                                                                                                view)))))))
                                            (iota 2)))
                               (tone-groups (map (lambda (p)
                                                   (screen-group gpu
                                                                 "upscale/tone"
                                                                 (● post tone)
                                                                 (list
                                                                  (TextureEntry 0 (● p view)))))
                                                 colors))
                               (fxaa-group (screen-group gpu "upscale/fxaa" (● post fxaa)
                                                         (list (TextureEntry 1 (● toned view))
                                                               (SamplerEntry 2
                                                                             (● post sampler))))))))
    (define (resolve-upscaled (gpu Gpu) (encoder GpuCommandEncoder) (canvas GpuTextureView)
                              (u Upscaler) (post Post) (frame I32) (valid Bool)) (→ Unit)
                              (let* ((i (i32->i64 (i32-and frame 1)))
                                     (j (sample-phase frame))
                                     (p (sample-phase (- frame 1)))
                                     (pass ((● gpu begin-compute-pass) encoder)))
                                ((● gpu write-buffer)
                                 (● u uniform)
                                 0
                                 (pod-bytes shift-shape
                                            (v4 (● j x) (● j y) (if valid (● p x) 2.0) (● p y))))
                                ((● gpu set-compute-pipeline) pass (● u kernel))
                                ((● gpu set-compute-bind-group) pass 0 (list-ref (● u groups) i))
                                ((● gpu dispatch-workgroups)
                                 pass
                                 (quotient (+ (● u width) 7) 8)
                                 (quotient (+ (● u height) 7) 8)
                                 1)
                                ((● gpu end-compute-pass) pass)
                                (screen-pass gpu
                                             encoder
                                             (● u toned view)
                                             (● post tone)
                                             (list-ref (● u tone-groups) i))
                                (screen-pass gpu encoder canvas (● post fxaa) (● u fxaa-group))))
    (define (release-upscaler (gpu Gpu) (u Upscaler)) (→ Unit)
      (for-each (lambda (g) ((● gpu destroy) (BindGroupObject g)))
                (append (● u groups) (Cons (● u fxaa-group) (● u tone-groups))))
      (for-each (lambda (p) (release-plane gpu p))
                (append (● u colors) (Cons (● u toned) (● u ids))))
      ((● gpu destroy) (BufferObject (● u uniform)))
      ((● gpu destroy) (ComputePipelineObject (● u kernel))))))