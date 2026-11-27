;; A camera that flies, +y being up: dragging turns it, W, A, S and D move
;; it along and across where it looks, Q and E down and up, and the wheel
;; changes its speed; [ and ] darken and brighten the exposure by half a
;; stop. It starts back from a scene's box, looking at its middle, or
;; where it is put; `upright` stands a scene whose up is another way. The
;; glTF viewer and the splats' share it.
(define-library (snail shell graphics fly)
  (export
   Fly
   Fly-stops-set
   fly-over
   fly-at
   fly-toward
   upright
   steered
   flown
   fly-fov
   fly-eye
   fly-target
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
   (only (snail shell math) sin cos asin atan atan2 exp)
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

    ;; Its vertical field of view, in radians.
    (define fly-fov (→ F64) 1.0)

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

    ;; The fly put at `eye`: x, y and z, then its heading and pitch.
    (define (fly-at (fly Fly) (eye (List F64))) (→ Fly)
      (new Fly
        (x (list-ref eye 0))
        (y (list-ref eye 1))
        (z (list-ref eye 2))
        (yaw (list-ref eye 3))
        (pitch (list-ref eye 4))
        (held (Nil))
        (drag (None))
        (speed (● fly speed))
        (stops (● fly stops))))

    ;; The fly put at `eye`, looking along the unit vector `toward`: the
    ;; heading and pitch that `looking` turns back into it. A fly has no
    ;; roll, so a camera's is lost.
    (define (fly-toward (fly Fly) (eye (List F64)) (toward (List F64))) (→ Fly)
      (fly-at fly
              (append eye
                      (list (atan2 (negate (list-ref toward 0)) (negate (list-ref toward 2)))
                            (asin (max -1.0 (min 1.0 (list-ref toward 1))))))))

    ;; The rotation, column by column, that stands a scene upright for a
    ;; fly: it turns the unit vector `up` to +y about the axis across the
    ;; two (Rodrigues's formula, with k = up × y and h = (1 - cos) / sin²).
    ;; When `up` is -y that axis is any, and it is half a turn about x.
    (define (upright (up (List F64))) (→ (List F64))
      (let ((c (list-ref up 1)) (kx (negate (list-ref up 2))) (kz (list-ref up 0)))
        (if (< c -0.999999)
            (list 1.0 0.0 0.0 0.0 -1.0 0.0 0.0 0.0 -1.0)
            (let ((h (/ 1.0 (+ 1.0 c))))
              (list (+ c (* h (* kx kx)))
                    kz
                    (* h (* kx kz))
                    (negate kz)
                    c
                    kx
                    (* h (* kx kz))
                    (negate kx)
                    (+ c (* h (* kz kz))))))))

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

    (define (fly-eye (fly Fly)) (→ Vec3f)
      (new Vec3f (x (f64->f32 (● fly x))) (y (f64->f32 (● fly y))) (z (f64->f32 (● fly z)))))

    ;; A point it looks at, one unit ahead.
    (define (fly-target (fly Fly)) (→ Vec3f)
      (let ((forward (looking fly)))
        (new Vec3f
          (x (f64->f32 (+ (● fly x) (list-ref forward 0))))
          (y (f64->f32 (+ (● fly y) (list-ref forward 1))))
          (z (f64->f32 (+ (● fly z) (list-ref forward 2)))))))

    (define (fly-camera (fly Fly) (aspect F64)) (→ Camera3D)
      (camera-3d (fly-eye fly) (fly-target fly) (Pinhole fly-fov) aspect 1.0))

    ;; Two to the stops.
    (define (fly-exposure (fly Fly)) (→ F32)
      (f64->f32 (exp (* (● fly stops) 0.6931471805599453))))

    ;; The angle one pixel of a canvas `height` tall spans.
    (define (fly-spread (height I32)) (→ F32)
      (f64->f32 (/ fly-fov (i32->f64 (max 1 height)))))

    ))
