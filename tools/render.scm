;; Render a PNG with the same forward renderer as the browser, without a window.
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
 (only (snail shell graphics environment) read-hdr)
 (snail shell graphics forward environment)
 (snail shell graphics gltf)
 (snail shell graphics forward scene)
 (snail shell graphics forward render)
 (snail shell graphics still)
 (snail shell graphics scene)
 (prefix (snail shell graphics renderer) api:)
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

(define (read-model (r api:Renderer) (fs Fs) (path String)) (→ api:ModelHandle)
  (let ((read (lambda ((paths (List String)))
                (→ (List Bytes))
                (map (lambda (p) (read-bytes fs p)) paths))))
    (match (attempt-reading (lambda () (api:create-scene-node! r read (ModelNode path))))
      ((Ok h) h) ((Err why) (panic why)))))

(define (sky-source (path String) (minute I64)) (→ SkySource)
  (if (string=? path "")
      (BakedSky
       (cond ((< minute 300) 3) ((< minute 600) 0) ((< minute 960) 1) ((< minute 1150) 2) (else 3)))
      (Panorama path)))
(define (lighting (gpu Gpu) (fs Fs) (sky SkySource)) (→ Environment)
  (match sky ((BakedSky p) (daylight gpu p))
         ((Panorama path)
          (match (read-hdr (read-bytes fs path))
            ((Ok hdr) (import-hdr gpu hdr))
            ((Err why) (panic why))))))

(define (real-setting (args Arguments) (key String) (default F64)) (→ F32)
  (match (string->json (setting args key (show default))) ((Some n) (coordinate n))
         (_ (panic (string-append key " must be a finite number")))))

;; Each duration ends when the last submitted draw finishes. Readback and
;; encoding are separate from timing. All iterations reuse the same scene.
(define (benchmark (gpu Gpu) (r api:Renderer) (view SceneFrame)
                   (clock Clock) (started I64) (fs Fs) (path String)) (→ Unit)
                   (let* ((now (● clock monotonic-nanoseconds))
                          (frame (lambda () (let ((start (now)))
                                              (api:render! r view)
                                              ((● gpu work-done))
                                              (/ (i64->f64 (- (now) start)) 1e9)))))
                     ((● gpu work-done))
                     (let* ((setup (/ (i64->f64 (- (now) started)) 1e9))
                            (warmup (frame)) (times (map (lambda (_) (show (frame))) (iota 5))))
                       (write-file fs (string-append path ".json")
                                   (string-append "{\"setupSeconds\":"
                                                  (show setup)
                                                  ",\"warmupSeconds\":"
                                                  (show warmup)
                                                  ",\"renderSeconds\":["
                                                  (string-join times ",")
                                                  "]}")))))

(define (configured-frame (args Arguments) (bounds (Pair (List F64) (List F64)))) (→ SceneFrame)
  (let* ((w (i64->i32 (number args "width" 960 1 16384)))
         (h (i64->i32 (number args "height" 540 1 16384)))
         (msaa (i64->i32 (number args "msaa" 1 1 4))) (shadows (setting args "shadows" "on"))
         (eye (setting args "eye" ""))
         (target (setting args "target" ""))
         (fov (real-setting args "fov" 0.8))
         (brdf (setting args "brdf" "pbr")) (aspect (/ (i32->f64 w) (i32->f64 h))))
    (unless (and (> fov 0.0) (< fov 3.14159)) (panic "invalid field of view"))
    (unless (if (string=? eye "") (string=? target "") (not (string=? target "")))
      (panic "supply eye and target together"))
    (let* ((camera
            (if (string=? eye "") (fly-camera (fly-over (● bounds first) (● bounds second)) aspect)
                (camera-3d (point eye)
                           (point target)
                           (PinholeRange (f32->f64 fov) 0.05 32000.0)
                           aspect
                           1.0)))
           (frame (scene-frame camera w h msaa (real-setting args "exposure" 1.0))))
      (set! (● frame shadows)
            (cond ((string=? shadows "on") #t)
                  ((string=? shadows "off") #f)
                  (else (panic "invalid shadows"))))
      (set! (● frame shading)
            (cond ((string=? brdf "pbr") (MetallicRoughness))
                  ((string=? brdf "blinn-phong") (BlinnPhong))
                  (else (panic "invalid brdf"))))
      (set! (● frame cascade) (i64->i32 (number args "cascade" -1 -1 2))) frame)))

(define (run-renderer (args Arguments) (fs Fs) (out OutputPort) (gpu Gpu) (clock Clock)
                      (port (Option OutputPort))) (→ Unit)
                      (let* ((r (api:make-renderer gpu (new api:RendererConfig (trace port))))
                             (started ((● clock monotonic-nanoseconds)))
                             (replay (setting args "replay" ""))
                             (path (setting args "output" "render.png"))
                             (linear (setting args "linear" ""))
                             (timing (setting args "timing" "")))
                        (if (string=? replay "")
                            (let* ((model (setting args "scene" ""))
                                   (_ (when (string=? model "")
                                        (panic "supply scene=PATH or replay=TRACE")))
                                   (handle (read-model r fs model))
                                   (sky (sky-source (setting args "environment" "")
                                                    (number args "minute" 1040 0 1439)))
                                   (f (configured-frame args (api:model-bounds r handle))))
                              (api:use-model! r handle)
                              (api:set-sky! r (lighting gpu fs sky) (Photographic))
                              (when (and (>= (● f cascade) 0) (not (string=? linear "")))
                                (panic "linear output needs a shaded frame"))
                              (if (string=? timing "") (begin (api:render! r f) (unit))
                                  (benchmark gpu r f clock started fs timing)))
                            (begin
                              (unless (and (string=? (setting args "scene" "") "")
                                           (string=? (setting args "environment" "") ""))
                                (panic "renderer traces contain their own meshes and lighting"))
                              (call-with-input-file fs replay (lambda (in)
                                                                (let ((limit
                                                                       (if (string=? (setting args
                                                                                              "commands"
                                                                                              "")
                                                                                     "")
                                                                           (None)
                                                                           (Some (number args
                                                                                         "commands"
                                                                                         0
                                                                                         0
                                                                                         2147483647)))))
                                                                  ((● r replay) in limit)
                                                                  (unit))))))
                        (let* ((size (api:renderer-size r)) (w (● size first)) (h (● size second)))
                          (when (and (> w 0) (string=? timing ""))
                            (write-bytes fs
                                         path
                                         (rgba->png w
                                                    h
                                                    (read-rgba gpu (api:renderer-output r) w h))))
                          (unless (string=? linear "")
                            (write-bytes fs linear (read-linear gpu (api:renderer-forward r))))
                          (api:release-renderer! r)
                          (write-line out (if (= w 0) "Replay stopped before the first draw."
                                              (string-append (if (string=? timing "")
                                                                 path
                                                                 (string-append timing ".json"))
                                                             " · "
                                                             (show w)
                                                             "×"
                                                             (show h)))))))

(define (main (args Arguments) (fs Fs) (out OutputPort) (host Host) (clock Clock)) (→ Unit)
  (let ((gpu (host-gpu host)) (record (setting args "record" "")))
    ((● gpu request-device))
    (if (string=? record "") (run-renderer args fs out gpu clock (None))
        (begin
          (when (string=? record (setting args "replay" ""))
            (panic "input and output trace must be different files"))
          (call-with-output-file fs
            record
            (lambda (port) (run-renderer args fs out gpu clock (Some port))))))))
