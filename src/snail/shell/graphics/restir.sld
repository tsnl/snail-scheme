;; Directional reservoirs for resampled importance sampling. The Pod records
;; are the shader's types and the layout a caller can read back from the GPU.
(define-library (snail shell graphics restir)
  (export
   LightSample
   Reservoir
   SurfaceReservoir
   reservoir-shader
   reservoir-buffer)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics kernel)
   (only (snail shell graphics shaders) reservoir-operations))
  (begin

    (record LightSample
      ((direction Vec3f)
       (target-value F32))
      (deriving Pod))

    (record Reservoir
      ((selected LightSample)
       (weight-sum F32)
       (count I32))
      (deriving Pod))

    ;; Octahedral normal, primitive ID and previous-camera clip depth occupy
    ;; 16 bytes. Only spatial reuse may borrow a neighbouring triangle.
    (record SurfaceReservoir
      ((reservoir Reservoir)
       (normal Vec2f)
       (triangle I32)
       (clip-depth F32))
      (deriving Pod))

    (define surface-shape (→ (Shape SurfaceReservoir)) (shape))
    (define reservoir-shader
      (→ String)
      (string-append (declarations surface-shape) reservoir-operations))

    (define (reservoir-buffer (gpu Gpu) (label String) (width I32) (height I32)) (→ GpuBuffer)
      (storage-buffer gpu label (* (stride surface-shape) (* (i32->i64 width) (i32->i64 height)))
                      (list (CopySrc))))))
