;; A camera that flies: dragging turns it, W, A, S and D move it along
;; and across where it looks, Q and E down and up, and the wheel changes
;; its speed; [ and ] darken and brighten the exposure by half a stop. It starts back from a scene's box, looking at its middle.
(define-library (apps viewer fly)
  (export
   Fly
   fly-over
   steered
   flown
   fly-camera
   fly-spread
   fly-exposure)
  (import
   (snail core base)
   (only (snail shell app)
         Input
         KeyDown
         KeyUp
         PointerDown
         PointerMove
         PointerUp
         PointerCancel
         Wheel)
   (only (snail shell math) sin cos atan exp)
   (snail shell graphics pod)
   (only (snail shell graphics raster) Camera3D camera-3d Pinhole))
  (begin

    ;; Where it is, its heading and pitch in radians, the keys held, where
    ;; a drag last was, its speed in units a second, and its exposure in
    ;; stops.
    (record Fly
      ((x F64)
       (y F64)
       (z F64)
       (yaw F64)
       (pitch F64)
       (held (List I32))
       (drag (Option (Pair I32 I32)))
       (speed F64)
       (stops F64)))

    (define fov (→ F64) 1.0)

    ;; Back from the box's middle along +z by its largest extent, a
    ;; little above, looking at the middle.
    (define (fly-over (low (List F64)) (high (List F64))) (→ Fly)
      (let* ((middle
              (map (lambda (axis) (* 0.5 (+ (list-ref low axis) (list-ref high axis)))) (iota 3)))
             (extent (fold-left max
                                0.0
                                (map (lambda (axis) (- (list-ref high axis) (list-ref low axis)))
                                     (iota 3))))
             (back (* 1.2 extent)))
        (new Fly
          (x (list-ref middle 0))
          (y (+ (list-ref middle 1) (* 0.15 extent)))
          (z (+ (list-ref middle 2) back))
          (yaw 0.0)
          (pitch (- 0.0 (atan (/ (* 0.15 extent) (max back 1e-6)))))
          (held (Nil))
          (drag (None))
          (speed (max 0.5 (* 0.4 extent)))
          (stops 0.0))))

    (define (steered (fly Fly) (input Input)) (→ Fly)
      (match input
        ((KeyDown 91 _) (Fly-stops-set fly (- (● fly stops) 0.5)))
        ((KeyDown 93 _) (Fly-stops-set fly (+ (● fly stops) 0.5)))
        ((KeyDown key _)
         (if (member? key (● fly held)) fly (Fly-held-set fly (Cons key (● fly held)))))
        ((KeyUp key) (Fly-held-set fly (filter (lambda (held) (not (= held key))) (● fly held))))
        ((PointerDown _ x y _) (Fly-drag-set fly (Some (new Pair (first x) (second y)))))
        ((PointerMove _ x y) (dragged fly x y))
        ((PointerUp _ _ _) (Fly-drag-set fly (None)))
        ((PointerCancel _) (Fly-drag-set fly (None)))
        ((Wheel pixels) (Fly-speed-set fly (* (● fly speed) (if (> pixels 0) 0.8 1.25))))
        (_ fly)))

    (define (dragged (fly Fly) (x I32) (y I32)) (→ Fly)
      (match (● fly drag)
        ((Some (Pair from-x from-y))
         (let ((turned (Fly-yaw-set fly (- (● fly yaw) (* 0.004 (i32->f64 (- x from-x)))))))
           (Fly-drag-set (Fly-pitch-set turned
                                        (clamped-pitch
                                         (- (● fly pitch) (* 0.004 (i32->f64 (- y from-y))))))
                         (Some (new Pair (first x) (second y))))))
        ((None) fly)))

    (define (clamped-pitch (pitch F64)) (→ F64) (max -1.55 (min 1.55 pitch)))

    ;; Moved by the keys held over `milliseconds`.
    (define (flown (fly Fly) (milliseconds I32)) (→ Fly)
      (let* ((step (* (● fly speed) (/ (i32->f64 milliseconds) 1000.0)))
             (axis (lambda ((plus I32) (minus I32)) (→ F64)
                     (- (if (member? plus (● fly held)) 1.0 0.0)
                        (if (member? minus (● fly held)) 1.0 0.0))))
             (ahead (* step (axis 119 115)))
             (across (* step (axis 100 97)))
             (up (* step (axis 101 113)))
             (forward (looking fly)))
        (new Fly
          (x (+ (● fly x) (+ (* ahead (list-ref forward 0)) (* across (cos (● fly yaw))))))
          (y (+ (● fly y) (+ (* ahead (list-ref forward 1)) up)))
          (z (+ (● fly z) (- (* ahead (list-ref forward 2)) (* across (sin (● fly yaw))))))
          (yaw (● fly yaw))
          (pitch (● fly pitch))
          (held (● fly held))
          (drag (● fly drag))
          (speed (● fly speed))
          (stops (● fly stops)))))

    ;; At yaw 0 it looks along -z.
    (define (looking (fly Fly)) (→ (List F64))
      (list (- 0.0 (* (sin (● fly yaw)) (cos (● fly pitch))))
            (sin (● fly pitch))
            (- 0.0 (* (cos (● fly yaw)) (cos (● fly pitch))))))

    (define (fly-camera (fly Fly) (aspect F64)) (→ Camera3D)
      (let ((forward (looking fly)))
        (camera-3d
         (new Vec3f (x (f64->f32 (● fly x))) (y (f64->f32 (● fly y))) (z (f64->f32 (● fly z))))
         (new Vec3f
           (x (f64->f32 (+ (● fly x) (list-ref forward 0))))
           (y (f64->f32 (+ (● fly y) (list-ref forward 1))))
           (z (f64->f32 (+ (● fly z) (list-ref forward 2)))))
         (Pinhole fov)
         aspect
         1.0)))

    ;; Two to the stops.
    (define (fly-exposure (fly Fly)) (→ F32)
      (f64->f32 (exp (* (● fly stops) 0.6931471805599453))))

    ;; The angle one pixel of a canvas `height` tall spans.
    (define (fly-spread (height I32)) (→ F32) (f64->f32 (/ fov (i32->f64 (max 1 height)))))

    ))
