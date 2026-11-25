;; Read the center pixel's history and noisy light. A sun lights the white
;; wall at 45 degrees. The black box can cover the sun while the camera
;; still sees the wall.
(define-library (gpu-test restir)
  (export check-restir)
  (import
   (snail core base)
   (snail shell gpu)
   (only (snail shell app) Box Vec3 item)
   (snail shell game scenery)
   (snail shell graphics pod)
   (snail shell graphics kernel)
   (snail shell graphics raster)
   (snail shell graphics gltf)
   (snail shell graphics environment)
   (only (snail shell graphics svgf) svgf-moments)
   (snail shell graphics restir)
   (snail shell graphics trace render)
   (only (snail shell graphics still) read-rgba)
   (only (snail shell little-endian) u32)
   (snail shell graphics trace scene)
   (snail shell graphics trace lights)
   (only (gpu-test shaders) inspect-reservoir))
  (begin

    (define (wall (gpu Gpu) (blocked Bool)) (→ Scene) (test-wall gpu blocked (Nil) 0))
    (define (test-wall (gpu Gpu) (blocked Bool) (lights (List Punctual)) (moving I64)) (→ Scene)
      (let ((empty
             (new Gltf (buffers (Nil)) (size 0) (images (Nil)) (materials (Nil)) (placed (Nil))))
            (box (item (Box) (new Vec3 (x 0.0) (y -3.0) (z 0.0))
                       (new Vec3 (x 6.0) (y 6.0) (z 1.0)) 0.0 16777215))
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
                                           (TextureEntry 5 (svgf-moments (● tracer svgf)))))
                            (group (kernel-group gpu kernel 0 "test/reservoir" entries)))
                       ((● gpu set-compute-pipeline) pass kernel)
                       ((● gpu set-compute-bind-group) pass 0 group)
                       ((● gpu dispatch-workgroups) pass 1 1 1)
                       ((● gpu end-compute-pass) pass)
                       ((● gpu copy-buffer-to-buffer) encoder result 0 readback 0 48)
                       ((● gpu submit) (list ((● gpu finish) encoder)))
                       ((● gpu destroy) (BindGroupObject group))
                       ((● gpu read-buffer) readback 0 48)))

    (define (expect (bytes Bytes) (offset I64) (words Vec4i)) (→ Unit)
      (let ((expected (pod-bytes (shape) words)))
        (unless (every? (lambda (i) (= (array-ref bytes (+ offset i)) (array-ref expected i)))
                        (iota 16))
          (panic (string-append "unexpected reservoir or coverage: "
                                (string-join (map (lambda (byte) (show (u8->i32 byte)))
                                                  (array->list bytes)) " "))))))

    (define (check-checkerboard (gpu Gpu) (t Tracer) (canvas Plane)
                                (kernel GpuComputePipeline) (result GpuBuffer) (back GpuBuffer))
      (→ Tracer)
      (let* ((view (● canvas view))
             (front (looking 4.0 0.0))
             (draw (lambda ((t Tracer) (camera Camera3D) (bounces I64)) (→ Tracer)
                     (draw-traced gpu t view camera 0.12 1.0 bounces)))
             (covered (lambda ((t Tracer) (even I32) (odd I32) (count I32)) (→ Tracer)
                        (expect (inspect gpu kernel t result back) 16
                                (new Vec4i (x even) (y odd) (z 1) (w count)))
                        t))
             (first (covered (draw t front 1) 41 40 8))
             (odd (covered (draw first front 1) 0 40 8))
             (even (covered (draw-moving-traced gpu odd view front 0.12 1.0 1 #f) 41 0 20))
             (moved (covered (draw-moving-traced gpu even view front 0.12 1.0 1 #t) 41 40 48))
             (closer (looking 3.5 0.0))
             (travelled (covered (draw moved closer 1) 41 40 104))
             (wide (covered (draw (resize-tracer gpu travelled 17 9) closer 1) 77 76 8))
             (half (covered (draw wide closer 1) 77 0 20)))
        (covered (draw half closer 2) 77 76 36)))

    ;; A wall travelling towards a stationary eye changes depth by far more
    ;; than the rejection threshold. Its previous pose still covers this pixel.
    (define (moving-depth (gpu Gpu) (t Tracer) (scene Scene) (day Environment) (canvas Plane)
                          (kernel GpuComputePipeline) (result GpuBuffer) (back GpuBuffer))
      (→ Tracer)
      (let* ((source (wall gpu #f)) (stage (moving-scene gpu source (list (● source vertex-count))))
             (draw (lambda (frame)
                     (draw-moving-traced gpu
                                         frame
                                         (● canvas view)
                                         (looking 4.0 0.0)
                                         0.12
                                         1.0
                                         1
                                         #t)))
             (initial (retrace gpu t (● stage scene) day)) (first (draw initial))
             (pose (new ObjectPose (place (new Vec4f (x 0.0) (y 0.0) (z 1.0) (w 1.0)))
                        (size (new Vec4f (x 1.0) (y 1.0) (z 1.0) (w 0.0))))))
        (pose-scene! gpu stage (list pose)) (refit-tracer! gpu first)
        (let* ((next (draw first)) (bytes (inspect gpu kernel next result back))
               (clean (retrace gpu next scene day)))
          (expect bytes 32 (new Vec4i (x 2) (y 24) (z 0) (w 0)))
          (release-moving-scene gpu stage) clean)))
    (define (lamp (x F32) (z F32) (power F32) (reach F32)) (→ Punctual)
      (point-light (new Vec3f (x x) (y 0.0) (z z)) (new Vec3f (x power) (y power) (z power)) reach))
    (define (local-light-checks (gpu Gpu) (t Tracer) (dark Environment)
                                (draw (Fn Tracer Camera3D I32 I32 I32 → Tracer))) (→ Tracer)
                                (let* ((front (looking 4.0 0.0)) (far (lamp 2.6 3.1 12.0 24.0))
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
                            (draw (Fn Tracer I32 → Tracer)) (center I64)) (→ Unit)
                            (let* ((s (test-wall gpu #f (Nil) 1))
                                   (read-level (lambda ()
                                                 (u8->i32
                                                  (array-ref (read-rgba gpu plane 17 15) center)))))
                              (update-moving-lights! gpu
                                                     (● s lights)
                                                     (list (lamp 0.5 1.05 6.0 0.8)))
                              (let* ((lit (fold-left (lambda (frame _) (draw frame 2))
                                                     (retrace gpu t s night)
                                                     (iota 8)))
                                     (on (read-level)))
                                (update-moving-lights! gpu (● s lights) (Nil))
                                (let* ((one (draw lit 2))
                                       (two (draw one 2))
                                       (after-two (read-level)))
                                  (draw (draw two 2) 2)
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
    ;; A flat lit wall has the same energy at two paths/pixel as at one.
    ;; Exercise all eight jitter phases, short driving histories, an odd-sized
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
             (draw (lambda ((frame Tracer) (count I32)) (→ Tracer)
                     (draw-sampled-traced gpu
                                          frame
                                          (● plane view)
                                          (looking 4.0 0.0)
                                          0.12
                                          1.0
                                          1
                                          #t
                                          (Reconstruct 17 15 count))))
             (center (* 4 (+ (* 7 17) 8)))
             (warm (fold-left (lambda (frame i) (draw frame (if (= i 0) 1 2))) t (iota 12)))
             (check (inspect gpu kernel warm result back))
             (bright (read-rgba gpu plane 17 15)))
        (unless (and (= (u32 check 8) 1) (>= (u32 check 32) 1) (<= (u32 check 32) 4)
                     (> (u32 check 36) 4) (<= (u32 check 36) 24)
                     (> (u8->i32 (array-ref bright center)) 20))
          (panic "driving sample energy, short history, or display reconstruction failed"))
        (let* ((dim (draw (retrace gpu warm scene night) 2)) (dark (read-rgba gpu plane 17 15)))
          (unless (and (= (u8->i32 (array-ref dark center)) 0)
                       (= (u8->i32 (array-ref dark (+ center 3))) 255))
            (panic "reconstructed display carried radiance across a scene cut"))
          (headlamp-trail gpu dim night plane draw center))
        (release-plane gpu plane)))
    (define (check-restir (gpu Gpu)) (→ String)
      (let* ((scene (wall gpu #f)) (blocked (wall gpu #t)) (day (sky gpu 1.0)) (night (sky gpu 0.0))
             (canvas (make-plane gpu "test/restir" 9 9 (Rgba8Unorm) (list (RenderAttachment))))
             (kernel (compute-kernel gpu ((● gpu create-shader-module)
                                          (new ShaderModuleDescriptor (label "test/reservoir")
                                               (code (string-append reservoir-shader
                                                                    inspect-reservoir))))
                                     "test"
                                     "inspect"))
             (result (storage-buffer gpu "test/reservoir" 48 (list (CopySrc))))
             (back ((● gpu create-buffer) (new BufferDescriptor (label "test/readback") (size 48)
                                               (usage (list (CopyDst) (MapRead))))))
             (draw
              (lambda ((t Tracer) (camera Camera3D) (count I32) (selected I32) (lit I32)) (→ Tracer)
                (let ((next (draw-sampled-traced gpu t (● canvas view) camera 0.12 1.0 1
                                                 #f (EveryPixel))))
                  (expect (inspect gpu kernel next result back) 0
                          (new Vec4i (x count) (y selected) (z lit) (w 1)))
                  next)))
             (front (looking 4.0 0.0))
             (initial (make-moving-tracer gpu scene day (Rgba8Unorm) 9 9 1))
             (first (draw initial front 8 1 1))
             (reused (fold-left (lambda (t n) (draw t (looking 3.5 0.0) n 1 1))
                                first (list 24 56 120 168 168)))
             (sky-only (draw reused (looking 4.0 8.0) 0 0 0))
             (uncovered (draw sky-only front 8 1 1))
             (shadow (draw (retrace gpu uncovered blocked day) front 8 1 0))
             (dark (draw (retrace gpu shadow scene night) front 8 0 0))
             (checks
              (check-checkerboard gpu (moving-depth gpu dark scene day canvas kernel result back)
                                  canvas kernel result back))
             (local (local-light-checks gpu (resize-tracer gpu checks 9 9) night draw))
             (mutable (make-sky-light gpu (test-sky 0.0) 128))
             (old-sky (draw (retrace gpu local scene (● mutable environment)) front 8 0 0)))
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
        "weighted draws, capped reuse, visible and blocked light, disocclusion, reset and checkerboard sampling"))))
