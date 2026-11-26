;; Read the center pixel's history and noisy light. A sun lights the white
;; wall at 45 degrees. The black box can cover the sun while the camera
;; still sees the wall.
(define-library (gpu-test restir)
  (export check-restir)
  (import
   (snail core base)
   (only (snail shell math) expt)
   (snail shell gpu)
   (only (snail shell app) Box Upright Vec3 item Item-glow-set)
   (snail shell game scenery)
   (snail shell graphics pod)
   (snail shell graphics kernel)
   (snail shell graphics raster)
   (snail shell graphics gltf)
   (snail shell graphics environment)
   (only (snail shell graphics upscale) sample-phase)
   (only (snail shell graphics svgf) svgf-moments)
   (snail shell graphics restir)
   (snail shell graphics trace render)
   (only (snail shell graphics passes) Filmic)
   (only (snail shell graphics still) read-rgba read-plane trace-reference)
   (only (snail shell little-endian) u32)
   (snail shell graphics trace scene)
   (snail shell graphics trace lights)
   (only (gpu-test shaders) inspect-reservoir))
  (begin

    (define (wall (gpu Gpu) (blocked Bool)) (→ Scene) (test-wall gpu blocked (Nil) 0))
    (define (test-wall (gpu Gpu) (blocked Bool) (lights (List Punctual)) (moving I64)) (→ Scene)
      (let ((empty
             (new Gltf (buffers (Nil)) (size 0) (images (Nil)) (materials (Nil)) (placed (Nil))))
            ;; Keep the measured pixel inside one triangle across subpixel offsets.
            (box (item (Box) (new Vec3 (x -4.8) (y -6.0) (z 0.0))
                       (new Vec3 (x 16.0) (y 12.0) (z 1.0)) 0.0 16777215))
            (blocker (item (Box) (new Vec3 (x 1.3) (y -1.0) (z 1.8))
                           (new Vec3 (x 0.8) (y 2.0) (z 0.6)) 0.0 0)))
        (upload-lit-scene gpu (lambda (_) (Nil))
                          (with-shapes empty (if blocked (list box blocker) (list box)))
                          1
                          lights
                          moving)))

    (define (sky (gpu Gpu) (strength F32))
      (→ Environment)
      (sky-environment gpu (test-sky strength) 128))
    (define (test-sky (strength F32)) (→ Sky)
      (let ((black (new Vec4f (x 0.0) (y 0.0) (z 0.0) (w 0.0))))
        (new Sky (zenith black) (horizon black) (ground black)
             (sun (new Vec4f (x 0.7071068) (y 0.0) (z 0.7071068) (w 0.995)))
             (sun-light
              (new Vec4f (x strength) (y strength) (z strength) (w 0.0))))))

    (define (looking (eye F32) (z F32)) (→ Camera3D)
      (camera-3d (new Vec3f (x 0.0) (y 0.0) (z eye))
                 (new Vec3f (x 0.0) (y 0.0) (z z)) (Pinhole 1.0) 1.0 0.0))

    (define (inspect (gpu Gpu) (kernel GpuComputePipeline) (tracer Tracer)
                     (result GpuBuffer) (readback GpuBuffer)) (→ Bytes)
                     (let* ((encoder ((● gpu create-command-encoder)))
                            (pass ((● gpu begin-compute-pass) encoder))
                            (entries (list (BufferEntry 0 (● tracer targets history) 0 0)
                                           (BufferEntry 1 result 0 0)
                                           (TextureEntry 2 (● tracer targets noisy view))
                                           (TextureEntry 3 (● tracer post targets light-view))
                                           (BufferEntry 4 (● tracer kit counts)
                                                        (i64->i32 (* slot most-bounces))
                                                        4)
                                           (TextureEntry 5 (svgf-moments (● tracer svgf)))
                                           (TextureEntry 6
                                                         (● (list-ref (● tracer targets planes) 4)
                                                            view))))
                            (group (kernel-group gpu kernel 0 "test/reservoir" entries)))
                       ((● gpu set-compute-pipeline) pass kernel)
                       ((● gpu set-compute-bind-group) pass 0 group)
                       ((● gpu dispatch-workgroups) pass 1 1 1)
                       ((● gpu end-compute-pass) pass)
                       ((● gpu copy-buffer-to-buffer) encoder result 0 readback 0 80)
                       ((● gpu submit) (list ((● gpu finish) encoder)))
                       ((● gpu destroy) (BindGroupObject group))
                       ((● gpu read-buffer) readback 0 80)))

    (define (expect (bytes Bytes) (offset I64) (words Vec4i)) (→ Unit)
      (let ((expected (pod-bytes (shape) words)))
        (unless (every? (lambda (i) (= (array-ref bytes (+ offset i)) (array-ref expected i)))
                        (iota 16))
          (panic (string-append "reservoir readback at " (show offset) " expected "
                                (repr (list (● words x) (● words y) (● words z) (● words w)))
                                " got " (repr (map (lambda (i) (u32 bytes (+ offset (* 4 i))))
                                                   (iota 4))))))))

    (define (output-settings (width I32) (height I32)) (→ TraceSettings)
      (new TraceSettings (display-width width) (display-height height)))

    ;; A stationary surface moves by previous minus current jitter in the G-buffer.
    ;; SVGF keeps accumulating that surface even though its sample position moves.
    (define (expect-jitter-motion (data Bytes) (frame I32)) (→ Unit)
      (let ((now (sample-phase (- frame 1))) (prev (sample-phase (- frame 2))))
        (unless (and (> (u32 data 32) 1)
                     (< (abs (- (* 9.0 (float-at data 40)) (- (● prev x) (● now x)))) 0.002)
                     (< (abs (- (* 9.0 (float-at data 44)) (- (● prev y) (● now y)))) 0.002))
          (panic "subpixel motion or SVGF reprojection failed on the 9×9 render grid"))))

    ;; The 9×9 render grid survives a display resize and back.
    ;; Camera jitter at the larger display size still belongs to a stationary view.
    (define (check-frame-grid (gpu Gpu) (t Tracer) (canvas Plane)
                              (kernel GpuComputePipeline) (result GpuBuffer) (back GpuBuffer))
      (→ Tracer)
      (let* ((front (looking 4.0 0.0))
             (large (make-plane gpu "test/display" 17 15 (Rgba8Unorm) (list (RenderAttachment))))
             (draw (lambda ((t Tracer) (plane Plane) (w I32) (h I32)) (→ Tracer)
                     (draw-traced gpu
                                  t
                                  (● plane view)
                                  front
                                  0.12
                                  1.0
                                  1
                                  #f
                                  (output-settings w h))))
             (first (draw t canvas 9 9)) (two (draw first canvas 9 9))
             (native (inspect gpu kernel two result back))
             (scaled (draw two large 17 15)) (still (draw scaled large 17 15))
             (scaled-rays (inspect gpu kernel still result back))
             (back-at-native (draw still canvas 9 9)))
        (expect native 16 (new Vec4i (x 81) (y 81) (z 1) (w 24)))
        (expect-jitter-motion native (● two frame))
        (expect-jitter-motion scaled-rays (● still frame))
        (unless (and (= (u32 scaled-rays 16) 81) (> (u32 scaled-rays 28) 8)
                     (= (tracer-frames back-at-native) 4)
                     (match (● still upscale) ((Some u) (= (● u age) 2)) (_ #f))
                     (match (● back-at-native upscale)
                       ((Some u) (and (= (● u width) 9) (= (● u age) 1))) (_ #f)))
          (panic "a display resize disrupted render-grid history"))
        (release-plane gpu large)
        back-at-native))

    ;; A wall travelling towards a stationary eye changes depth by far more
    ;; than the rejection threshold. Its previous pose still covers this pixel.
    (define (moving-depth (gpu Gpu) (t Tracer) (scene Scene) (day Environment) (canvas Plane)
                          (kernel GpuComputePipeline) (result GpuBuffer) (back GpuBuffer))
      (→ Tracer)
      (let* ((source (wall gpu #f)) (stage (moving-scene gpu source (list (● source vertex-count))))
             (draw (lambda (frame)
                     (draw-traced gpu
                                  frame
                                  (● canvas view)
                                  (looking 4.0 0.0)
                                  0.12
                                  1.0
                                  1
                                  #t (output-settings 9 9))))
             (initial (retrace gpu t (● stage scene) day)) (first (draw initial))
             (pose (new ObjectPose (place (new Vec4f (x 0.0) (y 0.0) (z 1.0) (w 1.0)))
                        (size (new Vec4f (x 1.0) (y 1.0) (z 1.0) (w 0.0))))))
        (pose-scene! gpu stage (list pose)) (refit-tracer! gpu first)
        (let* ((next (draw first)) (bytes (inspect gpu kernel next result back))
               (clean (retrace gpu next scene day)))
          (unless (and (= (u32 bytes 32) 2) (= (u32 bytes 36) 24))
            (panic "the moving wall lost its reprojected history"))
          (release-moving-scene gpu stage) clean)))
    (define (lamp (x F32) (z F32) (power F32) (reach F32)) (→ Punctual)
      (point-light (new Vec3f (x x) (y 0.0) (z z)) (new Vec3f (x power) (y power) (z power)) reach))
    (define (local-light-checks (gpu Gpu) (t Tracer) (dark Environment)
                                (draw (Fn Tracer Camera3D I32 I32 I32 → Tracer))) (→ Tracer)
                                (let* ((front (camera-3d (new Vec3f (x 0.0) (y 0.0) (z 4.0))
                                                         (new Vec3f (x 0.0) (y 0.0) (z 0.0))
                                                         (Pinhole 0.02) 1.0 0.0))
                                       (far (lamp 2.6 3.1 12.0 24.0))
                                       (lit (test-wall gpu #f (list far) 0))
                                       (occluded (test-wall gpu #t (list far) 0))
                                       (moving (test-wall gpu #t (Nil) 1))
                                       (first (draw (retrace gpu t lit dark) front 8 0 1))
                                       (blocked
                                        (draw (retrace gpu first occluded dark) front 8 0 0)))
                                  ;; The same blocker now lies beyond the moving source. A short-range
                                  ;; replacement and a spotlight pointing away must leave the wall dark.
                                  (update-moving-lights! gpu
                                                         (● moving lights)
                                                         (list (lamp 0.55 1.05 0.57 7.0)))
                                  (let ((near (draw (retrace gpu blocked moving dark) front 8 0 1)))
                                    (update-moving-lights! gpu (● moving lights)
                                                           (list (spot-light (new Vec3f
                                                                               (x 0.55)
                                                                               (y 0.0)
                                                                               (z 1.05))
                                                                             (new Vec3f
                                                                               (x 1.0)
                                                                               (y 1.0)
                                                                               (z 1.0))
                                                                             7.0
                                                                             (new Vec3f
                                                                               (x 0.0)
                                                                               (y 0.0)
                                                                               (z 1.0))
                                                                             0.85)))
                                    (let ((away (draw near front 24 0 0)))
                                      (update-moving-lights! gpu
                                                             (● moving lights)
                                                             (list (lamp 0.55 1.05 0.57 0.2)))
                                      (let ((short (draw away front 56 0 0)))
                                        (release-scene gpu lit)
                                        (release-scene gpu occluded)
                                        short)))))
    ;; A passing lamp changes illumination while the receiver's motion stays
    ;; zero. Measure the final display pixel, including both temporal filters.
    (define (headlamp-trail (gpu Gpu) (t Tracer) (night Environment) (plane Plane)
                            (draw (Fn Tracer → Tracer)) (center I64)) (→ Unit)
                            (let* ((s (test-wall gpu #f (Nil) 1))
                                   (read-level (lambda ()
                                                 (u8->i32
                                                  (array-ref (read-rgba gpu plane 17 15) center)))))
                              (update-moving-lights! gpu
                                                     (● s lights)
                                                     (list (lamp 0.5 1.05 6.0 0.8)))
                              (let* ((lit (fold-left (lambda (frame _) (draw frame))
                                                     (retrace gpu t s night)
                                                     (iota 8)))
                                     (on (read-level)))
                                (update-moving-lights! gpu (● s lights) (Nil))
                                (let* ((one (draw lit))
                                       (two (draw one))
                                       (after-two (read-level)))
                                  (draw (draw two))
                                  (let ((after-four (read-level)))
                                    (unless (and (> on 40)
                                                 (< (* after-two 3) on)
                                                 (< (* after-four 7) on))
                                      (panic
                                       (string-append "stationary surface kept a passing light: "
                                                      (show on)
                                                      " / "
                                                      (show after-two) " / " (show after-four)))))))
                              (release-scene gpu s)))
    ;; A clear sky has the same radiance along every path. Gathering two
    ;; or four paths must produce the same energy as one, before SVGF.
    (define (sample-budget (gpu Gpu) (t Tracer) (canvas Plane) (read (Fn Tracer → Bytes)))
      (→ Tracer)
      (let* ((color (new Vec4f (x 0.45) (y 0.45) (z 0.45) (w 1.0)))
             (sky (sky-environment gpu (new Sky (zenith color) (horizon color) (ground color)
                                            (sun (new Vec4f (x 0.0) (y 1.0) (z 0.0) (w 0.999)))
                                            (sun-light (new Vec4f (x 0.0) (y 0.0) (z 0.0) (w 0.0))))
                                   16))
             (air (retrace gpu t (● t world scene) sky))
             (draw (lambda (f n) (draw-traced-samples gpu f (● canvas view) (looking 4.0 8.0)
                                                      0.12 1.0 1 #f (output-settings 17 15) n))))
        (let* ((one (draw air 1)) (base (float-at (read one) 48))
               (two (draw one 2)) (paired (float-at (read two) 48))
               (four (draw two 4)) (many (float-at (read four) 48)))
          (unless (and (> base 0.1) (< (abs (- base paired)) 0.003) (< (abs (- base many)) 0.003))
            (panic (string-append "unexpected uniform sky at 1, 2 and 4 spp: "
                                  (show base)
                                  ", "
                                  (show paired)
                                  ", "
                                  (show many))))
          (let ((restored (retrace gpu four (● t world scene) (● t world environment))))
            (release-environment gpu sky)
            restored))))

    ;; Exercise successive Halton phases, short driving histories, an odd-sized
    ;; display readback and a scene cut from daylight straight to darkness.
    (define (check-reconstruction (gpu Gpu) (t Tracer) (scene Scene) (night Environment)
                                  (kernel GpuComputePipeline) (result GpuBuffer) (back GpuBuffer))
      (→ Unit)
      (let* ((plane (make-plane gpu
                                "test/upscale"
                                17
                                15
                                (Rgba8Unorm)
                                (list (RenderAttachment) (TextureCopySrc))))
             (draw (lambda ((frame Tracer)) (→ Tracer)
                     (draw-traced gpu
                                  frame
                                  (● plane view)
                                  (looking 4.0 0.0)
                                  0.12
                                  1.0
                                  1
                                  #t
                                  (output-settings 17 15))))
             (center (* 4 (+ (* 7 17) 8)))
             (fast
              (Tracer-guiding-set t (new LightGuiding (exploration-floor 0.0) (recovery-frames 1))))
             (rapid (draw (draw (discard-trace-history fast))))
             (fresh (inspect gpu kernel rapid result back))
             (once (draw (discard-trace-history (Tracer-guiding-set rapid (● t guiding)))))
             (observed (inspect gpu kernel once result back))
             (rate (light-guiding-rates (● t guiding)))
             (keep (- 1.0 (● rate visibility-gain)))
             (warm (fold-left (lambda (frame _) (draw frame)) once (iota 12)))
             (check (inspect gpu kernel warm result back))
             (bright (read-rgba gpu plane 17 15)))
        (unless (and (= (u32 fresh 0) 8)
                     (< (abs (- (float-at observed 76) (- 1.0 (* 0.5 keep)))) 1e-5)
                     (= (u32 check 8) 1) (>= (u32 check 32) 1) (<= (u32 check 32) 4)
                     (> (u32 check 36) 4) (<= (u32 check 36) 24)
                     (> (u8->i32 (array-ref bright center)) 20))
          (panic "driving sample energy, short history, or display reconstruction failed"))
        (let* ((dim (draw (retrace gpu warm scene night))) (dark (read-rgba gpu plane 17 15)))
          (unless (and (= (u8->i32 (array-ref dark center)) 0)
                       (= (u8->i32 (array-ref dark (+ center 3))) 255))
            (panic "reconstructed display carried radiance across a scene cut"))
          (headlamp-trail gpu
                          (sample-budget gpu
                                         dim
                                         plane
                                         (lambda (frame) (inspect gpu kernel frame result back)))
                          night plane draw center))
        (release-plane gpu plane)))
    ;; The receiver faces a unit-radiance rectangle one metre away. Relative
    ;; to the center of the wall it spans x=[0.2,2.2], y=[-1.5,1.5]. Integrating
    ;; its projected solid angle times the wall BRDF gives 0.3000 radiance.
    (define (rectangle-scene (gpu Gpu) (blocker-z F32)) (→ Scene)
      (let* ((empty
              (new Gltf (buffers (Nil)) (size 0) (images (Nil)) (materials (Nil)) (placed (Nil))))
             (wall (item (Upright) (new Vec3 (x 0.0) (y -2.0) (z 0.5))
                         (new Vec3 (x 4.0) (y 4.0) (z 1.0)) 0.0 16777215))
             (sign (Item-glow-set (item (Upright) (new Vec3 (x 1.2) (y -1.5) (z 1.5))
                                        (new Vec3 (x 2.0) (y 3.0) (z 1.0)) 0.0 16777215) 1.0))
             (blocker (item (Upright) (new Vec3 (x 1.14) (y -2.0) (z blocker-z))
                            (new Vec3 (x 2.16) (y 4.0) (z 1.0)) 0.0 0)))
        (upload-scene gpu (lambda (_) (Nil)) (with-shapes empty (list wall blocker sign)) 1)))

    ;; The sign covers the right half of the center pixel. Opposite Halton
    ;; phases hit either black sky or white emission at the same display pixel.
    (define (check-edge-coverage (gpu Gpu) (t Tracer) (night Environment) (canvas Plane)) (→ Tracer)
      (let* ((empty
              (new Gltf (buffers (Nil)) (size 0) (images (Nil)) (materials (Nil)) (placed (Nil))))
             (sign (Item-glow-set (item (Upright) (new Vec3 (x 2.0) (y -3.0) (z 0.5))
                                        (new Vec3 (x 4.0) (y 6.0) (z 1.0)) 0.0 16777215) 1.0))
             (scene (upload-scene gpu (lambda (_) (Nil)) (with-shapes empty (list sign)) 1))
             (draw (lambda ((f Tracer) (exposure F32)) (→ Tracer)
                     (draw-traced gpu f (● canvas view) (looking 4.0 0.0) 0.12 exposure 1 #f
                                  (output-settings 9 9))))
             (warm (fold-left (lambda (f _) (draw f 1.0)) (retrace gpu t scene night) (iota 16)))
             (image (read-rgba gpu canvas 9 9))
             (red (lambda (x) (u8->i32 (array-ref image (* 4 (+ 36 x))))))
             (dim (draw warm 0.0)) (black (read-rgba gpu canvas 9 9)))
        (unless (and (< (red 2) 5) (> (red 6) 100) (> (* 2 (red 4)) (red 6))
                     (< (* 10 (red 4)) (* 9 (red 6))) (= (u8->i32 (array-ref black 160)) 0))
          (panic "display coverage of a stationary edge or its exposure reset failed"))
        (let ((clean (retrace gpu dim (● t world scene) (● t world environment))))
          (release-scene gpu scene) clean)))

    (define (float-at (data Bytes) (offset I64)) (→ F32)
      (bits->f32 (i64->i32 (u32 data offset))))

    (record LightingStats
      ((sky-fraction F32)
       (mean F32)
       (variance F32))
      (deriving Repr))

    ;; The calibration light wins each probe. Independent opportunities
    ;; leave one tenth of its initial visibility error after twelve frames.
    (define (check-guiding-rates) (→ Unit)
      (let* ((s (new LightGuiding (exploration-floor 0.125) (recovery-frames 12)))
             (full (light-guiding-rates s))
             (slow (light-guiding-rates
                    (new LightGuiding (exploration-floor 0.125) (recovery-frames 48))))
             (residual (lambda ((r GuidingRates) (n F64)) (→ F64)
                         (expt (- 1.0 (f32->f64 (* (● r exploration) (● r visibility-gain)))) n))))
        (unless (and (< (abs (- (residual full 12.0) 0.1)) 1e-6)
                     (< (abs (- (residual slow 48.0) 0.1)) 1e-6)
                     (> (● full exploration) 0.125) (= (● slow exploration) 0.125))
          (panic "incorrect exploration or recovery for a recovery target"))))

    (define (check-halton) (→ Unit)
      (let ((phase (lambda ((i I32) (x F32) (y F32)) (→ Bool)
                     (let ((j (sample-phase i)))
                       (and (< (abs (- (● j x) x)) 1e-6) (< (abs (- (● j y) y)) 1e-6))))))
        (unless (and (phase 0 0.0 (/ -1.0 6.0)) (phase 1 -0.25 (/ 1.0 6.0))
                     (phase 2 0.25 (/ -7.0 18.0)) (phase 8 0.0625 (/ -25.0 54.0)))
          (panic "incorrect centered Halton(2,3) offsets"))))

    ;; Observe which light got the wall's 81 shadow rays and its raw red radiance.
    (define (light-window (t Tracer) (frames I64) (draw (Fn Tracer → Tracer))
                          (read (Fn Tracer → Bytes)))
      (→ (Pair Tracer LightingStats))
      (let loop ((f t) (i 0) (sky 0.0) (red 0.0) (square 0.0))
        (if (= i frames)
            (let* ((n (i64->f32 frames)) (mean (/ red n)))
              (new Pair (first f)
                   (second (new LightingStats (sky-fraction (/ sky (* 81.0 n))) (mean mean)
                                (variance (- (/ square n) (* mean mean)))))))
            (let* ((next (draw f)) (bytes (read next)))
              (unless (= (u32 bytes 68) 81) (panic "visibility changed the shadow ray budget"))
              (loop next (+ i 1) (+ sky (i64->f32 (u32 bytes 64)))
                    (+ red (float-at bytes 48)) (+ square (float-at bytes 52)))))))

    (define (mean-red (rgba Bytes)) (→ F32)
      (let ((n (quotient (array-length rgba) 16)))
        (/ (fold-left (lambda (sum i) (+ sum (float-at rgba (* 16 i)))) 0.0 (iota n))
           (i64->f32 n))))

    (define (expect-indoor-light (cold LightingStats) (closed LightingStats)
                                 (opening LightingStats) (open LightingStats) (reference F32))
      (→ Unit)
      (unless (and (> (● cold sky-fraction) 0.55)
                   (> (● closed sky-fraction) 0.03)
                   (< (● closed sky-fraction) (* 0.55 (● cold sky-fraction)))
                   (< (● closed variance) (* 0.55 (● cold variance)))
                   (< (abs (- (● cold mean) (● closed mean))) (* 0.15 (● closed mean)))
                   (> (● opening sky-fraction) (● closed sky-fraction))
                   (> (● open sky-fraction) 0.55)
                   (< (abs (- (● open mean) reference)) (* 0.12 reference)))
        (panic (string-append "indoor lighting " (repr (list cold closed opening open))
                              " against reference " (show reference)))))

    ;; A screen blocks the sun, leaving the weaker indoor lamp visible. Slide
    ;; it away while keeping the same receiver, both lights and their history.
    (define (indoor-lighting (gpu Gpu) (t Tracer) (day Environment) (canvas Plane)
                             (read (Fn Tracer → Bytes)))
      (→ Tracer)
      (let* ((source (test-wall gpu #t (list (lamp 0.0 1.5 0.22 12.0)) 0))
             (screen (moving-scene gpu source (list (quotient (● source vertex-count) 2))))
             (room (retrace gpu t (● screen scene) day))
             (camera (camera-3d (new Vec3f (x 0.0) (y 0.0) (z 4.0))
                                (new Vec3f (x 0.0) (y 0.0) (z 0.5)) (Pinhole 0.02) 1.0 0.0))
             (reference-frame (lambda (f) (trace-reference gpu f camera 0.002 1 300 1)))
             (before (reference-frame room))
             (draw (lambda (f)
                     (draw-traced gpu
                                  f
                                  (● canvas view)
                                  camera
                                  0.002
                                  1.0
                                  1
                                  #t
                                  (output-settings 9 9))))
             (control (new LightGuiding (exploration-floor 1.0) (recovery-frames 48)))
             (cold (light-window (Tracer-guiding-set room control) 12 draw read))
             (guided (discard-trace-history (Tracer-guiding-set (● cold first) (● room guiding))))
             (warm (fold-left (lambda (f _) (draw f)) guided (iota 20)))
             (closed (light-window warm 12 draw read))
             (saved (read (● closed first)))
             (after (reference-frame (● closed first)))
             (history (read (● closed first)))
             (pose (new ObjectPose (place (new Vec4f (x 6.0) (y 0.0) (z 0.0) (w 1.0)))
                        (size (new Vec4f (x 1.0) (y 1.0) (z 1.0) (w 0.0))))))
        (unless (and (every? (lambda (i) (= (array-ref before i) (array-ref after i)))
                             (iota (array-length before)))
                     (every? (lambda (i) (= (u32 saved i) (u32 history i))) (list 64 72 76)))
          (panic "the independent sample read or overwrote visibility history"))
        (pose-scene! gpu screen (list pose))
        (refit-tracer! gpu (● closed first))
        (let* ((opening (light-window (● closed first) 4 draw read))
               (open (light-window (● opening first) 12 draw read))
               (raw (trace-reference gpu (● open first) camera 0.002 1 512 32))
               (clean (retrace gpu (● open first) (● t world scene) (● t world environment))))
          (expect-indoor-light (● cold second) (● closed second) (● opening second) (● open second)
                               (mean-red raw))
          (release-moving-scene gpu screen)
          clean)))

    (define (check-emitter-table (gpu Gpu) (table EmitterTable)) (→ Unit)
      (let ((ids (read-plane gpu (● table triangles) 2 1 4))
            (weights (read-plane gpu (● table distribution) 3 1 16)))
        (unless (and (= (● table count) 2) (= (u32 ids 0) 4) (= (u32 ids 4) 5)
                     (< (abs (- (float-at weights 12) 3.0)) 1e-5)
                     (< (abs (- (float-at weights 28) 6.0)) 1e-5)
                     (= (float-at weights 28) (float-at weights 44)))
          (panic "incorrect two-triangle area distribution"))))

    ;; Keep the receiving wall fixed while its light crosses to the other side.
    ;; Temporal donors still name the same sign point in the new vertex buffer.
    (define (moving-sign (gpu Gpu) (t Tracer) (camera Camera3D) (canvas Plane)
                         (kernel GpuComputePipeline) (result GpuBuffer) (back GpuBuffer)) (→ Tracer)
                         (let* ((stage (moving-scene gpu (rectangle-scene gpu 1.8) (list 4)))
                                (dark (● t world environment))
                                (draw (lambda (f)
                                        (draw-traced gpu
                                                     f
                                                     (● canvas view)
                                                     camera
                                                     0.002
                                                     1.0
                                                     1
                                                     #t
                                                     (output-settings 9 9))))
                                (first (draw (retrace gpu t (● stage scene) dark)))
                                (pose (new ObjectPose
                                        (place (new Vec4f (x -2.4) (y 0.0) (z 0.0) (w 1.0)))
                                        (size (new Vec4f (x 1.0) (y 1.0) (z 1.0) (w 0.0))))))
                           (pose-scene! gpu stage (list pose))
                           (refit-tracer! gpu first)
                           (let* ((next (draw first)) (bytes (inspect gpu kernel next result back))
                                  (restored (retrace gpu next (● t world scene) dark)))
                             (unless (and (> (u32 bytes 0) 8)
                                          (> (u32 bytes 56) 0)
                                          (< (float-at bytes 60) 0.0)
                                          (> (float-at bytes 48) 0.15))
                               (panic "reused sign did not follow its mesh"))
                             (release-moving-scene gpu stage)
                             restored)))

    (define (rectangle-checks (gpu Gpu) (t Tracer) (dark Environment) (canvas Plane)
                              (kernel GpuComputePipeline) (result GpuBuffer) (back GpuBuffer))
      (→ Tracer)
      (let* ((lit (rectangle-scene gpu 1.8)) (blocked (rectangle-scene gpu 1.0))
             (reference (Scene-emitters-set lit (● t world scene emitters)))
             (camera
              (camera-3d (new Vec3f (x 0.0) (y 0.0) (z 4.0)) (new Vec3f (x 0.0) (y 0.0) (z 0.5))
                         (Pinhole 0.02) 1.0 0.0))
             (measure
              (lambda ((frame Tracer) (scene Scene) (n I64) (mesh Bool)) (→ (Pair Tracer Vec2f))
                (let loop ((f (retrace gpu frame scene dark)) (i 0) (sum 0.0) (square 0.0))
                  (if (= i n) (new Pair (first f) (second (new Vec2f
                                                            (x (/ sum (i64->f32 n)))
                                                            (y (/ square (i64->f32 n))))))
                      (let* ((next (draw-traced gpu
                                                f
                                                (● canvas view)
                                                camera
                                                0.002
                                                1.0
                                                1
                                                #f
                                                (output-settings 9 9)))
                             (data (inspect gpu kernel next result back)))
                        (unless (and (= (> (u32 data 56) 0) mesh)
                                     (= (u32 data 56) (u32 data 72))
                                     (or (not mesh)
                                         (and (> (float-at data 60) 0.0)
                                              (= (> (float-at data 76) 0.5)
                                                 (> (float-at data 48) 0.0)))))
                          (panic "wrong selected mesh endpoint"))
                        (loop next
                              (+ i 1)
                              (+ sum (float-at data 48))
                              (+ square (float-at data 52))))))))
             (sampled (measure t lit 12 #t))
             (raw (trace-reference gpu (● sampled first) camera 0.002 1 100 12))
             (mean (mean-red raw))
             (bsdf (measure (● sampled first) reference 24 #f))
             (shadow (measure (● bsdf first) blocked 2 #t)))
        (check-emitter-table gpu (● lit emitters))
        (unless (and (= (● shadow second x) 0.0)
                     (= (array-length raw) (* 16 81)) (< (abs (- mean 0.3000)) 0.035)
                     (< (abs (- (● sampled second x) 0.3000)) 0.035)
                     (< (abs (- (● bsdf second x) 0.3000)) 0.05)
                     (< (● sampled second y) (* 0.75 (● bsdf second y))))
          (panic (string-append "rectangle direct, BSDF-only, blocked: " (show (● sampled second x))
                                " / " (show (● bsdf second x)) " / " (show (● shadow second x)))))
        (let ((next (retrace gpu (● shadow first) (● t world scene) dark)))
          (release-scene gpu blocked)
          (release-scene gpu lit)
          (moving-sign gpu next camera canvas kernel result back))))

    (define (check-restir (gpu Gpu)) (→ String)
      (check-halton)
      (check-guiding-rates)
      (let* ((scene (wall gpu #f)) (blocked (wall gpu #t)) (day (sky gpu 1.0)) (night (sky gpu 0.0))
             (canvas (make-plane gpu
                                 "test/restir"
                                 9
                                 9
                                 (Rgba8Unorm)
                                 (list (RenderAttachment) (TextureCopySrc))))
             (kernel (compute-kernel gpu ((● gpu create-shader-module)
                                          (new ShaderModuleDescriptor (label "test/reservoir")
                                               (code (string-append reservoir-shader
                                                                    inspect-reservoir))))
                                     "test"
                                     "inspect"))
             (result (storage-buffer gpu "test/reservoir" 80 (list (CopySrc))))
             (back ((● gpu create-buffer) (new BufferDescriptor (label "test/readback") (size 80)
                                               (usage (list (CopyDst) (MapRead))))))
             (draw
              (lambda ((t Tracer) (camera Camera3D) (count I32) (selected I32) (lit I32)) (→ Tracer)
                (let ((next (draw-traced gpu t (● canvas view) camera 0.12 1.0 1
                                         #f (output-settings 9 9))))
                  (expect (inspect gpu kernel next result back) 0
                          (new Vec4i (x count) (y selected) (z lit) (w 1)))
                  next)))
             (front (looking 4.0 0.0))
             (initial (make-tracer gpu scene day (Rgba8Unorm) 9 9 1 (Filmic)))
             (first (draw initial front 8 1 1))
             (reused (fold-left (lambda (t n) (draw t (looking 3.5 0.0) n 1 1))
                                first (list 24 56 120 168 168)))
             (sky-only (draw reused (looking 4.0 8.0) 0 0 0))
             (uncovered (draw sky-only front 8 1 1))
             (shadow (draw (retrace gpu uncovered blocked day) front 8 1 0))
             (dark (draw (retrace gpu shadow scene night) front 8 0 0))
             (checks
              (check-frame-grid gpu (moving-depth gpu dark scene day canvas kernel result back)
                                canvas kernel result back))
             (local (local-light-checks gpu (resize-tracer gpu checks 9 9) night draw))
             (mutable (make-sky-light gpu (test-sky 0.0) 128))
             (sign (rectangle-checks gpu local night canvas kernel result back))
             (room
              (indoor-lighting gpu sign day canvas (lambda (t) (inspect gpu kernel t result back))))
             (edge (check-edge-coverage gpu room night canvas))
             (old-sky (draw (retrace gpu edge scene (● mutable environment)) front 8 0 0)))
        (update-sky! gpu mutable (test-sky 1.0))
        ;; A changed sky uses fresh proposals despite keeping its textures and camera.
        (check-reconstruction gpu (draw old-sky front 8 1 1) scene night kernel result back)
        (release-scene gpu (● local world scene))
        (release-sky-light gpu mutable)
        ((● gpu destroy) (BufferObject result))
        ((● gpu destroy) (BufferObject back))
        ((● gpu destroy) (ComputePipelineObject kernel))
        (release-plane gpu canvas)
        (release-environment gpu day)
        (release-environment gpu night)
        (release-scene gpu blocked)
        (release-scene gpu scene)
        "weighted draws, capped reuse, visible and blocked light, disocclusion and full coverage"))))
