;; Render a PNG with the same WebGPU tracer as the browser, without a window.
;; ./snail-scheme run --target node tools/render.scm scene=model.glb output=preview.png
(import
 (snail core base)
 (snail core io)
 (snail shell json)
 (snail shell json read)
 (snail shell math)
 (snail shell gpu)
 (snail shell png)
 (snail shell graphics pod)
 (snail shell graphics raster)
 (only (snail shell graphics bvh) ray-size)
 (snail shell graphics environment)
 (snail shell graphics gltf)
 (snail shell graphics trace scene)
 (snail shell graphics trace render)
 (snail shell graphics still)
 (only (snail shell graphics passes) Photographic)
 (only (snail shell graphics fly) fly-over fly-camera))

(define (setting (args Arguments) (key String) (fallback String)) (→ String)
  (let* ((prefix (string-append key "=")) (n (string-length prefix)))
    (match (find (lambda (s) (and (>= (string-length s) n) (string=? prefix (substring s 0 n))))
                 (list-tail (command-line args) 1))
      ((Some arg) (substring arg n (string-length arg)))
      (_ fallback))))
(define (number (args Arguments) (key String) (default I64) (lo I64) (hi I64)) (→ I64)
  (match (string->i64 (setting args key (show default)))
    ((Some n)
     (if (and (>= n lo) (<= n hi))
         n
         (panic (string-append key " outside " (show lo) ".." (show hi)))))
    (_ (panic (string-append key " must be an integer")))))
(define (coordinate (x Json)) (→ F32)
  (match x ((JsonInteger n) (f64->f32 (i64->f64 n))) ((JsonNumber n) (f64->f32 n))
         (_ (panic "camera coordinates must be numbers"))))
(define (point (text String)) (→ Vec3f)
  (match (string->json (string-append "[" text "]"))
    ((Some (JsonArray xs))
     (unless (= (length xs) 3) (panic "camera positions need x,y,z"))
     (new Vec3f
       (x (coordinate (list-ref xs 0)))
       (y (coordinate (list-ref xs 1)))
       (z (coordinate (list-ref xs 2)))))
    (_ (panic "camera positions need x,y,z"))))
;; Reconstruction inputs and targets share the camera, geometry and frame size.
;; Preserve the G-buffer's native formats and layer order for tensor consumers.
(define camera-shape (→ (Shape Camera3D)) (shape))
(define (capture-guides (gpu Gpu) (fs Fs) (prefix String) (planes (List Plane)) (depth Plane)
                        (width I32) (height I32)) (→ Unit)
                        (for-each (lambda (entry)
                                    (let ((format (● entry second)))
                                      (write-bytes fs (string-append prefix "." (● format first))
                                                   (read-plane gpu
                                                               (● entry first)
                                                               width
                                                               height
                                                               (● format second)))))
                                  (zip (append planes (list depth))
                                       (zip (list "normal.rg16f"
                                                  "emission.rgba16f"
                                                  "albedo.rgba8srgb"
                                                  "material.rgba8"
                                                  "motion.rg16f" "triangle.r32u" "depth.f32")
                                            (list 4 8 4 4 4 4 4)))))

(define (capture (gpu Gpu)
                 (fs Fs)
                 (t Tracer)
                 (camera Camera3D)
                 (prefix String)
                 (samples I64)
                 (bounces I64)
                 (seed I64)
                 (box Bool))
  (→ Unit)
  (let* ((w (● t targets width)) (h (● t targets height)) (spread (/ 1.0 (i32->f32 h)))
         (target (make-plane gpu "capture/display" w h (Rgba8Unorm) (list (RenderAttachment))))
         (noisy (draw-traced gpu (discard-trace-history t) (● target view)
                             camera
                             spread
                             1.0
                             bounces
                             #f
                             (new TraceSettings (display-width w) (display-height h))))
         (raster (match (● noisy last) ((Some view) (● view raster))
                        (_ (panic "capture has no rasterized frame"))))
         (first (+ (● noisy frame) (i64->i32 seed))))
    (write-bytes fs (string-append prefix ".noisy.rgba32f") (read-traced-radiance gpu noisy))
    (write-bytes fs (string-append prefix ".camera") (pod-bytes camera-shape raster))
    (capture-guides gpu
                    fs
                    (string-append prefix ".opaque")
                    (● t targets planes)
                    (● t targets depth)
                    w
                    h)
    (match (● t targets blended)
      ((Some b)
       (capture-guides gpu fs (string-append prefix ".blended") (● b planes) (● b depth) w h))
      (_ (unit)))
    (write-bytes fs (string-append prefix ".reference.rgba32f")
                 (if box (trace-film gpu noisy camera spread bounces first samples)
                     (trace-reference gpu noisy raster spread bounces first samples)))
    (write-file fs (string-append prefix ".json")
                (string-append "{\"width\":" (show w) ",\"height\":" (show h) ",\"layers\":"
                               (match (● t targets blended)
                                 ((Some _) "[\"opaque\",\"blended\"]")
                                 (_ "[\"opaque\"]"))
                               ",\"noisySeed\":"
                               (show (● t frame))
                               ",\"firstReferenceSeed\":"
                               (show first)
                               ",\"referenceSamples\":"
                               (show samples)
                               ",\"pixelFilter\":" (if box "\"box\"" "\"fixed\"")
                               ",\"bounces\":"
                               (show bounces)
                               "}"))
    (release-plane gpu target)))

(define (read-model (gpu Gpu) (fs Fs) (path String) (layers I32)) (→ Scene)
  (match (attempt-reading (lambda ()
                            (load-scene gpu
                                        (lambda (paths) (map (lambda (p) (read-bytes fs p)) paths))
                                        path layers)))
    ((Ok scene) scene)
    ((Err why) (panic why))))

;; Local solar time in minutes, with an equinox sun at a temperate latitude.
(define (sun-direction (minute I64)) (→ Vec3f)
  (let* ((angle (* (/ (- (i64->f64 minute) 360.0) 720.0) pi)) (s (sin angle)) (east (cos angle)))
    (new Vec3f
      (x (f64->f32 (- (* 0.9876 east) (* 0.0964 s))))
      (y (f64->f32 (* 0.79 s)))
      (z (f64->f32 (+ (* 0.1573 east) (* 0.6047 s)))))))

(define (exposure (sun Vec3f)) (→ F32)
  (let ((t (max 0.0 (min 1.0 (/ (- 0.20 (f32->f64 (● sun y))) 0.34)))))
    (f64->f32 (* 1.10 (expt 2.0 (* (* 2.0 (* t t)) (- 3.0 (* 2.0 t))))))))

(define (lighting (gpu Gpu) (fs Fs) (path String) (sun Vec3f)) (→ Environment)
  (if (string=? path "")
      (● (make-atmosphere-light gpu
                                (new Atmosphere
                                  (sun sun)
                                  (wind (new Vec2f (x 0.0) (y 0.0)))
                                  (cover 0.54))
                                1024)
         environment)
      (match (read-hdr (read-bytes fs path))
        ((Ok hdr) (hdr-environment gpu hdr 4096))
        ((Err why) (panic why)))))
;; Wall time through the synchronized linear film readback. Each run starts
;; with a fresh accumulation on the same resident scene and camera.
(define (time-film (gpu Gpu) (clock Clock) (fs Fs) (path String) (t Tracer) (camera Camera3D)
                   (samples I64) (depth I64) (started I64)) (→ Unit)
                   ((● gpu work-done))
                   (let* ((now (● clock monotonic-nanoseconds))
                          (setup (- (now) started))
                          (spread (/ 1.0 (i32->f32 (● t targets height))))
                          (run (lambda ((index I64)) (→ F64)
                                 (let* ((beginning (now))
                                        (film (trace-film gpu
                                                          t
                                                          camera
                                                          spread
                                                          depth
                                                          (i64->i32 (* samples index))
                                                          samples))
                                        (seconds (/ (i64->f64 (- (now) beginning)) 1e9)))
                                   (when (= index 5)
                                     (write-bytes fs (string-append path ".rgba32f") film))
                                   seconds))))
                     (let* ((warmup (run 0))
                            (times (map (lambda (index) (show (run index))) (list 1 2 3 4 5))))
                       (write-file fs (string-append path ".json")
                                   (string-append "{\"setupSeconds\":"
                                                  (show (/ (i64->f64 setup) 1e9))
                                                  ",\"warmupSeconds\":" (show warmup)
                                                  ",\"renderSeconds\":["
                                                  (string-join times ",")
                                                  "]}")))))

(define (main (args Arguments) (fs Fs) (out OutputPort) (host Host) (clock Clock)) (→ Unit)
  (let* ((name (setting args "scene" "")) (path (setting args "output" "render.png"))
         (width (number args "width" 960 1 16384)) (height (number args "height" 540 1 16384))
         (w (i64->i32 width)) (h (i64->i32 height)) (aspect (/ (i64->f64 width) (i64->f64 height)))
         (spp (number args "samples" 16 1 4096)) (depth (number args "bounces" 3 1 most-bounces))
         (sun (sun-direction (number args "minute" 1040 0 1439)))
         (layers (i64->i32 (number args "layers" 256 1 4096)))
         (eye (setting args "eye" "")) (target (setting args "target" "")))
    (when (string=? name "") (panic "supply scene=PATH to a glTF or GLB file"))
    (unless (if (string=? eye "") (string=? target "") (not (string=? target "")))
      (panic "supply eye and target together"))
    (let* ((started ((● clock monotonic-nanoseconds)))
           (gpu (host-gpu host)) (info ((● gpu request-device))))
      (unless (<= (* ray-size (* width height)) (i32->i64 (● info storage-binding-size)))
        (panic "image exceeds the GPU ray-buffer limit; reduce width or height"))
      (let* ((scene (read-model gpu fs name layers))
             (sky (lighting gpu fs (setting args "environment" "") sun))
             (tracer (make-tracer gpu
                                  scene
                                  sky
                                  (Rgba8Unorm)
                                  w
                                  h
                                  layers
                                  (Photographic)))
             (camera
              (if (string=? eye "") (fly-camera (fly-over (● scene low) (● scene high)) aspect)
                  (camera-3d (point eye)
                             (point target)
                             (PinholeRange 0.8 0.05 32000.0)
                             aspect
                             1.0)))
             (prefix (setting args "capture" "")) (timing (setting args "timing" "")))
        (cond ((not (string=? timing ""))
               (time-film gpu clock fs timing tracer camera spp depth started))
              ((string=? prefix "")
               (let ((draw (render-still gpu tracer camera spp depth (exposure sun))))
                 (write-bytes fs path (rgba->png w h (● draw second)))
                 (write-line out (string-append path " · " (show width) "×" (show height) " · "
                                                (show spp)
                                                " samples/pixel · "
                                                (show depth)
                                                " bounces"))))
              (else
               (let ((film (setting args "pixel-filter" "fixed")))
                 (unless (or (string=? film "fixed") (string=? film "box"))
                   (panic "pixel-filter must be fixed or box"))
                 (capture gpu fs tracer camera prefix spp depth (number args "seed" 0 0 2147479550)
                          (string=? film "box")))
               (write-line out (string-append prefix ".json · 1 spp input and " (show spp)
                                              " spp reference"))))))))
