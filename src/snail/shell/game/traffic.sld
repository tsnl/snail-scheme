;; Vehicles advance along directed road edges. Drivers yield to the car or
;; pedestrian ahead of them; sidewalk walkers use the existing gait machine.
(define-library (snail shell game traffic)
  (export Motor
          Motor-metres-set
          drive-with-traffic
          seed-motor
          motor-body
          advance-motor
          sidewalk-walker)
  (import
   (snail core base)
   (snail shell math)
   (snail shell wire)
   (snail shell game physics)
   (snail shell game vehicle)
   (snail shell game roads)
   (snail shell game atlas)
   (snail shell game pedestrian))
  (begin
    (record Motor
      ((from I64)
       (to I64)
       (metres F64)
       (speed F64)
       (seed I64)) (deriving Serialize Deserialize))
    (define (random-step (s I64)) (→ I64) (modulo (+ (* 48271 s) 1) 2147483647))
    (define (next-road (r Roads) (last I64) (n I64) (seed I64)) (→ I64)
      (let* ((out (exits r n)) (forward (filter (lambda (v) (not (= v last))) out))
             (ways (if (null? forward) out forward)))
        (cond ((null? ways) n)
              ((or (< last 0) (= (modulo seed 5) 0)) (list-ref ways (modulo seed (length ways))))
              (else (let ((incoming (heading-to (node-at r last) (node-at r n))))
                      (fold-left (lambda (best v)
                                   (if
                                    (> (cos (- (heading-to (node-at r n) (node-at r v)) incoming))
                                       (cos
                                        (- (heading-to (node-at r n) (node-at r best)) incoming)))
                                    v
                                    best))
                                 (list-ref ways 0) ways))))))
    (define (local-node (r Roads) (p XZ) (i I64)) (→ I64)
      (let ((a (* 2.39996 (i64->f64 (+ i 1)))) (reach (+ 24.0 (* 13.0 (i64->f64 (modulo i 7))))))
        (nearest-road r (offset p (forward a) reach))))
    (define (seed-motor (r Roads) (p XZ) (i I64)) (→ Motor)
      (let* ((from (local-node r p i))
             (seed (random-step (+ i 37)))
             (to (next-road r -1 from seed)))
        (new Motor
          (from from)
          (to to)
          (metres (* 0.43 (edge-distance r from to)))
          (speed 2.4)
          (seed seed))))
    (define (motor-body (r Roads) (m Motor)) (→ Body)
      (follow-edge r (● m from) (● m to) (● m metres) 1.7))
    (define (in-lane? (b Body) (p XZ)) (→ Bool)
      (let* ((dir (forward (● b heading)))
             (x (- (● p x) (● b position x)))
             (z (- (● p z) (● b position z)))
             (ahead (+ (* x (● dir x)) (* z (● dir z)))))
        (and (> ahead 0.05) (< ahead 6.5) (< (abs (- (* x (● dir z)) (* z (● dir x)))) 1.5))))
    (define (advance-motor (r Roads) (m Motor) (obstacles (List XZ)) (dt F64)) (→ Motor)
      (let* ((b (motor-body r m)) (yield (any? (lambda (p) (in-lane? b p)) obstacles))
             (v (if yield
                    (max 0.0 (- (● m speed) (* 8.5 dt)))
                    (min (+ 5.0 (i64->f64 (modulo (● m seed) 4))) (+ (● m speed) (* 1.9 dt)))))
             (d (+ (● m metres) (* dt v))) (length (edge-distance r (● m from) (● m to))))
        (if (< d length) (Motor-speed-set (Motor-metres-set m d) v)
            (let* ((seed (random-step (● m seed))) (n (next-road r (● m from) (● m to) seed)))
              (new Motor
                (from (● m to))
                (to n)
                (metres (min (- d length) (edge-distance r (● m to) n)))
                (speed v)
                (seed seed))))))
    ;; Crossing vehicles have a stable right of way by list order. Every
    ;; driver yields to traffic ahead in its lane and respects all car bodies.
    (define (drive-with-traffic (roads Roads) (m Motor) (cab Body) (feet (List XZ))
                                (bodies (List Body)) (i I64) (size CarDimensions) (dt F64))
      (→ Motor)
      (let* ((b (list-ref bodies i)) (others (append (take bodies i) (list-drop bodies (+ i 1)))))
        (let* ((ahead (filter (lambda (o) (> (cos (- (● b heading) (● o heading))) 0.80))
                              (list-drop bodies (+ i 1))))
               (leaders (append (take bodies i) ahead))
               (next (advance-motor roads
                                    m
                                    (Cons (● cab position)
                                          (append feet
                                                  (map (lambda (o) (● o position)) leaders)))
                                    dt))
               (target (motor-body roads next)))
          (if (any? (lambda (o) (closing-on-car? b target o size)) (Cons cab others))
              (Motor-speed-set m 0.0) next))))
    (define (sidewalk-leg (g Area) (r Roads) (from I64) (to I64)) (→ (Option Pedestrian))
      (let* ((distance-on-road (edge-distance r from to)) (start (* 0.20 distance-on-road))
             (end (min (* 0.85 distance-on-road) (+ start 12.0))))
        (let loop ((lanes (list 5.8 -5.8 7.0 -7.0 4.7 -4.7)))
          (match lanes ((Nil) (None))
                 ((Cons lane tail)
                  (let* ((a (● (follow-edge r from to start lane) position))
                         (b (● (follow-edge r from to end lane) position))
                         (walls (area-solids g a (+ 1.0 (distance a b)))))
                    (if
                     (and (> (distance a b) 2.0) (clear? a 0.35 walls) (clear-path? a b 0.35 walls))
                     (Some (pedestrian a b)) (loop tail))))))))
    (define (sidewalk-walker (g Area) (r Roads) (p XZ) (i I64)) (→ Pedestrian)
      (let loop ((attempt 0))
        (let* ((from (local-node r p (+ i (* attempt 7)))) (options (exits r from))
               (to (fold-left (lambda (best n)
                                (if (> (edge-distance r from n) (edge-distance r from best))
                                    n
                                    best))
                              from
                              options)))
          (match (sidewalk-leg g r from to)
            ((Some walker) walker)
            (_ (if (< attempt 6) (loop (+ attempt 1))
                   (let ((at (● (follow-edge r from to 1.0 6.2) position)))
                     (pedestrian at at))))))))))
