;; Free rigid bodies in metres, kilograms and seconds. All momenta are in world
;; coordinates. An impulse acts at a point, including when the point is off-centre.
(define-library (snail shell game rigid-body)
  (export V3 v3 v+ v- scaled dot cross squared unit-vector
          Rotation rotation around-y compose-rotation rotated unrotated between-rotations
          RigidBody box-body fixed-body copy-rigid velocity spin point-velocity
          inverse-inertia apply-impulse! apply-torque-impulse! accelerate! integrate!
          Ball ball world-balls Contact contact plane-contact sphere-contacts solve-contacts!)
  (import
   (snail core base)
   (snail shell math)
   (snail shell wire))
  (begin

    ;; ---- Vectors and orientations ----

    (record V3
      ((x F64)
       (y F64)
       (z F64)) (deriving Serialize Deserialize))
    (define (v3 (x F64) (y F64) (z F64)) (→ V3) (new V3 (x x) (y y) (z z)))
    (define (v+ (a V3) (b V3))
      (→ V3)
      (v3 (+ (● a x) (● b x)) (+ (● a y) (● b y)) (+ (● a z) (● b z))))
    (define (v- (a V3) (b V3))
      (→ V3)
      (v3 (- (● a x) (● b x)) (- (● a y) (● b y)) (- (● a z) (● b z))))
    (define (scaled (a V3) (s F64)) (→ V3) (v3 (* (● a x) s) (* (● a y) s) (* (● a z) s)))
    (define (dot (a V3) (b V3))
      (→ F64)
      (+ (* (● a x) (● b x)) (+ (* (● a y) (● b y)) (* (● a z) (● b z)))))
    (define (squared (a V3)) (→ F64) (dot a a))
    (define (cross (a V3) (b V3)) (→ V3)
      (v3 (- (* (● a y) (● b z)) (* (● a z) (● b y)))
          (- (* (● a z) (● b x)) (* (● a x) (● b z)))
          (- (* (● a x) (● b y)) (* (● a y) (● b x)))))
    (define (unit-vector (v V3)) (→ V3)
      (let ((n (squared v))) (if (> n 1e-24) (scaled v (/ 1.0 (sqrt n))) (v3 0.0 0.0 0.0))))
    (record Rotation
      ((axis V3)
       (w F64)) (deriving Serialize Deserialize))
    (define (rotation (axis V3) (w F64)) (→ Rotation)
      (let ((n (+ (squared axis) (* w w))))
        (when (<= n 1e-24) (panic "zero orientation"))
        (let ((s (/ 1.0 (sqrt n)))) (new Rotation (axis (scaled axis s)) (w (* w s))))))
    (define (around-y (angle F64)) (→ Rotation)
      (rotation (v3 0.0 (sin (* 0.5 angle)) 0.0) (cos (* 0.5 angle))))
    (define (compose-rotation (a Rotation) (b Rotation)) (→ Rotation)
      (let ((u (● a axis)) (v (● b axis)))
        (rotation (v+ (cross u v) (v+ (scaled u (● b w)) (scaled v (● a w))))
                  (- (* (● a w) (● b w)) (dot u v)))))
    (define (rotated (q Rotation) (v V3)) (→ V3)
      (let ((t (scaled (cross (● q axis) v) 2.0)))
        (v+ v (v+ (scaled t (● q w)) (cross (● q axis) t)))))
    (define (unrotated (q Rotation) (v V3)) (→ V3)
      (rotated (new Rotation (axis (scaled (● q axis) -1.0)) (w (● q w))) v))
    (define (between-rotations (a Rotation) (b Rotation) (t F64)) (→ Rotation)
      (let ((k (if (< (+ (dot (● a axis) (● b axis)) (* (● a w) (● b w))) 0.0) (negate t) t)))
        (rotation (v+ (scaled (● a axis) (- 1.0 t)) (scaled (● b axis) k))
                  (+ (* (- 1.0 t) (● a w)) (* k (● b w))))))

    ;; ---- Free motion ----

    (record RigidBody
      ((center V3)
       (orientation Rotation)
       (momentum V3)
       (angular V3)
       (inverse-mass F64)
       (inverse-inertia V3))
      (deriving Serialize Deserialize))
    (define (box-body (mass F64) (size V3) (center V3) (q Rotation)) (→ RigidBody)
      (when (or (<= mass 0.0) (<= (min (● size x) (min (● size y) (● size z))) 0.0))
        (panic "a rigid box needs positive mass and side lengths"))
      (let ((x (* (● size x) (● size x)))
            (y (* (● size y) (● size y)))
            (z (* (● size z) (● size z)))
            (k (/ 12.0 mass)))
        (new RigidBody
          (center center)
          (orientation q)
          (momentum (v3 0.0 0.0 0.0))
          (angular (v3 0.0 0.0 0.0))
          (inverse-mass (/ 1.0 mass))
          (inverse-inertia (v3 (/ k (+ y z)) (/ k (+ x z)) (/ k (+ x y)))))))
    (define (fixed-body) (→ RigidBody)
      (let ((zero (v3 0.0 0.0 0.0)))
        (new RigidBody (center zero) (orientation (around-y 0.0)) (momentum zero) (angular zero)
             (inverse-mass 0.0) (inverse-inertia zero))))
    ;; Components are replaced as whole values. A snapshot only needs a new body shell.
    (define (copy-rigid (b RigidBody)) (→ RigidBody) (RigidBody-center-set b (● b center)))
    (define (velocity (b RigidBody)) (→ V3) (scaled (● b momentum) (● b inverse-mass)))
    (define (inverse-inertia (b RigidBody) (v V3)) (→ V3)
      (let ((l (unrotated (● b orientation) v)) (i (● b inverse-inertia)))
        (rotated (● b orientation)
                 (v3 (* (● l x) (● i x)) (* (● l y) (● i y)) (* (● l z) (● i z))))))
    (define (spin (b RigidBody)) (→ V3) (inverse-inertia b (● b angular)))
    (define (point-velocity (b RigidBody) (point V3)) (→ V3)
      (if (= (● b inverse-mass) 0.0) (v3 0.0 0.0 0.0)
          (v+ (velocity b) (cross (spin b) (v- point (● b center))))))
    (define (apply-torque-impulse! (b RigidBody) (j V3)) (→ Unit)
      (when (> (● b inverse-mass) 0.0) (set! (● b angular) (v+ (● b angular) j))))
    (define (apply-impulse! (b RigidBody) (point V3) (j V3)) (→ Unit)
      (when (> (● b inverse-mass) 0.0) (set! (● b momentum) (v+ (● b momentum) j))
            (apply-torque-impulse! b (cross (v- point (● b center)) j))))
    (define (accelerate! (b RigidBody) (a V3) (dt F64)) (→ Unit)
      (when (> (● b inverse-mass) 0.0)
        (set! (● b momentum) (v+ (● b momentum) (scaled a (/ dt (● b inverse-mass)))))))
    (define (integrate! (b RigidBody) (dt F64)) (→ Unit)
      (when (and (> dt 0.0) (> (● b inverse-mass) 0.0))
        (let* ((q (● b orientation)) (u (● q axis)) (v (scaled (spin b) (* 0.5 dt))))
          (set! (● b center) (v+ (● b center) (scaled (velocity b) dt)))
          (set! (● b orientation)
                (rotation (v+ u (v+ (scaled v (● q w)) (cross v u))) (- (● q w) (dot v u)))))))

    ;; ---- Contacts ----

    (record Ball
      ((center V3)
       (radius F64)))
    (define (ball (center V3) (radius F64)) (→ Ball)
      (when (<= radius 0.0) (panic "a collision sphere needs a positive radius"))
      (new Ball (center center) (radius radius)))
    (define (world-balls (b RigidBody) (shape (List Ball))) (→ (List Ball))
      (map
       (lambda (s) (Ball-center-set s (v+ (● b center) (rotated (● b orientation) (● s center)))))
       shape))
    ;; The normal points from b toward a. Accumulated impulses live only for this substep.
    (record Contact
      ((a RigidBody)
       (b RigidBody)
       (point V3)
       (normal V3)
       (target F64)
       (friction F64)
       (load F64)
       (slide V3)))
    (define (relative-speed (a RigidBody) (b RigidBody) (p V3)) (→ V3)
      (v- (point-velocity a p) (point-velocity b p)))
    (define (contact (a RigidBody) (b RigidBody) (point V3) (normal V3)
                     (depth F64) (friction F64) (bounce F64) (dt F64)) (→ Contact)
                     (when (or (<= dt 0.0)
                               (<= (squared normal) 1e-24)
                               (< friction 0.0)
                               (< bounce 0.0))
                       (panic
                        "contact needs a direction, positive timestep and nonnegative material coefficients"))
                     (let* ((n (unit-vector normal)) (speed (dot (relative-speed a b point) n))
                            (separate (min 2.0 (/ (* 0.22 (max 0.0 (- depth 0.001))) dt))))
                       (new Contact (a a) (b b) (point point) (normal n)
                            (target
                             (max separate (if (< speed -1.0) (* (negate speed) bounce) 0.0)))
                            (friction friction) (load 0.0) (slide (v3 0.0 0.0 0.0)))))
    (define (plane-contact (b RigidBody) (fixed RigidBody) (s Ball) (plane V3) (normal V3)
                           (friction F64) (dt F64)) (→ (Option Contact))
                           (let* ((n (unit-vector normal))
                                  (depth (- (● s radius) (dot (v- (● s center) plane) n))))
                             (if (< depth -0.001) (None)
                                 (Some (contact b
                                                fixed
                                                (v- (● s center) (scaled n (● s radius)))
                                                n
                                                depth
                                                friction
                                                0.0
                                                dt)))))
    (define (sphere-contacts (a RigidBody) (as (List Ball)) (b RigidBody) (bs (List Ball))
                             (friction F64) (bounce F64) (dt F64)) (→ (List Contact))
                             (fold-left (lambda (out u)
                                          (fold-left (lambda (xs v)
                                                       (let* ((delta (v- (● u center) (● v center)))
                                                              (r (+ (● u radius) (● v radius)))
                                                              (d2 (squared delta)))
                                                         (if (>= d2 (* r r)) xs
                                                             (let* ((d (sqrt d2))
                                                                    (n (if (> d 1e-9)
                                                                           (scaled delta (/ 1.0 d))
                                                                           (v3 1.0 0.0 0.0)))
                                                                    (p (v- (● u center)
                                                                           (scaled n
                                                                                   (- (● u radius)
                                                                                      (* 0.5
                                                                                         (- r
                                                                                            d)))))))
                                                               (Cons (contact a
                                                                              b
                                                                              p
                                                                              n
                                                                              (- r d)
                                                                              friction
                                                                              bounce
                                                                              dt)
                                                                     xs)))))
                                                     out
                                                     bs))
                                        (Nil)
                                        as))
    (define (response (b RigidBody) (point V3) (axis V3)) (→ F64)
      (if (= (● b inverse-mass) 0.0) 0.0
          (let ((r (cross (v- point (● b center)) axis)))
            (+ (● b inverse-mass) (dot r (inverse-inertia b r))))))
    (define (effective (c Contact) (axis V3)) (→ F64)
      (max 1e-12 (+ (response (● c a) (● c point) axis) (response (● c b) (● c point) axis))))
    (define (exchange! (c Contact) (j V3)) (→ Unit)
      (apply-impulse! (● c a) (● c point) j) (apply-impulse! (● c b) (● c point) (scaled j -1.0)))
    (define (friction! (c Contact)) (→ Unit)
      (let* ((n (● c normal)) (v (relative-speed (● c a) (● c b) (● c point)))
             (slip (v- v (scaled n (dot v n)))) (speed (sqrt (squared slip)))
             (old (● c slide))
             (trial (if (< speed 1e-7)
                        old
                        (v- old (scaled slip (/ 1.0 (effective c (scaled slip (/ 1.0 speed))))))))
             (limit (* (● c load) (● c friction)))
             (next (scaled trial (min 1.0 (/ limit (max 1e-12 (sqrt (squared trial))))))))
        ;; Another contact may unload this one after slip has already stopped.
        (exchange! c (v- next old)) (set! (● c slide) next)))
    (define (resolve! (c Contact)) (→ Unit)
      (let* ((n (● c normal)) (speed (dot (relative-speed (● c a) (● c b) (● c point)) n))
             (load (max 0.0 (+ (● c load) (/ (- (● c target) speed) (effective c n))))))
        (exchange! c (scaled n (- load (● c load)))) (set! (● c load) load)
        (when (> (● c friction) 0.0) (friction! c))))
    (define (solve-contacts! (contacts (List Contact)) (iterations I64)) (→ Unit)
      (let loop ((left iterations))
        (when (and (> left 0) (not (null? contacts)))
          (for-each resolve! contacts)
          (loop (- left 1)))))))
