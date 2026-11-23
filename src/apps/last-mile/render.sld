;; The street is static. The sedan, actors and props share the moving vertex buffer.
(define-library (apps last-mile render)
  (export Renderer make-renderer draw!)
  (import
   (snail core base)
   (snail shell math)
   (snail shell app)
   (only (snail shell gpu) Gpu view-of ViewObject)
   (only (snail shell graphics pod) Vec3f Vec4f Mat4x4f)
   (only (snail shell graphics animation)
         Rig
         posed-nodes
         skin-palette
         matrix-product
         rigid-binding
         named-node
         named-branch)
   (snail shell graphics gltf animation)
   (snail shell graphics gltf)
   (only (snail shell graphics raster) camera-3d Pinhole Camera3D)
   (snail shell graphics trace scene)
   (snail shell graphics trace render)
   (snail shell graphics environment)
   (snail shell game scenery)
   (snail shell game physics)
   (snail shell game boarding)
   (snail shell game humanoid)
   (snail shell game pedestrian)
   (snail shell game drawing)
   (apps last-mile district)
   (apps last-mile game)
   (apps last-mile street))
  (begin
    (record Renderer
      ((stage MovingScene)
       (tracer Tracer)
       (actor Humanoid)
       (marker-hand I64)
       (reel-hand I64)
       (palette (List Mat4x4f))
       (tick I64)
       (budget I32)
       (streak-frames I32)
       (eye XZ)))

    (define (rgba (x F32) (y F32) (z F32) (w F32)) (→ Vec4f) (new Vec4f (x x) (y y) (z z) (w w)))
    (define sky (→ Sky)
      (new Sky (sun (rgba -0.6000 0.69282 0.4000 0.9997)) (sun-light (rgba 7.5 6.7 5.5 0.0))
           (zenith (rgba 0.26 0.46 0.78 1.0))
           (horizon (rgba 0.87 0.87 0.78 1.0))
           (ground (rgba 0.21 0.19 0.17 1.0))))

    (define (sedan-pose (b Body)) (→ ObjectPose)
      ;; Kenney's front wheels lie toward +z. One source unit along z is 1.8 m.
      (let ((p (● b position)) (a (- pi (● b heading))))
        (new ObjectPose (place (rgba (f64->f32 (● p x)) 0.0 (f64->f32 (● p z)) (f64->f32 (cos a))))
             (size (rgba 1.25 1.4 1.8 (f64->f32 (sin a)))))))

    (define (streak (w Game)) (→ Item)
      (match (● w shot)
        ((None) (piece (Box) (rgb 252 178 55) 0.0 -4.0 0.0 0.03 0.03 0.1 0.3))
        ((Some shot)
         (let ((a (● shot start)) (b (● shot end)))
           (Item-yaw-set (piece (Box) (rgb 252 178 55) (* 0.5 (+ (● a x) (● b x)))
                                1.48
                                (* 0.5 (+ (● a z) (● b z)))
                                0.045
                                0.045
                                (max 0.05 (distance a b))
                                0.3)
                         (f64->f32 (negate (heading-to a b))))))))

    (define (props (w Game)) (→ (List Item)) (append (prop-items w) (list (streak w))))

    (define (crew (model Rigged)) (→ Humanoid)
      (let ((upper (named-branch (● model rig) "Spine")))
        (when (null? upper) (unreadable "crew.glb needs its Spine branch for the paint marker"))
        (new Humanoid (rig (● model rig)) (idle (named-clip model "idle"))
             (walk (named-clip model "walk")) (brace (named-clip model "shoot"))
             (drive (named-clip model "racingIdle")) (upper-body upper))))

    ;; Crew models stand 3.76 source units tall and face +z. Each rider's
    ;; world position already includes their door-to-seat movement.
    (define (actor-nodes (h Humanoid) (b Body) (g Gait) (clock F64) (action F64))
      (→ (Array Mat4x4f))
      (let* ((yaw (- pi (● b heading))) (p (● b position))
             (at (new ObjectPose
                   (place (rgba (f64->f32 (● p x)) (f64->f32 (* 0.03 (● g seat)))
                                (f64->f32 (● p z)) (f64->f32 (cos yaw))))
                   (size (rgba 0.47 0.47 0.47 (f64->f32 (sin yaw)))))))
        (posed-nodes (● h rig) (humanoid-pose h g clock action) (pose-matrix at))))
    (define (hand (rig Rig) (name String)) (→ I64)
      (match (named-node rig name)
        ((Some i) i)
        (_ (unreadable (string-append "crew.glb needs " name)))))
    (define marker (→ Item) (piece (Box) (rgb 232 107 41) 0.0 -0.05 0.15 0.22 0.18 0.72 0.0))
    (define reel (→ Item) (piece (Prism) (rgb 240 173 60) 0.0 -0.23 0.0 0.80 0.24 0.80 0.0))
    (define (world-palette (h Humanoid) (marker-hand I64) (reel-hand I64) (w Game))
      (→ (List Mat4x4f))
      (let* ((clock (* 0.001 (i64->f64 (* (● w tick) tick-ms))))
             (action (* (● h brace duration) (/ (i64->f64 (- 8 (● w cooldown))) 8.0)))
             (driver (actor-nodes h (driver-body w) (● w gait) clock action))
             (rosa (actor-nodes h (rosa-body w) (● w rosa-gait) (+ clock 0.28) 0.0))
             (can (match (● w mission)
                    ((Finished)
                     (pose-matrix (item-pose (piece (Prism) (● reel color) (● cutting-room x) 1.20
                                                    (● cutting-room z) 0.38 0.12 0.38 0.0))))
                    (_
                     (matrix-product (array-ref rosa reel-hand) (pose-matrix (item-pose reel)))))))
        (concatenate (list (list (pose-matrix (sedan-pose (● w cab))))
                           (skin-palette (● h rig) driver) (skin-palette (● h rig) rosa)
                           (concatenate (map-indexed
                                         (lambda (i p)
                                           (skin-palette (● h rig)
                                                         (actor-nodes h (● p body) (● p gait)
                                                                      (+ clock
                                                                         (* 0.37
                                                                            (i64->f64 (+ i 1))))
                                                                      0.0)))
                                         (● w residents)))
                           (map (lambda (p) (pose-matrix (item-pose p))) (props w))
                           (list (matrix-product (array-ref driver marker-hand)
                                                 (pose-matrix (item-pose marker)))
                                 can)))))
    (define (park-van (model Gltf)) (→ Gltf)
      (gltf-transformed model (list 0.0 0.0 -1.4 0.0  0.0 1.4 0.0 0.0  1.5 0.0 0.0 0.0
                                    (+ (● van-center x) 0.0375) 0.0 (● van-center z) 1.0)))

    (define (unit-item (p Item)) (→ Item)
      (Item-glow-set (item (● p mesh) (xyz 0.0 0.0 0.0) (xyz 1.0 1.0 1.0) 0.0 (● p color))
                     (● p glow)))

    (define (vertex-count (p Placed)) (→ I64) (● p primitive positions count))

    ;; One palette entry for the sedan, one joint palette per actor and a
    ;; final rigid entry per prop. All actors share the asset and its clips.
    (define (build-stage (gpu Gpu)
                         (read (Fn (List String) → (List Bytes)))
                         (car Gltf)
                         (van Gltf)
                         (model Rigged)
                         (people I64)
                         (parts (List Item)))
      (→ MovingScene)
      (let* ((street (street-items)) (vehicles (append-gltf car van))
             (merged (append-gltf vehicles (● model model)))
             (car-meshes (take (● merged placed) (length (● car placed))))
             (van-meshes
              (take (list-drop (● merged placed) (length car-meshes)) (length (● van placed))))
             (actor-meshes (list-drop (● merged placed) (length (● vehicles placed))))
             (g (with-shapes (Gltf-placed-set merged (Nil)) (append street (map unit-item parts))))
             (fixed (take (● g placed) (length street)))
             (props (list-drop (● g placed) (length street)))
             (actors (iota people))
             (meshes (concatenate (list fixed van-meshes
                                        car-meshes
                                        (concatenate (map (lambda (_) actor-meshes) actors))
                                        props)))
             (car-binding (rigid-binding (fold-left + 0 (map vertex-count car-meshes))))
             (bindings (Cons car-binding (append (map (lambda (_) (● model binding)) actors)
                                                 (map (lambda (p) (rigid-binding (vertex-count p)))
                                                      props)))))
        (skin-scene gpu (upload-scene gpu read (Gltf-placed-set g meshes) 128) bindings)))

    (define (size-at (width I32) (height I32) (budget I32)) (→ (Pair I32 I32))
      (let ((scale (min 1.0
                        (min (/ (* (i32->f64 budget) (/ 16.0 9.0)) (i32->f64 (max 1 width)))
                             (/ (i32->f64 budget) (i32->f64 (max 1 height)))))))
        (new Pair (first (max 1 (f64->i32 (* scale (i32->f64 width)))))
             (second (max 1 (f64->i32 (* scale (i32->f64 height))))))))

    (define (make-renderer (gpu Gpu) (read (Fn (List String) → (List Bytes))) (w Game))
      (→ Renderer)
      (let* ((format (● ((● gpu request-device)) format))
             (models (read (list "./sedan.glb" "./crew.glb" "./delivery.glb")))
             (car (read-gltf (list-ref models 0) "./"))
             (model (read-rigged-gltf (list-ref models 1) "./" read))
             (actor (crew model))
             (right (hand (● actor rig) "RightHand"))
             (left (hand (● actor rig) "LeftHand"))
             (van (park-van (read-gltf (list-ref models 2) "./")))
             (palette (world-palette actor right left w))
             (stage (build-stage gpu
                                 read
                                 car
                                 van
                                 model
                                 (+ 2 (length (● w residents)))
                                 (append (props w) (list marker reel))))
             (canvas ((● gpu current-texture)))
             (size (size-at (● canvas width) (● canvas height) 270)))
        (deform-scene! gpu stage palette)
        (new Renderer
          (stage stage)
          (actor actor) (marker-hand right) (reel-hand left)
          (palette palette)
          (tick (● w tick))
          (budget 270)
          (streak-frames 0)
          (eye (offset (● (carrier w) position) (forward (● (carrier w) heading)) -5.6))
          (tracer (make-moving-tracer gpu (● stage scene) (sky-environment gpu sky 512) format
                                      (● size first) (● size second) 128 2)))))

    ;; A camera beside a tree can pass below its crown. Using only the
    ;; trunk's ground footprint would put the eye inside an opaque mesh.
    (define (camera-height (p XZ) (eye XZ) (seated Bool)) (→ F32)
      (let ((reach (distance p eye)))
        (if
         (< (trace-distance p (forward (heading-to p eye)) (+ reach 0.25) canopies) (+ reach 0.25))
         1.95 (if seated 3.65 2.85))))

    (define (camera! (r Renderer) (b Body) (seated Bool) (elapsed I32) (aspect F64)) (→ Camera3D)
      (let* ((p (● b position))
             (ahead (forward (● b heading)))
             (back (offset (xz 0.0 0.0) ahead -1.0))
             (d (min (if seated 8.3 5.6) (max 0.5 (- (trace-distance p back 9.0 walls) 0.4))))
             (wanted (offset p back d)) (old (● r eye)) (a (min 1.0 (* 0.012 (i32->f64 elapsed))))
             (eye (xz (+ (● old x) (* a (- (● wanted x) (● old x))))
                      (+ (● old z) (* a (- (● wanted z) (● old z))))))
             (at (offset p ahead 3.6)))
        (set! (● r eye) (if (clear? eye 0.2 walls) eye wanted))
        (camera-3d
         (new Vec3f
           (x (f64->f32 (● r eye x)))
           (y (camera-height p (● r eye) seated))
           (z (f64->f32 (● r eye z))))
         (new Vec3f (x (f64->f32 (● at x))) (y 1.35) (z (f64->f32 (● at z))))
         (Pinhole 1.0)
         aspect
         1.0)))

    ;; Adjust only after a run of slow or fast frames so resizing does not
    ;; repeatedly throw away the filter's history near a threshold.
    (define (budget! (r Renderer) (ms I32)) (→ I32)
      (let ((n (cond ((> ms 48) (- (min 0 (● r streak-frames)) 1))
                     ((and (> ms 0) (< ms 22)) (+ (max 0 (● r streak-frames)) 1))
                     (else 0))))
        (cond ((<= n -4) (set! (● r budget) (max 120 (quotient (* 2 (● r budget)) 3)))
               (set! (● r streak-frames) 0))
              ((>= n 90) (set! (● r budget) (min 540 (quotient (* 3 (● r budget)) 2)))
               (set! (● r streak-frames) 0))
              (else (set! (● r streak-frames) n)))
        (● r budget)))

    (define (draw! (r Renderer) (gpu Gpu) (w Game) (elapsed I32)) (→ Unit)
      (let* ((canvas ((● gpu current-texture))) (width (● canvas width)) (height (● canvas height))
             (size (size-at width height (budget! r elapsed)))
             (changed (not (= (● r tick) (● w tick))))
             (camera (camera! r (carrier w) (aboard? (● w driver)) elapsed
                              (/ (i32->f64 width) (i32->f64 (max 1 height))))))
        (when changed
          (set! (● r palette) (world-palette (● r actor) (● r marker-hand) (● r reel-hand) w))
          (set! (● r tick) (● w tick)))
        (deform-scene! gpu (● r stage) (● r palette))
        (when changed (refit-tracer! gpu (● r tracer)))
        (let ((view (view-of gpu (● canvas texture) 1)))
          (set! (● r tracer)
                (draw-moving-traced gpu
                                    (resize-tracer gpu (● r tracer) (● size first) (● size second))
                                    view camera (/ 1.0 (i32->f32 (● size second))) 1.3 changed))
          ((● gpu destroy) (ViewObject view))
          ((● gpu work-done)))))))
