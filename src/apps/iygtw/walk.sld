;; A command changes cadence and the feedback to the motors. The pelvis has no
;; drive: distance, velocity and all six joint readings come from Rapier.
(define-library (apps iygtw walk)
  (export Route lantern-row orchard-rise lower-fields mill-bridge foxglove-farm high-meadow
          walking-ground course course-height course-x reset-walk! step-walk! fallen?
          joint-error walk-reward next-phase policy-size initial-policy read-policy trained-policy)
  (import
   (snail core base)
   (snail shell math)
   (only (snail shell little-endian) u32)
   (snail shell resource)
   (snail shell game terrain)
   (snail shell game physics)
   (snail shell game biped)
   (apps iygtw walking reference))
  (begin

    ;; ---- Sections of the Willowbank survey ----

    (define (walking-ground (resources Resources)) (→ Terrain)
      (read-terrain (read-resource resources (link-file "willowbank/main.resources/ground.bin"))))
    (define (course-x (i I64)) (→ F64) (- (* 0.5 (i64->f64 i)) 2.0))
    (record Route
      ((name String)
       (origin XZ)
       (bearing F64)))
    (define (route (name String) (x F64) (z F64) (bearing F64)) (→ Route)
      (new Route (name name) (origin (xz x z)) (bearing bearing)))
    (define lantern-row (→ Route) (route "Lantern Row" -7.0 53.0 0.0))
    (define orchard-rise (→ Route) (route "Orchard Rise" -29.0 -4.0 3.927))
    (define lower-fields (→ Route) (route "Lower Fields" 25.0 19.0 4.7124))
    (define mill-bridge (→ Route) (route "Mill Bridge" 16.0 -27.0 0.0))
    (define foxglove-farm (→ Route) (route "Foxglove Farm" -1.0 -75.0 5.8905))
    (define high-meadow (→ Route) (route "High Meadow" -62.0 -58.0 0.7854))
    (define (course (terrain Terrain) (route Route)) (→ (Array F64))
      (let* ((origin (● route origin))
             (axis (forward (● route bearing)))
             (base (ground-height terrain origin)))
        (array-generate 49
                        (lambda (i)
                          (- (ground-height terrain (offset origin axis (course-x i))) base)))))
    (define (course-height (ground (Array F64)) (x F64)) (→ F64)
      (let* ((at (max 0.0 (min (i64->f64 (- (array-length ground) 1)) (* 2.0 (+ x 2.0)))))
             (i (f64->i64 at)) (j (min (+ i 1) (- (array-length ground) 1))))
        (+ (array-ref ground i)
           (* (- at (i64->f64 i)) (- (array-ref ground j) (array-ref ground i))))))

    ;; ---- Reference tracking ----

    (define (reset-walk! (ground (Array F64)) (clip Stride) (phase F64)) (→ Unit)
      (let* ((pose (reference-pose clip phase))
             (dt (/ (● clip duration) (i64->f64 (● clip frames))))
             (next (reference-pose clip (+ phase (/ dt (● clip duration)))))
             (rates
              (array-generate 8 (lambda (i) (/ (- (array-ref next i) (array-ref pose i)) dt)))))
        (start-biped! ground (course-x 0) 0.5 (+ (course-height ground 0.0) (array-ref pose 7))
                      (/ (● clip length) (● clip duration)) pose rates)))
    (define (next-phase (clip Stride) (phase F64) (command F64)) (→ F64)
      (let ((p (+ phase (/ command (* 30.0 (● clip length)))))) (- p (floor p))))
    (define (clamp (x F64) (lo F64) (hi F64)) (→ F64) (max lo (min x hi)))
    (define policy-size (→ I64) 15)
    (define (initial-policy) (→ (Array F64))
      (list->array (list 1.2 0.25 0.0 0.0 0.55 0.0 0.0 0.0 0.0 0.0 -0.45 0.0 0.0 0.0 0.0)))
    (define (read-policy (bytes Bytes)) (→ (Array F64))
      (unless (= (array-length bytes) (* 4 policy-size)) (panic "wrong walking policy size"))
      (array-generate policy-size
                      (lambda (i) (f32->f64 (bits->f32 (i64->i32 (u32 bytes (* i 4))))))))

    (define (trained-policy (resources Resources)) (→ (Array F64))
      (read-policy (read-resource resources (link-file "walking/policy.bin"))))

    ;; Subtracting the local surface from each ankle matters on a grade:
    ;; the uphill stance foot can be higher in the world than the swing foot.
    (define (ankle-clearance (g (Array F64)) (i I64)) (→ F64)
      (- (link-height i) (course-height g (link-x i))))
    ;; Each leg shares the same gains. On the ground the hip and ankle
    ;; balance the torso. In swing the hip places the foot relative to the
    ;; supporting ankle. The correction fades between these two tasks.
    (define (step-walk! (weights (Array F64)) (pose (Array F64)) (command F64) (ground (Array F64)))
      (→ Unit)
      (define (w (i I64)) (→ F64) (array-ref weights i))
      (let* ((lean (- (link-pitch 0) (array-ref pose 6))) (rate (clamp (pitch-rate) -4.0 4.0))
             (speed (clamp (- (forward-speed) command) -2.0 2.0)) (x (link-x 0))
             (grade (- (course-height ground (+ x 0.5)) (course-height ground (- x 0.5))))
             (right (clamp (+ 0.5 (* 7.0 (- (ankle-clearance ground 6) (ankle-clearance ground 3))))
                           0.0
                           1.0))
             (hip (+ (+ (* (w 0) lean) (* (w 1) rate)) (+ (* (w 2) speed) (w 3))))
             (ankle (+ (+ (* (w 10) speed) (w 11)) (+ (* (w 12) lean) (* (w 13) rate)))))
        (define (correction (i I64)) (→ F64)
          (let* ((stance (if (< i 3) right (- 1.0 right))) (swing (- 1.0 stance))
                 (placement (- (- x (link-x (if (< i 3) 6 3))) 0.05)))
            (case (modulo i 3)
              ((0) (let ((reach (+ (+ (* (w 4) speed) (w 5)) (* (w 6) placement))))
                     (clamp (+ (- (+ (* stance hip) (* swing reach)) (* (w 7) lean))
                               (* (w 14) grade)) -1.0 1.0)))
              ((1) (clamp (+ (* stance (w 8)) (* swing (w 9))) -0.6 0.6))
              (else (clamp (+ grade (* stance ankle)) -0.9 0.9)))))
        (drive-biped! (array-generate 6 (lambda (i) (+ (array-ref pose i) (correction i)))))))
    (define (fallen? (ground (Array F64))) (→ Bool)
      (or (< (- (link-height 0) (course-height ground (link-x 0))) 0.59)
          (> (abs (link-pitch 0)) 0.95)))
    (define (joint-error (pose (Array F64))) (→ F64)
      (let loop ((i 0) (error 0.0))
        (if (= i 6) (/ error 6.0)
            (let* ((parent (if (= (modulo i 3) 0) 0 i))
                   (relative (- (link-pitch (+ i 1)) (link-pitch parent)))
                   (d (- relative (array-ref pose i))))
              (loop (+ i 1) (+ error (* d d)))))))
    (define (walk-reward (speed-error F64) (pose-error F64)) (→ F64)
      (+ 0.10
         (+ (/ 0.60 (+ 1.0 (* 5.0 (* speed-error speed-error))))
            (/ 0.30 (+ 1.0 (* 8.0 pose-error))))))))
