;; The ground keeps wheel passages in world coordinates. The physics clock also
;; ages the water and the ruts, so a paused or saved ride keeps the same road.
(define-library (apps iygtw soil)
  (export Basin read-basins Rut PoolWake Soil fresh-soil wheel-at pool-cover pool-level
          rut-life rut-depth wetness press-wheels rest-ground clear-wheel-contact)
  (import
   (snail core base)
   (snail shell math)
   (snail shell wire)
   (snail shell little-endian)
   (snail shell game physics))
  (begin
    (record Basin
      ((at XZ)
       (rx F64)
       (rz F64)))
    (define (read-basins (b Bytes)) (→ (List Basin))
      (unless (= (modulo (array-length b) 8) 0) (panic "truncated road basin"))
      (let ((m (lambda (i) (* 0.01 (i64->f64 (i16 b i))))))
        (map (lambda (n)
               (let ((i (* 8 n)))
                 (unless (> (min (m (+ i 4)) (m (+ i 6))) 0.0) (panic "invalid basin radius"))
                 (new Basin (at (xz (m i) (m (+ i 2)))) (rx (m (+ i 4))) (rz (m (+ i 6))))))
             (iota (quotient (array-length b) 8)))))
    (record Rut
      ((a XZ)
       (b XZ)
       (born I64)
       (load F64)) (deriving Serialize Deserialize))
    (record PoolWake
      ((index I64)
       (tick I64)
       (loss F64)
       (at XZ)) (deriving Serialize Deserialize))
    (record Soil
      ((tick I64)
       (ruts (List Rut))
       (wakes (List PoolWake))
       (front (Option XZ))
       (rear (Option XZ)))
      (deriving Serialize Deserialize))
    (define (fresh-soil) (→ Soil)
      (new Soil (tick 0) (ruts (Nil)) (wakes (Nil)) (front (None)) (rear (None))))
    (define (wheel-at (b Body) (axle F64)) (→ XZ)
      (offset (● b position) (forward (● b heading)) axle))
    (define (pool-cover (b Basin) (p XZ)) (→ F64)
      (let ((x (/ (- (● p x) (● b at x)) (● b rx)))
            (z (/ (- (● p z) (● b at z)) (● b rz))))
        (max 0.0 (- 1.0 (+ (* x x) (* z z))))))
    (define (pool-level (w (Option PoolWake)) (tick I64)) (→ F64)
      (match w
        ((Some wake) (- 1.0 (* (● wake loss) (exp (* -0.002 (i64->f64 (- tick (● wake tick))))))))
        (_ 1.0)))
    (define (wetness (basins (List Basin)) (s Soil) (p XZ)) (→ F64)
      (let loop ((rest basins) (i 0) (best 0.0))
        (match rest ((Nil) best)
               ((Cons b tail)
                (let ((cover (pool-cover b p)))
                  (loop tail (+ i 1) (if (> cover 0.0)
                                         (max best
                                              (* cover
                                                 (pool-level
                                                  (find (lambda (w) (= (● w index) i)) (● s wakes))
                                                  (● s tick))))
                                         best)))))))
    (define rut-life (→ I64) 8500)
    ;; Wheel support drops up to 3.5 cm in a repeatedly loaded groove.
    (define (rut-depth (s Soil) (p XZ)) (→ F64)
      (let loop ((rest (● s ruts)) (depth 0.0))
        (match rest ((Nil) depth)
               ((Cons r tail)
                (let* ((a (● r a)) (b (● r b)) (dx (- (● p x) (● a x))) (dz (- (● p z) (● a z))))
                  (if (or (> (abs dx) 0.70) (> (abs dz) 0.70)) (loop tail depth)
                      (let* ((x (- (● b x) (● a x))) (z (- (● b z) (● a z)))
                             (t (max 0.0
                                     (min 1.0
                                          (/ (+ (* dx x) (* dz z))
                                             (max 0.000001 (+ (* x x) (* z z)))))))
                             (off (distance p (offset a (xz x z) t)))
                             (age (/ (i64->f64 (- (● s tick) (● r born))) (i64->f64 rut-life)))
                             (added (* (* 0.012 (● r load))
                                       (* (max 0.0 (- 1.0 age)) (max 0.0 (- 1.0 (/ off 0.094)))))))
                        (if (>= (+ depth added) 0.035) 0.035 (loop tail (+ depth added))))))))))
    (define (clear-wheel-contact (s Soil)) (→ Soil)
      (Soil-rear-set (Soil-front-set s (None)) (None)))
    ;; Sample travel, not elapsed time. Both tyres can share a groove on a
    ;; straight but leave distinct arcs under steering. Never bridge a dry gap.
    (define (wheel-stroke (anchor (Option XZ)) (from XZ) (to XZ) (soft Bool) (tick I64)
                          (load F64) (ruts (List Rut))) (→ (Pair (Option XZ) (List Rut)))
                          (let ((a (match anchor ((Some p) p) (_ from))))
                            (cond ((not soft) (new Pair (first (None)) (second ruts)))
                                  ((< (distance a to) 0.24)
                                   (new Pair (first (Some a)) (second ruts)))
                                  (else (new Pair (first (Some to))
                                             (second
                                              (Cons (new Rut (a a) (b to) (born tick) (load load))
                                                    ruts)))))))
    (define (splash (basins (List Basin)) (s Soil) (p XZ) (travel F64) (tick I64))
      (→ (List PoolWake))
      (let loop ((bs basins) (i 0) (wakes (● s wakes)))
        (match bs ((Nil) wakes)
               ((Cons b rest)
                (let ((cover (pool-cover b p)))
                  (if (or (< cover 0.04) (< travel 0.001)) (loop rest (+ i 1) wakes)
                      (let* ((old (find (lambda (w) (= i (● w index))) wakes))
                             (loss (min 0.78
                                        (+ (- 1.0 (pool-level old tick))
                                           (* 0.19 (* cover travel))))))
                        (loop rest
                              (+ i 1)
                              (Cons (new PoolWake (index i) (tick tick) (loss loss) (at p))
                                    (filter (lambda (w) (not (= (● w index) i))) wakes))))))))))
    (define (weathered-ruts (s Soil) (tick I64)) (→ (List Rut))
      (if (= (modulo tick 100) 0)
          (take (filter (lambda (r) (< (- tick (● r born)) rut-life)) (● s ruts)) 1536)
          (● s ruts)))
    (define (rest-ground (s Soil)) (→ Soil)
      (let ((tick (+ (● s tick) 1)))
        (new Soil
          (tick tick)
          (ruts (weathered-ruts s tick))
          (front (None))
          (rear (None))
          (wakes (● s wakes)))))
    (define (press-wheels (basins (List Basin)) (s Soil) (before Body) (after Body)
                          (soft (Fn XZ → Bool)) (load F64) (grounded Bool)) (→ Soil)
                          (let* ((tick (+ (● s tick) 1)) (ruts (weathered-ruts s tick))
                                 (f (wheel-at after 0.54)) (r (wheel-at after -0.54))
                                 (front (wheel-stroke (● s front)
                                                      (wheel-at before 0.54)
                                                      f
                                                      (and grounded (soft f))
                                                      tick
                                                      0.64
                                                      ruts))
                                 (rear (wheel-stroke (● s rear)
                                                     (wheel-at before -0.54)
                                                     r
                                                     (and grounded (soft r))
                                                     tick
                                                     load
                                                     (● front second))))
                            (new Soil
                              (tick tick)
                              (ruts (● rear second))
                              (front (● front first))
                              (rear (● rear first))
                              (wakes (if grounded
                                         (splash basins
                                                 s
                                                 f
                                                 (distance (wheel-at before 0.54) f)
                                                 tick)
                                         (● s wakes))))))))
