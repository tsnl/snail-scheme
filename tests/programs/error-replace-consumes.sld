(import
 (snail core base))

;; A replacement consumes the linear record it is given.
(record Job
  ((attempts I64)
   (work (FnOnce → Unit))))

(define (twice (job Job)) (→ (Pair Job Job))
  (new Pair (first (Job-attempts-set job 1)) (second (Job-attempts-set job 2))))
