;; All distances are metres. Blender supplies the road, its grade and the
;; collision spans; the bicycle is free to cross the verge or take any lane.
(define-library (apps iygtw ride)
  (export Valley read-valley start-ride Ride step-ride surface-at place-at
          surface-name
          Ride-quality-set
          Ride-light-set
          Ride-samples-set
          Ride-bounces-set
          restore-ride
          reset-ride
          mix
          pedal-speed)
  (import
   (snail core base)
   (snail shell math)
   (snail shell wire)
   (snail shell little-endian)
   (only (snail shell utf8) utf8->string)
   (snail shell game physics)
   (snail shell game terrain)
   (snail shell game vehicle))
  (begin

    ;; ---- The survey ----

    (record Place
      ((name String)
       (at XZ)
       (radius F64)))
    (record Valley
      ((ground Terrain)
       (surfaces Bytes)
       (places (List Place))))
    (define (places (b Bytes) (i I64)) (→ (List Place))
      (if (= i (array-length b)) (Nil)
          (begin
            (when (> (+ i 8) (array-length b)) (panic "truncated village waymark"))
            (let ((end (+ (+ i 8) (u16 b (+ i 6)))))
              (when (> end (array-length b)) (panic "truncated waymark name"))
              (let ((name (match (utf8->string (subarray b (+ i 8) end))
                            ((Ok s) s) (_ (panic "invalid waymark name")))))
                (Cons (new Place (name name)
                           (at (xz (i64->f64 (i16 b i)) (i64->f64 (i16 b (+ i 2)))))
                           (radius (i64->f64 (u16 b (+ i 4)))))
                      (places b end)))))))
    (define (read-valley (ground Bytes) (surfaces Bytes) (marks Bytes)) (→ Valley)
      (let ((g (read-terrain ground)) (p (places marks 0)))
        (unless (and (not (null? p)) (= (● g cell) 1)
                     (= (array-length surfaces) (* (● g cols) (● g rows))))
          (panic "village ground and surface map disagree"))
        (new Valley (ground g) (surfaces surfaces) (places p))))
    (define (surface-at (v Valley) (p XZ)) (→ I32)
      (let* ((g (● v ground))
             (x (max 0 (min (- (● g cols) 1) (- (f64->i64 (floor (● p x))) (● g west)))))
             (z (max 0 (min (- (● g rows) 1) (- (f64->i64 (floor (● p z))) (● g north))))))
        (u8->i32 (array-ref (● v surfaces) (+ x (* z (● g cols)))))))
    (define (surface-name (s I32)) (→ String)
      (case s ((1) "Paved lane") ((2) "Dirt track") ((3) "Bridge") (else "Meadow")))
    (define (place-at (v Valley) (p XZ)) (→ String)
      (let loop ((rest (● v places)) (best 1.0) (name "Field Road"))
        (match rest
          ((Nil) name)
          ((Cons h tail) (let ((d (/ (distance p (● h at)) (max 1.0 (● h radius)))))
                           (if (< d best) (loop tail d (● h name)) (loop tail best name)))))))

    ;; ---- Bicycle and companion ----

    (record Ride
      ((bike Body)
       (dog Body)
       (steer F64)
       (lean F64)
       (crank F64)
       (wheel F64)
       (stride F64)
       (metres F64)
       (quality I64)
       (light I64)
       (samples I32)
       (bounces I64)
       (standing F64))
      (deriving Serialize Deserialize))
    (define roadster (→ CarDimensions)
      (new CarDimensions (wheelbase 1.08) (width 0.52) (length 1.76)))
    (define (start-ride (v Valley)) (→ Ride)
      (let ((p (● (list-ref (● v places) 0) at)))
        (new Ride (bike (body p 0.0)) (dog (body (offset p (xz 1.0 0.0) 1.15) 0.0))
             (steer 0.0) (lean 0.0) (crank 0.0) (wheel 0.0) (stride 0.0)
             (metres 0.0) (quality 4) (light 0) (samples 2) (bounces 2) (standing 0.0))))

    (define (reset-ride (v Valley) (s Ride)) (→ Ride)
      (let ((r (start-ride v)))
        (Ride-bounces-set (Ride-samples-set (Ride-quality-set (Ride-light-set r (● s light))
                                                              (● s quality)) (● s samples))
                          (● s bounces))))

    ;; The first Willowbank save predates the shorter survey. Its wire tag
    ;; identifies the original field layout, including the two Body records.
    (define (restore-ride (v Valley) (bytes Bytes)) (→ Ride)
      (let* ((d (new Decoder (bytes bytes) (position 0))) (tag (ann (decode d) I32)))
        (if (= tag -613528936) (restore-first-survey v d) (ann (deserialize bytes) Ride))))

    (define (resurvey (v Valley) (b Body) (fallback Body)) (→ Body)
      (let* ((where (● b position))
             (p (xz (/ (* 2.0 (● where x)) 3.0) (/ (* 2.0 (● where z)) 3.0))))
        (if (clear? p 0.44 (nearby-solids (● v ground) p 2.0)) (body p (● b heading)) fallback)))

    (define (restore-first-survey (v Valley) (d Decoder)) (→ Ride)
      (let* ((r (start-ride v)) (b (resurvey v (ann (decode d) Body) (● r bike)))
             (dog (resurvey v (ann (decode d) Body) (body (● b position) (● b heading))))
             (steer (ann (decode d) F64)) (lean (ann (decode d) F64))
             (crank (ann (decode d) F64)) (wheel (ann (decode d) F64)) (stride (ann (decode d) F64))
             (metres (ann (decode d) F64)) (q (ann (decode d) I64)) (light (ann (decode d) I64)))
        (new Ride
          (standing 0.0)
          (bike b)
          (dog dog)
          (steer steer)
          (lean lean)
          (crank crank)
          (wheel wheel)
          (stride stride) (metres metres) (quality q) (light light)
          (samples (if (>= q 3) 2 1)) (bounces (if (< q 2) 1 2)))))
    (define (mix (a F64) (b F64) (t F64)) (→ F64) (+ a (* (- b a) t)))
    (define (toward (a F64) (b F64) (amount F64)) (→ F64)
      (+ a (max (negate amount) (min amount (- b a)))))
    ;; At low speed or on a steep grade, the rider can put body weight into
    ;; the downstroke. The same load raises the pelvis in the animated pose.
    (define (standing-effort (speed F64) (grade F64) (driving Bool)) (→ F64)
      (if driving
          (max 0.0 (min 1.0 (max (- 1.0 (/ speed 3.6)) (/ (- grade 0.025) 0.085))))
          0.0))

    (define (pedal-speed (speed F64) (grade F64) (surface I32)
                         (pedal Bool) (back Bool) (brake Bool) (dt F64)) (→ F64)
                         (let* ((rolling (case surface ((0) 0.85) ((2) 0.39) (else 0.145)))
                                (push (+ 3.4 (* 0.50 (standing-effort (abs speed) grade pedal))))
                                (drive (cond (pedal (/ push (+ 1.0 (* 0.21 (max 0.0 speed)))))
                                             (back (if (> speed 0.15) -5.2 -1.25)) (else 0.0)))
                                (next (+ speed
                                         (* dt
                                            (- (- drive (* 8.7 grade))
                                               (* (* 0.016 speed) (abs speed)))))))
                           (cond (brake (toward speed 0.0 (* dt 6.0)))
                                 ((and (not pedal) (not back) (< (abs speed) 0.08)) 0.0)
                                 (else (max (if back -1.45 0.0)
                                            (min 15.0 (toward next 0.0 (* dt rolling))))))))
    (define (companion (g Terrain) (old Body) (bike Body) (dt F64)) (→ Body)
      (let* ((p (● old position)) (b (● bike position)) (yaw (● bike heading))
             (goal (offset (offset b (forward (+ yaw (* pi 0.5))) 1.10)
                           (forward yaw) (if (> (signed-speed bike) 5.0) -0.8 0.36)))
             (d (distance p goal)) (heading (heading-to p goal))
             (speed (min 15.0 (max 0.0 (* 2.5 (- d 0.20))))))
        (if (> (distance p b) 15.0) (body b yaw)
            (travel p (offset (xz 0.0 0.0) (forward heading) speed)
                    (if (> speed 0.24) heading (● old heading)) 0.18
                    (nearby-solids g p 1.3) dt))))
    ;; Wheel angle and body bank come from the same turn radius. A digital
    ;; reversal takes time to pass through straight ahead, even at full lock.
    (define (settle (old F64) (target F64) (amount F64)) (→ F64)
      (if (< (abs (- old target)) 0.0001) target (mix old target amount)))
    (define (steering-angle (old F64) (turn F64) (speed F64)) (→ F64)
      (settle old (atan2 (* turn 0.68) (+ 1.0 (* 0.105 (* speed speed)))) 0.061))

    ;; The Snail fixed tick is 20 ms; steering remains useful at walking pace.
    ;; The two animation clocks follow the crank and the road independently.
    (define (step-ride (v Valley) (r Ride) (turn F64) (pedal Bool) (back Bool) (brake Bool))
      (→ Ride)
      (let* ((dt 0.02) (g (● v ground)) (b (● r bike)) (p (● b position)) (s (signed-speed b))
             (grade (ground-slope g p (forward (● b heading)) 1.08))
             (next (pedal-speed s grade (surface-at v p) pedal back brake dt))
             (steer (steering-angle (● r steer) turn s))
             (bike (bicycle-step b roadster steer next (nearby-solids g p 2.5) dt))
             (length (distance p (● bike position)))
             (dog (companion g (● r dog) bike dt))
             (lean (atan2 (* (* s s) (tan steer)) (* 9.81 1.08)))
             (driving (and pedal (not brake) (>= (signed-speed bike) 0.0)))
             (rollout (max 2.35 (min 7.0 (+ 1.7 (* 0.72 (abs s)))))))
        (new Ride (bike bike) (dog dog) (steer steer)
             (lean (settle (● r lean) (max -0.54 (min 0.54 lean)) 0.065))
             (crank (+ (● r crank)
                       (if driving (/ length rollout) 0.0)))
             (wheel (+ (● r wheel)
                       (/ (* (if (< (signed-speed bike) 0.0) -1.0 1.0) length)
                          (* (* 2.0 pi) 0.355))))
             (stride
              (+ (● r stride) (/ (min 0.30 (distance (● r dog position) (● dog position))) 0.85)))
             (metres (+ (● r metres) length)) (quality (● r quality)) (light (● r light))
             (samples (● r samples)) (bounces (● r bounces))
             (standing (settle (● r standing) (standing-effort (abs s) grade driving) 0.065)))))))
