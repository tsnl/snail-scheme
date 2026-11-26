;; Light reservoirs for resampled importance sampling. The Pod records
;; are the shader's types and the layout a caller can read back from the GPU.
(define-library (snail shell graphics restir)
  (export
   LightSample
   Reservoir
   LightVisibility
   VisibilityHistory
   LightGuiding
   GuidingRates
   default-light-guiding
   light-guiding-rates
   SurfaceReservoir
   reservoir-shader
   reservoir-buffer)
  (import
   (snail core base)
   (only (snail shell math) expt)
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
       (count I32)
       ;; Zero names the sky. For a mesh sample these are its one-based
       ;; emitter-table slot and two packed 16-bit uniform sample coordinates.
       (emitter I32)
       (coordinates I32))
      (deriving Pod))

    (record LightVisibility
      ((key I32)
       (visibility F32))
      (deriving Pod))

    (record VisibilityHistory
      ((recent LightVisibility)
       (previous LightVisibility))
      (deriving Pod))

    ;; A neighbor can supply a light sample. Only the same reprojected
    ;; surface can supply observations of which lights it could see.
    (record SurfaceReservoir
      ((reservoir Reservoir)
       (normal Vec2f)
       (triangle I32)
       (clip-depth F32)
       (visibility VisibilityHistory))
      (deriving Pod))

    ;; ---- Light selection and recovery ----

    (record LightGuiding
      ((exploration-floor F32)
       (recovery-frames I32)))

    (define (default-light-guiding) (→ LightGuiding)
      (new LightGuiding (exploration-floor 0.125) (recovery-frames 48)))

    (record GuidingRates
      ((exploration F32)
       (visibility-gain F32)
       (visibility-floor F32)
       (history-limit F32))
      (deriving Pod))

    ;; Close 90% of the gap in N opportunities: (1 - rate)^N = 0.1.
    (define (recovery-rate (n F64)) (→ F64) (- 1.0 (expt 0.1 (/ 1.0 n))))

    ;; A pixel's one path a frame observes visibility once. For a light
    ;; that wins each probe, expected progress per path is probe × gain.
    (define (light-guiding-rates (settings LightGuiding)) (→ GuidingRates)
      (let ((floor (● settings exploration-floor)) (frames (● settings recovery-frames)))
        (unless (and (>= floor 0.0) (<= floor 1.0) (> frames 0))
          (panic "light guiding needs an exploration floor in [0,1] and positive frames"))
        (let* ((rate (recovery-rate (i32->f64 frames))) (probe (max (f32->f64 floor) rate)))
          (new GuidingRates
            (exploration (f64->f32 probe))
            (visibility-gain (f64->f32 (/ rate probe)))
            (visibility-floor (f64->f32 (min 0.5 rate)))
            (history-limit (f64->f32 (min 20.0 (/ (- 1.0 rate) rate))))))))

    ;; ---- Shader and storage ----

    (define surface-shape (→ (Shape SurfaceReservoir)) (shape))
    (define reservoir-shader
      (→ String)
      (string-append (declarations surface-shape) reservoir-operations))

    (define (reservoir-buffer (gpu Gpu) (label String) (width I32) (height I32)) (→ GpuBuffer)
      (storage-buffer gpu label (* (stride surface-shape) (* (i32->i64 width) (i32->i64 height)))
                      (list (CopySrc))))))
