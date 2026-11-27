;; The city and cast share the forward renderer, image table and metre-scale world.
(define-library (apps last-mile render)
  (export Renderer
          Chase
          follow
          make-renderer
          make-street-renderer
          street-camera
          street-exposure
          prepare-street!
          draw!
          render-resolution
          reset-view!)
  (import
   (snail core base)
   (apps last-mile lamps)
   (snail shell math)
   (snail shell app)
   (only (snail shell gpu) Gpu)
   (only (snail shell graphics pod) Vec4f Vec3f Vec2f Mat4x4f)
   (only (snail shell graphics animation)
         posed-nodes
         skin-palette
         rigid-binding
         named-branch
         unit-matrix
         product-column)
   (snail shell graphics gltf animation)
   (snail shell graphics gltf)
   (only (snail shell graphics raster) camera-3d PinholeRange Camera3D Camera3D-scene-time-set)
   (snail shell graphics forward scene)
   (only (snail shell graphics forward render)
         Forward
         make-forward
         resize-forward
         set-scene!
         set-environment!
         draw-forward)
   (only (snail shell graphics passes) Photographic)
   (snail shell graphics forward environment)
   (snail shell graphics compositor)
   (snail shell graphics scene)
   (snail shell game physics)
   (snail shell game atlas)
   (only (snail shell game chassis) chassis-clearance walker-height)
   (snail shell game vehicle)
   (prefix (snail shell game rigid-body) rigid:)
   (snail shell game boarding)
   (snail shell game humanoid)
   (snail shell game pedestrian)
   (snail shell game scenery)
   (snail shell graphics forward lights)
   (apps last-mile district)
   (apps last-mile city)
   (apps last-mile game))
  (begin
    (record Cast
      ((model Gltf)
       (skin SkinLayout)
       (traffic I64)
       (residents I64)))
    (record Prepared
      ((sector I64)
       (stage MovingScene)))
    (record Renderer
      ((ground Area)
       (read (Fn (List String) → (List Bytes)))
       (cast Cast)
       (cast-for (Fn Game → Cast))
       (pending (Option Prepared))
       (marked-stand I64)
       (marks (List Mat4x4f))
       (actor Humanoid)
       (horizon Gltf)
       (stage MovingScene)
       (sector I64)
       (images SceneImages)
       (sky Environment)
       (minute I64)
       (forward-renderer Forward)
       (compositor Compositor)
       (palette (List Mat4x4f))
       (time F64)
       (rig (Option Chase))))
    (define (rgba (x F32) (y F32) (z F32) (w F32)) (→ Vec4f) (new Vec4f (x x) (y y) (z z) (w w)))
    ;; Equinox sunlight at San Francisco's latitude in the rotated street
    ;; frame. Wind follows elapsed simulation time through midnight and saves.
    (define (solar-angle (minute I64)) (→ F64)
      (* (/ (- (i64->f64 minute) 360.0) 720.0) pi))

    (define (sky-period (minute I64)) (→ I64)
      (cond ((or (< minute 330) (>= minute 1140)) 3)
            ((< minute 550) 0)
            ((< minute 975) 1)
            (else 2)))
    (define (street-sun (minute I64)) (→ rigid:V3)
      (let* ((angle (solar-angle minute)) (s (sin angle)) (east (cos angle))
             (sun (rigid:v3 (- (* 0.9876 east) (* 0.0964 s))
                            (* 0.79 s)
                            (+ (* 0.1573 east) (* 0.6047 s)))))
        (rigid:unit-vector (if (< s 0.0) (rigid:scaled sun -1.0) sun))))

    ;; The moonlit environment already includes ambient light. Lift exposure
    ;; by half a stop through dusk to keep the street and headlights legible.
    (define (street-exposure (minute I64)) (→ F32)
      (let* ((up (* 0.79 (sin (solar-angle minute))))
             (t (max 0.0 (min 1.0 (/ (- 0.20 up) 0.34)))))
        (f64->f32 (* 1.10 (expt 2.0 (* (* 0.5 (* t t)) (- 3.0 (* 2.0 t))))))))

    (define (column (x F64) (y F64) (z F64) (scale F64)) (→ Vec4f)
      (rgba (f64->f32 (* x scale)) (f64->f32 (* y scale)) (f64->f32 (* z scale)) 0.0))

    ;; Local +z is the model's nose. Sample front/back and side-to-side at
    ;; the wheels, then build an orthonormal frame on their contact plane.
    (define (mount (g Area) (b Body) (lean F64) (sx F64) (sy F64) (sz F64)) (→ Mat4x4f)
      (let* ((p (● b position)) (f (forward (● b heading))) (fx (● f x)) (fz (● f z))
             (l (xz fz (- 0.0 fx)))
             (rise (if (= lean 0.0) 0.0 (* lean (area-slope g p f 2.376))))
             (bank (if (= lean 0.0) 0.0 (* lean (area-slope g p l 1.6))))
             (nz (/ 1.0 (sqrt (+ 1.0 (* rise rise)))))
             (ny (/ 1.0 (sqrt (+ (+ 1.0 (* rise rise)) (* bank bank)))))
             (ux (* ny (- 0.0 (+ (* rise fx) (* bank (● l x))))))
             (uz (* ny (- 0.0 (+ (* rise fz) (* bank (● l z))))))
             (height (area-height g p)))
        (new Mat4x4f
          (x (column (* nz (- (* ny fz) (* uz rise))) (* nz (- (* uz fx) (* ux fz)))
                     (* nz (- (* ux rise) (* ny fx))) sx))
          (y (column ux ny uz sy)) (z (column fx rise fz (* nz sz)))
          (w (rgba (f64->f32 (● p x)) (f64->f32 height) (f64->f32 (● p z)) 1.0)))))


    (define (crew (model Rigged)) (→ Humanoid)
      (new Humanoid
        (rig (● model rig))
        (idle (named-clip model "idle"))
        (walk (named-clip model "walk"))
        (brace (named-clip model "shoot"))
        (drive (named-clip model "racingIdle"))
        (upper-body (named-branch (● model rig) "Spine"))))
    (define (display-body (a Body) (b Body) (t F64)) (→ Body)
      (if (> (distance (● a position) (● b position)) 18.0) b (between-bodies a b t)))
    (define (bones (g Area) (h Humanoid) (a Body) (b Body) (ga Gait) (gb Gait) (t F64) (clock F64))
      (→ (List Mat4x4f))
      (let ((gait (between-gaits ga gb t)))
        (skin-palette (● h rig) (posed-nodes (● h rig) (humanoid-pose h gait clock 0.0)
                                             (mount g
                                                    (display-body a b t)
                                                    (● gait seat)
                                                    0.47
                                                    0.47
                                                    0.47)))))
    (define (basis-column (v rigid:V3) (scale F64)) (→ Vec4f)
      (column (● v x) (● v y) (● v z) scale))
    (define (body-mount (a rigid:RigidBody) (b rigid:RigidBody) (t F64) (side F64) (lift F64)
                        (sx F64) (sy F64) (sz F64)) (→ Mat4x4f)
                        (let* ((delta (rigid:v- (● b center) (● a center)))
                               (f (if (> (rigid:squared delta) 324.0) 1.0 t))
                               (q
                                (rigid:between-rotations (● a orientation) (● b orientation) f))
                               (p (rigid:v+ (rigid:v+ (● a center) (rigid:scaled delta f))
                                            (rigid:rotated q
                                                           (rigid:v3 side
                                                                     (negate lift)
                                                                     0.0)))))
                          (new Mat4x4f
                            (x (basis-column (rigid:rotated q (rigid:v3 -1.0 0.0 0.0)) sx))
                            (y (basis-column (rigid:rotated q (rigid:v3 0.0 1.0 0.0)) sy))
                            (z (basis-column (rigid:rotated q (rigid:v3 0.0 0.0 -1.0)) sz))
                            (w (rgba (f64->f32 (● p x))
                                     (f64->f32 (● p y))
                                     (f64->f32 (● p z))
                                     1.0)))))
    (define (actor-bones (g Area) (h Humanoid) (before Shift) (now Shift) (slot I64)
                         (a Body) (b Body) (ga Gait) (gb Gait) (t F64) (clock F64))
      (→ (List Mat4x4f))
      (match (fall-at now slot)
        ((Some k) (let* ((c (● k motion))
                         (prev (match (fall-at before slot) ((Some old) (● old motion)) (_ c)))
                         (rise (min 1.0 (max 0.0 (/ (- (● k rest) 0.28) 0.52))))
                         (upright (rigid:copy-rigid c)) (p (● b position)))
                    (set! (● upright orientation) (rigid:around-y (negate (● b heading))))
                    (set! (● upright center)
                          (rigid:v3 (● p x) (+ (area-height g p) walker-height) (● p z)))
                    (skin-palette (● h rig)
                                  (posed-nodes (● h rig) (humanoid-pose h resting clock 0.0)
                                               (if (> rise 0.0)
                                                   (body-mount c
                                                               upright
                                                               rise
                                                               0.0
                                                               walker-height
                                                               0.47
                                                               0.47
                                                               0.47)
                                                   (body-mount prev
                                                               c
                                                               t
                                                               0.0
                                                               walker-height
                                                               0.47
                                                               0.47
                                                               0.47))))))
        (_ (bones g h a b ga gb t clock))))
    (define (cab-rider (g Area)
                       (h Humanoid)
                       (before Shift)
                       (now Shift)
                       (driver Bool)
                       (t F64)
                       (clock F64))
      (→ (List Mat4x4f))
      (let* ((a (● before game)) (b (● now game))
             (ra (if driver (● a driver) (● a passenger)))
             (rb (if driver (● b driver) (● b passenger)))
             (ga (if driver (● a gait) (● a passenger-gait)))
             (gb (if driver (● b gait) (● b passenger-gait))))
        (if (and (aboard? ra) (aboard? rb))
            (let ((m (body-mount (list-ref (● before cars) 0) (list-ref (● now cars) 0) t
                                 (* (if driver -0.21 0.21) (● sedan width))
                                 chassis-clearance
                                 0.47
                                 0.47
                                 0.47)))
              (skin-palette (● h rig)
                            (posed-nodes (● h rig)
                                         (humanoid-pose h (between-gaits ga gb t) clock 0.0)
                                         m)))
            (actor-bones g
                         h before now (if driver 0 1)
                         (if driver (driver-body a) (passenger-body a))
                         (if driver (driver-body b) (passenger-body b))
                         ga gb t clock))))
    (define blank-model (→ Gltf)
      (new Gltf (buffers (Nil)) (size 0) (images (Nil)) (materials (Nil)) (placed (Nil))))
    (define (xyz (x F32) (y F32) (z F32)) (→ Vec3) (new Vec3 (x x) (y y) (z z)))
    (define (braking? (s Shift) (i I64)) (→ Bool)
      (match (list-drop (● s braking) i) ((Cons b _) b) (_ #f)))
    (define (translated (m Mat4x4f) (x F32) (y F32) (z F32)) (→ Mat4x4f)
      (new Mat4x4f (x (● m x)) (y (● m y)) (z (● m z)) (w (product-column m (rgba x y z 1.0)))))
    ;; Each arc segment rests on its own terrain sample. Its rigid joint moves
    ;; to the next fare with the fleet, so boarding does not rebuild the city.
    (define zone-segments (→ I64) 24)
    (define (zone-stand (w Game)) (→ I64)
      (match (● (objective w) kind)
        ((Collect) (pickup-index (● w dispatch)))
        ((Deliver) (drop-index (● w dispatch)))
        (_ -1)))
    (define (zone-poses (g Area) (id I64)) (→ (List Mat4x4f))
      (if (< id 0) (map (lambda (_) (translated unit-matrix 0.0 -30.0 0.0)) (iota zone-segments))
          (let ((p (● (stand id) stop)))
            (map (lambda (i) (zone-pose g p i)) (iota zone-segments)))))
    (define (zone-pose (g Area) (p XZ) (i I64)) (→ Mat4x4f)
      (let* (
             (angle (* (* 2.0 pi) (/ (i64->f64 i) (i64->f64 zone-segments))))
             (pos (offset p (forward angle) stand-radius))
             (local (any? (lambda (s) (= (● s id) (sector-id (● g atlas) pos))) (● g sectors))))
        (if local (let ((m (mount g (body pos (+ angle (* 0.5 pi))) 1.0 0.27 0.045 1.36)))
                    (translated m 0.0 2.0 0.0))
            (translated unit-matrix 0.0 -30.0 0.0))))
    (define (world-palette (g Area)
                           (h Humanoid)
                           (marks (List Mat4x4f))
                           (before Shift)
                           (now Shift)
                           (t F64)
                           (clock F64))
      (→ (List Mat4x4f))
      (let* ((a (● before game)) (w (● now game))
             (cars (map (lambda (p)
                          (body-mount (● p first)
                                      (● p second)
                                      (if (> (rigid:squared
                                              (rigid:v- (● p second center) (● p first center)))
                                             100.0)
                                          1.0
                                          t)
                                      0.0
                                      chassis-clearance
                                      1.25
                                      1.4
                                      1.8))
                        (zip (● before cars) (● now cars))))
             (walkers (map-indexed (lambda (i p) (let ((u (● p first)) (v (● p second)))
                                                   (actor-bones g
                                                                h before now (+ i 2)
                                                                (● u body)
                                                                (● v body)
                                                                (● u gait)
                                                                (● v gait)
                                                                t
                                                                (+ clock (* (i64->f64 i) 0.37)))))
                                   (zip (● a residents) (● w residents)))))
        (concatenate
         (list cars
               (map-indexed (lambda (i m)
                              (brake-mount m (= i 0) (braking? now i)))
                            cars)
               marks
               (cab-rider g h before now #t t clock)
               (cab-rider g h before now #f t (+ clock 0.28))
               (concatenate walkers)))))
    (define (vertex-count (g Gltf)) (→ I64)
      (fold-left (lambda (n p) (+ n (● p primitive positions count))) 0 (● g placed)))
    ;; The static prefix has no skin binding. Cars use one rigid joint each,
    ;; and the repeated people use the joints of their shared model.
    (define (cast-for (taxi Gltf) (car Gltf) (brake Gltf) (marker Gltf) (people Rigged) (w Game))
      (→ Cast)
      (let* ((cars (append-gltf taxi car))
             (brakes (append-gltf cars brake)) (zone (append-gltf brakes marker))
             (all (append-gltf zone (● people model)))
             (traffic-parts (list-drop (● cars placed) (length (● taxi placed))))
             (tails (list-drop (● brakes placed) (length (● cars placed))))
             (stripe (list-drop (● zone placed) (length (● brakes placed))))
             (fleet (iota (+ 1 (length (● w traffic)))))
             (person (list-drop (● all placed) (length (● zone placed))))
             (actors (iota (+ 2 (length (● w residents)))))
             (placed (concatenate (list (● taxi placed)
                                        (concatenate (map (lambda (_) traffic-parts) (● w traffic)))
                                        (concatenate (map (lambda (_) tails) fleet))
                                        (concatenate (map (lambda (_) stripe) (iota zone-segments)))
                                        (concatenate (map (lambda (_) person) actors)))))
             (bindings (concatenate (list (list (rigid-binding (vertex-count taxi)))
                                          (map (lambda (_) (rigid-binding (vertex-count car)))
                                               (● w traffic))
                                          (map (lambda (_) (rigid-binding (vertex-count brake)))
                                               fleet)
                                          (map (lambda (_) (rigid-binding (vertex-count marker)))
                                               (iota zone-segments))
                                          (map (lambda (_) (● people binding)) actors)))))
        (new Cast (model (Gltf-placed-set all placed)) (skin (pack-skin bindings))
             (traffic (length (● w traffic))) (residents (length (● w residents))))))
    (define (stage-model (g Area) (horizon Gltf) (cast Cast)) (→ Gltf)
      (append-gltf (append-gltf horizon (city-model g)) (● cast model)))
    (define (build-stage (gpu Gpu) (read (Fn (List String) → (List Bytes))) (g Area)
                         (model Gltf) (cast Cast) (images SceneImages)) (→ MovingScene)
                         (skin-with-layout gpu
                                           (upload-with-images gpu
                                                               read
                                                               model
                                                               images
                                                               (city-lights g)
                                                               (* 4 (+ 1 (● cast traffic))))
                                           (● cast skin)))
    (define (street-samples (g Graphics)) (→ I32) (if (= (● g samples) 4) 4 1))

    (define (make-renderer (gpu Gpu) (read (Fn (List String) → (List Bytes))) (models (List Bytes))
                           (g Area) (s Shift)) (→ Renderer)
                           ((● gpu request-device))
                           (let ((canvas ((● gpu current-texture))))
                             (make-street-renderer gpu
                                                   read
                                                   models
                                                   g
                                                   s
                                                   (● canvas width)
                                                   (● canvas height))))
    (define (make-street-renderer (gpu Gpu)
                                  (read (Fn (List String) → (List Bytes)))
                                  (models (List Bytes))
                                  (g Area) (s Shift) (width I32) (height I32)) (→ Renderer)
                                  (let* ((w (● s game))
                                         (info ((● gpu request-device)))
                                         (format (● info format))
                                         (taxi (lit-car (read-gltf (list-ref models 0) "./") #t))
                                         (car (lit-car (read-gltf (list-ref models 1) "./") #f))
                                         (brake (brake-model blank-model))
                                         (marker (with-shapes blank-model
                                                              (list (Item-glow-set (item (Box)
                                                                                         (xyz 0.0
                                                                                              0.0
                                                                                              0.0)
                                                                                         (xyz 1.0
                                                                                              1.0
                                                                                              1.0)
                                                                                         0.0
                                                                                         (rgb 255
                                                                                              187
                                                                                              45))
                                                                                   2.4))))
                                         (people (read-rigged-gltf (list-ref models 2) "./" read))
                                         (horizon (read-gltf (list-ref models 3) "./"))
                                         (actor (crew people))
                                         (make-cast (lambda ((game Game))
                                                      (→ Cast)
                                                      (cast-for taxi car brake marker people game)))
                                         (cast (make-cast w))
                                         (model (stage-model g horizon cast))
                                         (images (load-scene-images gpu read model))
                                         (stage (build-stage gpu read g model cast images))
                                         (light (daylight gpu (sky-period (clock-minute w))))
                                         (marked (zone-stand w)) (marks (zone-poses g marked))
                                         (palette (world-palette g actor marks s s 1.0 0.0)))
                                    (set! (● light sun) (street-sun (clock-minute w)))
                                    (deform-scene! gpu stage palette)
                                    (write-lamps! gpu stage palette s)
                                    (new Renderer
                                      (ground g)
                                      (read read)
                                      (cast cast)
                                      (cast-for make-cast)
                                      (pending (None))
                                      (marks marks)
                                      (marked-stand marked)
                                      (actor actor)
                                      (horizon horizon)
                                      (stage stage)
                                      (sector (● g center))
                                      (images images) (sky light)
                                      (minute (clock-minute w))
                                      (palette palette)
                                      (time -1.0)
                                      (compositor (make-compositor gpu format))
                                      (rig (None))
                                      (forward-renderer
                                       (make-forward gpu (● stage scene) light width height
                                                     (street-samples (● s graphics))
                                                     (Photographic))))))
    (define (discard-pending! (gpu Gpu) (r Renderer)) (→ Unit)
      (match (● r pending)
        ((Some old) (release-moving-scene gpu (● old stage)) (set! (● r pending) (None)))
        (_ (unit))))
    (define (stage-at (gpu Gpu) (r Renderer) (g Area)) (→ MovingScene)
      (build-stage gpu
                   (● r read)
                   g
                   (stage-model g (● r horizon) (● r cast))
                   (● r cast)
                   (● r images)))
    ;; Forecast four seconds of travel, bounded to less than half a sector.
    ;; Decode and upload one predicted window while the current street stays visible.
    (define (prepare-street! (gpu Gpu) (r Renderer) (b Body)) (→ Unit)
      (let* ((p (● b position)) (v (● b velocity)) (speed (distance v (xz 0.0 0.0)))
             (g (● r ground)) (wanted (focus-sector g p)) (crossed (not (= wanted (● g center))))
             ;; At a corner or after a U-turn the current road takes priority.
             ;; The old window covers it while a missed prediction catches up.
             (ahead (if crossed p (offset p v (min 4.0 (/ 125.0 (max 1.0 speed))))))
             (id (sector-id (● g atlas) ahead)))
        (when (and (or crossed (> speed 1.0))
                   (>= id 0)
                   (not (= (● g center) id))
                   (= (● r sector) (● g center)))
          (match (● r pending)
            ((Some pending)
             (if (= id (● pending sector))
                 (when crossed (focus-area! g p))
                 (discard-pending! gpu r)))
            (_ (match (prepare-area! g ahead)
                 ((Some next) (set! (● r pending)
                                    (Some (new Prepared
                                            (sector id)
                                            (stage (stage-at gpu r next))))))
                 (_ (unit))))))))
    (define (refresh! (r Renderer) (gpu Gpu) (w Game)) (→ Unit)
      (when (not (= (● r sector) (● r ground center)))
        (let* ((old (● r stage)) (id (● r ground center))
               (changed (or (not (= (● r cast traffic) (length (● w traffic))))
                            (not (= (● r cast residents) (length (● w residents)))))))
          (when changed (discard-pending! gpu r) (set! (● r cast) ((● r cast-for) w)))
          (match (● r pending)
            ((Some p) (unless (= id (● p sector)) (discard-pending! gpu r)))
            (_ (unit)))
          (let ((next
                 (match (● r pending) ((Some p) (● p stage)) (_ (stage-at gpu r (● r ground))))))
            (set-scene! gpu (● r forward-renderer) (● next scene))
            (set! (● r pending) (None))
            (set! (● r stage) next))
          (set! (● r marked-stand) -2) (set! (● r sector) id) (set! (● r time) -1.0)
          (release-moving-scene gpu old)))
      (let ((id (zone-stand w))) (unless (= id (● r marked-stand))
                                   (set! (● r marks) (zone-poses (● r ground) id))
                                   (set! (● r marked-stand) id)))
      (let ((minute (clock-minute w)))
        (unless (= minute (● r minute))
          (unless (= (sky-period minute) (sky-period (● r minute)))
            (let ((sky (daylight gpu (sky-period minute))))
              (set-environment! gpu (● r forward-renderer) sky)
              (release-environment gpu (● r sky)) (set! (● r sky) sky)))
          (set! (● r sky sun) (street-sun minute)) (set! (● r minute) minute))))
    ;; The camera owns a world-space focus, its velocity and an orbit heading.
    ;; Integrate a critically damped spring exactly for each presentation interval.
    (record Chase
      ((focus rigid:V3)
       (velocity rigid:V3)
       (heading F64)
       (boom F64)))
    (define (follow (rig (Option Chase)) (target rigid:V3) (heading F64) (dt F64) (length F64))
      (→ Chase)
      (match rig
        ((Some old)
         (let* ((delta (rigid:v- (● old focus) target))
                (rate 9.0) (decay (exp (* (negate rate) dt)))
                (slope (rigid:v+ (● old velocity) (rigid:scaled delta rate)))
                (angle (- heading (● old heading))))
           (if (< (rigid:squared delta) 576.0)
               (new Chase
                 (focus
                  (rigid:v+ target (rigid:scaled (rigid:v+ delta (rigid:scaled slope dt)) decay)))
                 (velocity
                  (rigid:scaled (rigid:v- (● old velocity) (rigid:scaled slope (* rate dt))) decay))
                 (heading
                  (+ (● old heading) (* (- 1.0 (exp (* -4.0 dt))) (atan2 (sin angle) (cos angle)))))
                 (boom (● old boom)))
               (follow (None) target heading dt length))))
        (_ (new Chase
             (focus target)
             (velocity (rigid:v3 0.0 0.0 0.0))
             (heading heading)
             (boom length)))))
    (define (camera! (r Renderer) (b Body) (h F64) (seated Bool) (yaw F64) (pitch F64)
                     (elapsed I32) (aspect F64)) (→ Camera3D)
                     (let* ((g (● r ground)) (p (● b position)) (dt (* 0.001 (i32->f64 elapsed)))
                            (v (● b velocity))
                            (lead (if seated 0.18 0.0))
                            (length (if seated 8.3 5.6))
                            (target
                             (rigid:v3 (+ (● p x) (* lead (● v x))) h (+ (● p z) (* lead (● v z)))))
                            (rig (follow (● r rig) target (● b heading) dt length))
                            (center (xz (● rig focus x) (● rig focus z)))
                            (ahead (forward (+ (if seated (● rig heading) (● b heading)) yaw)))
                            (back (xz (negate (● ahead x)) (negate (● ahead z))))
                            (limit (max 0.20 (- (area-trace-distance g center back (+ length 0.45))
                                                0.45)))
                            (wanted (* length (cos pitch)))
                            (d (min limit
                                    (+ (● rig boom)
                                       (* (- 1.0 (exp (* -5.0 dt))) (- wanted (● rig boom))))))
                            (eye (offset center back d))
                            (at (offset center ahead 2.0))
                            (y (● rig focus y)))
                       (set! (● r rig) (Some (Chase-boom-set rig d)))
                       (camera-3d
                        (new Vec3f (x (f64->f32 (● eye x)))
                             (y (f64->f32 (max (+ 0.45 (area-height g eye))
                                               (+ (+ y 1.5) (* length (sin pitch))))))
                             (z (f64->f32 (● eye z))))
                        (new Vec3f
                          (x (f64->f32 (● at x)))
                          (y (f64->f32 (+ y 1.38)))
                          (z (f64->f32 (● at z))))
                        (PinholeRange 1.0 0.35 32000.0) aspect 1.0)))
    (define (reset-view! (r Renderer)) (→ Unit) (set! (● r rig) (None)) (set! (● r sector) -1))
    (define (render-resolution (r Renderer)) (→ String)
      (let ((target (● r forward-renderer target)))
        (string-append (show (● target w))
                       "×"
                       (show (● target h))
                       " · "
                       (show (● target samples))
                       "× MSAA")))
    (define (street-camera (r Renderer) (s Shift) (aspect F64)) (→ Camera3D)
      (let* ((b (carrier (● s game))) (h (area-height (● r ground) (● b position))))
        (camera! r b h (aboard? (● s game driver)) 0.0 0.28 0 aspect)))
    (define (write-lamps! (gpu Gpu) (stage MovingScene) (palette (List Mat4x4f)) (s Shift)) (→ Unit)
      (update-moving-lights! gpu (● stage scene lights)
                             (concatenate
                              (map-indexed (lambda (i m) (car-lights m (= i 0) (braking? s i)))
                                           (take palette (length (● s cars)))))))
    (define (draw! (r Renderer)
                   (gpu Gpu)
                   (before Shift)
                   (now Shift)
                   (t F64)
                   (yaw F64)
                   (pitch F64)
                   (elapsed I32))
      (→ Unit)
      ;; The last frame's work finishes before this one's is queued, so at
      ;; most one frame waits on the device, and the simulation of this frame
      ;; ran while the device drew the last.
      ((● gpu work-done))
      (refresh! r gpu (● now game))
      (let* ((w (● now game))
             (canvas ((● gpu current-texture)))
             (width (● canvas width))
             (height (● canvas height))
             (settings (● now graphics))
             (time (+ (i64->f64 (● w tick)) t))
             (changed (not (= (● r time) time)))
             (focus (display-body (carrier (● before game)) (carrier w) t))
             (seated (aboard? (● w driver)))
             (h (if seated
                    (let ((y (● (list-ref (● before cars) 0) center y))
                          (next (● (list-ref (● now cars) 0) center y)))
                      (- (+ y (* t (- next y))) chassis-clearance))
                    (area-height (● r ground) (● focus position))))
             (camera (camera! r focus h seated yaw pitch elapsed
                              (/ (i32->f64 width) (i32->f64 (max 1 height))))))
        (when changed
          (set! (● r palette)
                (world-palette (● r ground) (● r actor) (● r marks)
                               before
                               now
                               t
                               (* (* 0.001 (i64->f64 tick-ms)) (max 0.0 (- time 1.0)))))
          (set! (● r time) time))
        (when changed
          (deform-scene! gpu (● r stage) (● r palette))
          (write-lamps! gpu (● r stage) (● r palette) now))
        (let ((frame (scene-frame (Camera3D-scene-time-set camera (f64->f32 (* time 0.05)))
                                  width
                                  height
                                  (street-samples settings)
                                  (street-exposure (clock-minute w)))))
          (present-scene! (● r forward-renderer) frame (● r compositor) canvas))))))
