;; A gaussian-splat viewer: one cloud of gaussians, a ring, written three
;; times, each copy on its own row of the transforms table. Each frame
;; poses the rows, so two rings turn linked like a chain's and a third,
;; smaller, tumbles around them, while the gaussians stay where they were
;; written. Dragging orbits the camera and the wheel brings it nearer.
(define-library (apps splats viewer)
  (export
   View
   new-view
   update-view
   Drawing
   start-drawing
   draw-view)
  (import
   (snail core base)
   (snail shell math)
   (only (snail shell app)
         Input
         Elapsed
         PointerDown
         PointerMove
         PointerUp
         PointerCancel
         Wheel)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics splat)
   (only (snail shell task) tasks))
  (begin

    ;; ---- The view ----

    ;; The camera's orbit, the seconds shown, and where a drag last was.
    (record View
      ((yaw F64)
       (pitch F64)
       (distance F64)
       (seconds F64)
       (drag (Option (Pair I32 I32)))))

    (define (new-view (seed I32) (width I32) (height I32)) (→ View)
      (new View (yaw 0.6) (pitch 0.45) (distance 6.0) (seconds 0.0) (drag (None))))

    (define (update-view (view View) (input Input)) (→ View)
      (match input
        ((Elapsed milliseconds)
         (View-seconds-set view (+ (● view seconds) (/ (i32->f64 milliseconds) 1000.0))))
        ((PointerDown _ x y _) (View-drag-set view (Some (new Pair (first x) (second y)))))
        ((PointerMove _ x y) (dragged view x y))
        ((PointerUp _ _ _) (View-drag-set view (None)))
        ((PointerCancel _) (View-drag-set view (None)))
        ((Wheel pixels)
         (View-distance-set view
                            (max 2.0
                                 (min 20.0
                                      (* (● view distance) (exp (* 0.001 (i32->f64 pixels))))))))
        (_ view)))

    ;; A drag turns the orbit by a hundredth of a radian a pixel.

    (define (dragged (view View) (x I32) (y I32)) (→ View)
      (match (● view drag)
        ((Some at)
         (let ((dx (i32->f64 (- x (● at first)))) (dy (i32->f64 (- y (● at second)))))
           (View-drag-set (View-pitch-set (View-yaw-set view (- (● view yaw) (* 0.01 dx)))
                                          (max -1.5 (min 1.5 (+ (● view pitch) (* 0.01 dy)))))
                          (Some (new Pair (first x) (second y))))))
        ((None) view)))

    (define (camera (view View) (width I32) (height I32)) (→ SplatCamera)
      (let ((d (● view distance)) (yaw (● view yaw)) (pitch (● view pitch)))
        (splat-camera
         (vec3 (* d (* (cos pitch) (sin yaw))) (* d (sin pitch)) (* d (* (cos pitch) (cos yaw))))
         (vec3 0.0 0.0 0.0)
         (vec3 0.0 1.0 0.0)
         0.8
         width
         height)))

    (define (vec3 (x F64) (y F64) (z F64)) (→ Vec3f)
      (new Vec3f (x (f64->f32 x)) (y (f64->f32 y)) (z (f64->f32 z))))

    ;; ---- The ring ----

    ;; How many gaussians a ring has.
    (define ring-size (→ I64) 20000)

    ;; A number in [0, 1) for each index and stream, by multiplicative
    ;; hashing.
    (define (hashed (index I64) (stream I64)) (→ F64)
      (/ (i64->f64 (modulo (* (+ (* index 7) (+ stream 1)) 2654435761) 4294967296)) 4294967296.0))

    ;; A torus of radii 1 and 0.3 in the xz plane, its gaussians stretched
    ;; along the ring, colored by their angle around it, with a sheen
    ;; toward +z in their first-degree coefficients. A turn by θ about y
    ;; takes x to (cos θ, 0, -sin θ), so the tangent at angle u, (-sin u,
    ;; 0, cos u), is θ = -(u + π/2), a quaternion of half that angle.

    (define (ring-gaussian (index I64) (transform I32)) (→ Gaussian)
      (let* ((u (* 2.0 (* pi (hashed index 0))))
             (v (* 2.0 (* pi (hashed index 1))))
             (r (+ 1.0 (* 0.3 (cos v))))
             (turn (/ (+ u (/ pi 2.0)) -2.0)))
        (new Gaussian
          (position (vec3 (* r (cos u)) (* 0.3 (sin v)) (* r (sin u))))
          (transform transform)
          (rotation (new Vec4f (x 0.0) (y (f64->f32 (sin turn))) (z 0.0) (w (f64->f32 (cos turn)))))
          (scale (vec3 0.07 0.025 0.025))
          (opacity 0.7))))

    (define (ring-colors (index I64)) (→ (List Vec3f))
      (let ((u (* 2.0 (* pi (hashed index 0)))) (c (lambda (x) (/ (- x 0.5) 0.2820948))))
        (list (vec3 (c (+ 0.5 (* 0.45 (cos u))))
                    (c (+ 0.5 (* 0.45 (cos (+ u 2.1)))))
                    (c (+ 0.5 (* 0.45 (cos (+ u 4.2))))))
              (vec3 0.0 0.0 0.0)
              (vec3 0.4 0.4 0.4)
              (vec3 0.0 0.0 0.0))))

    (define (ring (transform I32)) (→ Cloud)
      (pack-cloud (map (lambda (index) (ring-gaussian index transform)) (iota ring-size))
                  (map ring-colors (iota ring-size))))

    ;; ---- Poses ----

    ;; A transform from a 3x3 linear part, column by column, and a
    ;; translation.

    (define (pose (m (List F64)) (x F64) (y F64) (z F64)) (→ Mat4x4f)
      (let ((column (lambda (c w)
                      (new Vec4f
                        (x (f64->f32 (list-ref m (* 3 c))))
                        (y (f64->f32 (list-ref m (+ (* 3 c) 1))))
                        (z (f64->f32 (list-ref m (+ (* 3 c) 2))))
                        (w w)))))
        (new Mat4x4f
          (x (column 0 0.0))
          (y (column 1 0.0))
          (z (column 2 0.0))
          (w (new Vec4f (x (f64->f32 x)) (y (f64->f32 y)) (z (f64->f32 z)) (w 1.0))))))

    (define (about-y (a F64)) (→ (List F64))
      (list (cos a) 0.0 (negate (sin a)) 0.0 1.0 0.0 (sin a) 0.0 (cos a)))

    (define (about-x (a F64)) (→ (List F64))
      (list 1.0 0.0 0.0 0.0 (cos a) (sin a) 0.0 (negate (sin a)) (cos a)))

    (define (times (a (List F64)) (b (List F64))) (→ (List F64))
      (map (lambda (index)
             (let ((column (quotient index 3)) (row (remainder index 3)))
               (fold-left (lambda (sum k)
                            (+ sum
                               (* (list-ref a (+ (* k 3) row)) (list-ref b (+ (* column 3) k)))))
                          0.0
                          (iota 3))))
           (iota 9)))

    (define (scaled (m (List F64)) (s F64)) (→ (List F64))
      (map (lambda (x) (* s x)) m))

    ;; The rings at `t` seconds: the first flat at the origin, the second
    ;; standing through it, both turning together, and a third at 0.4 its
    ;; size tumbling on an orbit around them.

    (define (poses (t F64)) (→ (List Mat4x4f))
      (let ((spin (about-y (* 0.3 t))))
        (list (pose spin 0.0 0.0 0.0)
              (pose (times spin (about-x (/ pi 2.0)))
                    (* 1.0 (cos (* 0.3 t)))
                    0.0
                    (negate (sin (* 0.3 t))))
              (pose (scaled (times (about-y t) (about-x (* 1.7 t))) 0.4)
                    (* 2.4 (cos (* 0.5 t)))
                    (* 0.6 (sin t))
                    (* 2.4 (sin (* 0.5 t)))))))

    ;; ---- Drawing ----

    ;; The splats, made on the first frame once the device answers.
    (record Drawing
      ((splats (Option Splats))))

    (define (start-drawing) (→ Drawing) (new Drawing (splats (None))))

    (define (splats-of (drawing Drawing)) (→ Splats) (! gpu tasks)
      (match (● drawing splats)
        ((Some splats) splats)
        ((None)
         (let ((splats (make-splats "rings" (● (request-device) format) (* 3 ring-size) 3)))
           (for-each (lambda (k) (write-cloud splats (* k ring-size) (ring (i64->i32 k)))) (iota 3))
           splats))))

    ;; Pose the rings, sort, and draw them over the backdrop.

    (define (draw-view (view View) (drawing Drawing)) (→ Drawing) (! gpu tasks)
      (let* ((splats (splats-of drawing))
             (canvas (current-texture))
             (encoder (create-command-encoder)))
        (write-transforms splats (poses (● view seconds)))
        (sort-splats encoder splats (camera view (● canvas width) (● canvas height)))
        (let ((pass (begin-render-pass encoder
                                       (new RenderPassDescriptor
                                         (colors (list (Some (new ColorAttachment
                                                               (view (view-of (● canvas texture) 1))
                                                               (load (Clear (new Color
                                                                              (red 0.02)
                                                                              (green 0.02)
                                                                              (blue 0.03)
                                                                              (alpha 1.0))))
                                                               (store #t)))))
                                         (depth (None))))))
          (draw-splats pass splats)
          (end-pass pass))
        (submit (list (finish encoder)))
        (new Drawing (splats (Some splats)))))

    ))
