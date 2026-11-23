;; Posed RGB samples for the foam. The built-in scene and photographs
;; from the splat trainer both enter through COLMAP pinhole cameras.
(define-library (apps foam views)
  (export Model View Experiment demo-experiment photo-experiment)
  (import
   (snail core base)
   (only (snail shell math) cos sin pi)
   (snail shell wire)
   (snail shell gpu)
   (snail shell graphics colmap)
   (snail shell graphics radiant-foam)
   (only (snail shell graphics splat-fit) texel-pitch)
   (apps train dataset)
   (only (apps train trainer) Scene))
  (begin

    ;; ---- Views ----

    ;; Model coordinates are (world - center) / radius. Storing that
    ;; transform with the sites lets an exported face return to COLMAP space.
    (record Model
      ((center Vec3d)
       (radius F64)
       (sites (List Site)))
      (deriving Serialize Deserialize))

    (record View
      ((name String)
       (camera RayCamera)
       (width I64)
       (height I64)
       (samples (Array Sample))))

    (record Experiment
      ((initial Model)
       (training (Array Sample))
       (held View)))

    (define (three (values (List F64))) (→ Vec3d)
      (vec3d (list-ref values 0) (list-ref values 1) (list-ref values 2)))

    ;; R maps world to camera. Its rows are the camera axes in the world.
    (define (pose-camera (model Model) (cam ColmapCamera) (pose ColmapImage)) (→ RayCamera)
      (let* ((rows (image-rotation pose)) (forward (three (list-tail rows 6)))
             (dx (v* (three rows) (/ 1.0 (● cam fx))))
             (dy (v* (three (list-tail rows 3)) (/ 1.0 (● cam fy))))
             (eye (v* (v- (three (image-center pose)) (● model center)) (/ 1.0 (● model radius))))
             (corner (v+ forward (v+ (v* dx (- 0.5 (● cam cx))) (v* dy (- 0.5 (● cam cy)))))))
        (new RayCamera (eye eye) (corner corner) (dx dx) (dy dy)
             (width (● cam width)) (height (● cam height)))))

    ;; One original pixel nearest each thumbnail pixel center. Both the
    ;; ray and the RGB refer to that same original pixel.
    (define (thumbnail (model Model) (cam ColmapCamera) (pose ColmapImage) (width I64)
                       (color (Fn I64 I64 Ray → Vec3d)))
      (→ View)
      (let* ((w (min width (● cam width)))
             (h
              (max 1 (quotient (+ (* w (● cam height)) (quotient (● cam width) 2)) (● cam width))))
             (pixel (lambda (i source size) (quotient (* (+ (* 2 i) 1) source) (* 2 size))))
             (camera (pose-camera model cam pose)))
        (new View
          (name (● pose name)) (camera camera) (width w) (height h)
          (samples (array-generate (* w h)
                                   (lambda (i)
                                     (let* ((x (pixel (remainder i w) (● cam width) w))
                                            (y (pixel (quotient i w) (● cam height) h))
                                            (r (camera-ray camera x y)))
                                       (new Sample (ray r) (rgb (color x y r))))))))))

    ;; ---- A small example ----

    ;; Two colored sites inside a ring of clear cells. The target images
    ;; see this foam, while fitting starts from displaced sites, weaker
    ;; extinction and gray RGB. Only the posed images reach the optimizer.
    (define clear-sites (→ (List Site))
      (map (lambda (p) (site p 0.0 (vec3d 0.0 0.0 0.0)))
           (list (vec3d -0.98 0.0 0.0) (vec3d 0.98 0.0 0.0) (vec3d 0.0 -0.85 0.0)
                 (vec3d 0.0 0.72 0.0) (vec3d 0.0 0.0 -0.8) (vec3d 0.0 0.0 0.9))))

    (define reference (→ Foam)
      (make-foam (append (list (site (vec3d -0.27 -0.10 0.04) 3.5 (vec3d 0.98 0.4 0.12))
                               (site (vec3d 0.26 0.10 -0.08) 2.8 (vec3d 0.12 0.7 0.93)))
                         clear-sites)))

    (define demo-model (→ Model)
      (let ((gray (vec3d 0.5 0.5 0.5)))
        (new Model
          (center (vec3d 0.0 0.0 0.0)) (radius 1.0)
          (sites (append (list (site (vec3d -0.17 0.0 0.1) 1.5 gray)
                               (site (vec3d 0.16 0.0 0.0) 1.5 gray))
                         (map (lambda (s) (site (v* (● s position) 0.88) 0.12 gray))
                              clear-sites))))))

    (define demo-camera (→ ColmapCamera)
      (new ColmapCamera (id 1) (width 96) (height 72) (fx 112.0) (fy 112.0) (cx 48.0) (cy 36.0)))

    (define (demo-view (model Model) (angle F64) (width I64)) (→ View)
      (let* ((half (* angle 0.5))
             (pose (new ColmapImage (id 0) (camera 1) (name "synthetic")
                        (rotation (list (cos half) 0.0 (sin half) 0.0))
                        (translation (list 0.0 0.0 2.6)))))
        (thumbnail model demo-camera pose width (lambda (x y r) (render-ray reference r)))))

    (define (demo-experiment (saved (Option Model)) (train Bool) (index I64) (width I64))
      (→ Experiment)
      (let* ((model (match saved ((Some m) m) ((None) demo-model)))
             (angle (lambda (i) (* (i64->f64 i) (/ pi 4.0))))
             (views (if train (map (lambda (i) (demo-view model (angle i) 96)) (iota 8)) (Nil))))
        (new Experiment
          (initial model)
          (training (array-concatenate (map (lambda (v) (● v samples)) views)))
          (held (demo-view model (+ (angle index) (/ pi 8.0)) width)))))

    ;; ---- COLMAP photographs ----

    ;; One item from the middle of each equal-sized part of the list.
    (define (evenly (items (List T)) (count I64)) (→ (List T)) (∀ (T))
      (let* ((a (list->array items)) (n (array-length a)) (k (min count n)))
        (map (lambda (i) (array-ref a (quotient (* (+ (* 2 i) 1) n) (* 2 k)))) (iota k))))

    (define (photo-model (scene Scene) (count I64)) (→ Model)
      (let* ((poses (append (● scene training) (● scene held)))
             (center (v* (fold-left (lambda (v p) (v+ v (three (image-center p))))
                                    (vec3d 0.0 0.0 0.0) poses) (/ 1.0 (i64->f64 (length poses)))))
             (radius (● scene extent))
             (local (lambda (p) (v* (v- (three (● p position)) center) (/ 1.0 radius))))
             (inside (lambda (v) (<= (max (abs (● v x)) (max (abs (● v y)) (abs (● v z)))) 1.0))))
        (unless (> radius 0.0) (panic "foam needs distinct camera centers"))
        (let ((points (evenly (filter (lambda (p) (inside (local p))) (● scene points)) count)))
          (when (null? points) (panic "no sparse points inside the camera bounds"))
          (new Model (center center) (radius radius)
               (sites (map (lambda (p) (site (local p) 1.0 (three (● p color)))) points))))))

    ;; Read the decoder's RGBA rows with the same alignment as splat training.
    (define (photo-bytes (gpu Gpu) (image Image) (pitch I32)) (→ Bytes)
      (let* ((size (* pitch (● image height)))
             (buffer ((● gpu create-buffer) (new BufferDescriptor
                                              (label "foam/photograph")
                                              (size size)
                                              (usage (list (CopyDst) (MapRead))))))
             (encoder ((● gpu create-command-encoder))))
        ((● gpu copy-texture-to-buffer) encoder (whole-texture (● image texture)) buffer 0 pitch
         (● image width) (● image height))
        ((● gpu submit) (list ((● gpu finish) encoder)))
        ((● gpu destroy) (TextureObject (● image texture)))
        (let ((bytes ((● gpu read-buffer) buffer 0 size)))
          ((● gpu destroy) (BufferObject buffer))
          bytes)))

    (define (photo-view (model Model) (gpu Gpu) (cam ColmapCamera) (pose ColmapImage)
                        (image Image) (width I64))
      (→ View)
      (unless (and (= (● pose camera) (● cam id))
                   (= (i32->i64 (● image width)) (● cam width))
                   (= (i32->i64 (● image height)) (● cam height)))
        (panic "foam needs photographs from the scene's one pinhole camera at a common size"))
      (let* ((pitch (* 4 (texel-pitch (● cam width))))
             (pixels (photo-bytes gpu image (i64->i32 pitch)))
             (channel (lambda (at) (/ (i32->f64 (u8->i32 (array-ref pixels at))) 255.0))))
        (thumbnail model cam pose width
                   (lambda (x y r)
                     (let ((i (+ (* y pitch) (* 4 x))))
                       (vec3d (channel i) (channel (+ i 1)) (channel (+ i 2))))))))

    (define (photo-experiment (gpu Gpu) (read (Fn String → Bytes)) (settings Settings)
                              (saved (Option Model))
                              (train Bool)
                              (index I64)
                              (count I64)
                              (width I64))
      (→ Experiment)
      (let* ((scene (dataset-scene gpu read settings))
             (model (match saved ((Some m) m) ((None) (photo-model scene count))))
             (view (lambda (pose width) (photo-view model gpu (● scene camera) pose
                                                    (dataset-photograph gpu read settings pose)
                                                    width)))
             (training (if train (● scene training) (Nil))))
        (when (>= index (length (● scene held))) (panic "view is outside the held-out split"))
        (new Experiment (initial model)
             (training
              (array-concatenate (map (lambda (pose) (● (view pose 48) samples)) training)))
             (held (view (list-ref (● scene held) index) width)))))

    ))
