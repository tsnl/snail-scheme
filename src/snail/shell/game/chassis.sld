;; Road grip acts only while the wheels meet the ground. Gravity and impact
;; impulses always act on the free chassis, including a parked or overturned car.
(define-library (snail shell game chassis)
  (export Drive drive road-chassis chassis-body CarStep car-step step-cars! chassis-clearance)
  (import
   (snail core base)
   (snail shell math)
   (snail shell game physics)
   (snail shell game atlas)
   (snail shell game vehicle)
   (snail shell game rigid-body))
  (begin
    (record Drive
      ((pedal F64)
       (wheel F64)
       (brake Bool)))
    (define (drive (pedal F64) (wheel F64) (brake Bool)) (→ Drive)
      (new Drive (pedal pedal) (wheel wheel) (brake brake)))
    (define chassis-clearance (→ F64) 0.60)
    (define up (→ V3) (v3 0.0 1.0 0.0))
    (define (nose (b RigidBody)) (→ V3) (rotated (● b orientation) (v3 0.0 0.0 -1.0)))
    (define (flat (v V3)) (→ XZ) (xz (● v x) (● v z)))
    (record RoadPatch
      ((point V3)
       (normal V3)
       (walls (List Footprint))))
    (define (road-patch (g Area) (p XZ) (walls (List Footprint))) (→ RoadPatch)
      (let ((gx (area-slope g p (xz 1.0 0.0) 1.6)) (gz (area-slope g p (xz 0.0 1.0) 2.3)))
        (new RoadPatch (point (v3 (● p x) (area-height g p) (● p z)))
             (normal (unit-vector (v3 (negate gx) 1.0 (negate gz)))) (walls walls))))
    (define (road-chassis (g Area) (size CarDimensions) (b Body) (mass F64)) (→ RigidBody)
      (let* ((road (road-patch g (● b position) (Nil))) (n (● road normal))
             (tilt (rotation (cross up n) (+ 1.0 (● n y))))
             (q (compose-rotation tilt (around-y (negate (● b heading)))))
             (c (box-body mass (v3 (● size width) 1.42 (● size length))
                          (v+ (● road point) (v3 0.0 (/ chassis-clearance (● n y)) 0.0)) q))
             (v (● b velocity)))
        (set! (● c momentum) (scaled (v3 (● v x)
                                         (/ (negate (+ (* (● n x) (● v x)) (* (● n z) (● v z))))
                                            (● n y))
                                         (● v z))
                                     mass))
        c))
    (define (chassis-body (c RigidBody)) (→ Body)
      (let ((f (nose c)))
        (new Body (position (flat (● c center))) (heading (atan2 (● f x) (negate (● f z))))
             (velocity (flat (velocity c))))))
    ;; ---- Tyres and bodywork ----

    (define (two-sides (x F64) (y F64) (z F64) (r F64)) (→ (List Ball))
      (list (ball (v3 x y z) r) (ball (v3 (negate x) y z) r)))
    (define (hull (size CarDimensions)) (→ (List Ball))
      (let ((x (- (* 0.5 (● size width)) chassis-clearance))
            (l (- (* 0.5 (● size length)) chassis-clearance)))
        (concatenate (map (lambda (s) (two-sides x 0.0 (* l s) chassis-clearance))
                          (list -1.0 -0.3333333333333333 0.3333333333333333 1.0)))))
    (define (tyres (size CarDimensions)) (→ (List Ball))
      (let ((x (* 0.41 (● size width))) (z (* 0.5 (● size wheelbase))))
        (append (two-sides x -0.36 z 0.24) (two-sides x -0.36 (negate z) 0.24))))
    (define (tangent (v V3) (n V3)) (→ V3) (v- v (scaled n (dot v n))))
    (define (clamp-change (x F64) (limit F64)) (→ F64) (max (negate limit) (min limit x)))
    (define (turn! (b RigidBody) (n V3) (rate F64) (dt F64)) (→ Unit)
      (let* ((change (clamp-change (- rate (dot (spin b) n)) (* 5.5 dt)))
             (j (/ change (dot n (inverse-inertia b n)))))
        (apply-torque-impulse! b (scaled n j))))
    (define (traction! (b RigidBody) (n V3) (size CarDimensions) (control Drive) (dt F64)) (→ Unit)
      (let* ((f (unit-vector (tangent (nose b) n))) (right (cross f n)) (v (velocity b))
             (speed (dot v f)) (grade (/ (● f y) (max 0.1 (sqrt (- 1.0 (* (● f y) (● f y)))))))
             (next (road-speed speed (● control pedal) (● control brake) grade dt))
             (change (+ (- next speed) (* 9.81 (* (● f y) dt))))
             (side (clamp-change (- (* 9.81 (* (● right y) dt)) (dot right v)) (* 8.2 dt)))
             (wheel (road-steering size (● control wheel) speed (/ (- next speed) dt) grade)))
        (apply-impulse! b
                        (● b center)
                        (scaled (v+ (scaled f change) (scaled right side))
                                (/ 1.0 (● b inverse-mass))))
        (turn! b n (/ (* (negate speed) (tan wheel)) (● size wheelbase)) dt)))
    (define (ground-gap (s Ball) (road RoadPatch)) (→ F64)
      (- (dot (v- (● s center) (● road point)) (● road normal)) (● s radius)))

    ;; The city supplies vertical solid footprints. Use the nearest face when
    ;; a sphere starts inside one, as can happen beside a streamed street.
    (define (wall-plane (s Ball) (w Footprint)) (→ (Pair V3 V3))
      (let* ((p (● s center)) (x (● p x)) (z (● p z))
             (q (v3 (max (● w west) (min x (● w east)))
                    (● p y)
                    (max (● w north) (min z (● w south)))))
             (d (v- p q))
             (l (- x (● w west)))
             (r (- (● w east) x))
             (t (- z (● w north)))
             (b (- (● w south) z))
             (side (min (min l r) (min t b))))
        (if (> (squared d) 1e-12) (new Pair (first q) (second (unit-vector d)))
            (let ((n (cond ((= side l) (v3 -1.0 0.0 0.0)) ((= side r) (v3 1.0 0.0 0.0))
                           ((= side t) (v3 0.0 0.0 -1.0)) (else (v3 0.0 0.0 1.0)))))
              (new Pair (first (v+ p (scaled n side))) (second n))))))
    (define (wall-contacts (b RigidBody) (fixed RigidBody) (balls (List Ball))
                           (walls (List Footprint)) (dt F64)) (→ (List Contact))
                           (fold-left (lambda (out w) (fold-left (lambda (xs s)
                                                                   (let ((p (● s center))
                                                                         (r (● s radius)))
                                                                     (if (or (< (+ (● p x) r)
                                                                                (● w west))
                                                                             (> (- (● p x) r)
                                                                                (● w east))
                                                                             (< (+ (● p z) r)
                                                                                (● w north))
                                                                             (> (- (● p z) r)
                                                                                (● w south)))
                                                                         xs
                                                                         (let ((face
                                                                                (wall-plane s w)))
                                                                           (match (plane-contact b
                                                                                                 fixed
                                                                                                 s
                                                                                                 (●
                                                                                                  face
                                                                                                  first)
                                                                                                 (●
                                                                                                  face
                                                                                                  second)
                                                                                                 0.55
                                                                                                 dt)
                                                                             ((Some c) (Cons c xs))
                                                                             (_ xs))))))
                                                                 out
                                                                 balls))
                                      (Nil)
                                      walls))
    (record CarStep
      ((body RigidBody)
       (road RoadPatch)
       (drive Drive)))
    (define (car-step (g Area) (b RigidBody) (control Drive) (walls (List Footprint))) (→ CarStep)
      (new CarStep (body b) (road (road-patch g (flat (● b center)) walls)) (drive control)))
    ;; Static tyre friction holds a stopped car on a grade. Wall and vehicle
    ;; contacts can still apply an impulse which wakes it the next substep.
    (define (parked? (s CarStep) (supports (List Ball))) (→ Bool)
      (let ((b (● s body)) (road (● s road)) (control (● s drive)))
        (and (> (● road normal y) 0.76) (or (● control brake) (= (● control pedal) 0.0))
             (< (squared (velocity b)) 0.008) (< (squared (spin b)) 0.025)
             (every? (lambda (wheel) (let ((gap (ground-gap wheel road)))
                                       (and (> gap -0.025) (< gap 0.035)))) supports))))
    (define (street-forces! (s CarStep) (size CarDimensions) (fixed RigidBody)
                            (shape (List Ball)) (wheels (List Ball)) (dt F64)) (→ (List Contact))
                            (let* ((b (● s body))
                                   (road (● s road))
                                   (n (● road normal))
                                   (control (● s drive))
                                   (standing (> (dot (rotated (● b orientation) up) n) 0.50))
                                   (supports (world-balls b (if standing wheels shape)))
                                   (grip (if standing 0.0 0.65))
                                   (walls (wall-contacts b
                                                         fixed
                                                         (world-balls b shape)
                                                         (● road walls)
                                                         dt)))
                              (if (and standing (parked? s supports))
                                  (begin
                                    (set! (● b momentum) (v3 0.0 0.0 0.0))
                                    (set! (● b angular) (v3 0.0 0.0 0.0))
                                    walls)
                                  (begin
                                    (when (and standing
                                               (any? (lambda (t) (< (ground-gap t road) 0.035))
                                                     supports))
                                      (traction! b n size control dt))
                                    (accelerate! b (v3 0.0 -9.81 0.0) dt)
                                    (fold-left (lambda (out t)
                                                 (match (plane-contact b
                                                                       fixed
                                                                       t
                                                                       (● road point)
                                                                       n
                                                                       grip
                                                                       dt)
                                                   ((Some c) (Cons c out)) (_ out)))
                                               walls
                                               supports)))))
    (define (pair-contacts (cars (List CarStep)) (shape (List Ball)) (reach F64) (dt F64))
      (→ (List Contact))
      (match cars ((Nil) (Nil))
             ((Cons first others)
              (let ((a (● first body)))
                (fold-left (lambda (contacts other)
                             (let ((b (● other body)))
                               (if (>= (squared (v- (● a center) (● b center))) (* reach reach))
                                   contacts
                                   (append (sphere-contacts a
                                                            (world-balls a shape)
                                                            b
                                                            (world-balls b shape)
                                                            0.58
                                                            0.12
                                                            dt)
                                           contacts))))
                           (pair-contacts others shape reach dt) others)))))
    ;; At the speed limit two oncoming bumpers move less than a hull diameter
    ;; relative to each other in one substep. Contacts are visited in car order.
    (define (step-cars! (size CarDimensions) (cars (List CarStep)) (seconds F64)) (→ Unit)
      (let* ((shape (hull size)) (wheels (tyres size)) (fixed (fixed-body))
             (count (max 1 (f64->i64 (ceiling (/ seconds 0.0125)))))
             (dt (/ seconds (i64->f64 count))))
        (when (> dt 0.0)
          (for-each (lambda (_)
                      (let ((contacts (concatenate (map (lambda (c)
                                                          (street-forces! c
                                                                          size
                                                                          fixed
                                                                          shape
                                                                          wheels
                                                                          dt))
                                                        cars))))
                        (solve-contacts!
                         (append (pair-contacts cars shape (+ 1.0 (● size length)) dt) contacts)
                         6)
                        (for-each (lambda (s) (integrate! (● s body) dt)) cars))) (iota count)))))))
