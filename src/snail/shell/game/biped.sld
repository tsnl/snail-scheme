;; The game and trainer each own one sagittal Rapier trial in their instance.
(define-library (snail shell game biped)
  (export start-biped!
          drive-biped!
          end-biped!
          link-x
          link-height
          link-pitch
          forward-speed
          pitch-rate)
  (import
   (snail core base))
  (begin
    (extern ground-point "snail.core.support" "snail:biped/ground-point" (Fn F64 F64 → Unit))
    (extern start
            "snail.core.support"
            "snail:biped/start"
            (Fn F64 F64 F64 F64 F64 F64 F64 F64 → Unit))
    (extern launch
            "snail.core.support"
            "snail:biped/launch"
            (Fn F64 F64 F64 F64 F64 F64 F64 F64 F64 → Unit))
    (extern drive "snail.core.support" "snail:biped/step" (Fn F64 F64 F64 F64 F64 F64 → Unit))
    (extern state "snail.core.support" "snail:biped/state" (Fn I64 I64 → F64))
    (extern end-biped! "snail.core.support" "snail:biped/end" (Fn → Unit))

    ;; Link zero is the pelvis, then hip, knee and ankle on the right and left.
    (define (link-x (i I64)) (→ F64) (state i 0))
    (define (link-height (i I64)) (→ F64) (state i 1))
    (define (link-pitch (i I64)) (→ F64) (state i 2))
    (define (forward-speed) (→ F64) (state 0 3))
    (define (pitch-rate) (→ F64) (state 0 4))

    (define (start-biped! (ground (Array F64)) (origin F64) (spacing F64) (height F64)
                          (speed F64) (legs (Array F64)) (rates (Array F64))) (→ Unit)
                          (unless (and (>= (array-length ground) 2)
                                       (> spacing 0.0)
                                       (>= (array-length legs) 8)
                                       (>= (array-length rates) 8))
                            (panic "biped needs ground samples and six joint targets"))
                          (for-each (lambda (i)
                                      (ground-point (+ origin (* spacing (i64->f64 i)))
                                                    (array-ref ground i)))
                                    (iota (array-length ground)))
                          (start height
                                 (array-ref legs 6)
                                 (array-ref legs 0)
                                 (array-ref legs 1)
                                 (array-ref legs 2)
                                 (array-ref legs 3) (array-ref legs 4) (array-ref legs 5))
                          (launch speed
                                  (array-ref rates 7)
                                  (array-ref rates 6)
                                  (array-ref rates 0)
                                  (array-ref rates 1)
                                  (array-ref rates 2)
                                  (array-ref rates 3) (array-ref rates 4) (array-ref rates 5)))

    (define (drive-biped! (legs (Array F64))) (→ Unit)
      (drive (array-ref legs 0) (array-ref legs 1) (array-ref legs 2)
             (array-ref legs 3) (array-ref legs 4) (array-ref legs 5)))))
