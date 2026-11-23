;; Rear-axle kinematic bicycle update from Atsushi Sakai's PythonRobotics,
;; PathTracking/stanley_control/stanley_control.py, State.update (MIT).
;; Copyright (c) 2016 - now Atsushi Sakai and other contributors.
;; The full MIT notice ships in src/apps/last-mile/public/CREDITS.txt.
;; The game supplies pedals, dimensions, speed limits and street footprints.
(define-library (snail shell game vehicle)
  (export CarDimensions parked-footprint signed-speed bicycle-step)
  (import
   (snail core base)
   (snail shell math)
   (snail shell game physics))
  (begin
    (record CarDimensions
      ((wheelbase F64)
       (width F64)
       (length F64)))

    (define (signed-speed (b Body)) (→ F64)
      (let ((axis (forward (● b heading))) (v (● b velocity)))
        (+ (* (● v x) (● axis x)) (* (● v z) (● axis z)))))

    (define (extent (size CarDimensions) (yaw F64)) (→ XZ)
      (let ((c (* 0.5 (abs (cos yaw)))) (s (* 0.5 (abs (sin yaw)))))
        (xz (+ (* (● size width) c) (* (● size length) s))
            (+ (* (● size length) c) (* (● size width) s)))))

    (define (parked-footprint (b Body) (size CarDimensions)) (→ Footprint)
      (let ((e (extent size (● b heading))) (p (● b position)))
        (footprint (● p x) (● p z) (* 2.0 (● e x)) (* 2.0 (● e z)))))

    ;; Compute the rear axle's Euler step in the old heading, then recover
    ;; the chassis center from the new heading. Speed is signed in reverse.
    (define (bicycle-step (b Body) (size CarDimensions) (steering F64) (next-speed F64)
                          (walls (List Footprint)) (dt F64)) (→ Body)
                          (let* ((speed (signed-speed b)) (yaw (● b heading)) (axis (forward yaw))
                                 (l (● size wheelbase))
                                 (next (+ yaw (* dt (* (/ speed l) (tan steering)))))
                                 (rear (offset (● b position) axis (* -0.5 l)))
                                 (goal (offset (offset rear axis (* dt speed))
                                               (forward next)
                                               (* 0.5 l))))
                            (if (or (<= dt 0.0) (= speed 0.0))
                                (new Body (position (● b position)) (heading yaw)
                                     (velocity (offset (xz 0.0 0.0) axis next-speed)))
                                (drive-to b size goal next next-speed walls dt))))

    ;; Expand the street by the chassis before sweeping its center. A car
    ;; that hits a curb stops. Its driver can back away on the next tick.
    (define (drive-to (b Body) (size CarDimensions) (goal XZ) (yaw F64) (speed F64)
                      (walls (List Footprint)) (dt F64)) (→ Body)
                      (let* ((p (● b position)) (e (extent size yaw))
                             (padded (map (lambda (w) (new Footprint (west (- (● w west) (● e x)))
                                                           (east (+ (● w east) (● e x)))
                                                           (north (- (● w north) (● e z)))
                                                           (south (+ (● w south) (● e z))))) walls))
                             (v (xz (/ (- (● goal x) (● p x)) dt) (/ (- (● goal z) (● p z)) dt)))
                             (end (travel p v yaw 0.0 padded dt)))
                        (if (or (> (distance (● end position) goal) 0.000001)
                                (not (clear? goal 0.0 padded)))
                            (body p (● b heading))
                            (new Body
                              (position goal)
                              (heading yaw)
                              (velocity (offset (xz 0.0 0.0) (forward yaw) speed))))))))
