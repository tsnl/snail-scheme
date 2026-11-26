;; Resolve a jittered first hit on the stable display grid, and tone map it
;; there, for FXAA to smooth into the canvas.
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
   (only (snail shell graphics shaders) tone-shader upscale-shader))
  (begin
    ;; Reverse the base-b digits of n across the radix point.
    (define (radical-inverse (n I64) (base I64)) (→ F64)
      (let ((step (/ 1.0 (i64->f64 base))))
        (let loop ((digits n) (place step) (value 0.0))
          (if (= digits 0) value
              (loop (quotient digits base) (* place step)
                    (+ value (* place (i64->f64 (remainder digits base)))))))))

    ;; Halton(2,3), starting at index one. The offset is measured from
    ;; the center of an internal pixel, with positive y down.
    (define (sample-phase (frame I32)) (→ Vec2f)
      (let ((index (+ 1 (i32->i64 (i32-and frame 2147483647)))))
        (new Vec2f (x (f64->f32 (- (radical-inverse index 2) 0.5)))
             (y (f64->f32 (- (radical-inverse index 3) 0.5))))))
    (define (jitter-camera (c Camera3D) (j Vec2f) (width I32) (height I32)) (→ Camera3D)
      (let* ((x (/ (* -2.0 (● j x)) (i32->f32 width))) (y (/ (* 2.0 (● j y)) (i32->f32 height)))
             (shift (lambda (a b) (Mat4x4f-w-set unit-matrix (v4 a b 0.0 1.0)))))
        (Camera3D-inverse-set
         (Camera3D-view-projection-set c (matrix-product (shift x y) (● c view-projection)))
         (matrix-product (● c inverse) (shift (negate x) (negate y))))))
    (record Upscaler
      ((width I32)
       (height I32)
       (age I32)
       (kernel GpuComputePipeline)
       (uniform GpuBuffer)
       (colors (List Plane))
       (ids (List Plane))
       (toned Plane)
       (groups (List GpuBindGroup))
       (fxaa-group GpuBindGroup)))
    ;; The jitter now and before, how much a still view's history keeps,
    ;; whether it is valid, and the tone curve (tone.wgsl.scm's number).
    (record DisplayFrame
      ((jitter Vec2f)
       (previous-jitter Vec2f)
       (still-weight F32)
       (valid I32)
       (curve I32))
      (deriving Pod))
    (define (curve-number (curve Tone)) (→ I32)
      (match curve
        ((Neutral) 0)
        ((Filmic) 1)
        ((Photographic) 2)))
    (define display-shape (→ (Shape DisplayFrame)) (shape))
    (define camera-shape (→ (Shape Camera3D)) (shape))
    (define (make-upscaler (gpu Gpu) (post Post) (camera GpuBuffer) (depth Plane) (front Plane)
                           (planes (List Plane)) (w I32) (h I32)) (→ Upscaler)
                           (let* ((module ((● gpu create-shader-module)
                                           (new ShaderModuleDescriptor (label "upscale")
                                                (code (string-append (declarations camera-shape)
                                                                     (declarations display-shape)
                                                                     tone-shader
                                                                     upscale-shader)))))
                                  (kernel (compute-kernel gpu module "upscale" "resolve"))
                                  (uniform (uniform-buffer gpu
                                                           "upscale/jitter"
                                                           (make-array (stride display-shape)
                                                                       (i32->u8 0))))
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
                                                     (list (StorageBinding) (TextureBinding))))
                                  (inputs
                                   (list (BufferEntry 0 camera 0 0) (BufferEntry 1 uniform 0 0)
                                         (TextureEntry 2 (● post targets light-view))
                                         (TextureEntry 3 (● depth view))
                                         (TextureEntry 4 (● (list-ref planes 4) view))
                                         (TextureEntry 5 (● (list-ref planes 1) view))
                                         (TextureEntry 6 (● (list-ref planes 5) view))
                                         (TextureEntry 11 (● front view))
                                         (TextureEntry 12 (● toned view)))))
                             ((● gpu destroy) (ModuleObject module))
                             (new Upscaler
                               (width w)
                               (height h) (age 0)
                               (kernel kernel)
                               (uniform uniform)
                               (colors colors)
                               (ids ids)
                               (toned toned)
                               (groups (map (lambda (i)
                                              (let ((old (- 1 i)))
                                                (kernel-group gpu kernel 0 "upscale"
                                                              (append inputs
                                                                      (list (TextureEntry 7
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
                               (fxaa-group (screen-group gpu "upscale/fxaa" (● post fxaa)
                                                         (list (TextureEntry 1 (● toned view))
                                                               (SamplerEntry 2
                                                                             (● post sampler))))))))
    (define (resolve-upscaled (gpu Gpu) (encoder GpuCommandEncoder) (canvas GpuTextureView)
                              (u Upscaler) (post Post) (frame I32) (valid Bool) (moving Bool))
      (→ Upscaler)
      (let* ((i (i32->i64 (i32-and frame 1)))
             (age (if (and valid (not moving)) (min 16 (+ (● u age) 1)) 1))
             (pass ((● gpu begin-compute-pass) encoder)))
        ((● gpu write-buffer)
         (● u uniform)
         0
         (pod-bytes display-shape
                    (new DisplayFrame
                      (jitter (sample-phase frame))
                      (previous-jitter (sample-phase (- frame 1)))
                      (still-weight (/ (i32->f32 (- age 1)) (i32->f32 age)))
                      (valid (if valid 1 0))
                      (curve (curve-number (● post curve))))))
        ((● gpu set-compute-pipeline) pass (● u kernel))
        ((● gpu set-compute-bind-group) pass 0 (list-ref (● u groups) i))
        ((● gpu dispatch-workgroups)
         pass
         (quotient (+ (● u width) 7) 8)
         (quotient (+ (● u height) 7) 8)
         1)
        ((● gpu end-compute-pass) pass)
        (screen-pass gpu encoder canvas (● post fxaa) (● u fxaa-group))
        (Upscaler-age-set u age)))
    (define (release-upscaler (gpu Gpu) (u Upscaler)) (→ Unit)
      (for-each (lambda (g) ((● gpu destroy) (BindGroupObject g)))
                (Cons (● u fxaa-group) (● u groups)))
      (for-each (lambda (p) (release-plane gpu p))
                (append (● u colors) (Cons (● u toned) (● u ids))))
      ((● gpu destroy) (BufferObject (● u uniform)))
      ((● gpu destroy) (ComputePipelineObject (● u kernel))))))
