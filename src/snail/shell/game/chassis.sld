;; The city and its saved bodies live in Snail. One synchronous Rapier step
;; advances the cab, traffic, and nearby pedestrians against the same bodywork.
(define-library (snail shell game chassis)
  (export Drive
          drive
          road-chassis
          chassis-body
          CarStep
          car-step
          step-cars!
          step-traffic!
          WalkerStep
          walker-step
          walker-body
          walker-height
          chassis-clearance)
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
    (record CarStep
      ((body RigidBody)
       (road RoadPatch)
       (drive Drive)))
    (define (car-step (g Area) (b RigidBody) (control Drive) (walls (List Footprint))) (→ CarStep)
      (new CarStep (body b) (road (road-patch g (flat (● b center)) walls)) (drive control)))
    ;; A standing person's contact volume extends from shoes to shoulders.
    ;; Until a moving vehicle touches it the walker remains under foot control.
    (define walker-height (→ F64) 0.82)
    (record WalkerStep
      ((body RigidBody)
       (road RoadPatch)
       (active Bool)))
    (define (walker-body (b RigidBody) (heading F64)) (→ Body)
      (new Body (position (flat (● b center))) (velocity (flat (velocity b))) (heading heading)))
    (define (walker-step (g Area) (b Body) (motion (Option RigidBody))) (→ WalkerStep)
      (let* ((p (● b position)) (road (road-patch g p (area-solids g p 3.0)))
             (physical (match motion ((Some c) (copy-rigid c))
                              (_ (let ((c (box-body 72.0 (v3 0.55 1.64 0.42)
                                                    (v+ (● road point) (v3 0.0 walker-height 0.0))
                                                    (around-y (negate (● b heading))))))
                                   (set! (● c momentum)
                                         (scaled (v3 (● b velocity x) 0.0 (● b velocity z)) 72.0))
                                   c)))))
        (new WalkerStep (body physical) (road road) (active (match motion ((Some _) #t) (_ #f))))))

    ;; ---- Rapier traffic ----

    ;; A tick passes only scalars to Rust. Body indices live from begin through
    ;; end. The ordered results are copied into the same managed objects that
    ;; the game holds and serializes.
    (extern begin-traffic "snail.core.support" "snail:traffic/begin" (Fn F64 F64 F64 F64 → Unit))
    (extern add-body "snail.core.support" "snail:traffic/body"
            (Fn F64 F64 F64 F64 F64 F64 F64 F64 F64 F64 F64 F64 F64 F64 F64 F64 F64 → I64))
    (extern add-wall "snail.core.support" "snail:traffic/wall" (Fn F64 F64 F64 F64 → Unit))
    (extern add-car "snail.core.support" "snail:traffic/car"
            (Fn I64 F64 F64 F64 F64 F64 F64 F64 F64 I32 → Unit))
    (extern add-walker "snail.core.support" "snail:traffic/walker"
            (Fn I64 F64 F64 F64 F64 F64 F64 I32 → Unit))
    (extern simulate "snail.core.support" "snail:traffic/step" (Fn F64 → Unit))
    (extern body-value "snail.core.support" "snail:traffic/value" (Fn I64 I64 → F64))
    (extern walker-active "snail.core.support" "snail:traffic/walker-active" (Fn I64 → I32))
    (extern end-traffic "snail.core.support" "snail:traffic/end" (Fn → Unit))

    (define (stage-body (b RigidBody) (road RoadPatch)) (→ I64)
      (for-each (lambda (w) (add-wall (● w west) (● w north) (● w east) (● w south)))
                (● road walls))
      (let ((c (● b center)) (q (● b orientation)) (p (● b momentum)) (l (● b angular))
            (i (● b inverse-inertia)))
        (add-body (● c x) (● c y) (● c z) (● q axis x) (● q axis y) (● q axis z) (● q w)
                  (● p x) (● p y) (● p z) (● l x) (● l y) (● l z) (● b inverse-mass)
                  (● i x) (● i y) (● i z))))

    (define (body-vector (id I64) (i I64)) (→ V3)
      (v3 (body-value id i) (body-value id (+ i 1)) (body-value id (+ i 2))))
    (define (read-body! (id I64) (b RigidBody)) (→ Unit)
      (set! (● b center) (body-vector id 0))
      (set! (● b orientation) (new Rotation (axis (body-vector id 3)) (w (body-value id 6))))
      (set! (● b momentum) (body-vector id 7))
      (set! (● b angular) (body-vector id 10)))

    (define (stage-car (size CarDimensions) (s CarStep) (dt F64)) (→ (Fn → Unit))
      (let* ((b (● s body)) (road (● s road)) (p (● road point)) (n (● road normal))
             (id (stage-body b road)) (control (● s drive)) (nose-axis (nose b))
             (f (unit-vector (v- nose-axis (scaled n (dot nose-axis n)))))
             (speed (dot (velocity b) f))
             (grade (/ (● f y) (max 0.1 (sqrt (- 1.0 (* (● f y) (● f y)))))))
             (next (road-speed speed (● control pedal) (● control brake) grade dt))
             (accel (/ (- next speed) dt)))
        ;; Rapier applies gravity. Only the tyre contribution goes to the wheels.
        (add-car id (● p x) (● p y) (● p z) (● n x) (● n y) (● n z)
                 (+ accel (* 9.81 (● f y))) (road-steering size (● control wheel) speed accel grade)
                 (i64->i32 (if (or (● control brake) (= (● control pedal) 0.0)) 1 0)))
        (lambda () (read-body! id b))))

    (define (stage-walker (index I64) (s WalkerStep)) (→ (Fn → Unit))
      (let* ((b (● s body)) (road (● s road)) (p (● road point)) (n (● road normal))
             (id (stage-body b road)))
        (add-walker id (● p x) (● p y) (● p z) (● n x) (● n y) (● n z)
                    (i64->i32 (if (● s active) 1 0)))
        (lambda ()
          (when (= (i32->i64 (walker-active index)) 1)
            (set! (● s active) #t)
            (read-body! id b)))))

    (define (step-cars! (size CarDimensions) (cars (List CarStep)) (seconds F64)) (→ Unit)
      (step-traffic! size cars (Nil) seconds))
    (define (step-traffic! (size CarDimensions) (cars (List CarStep)) (people (List WalkerStep))
                           (seconds F64)) (→ Unit)
                           (when (> seconds 0.0)
                             (begin-traffic (● size width)
                                            (● size length)
                                            (● size wheelbase)
                                            chassis-clearance)
                             (let* ((fleet (map (lambda (s) (stage-car size s seconds)) cars))
                                    (walkers (map-indexed stage-walker people)))
                               (simulate seconds)
                               (for-each (lambda (write!) (write!)) fleet)
                               (for-each (lambda (write!) (write!)) walkers)
                               (end-traffic))))))
