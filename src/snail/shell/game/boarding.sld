;; Door and seat anchors follow the vehicle's heading. Approaching actors
;; can wait while the vehicle repositions. Crossing the sill holds the car
;; still; the same saved progress locates the actor for physics and drawing.
(define-library (snail shell game boarding)
  (export Door DriverDoor PassengerDoor Rider Ground AtDoor Entering Aboard Leaving
          seat-point door-point rider-body seat-weight crossing? aboard? stopped?
          door-clear? approach-door leave-seat advance-rider walk-around-car)
  (import
   (snail core base)
   (snail shell math)
   (snail shell wire)
   (snail shell game physics)
   (snail shell game vehicle))
  (begin
    (enum Door (DriverDoor) (PassengerDoor))
    (enum Rider
      (Ground ((body Body)))
      (AtDoor ((body Body)))
      (Entering ((tick I64) (heading F64)))
      (Aboard)
      (Leaving ((tick I64)))
      (deriving Serialize Deserialize))
    (define crossing-ticks (→ I64) 12)
    (define (aboard? (r Rider)) (→ Bool) (match r ((Aboard) #t) (_ #f)))
    (define (crossing? (r Rider)) (→ Bool) (match r ((Entering _ _) #t) ((Leaving _) #t) (_ #f)))
    (define (stopped? (b Body)) (→ Bool) (< (abs (signed-speed b)) 0.25))
    (define (side (b Body) (door Door)) (→ XZ)
      (let ((k (match door ((DriverDoor) -1.0) ((PassengerDoor) 1.0))))
        (xz (* k (cos (● b heading))) (* k (sin (● b heading))))))
    (define (seat-point (b Body) (size CarDimensions) (door Door)) (→ XZ)
      (offset (● b position) (side b door) (* 0.21 (● size width))))
    ;; The foot collider uses the parked car's axis-aligned footprint. Walk
    ;; far enough along the door's own lateral axis to clear that footprint.
    (define (door-point (b Body) (size CarDimensions) (door Door)) (→ XZ)
      (let* ((p (● b position)) (v (side b door)) (box (parked-footprint b size))
             (dx (/ (+ 0.44 (- (● box east) (● p x))) (max 0.00001 (abs (● v x)))))
             (dz (/ (+ 0.44 (- (● box south) (● p z))) (max 0.00001 (abs (● v z))))))
        (offset p v (min dx dz))))
    (define (door-clear? (car Body) (size CarDimensions) (door Door) (walls (List Footprint)))
      (→ Bool)
      (clear-path? (seat-point car size door) (door-point car size door) 0.36 walls))

    (define (seat-weight (r Rider)) (→ F64)
      (let* ((tick (match r ((Aboard) crossing-ticks) ((Entering n _) n)
                          ((Leaving n) (- crossing-ticks n)) (_ 0)))
             (t (/ (i64->f64 tick) (i64->f64 crossing-ticks))))
        (* t (* t (- 3.0 (* 2.0 t))))))
    (define (rider-body (r Rider) (car Body) (size CarDimensions) (door Door)) (→ Body)
      (match r
        ((Ground b) b) ((AtDoor b) b)
        ((Aboard)
         (new Body
           (position (seat-point car size door))
           (heading (● car heading))
           (velocity (● car velocity))))
        (_ (let* ((t (seat-weight r)) (a (door-point car size door)) (b (seat-point car size door))
                  (h (match r ((Entering _ h) h) (_ (● car heading)))) (d (- (● car heading) h)))
             (body (xz (+ (● a x) (* t (- (● b x) (● a x)))) (+ (● a z) (* t (- (● b z) (● a z)))))
                   (+ h (* t (atan2 (sin d) (cos d)))))))))

    ;; ---- Walking around a parked vehicle ----

    ;; A path around a rectangle can turn at its four expanded corners.
    ;; Each candidate leg must also clear the street. Visiting a corner once
    ;; bounds the search and lets an actor choose either end of the sedan.
    (record Route
      ((next XZ)
       (length F64)))
    (define (corners (box Footprint)) (→ (List XZ))
      (let ((w (- (● box west) 0.44)) (e (+ (● box east) 0.44))
            (n (- (● box north) 0.44)) (s (+ (● box south) 0.44)))
        (list (xz w n) (xz e n) (xz e s) (xz w s))))
    (define (route (p XZ) (goal XZ) (via (List XZ)) (walls (List Footprint))) (→ (Option Route))
      (if (clear-path? p goal 0.36 walls)
          (Some (new Route (next goal) (length (distance p goal))))
          (fold-left (lambda (best corner)
                       (let ((leg (distance p corner)))
                         (if (or (< leg 0.001) (not (clear-path? p corner 0.36 walls))) best
                             (match (route corner
                                           goal
                                           (filter (lambda (v) (> (distance v corner) 0.001)) via)
                                           walls)
                               ((None) best)
                               ((Some tail)
                                (let ((n (+ leg (● tail length))))
                                  (if (match best ((Some old) (< (● old length) n)) (_ #f))
                                      best (Some (new Route (next corner) (length n))))))))))
                     (None) via)))
    (define (walk-around-car (b Body) (goal XZ) (car Body) (size CarDimensions)
                             (walls (List Footprint)) (dt F64)) (→ Body)
                             (let* ((box (parked-footprint car size))
                                    (solids (Cons box walls))
                                    (p (● b position)))
                               (match (route p goal (corners box) solids)
                                 ((Some path) (let* ((at (● path next)) (d (distance p at)))
                                                (if (< d 0.001) (body p (● b heading))
                                                    (walk b
                                                          (heading-to p at)
                                                          (min 2.5 (/ d dt))
                                                          solids
                                                          dt))))
                                 ((None) (body p (● b heading))))))

    ;; ---- The seat interaction ----

    (define (approach-door (r Rider) (car Body) (reach F64)) (→ Rider)
      (match r
        ((Ground b) (if (and (stopped? car) (<= (distance (● b position) (● car position)) reach))
                        (AtDoor b) r)) (_ r)))
    (define (leave-seat (r Rider)
                        (car Body)
                        (size CarDimensions)
                        (door Door)
                        (walls (List Footprint)))
      (→ Rider)
      (if (and (aboard? r) (stopped? car) (door-clear? car size door walls)) (Leaving 0) r))
    (define (advance-rider (r Rider) (car Body) (size CarDimensions) (door Door)
                           (walls (List Footprint)) (dt F64)) (→ Rider)
                           (match r
                             ((AtDoor b)
                              (cond
                               ((not (stopped? car)) (Ground (body (● b position) (● b heading))))
                               ((not (door-clear? car size door walls)) r)
                               (else (let* ((at (door-point car size door))
                                            (walked (walk-around-car b at car size walls dt)))
                                       (if (< (distance (● walked position) at) 0.001)
                                           (Entering 0 (● walked heading))
                                           (AtDoor walked))))))
                             ((Entering n h)
                              (if (>= (+ n 1) crossing-ticks) (Aboard) (Entering (+ n 1) h)))
                             ((Leaving n)
                              (if (>= (+ n 1) crossing-ticks)
                                  (Ground (body (door-point car size door) (● car heading)))
                                  (Leaving (+ n 1))))
                             (_ r)))))
