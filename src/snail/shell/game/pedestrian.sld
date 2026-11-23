;; A pedestrian walks between two points. A nearby disturbance preempts
;; that route for a short run, then the pedestrian resumes the same leg.
(define-library (snail shell game pedestrian)
  (export Pedestrian pedestrian advance-pedestrian!)
  (import
   (snail core base)
   (snail shell wire)
   (snail shell game physics)
   (snail shell game humanoid))
  (begin
    (enum Intent
      (Patrol)
      (Flee ((seconds F64) (heading F64)))
      (deriving Serialize Deserialize))
    (record Pedestrian
      ((body Body)
       (next XZ)
       (after XZ)
       (intent Intent)
       (gait Gait))
      (deriving Serialize Deserialize))

    (define (pedestrian (home XZ) (away XZ)) (→ Pedestrian)
      (new Pedestrian (body (body home (heading-to home away))) (next away) (after home)
           (intent (Patrol)) (gait resting)))

    (define (intent (current Intent) (at XZ) (noise (Option XZ)) (dt F64)) (→ Intent)
      (match noise
        ((Some p) (Flee 1.6 (heading-to p at)))
        (_ (match current
             ((Flee t angle) (if (> t dt) (Flee (- t dt) angle) (Patrol)))
             (_ (Patrol))))))

    (define (advance-pedestrian! (r Pedestrian)
                                 (noise (Option XZ))
                                 (walls (List Footprint))
                                 (dt F64))
      (→ Unit)
      (let* ((b (● r body)) (at (● b position)) (goal (● r next))
             (plan (intent (● r intent) at noise dt))
             (moved (match plan ((Flee _ angle) (walk b angle 3.7 walls dt))
                           ((Patrol) (walk b (heading-to at goal) 1.15 walls dt)))))
        (set! (● r body) moved) (set! (● r intent) plan)
        (set! (● r gait) (animate (● r gait) (Striding) (distance at (● moved position)) dt))
        (when (< (distance (● moved position) goal) 0.35)
          (set! (● r next) (● r after)) (set! (● r after) goal))))))
