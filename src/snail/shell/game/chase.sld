(define-library (snail shell game chase)
  (export Chase follow)
  (import
   (snail core base)
   (snail shell math)
   (only (snail shell game rigid-body) V3 v3 v- v+ scaled squared))
  (begin
    ;; The camera owns a world-space focus, its velocity and an orbit heading.
    ;; Integrate a critically damped spring exactly for each presentation interval.
    (record Chase
      ((focus V3)
       (velocity V3)
       (heading F64)
       (boom F64)))
    (define (follow (rig (Option Chase)) (target V3) (heading F64) (dt F64) (length F64))
      (→ Chase)
      (match rig
        ((Some old)
         (let* ((delta (v- (● old focus) target))
                (rate 9.0) (decay (exp (* (negate rate) dt)))
                (slope (v+ (● old velocity) (scaled delta rate)))
                (angle (- heading (● old heading))))
           (if (< (squared delta) 576.0)
               (new Chase
                 (focus
                  (v+ target (scaled (v+ delta (scaled slope dt)) decay)))
                 (velocity
                  (scaled (v- (● old velocity) (scaled slope (* rate dt))) decay))
                 (heading
                  (+ (● old heading) (* (- 1.0 (exp (* -4.0 dt))) (atan2 (sin angle) (cos angle)))))
                 (boom (● old boom)))
               (follow (None) target heading dt length))))
        (_ (new Chase
             (focus target)
             (velocity (v3 0.0 0.0 0.0))
             (heading heading)
             (boom length)))))))
