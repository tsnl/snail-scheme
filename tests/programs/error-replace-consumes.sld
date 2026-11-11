(import
 (snail core base))

;; A replacement consumes the linear record it is given.
(struct Job
  ((attempts I64)
   (work (dyn (FnOnce → Unit)))))

(define (twice (job Job)) (→ (Pair Job Job))
  (Pair (Job-attempts-set job 1) (Job-attempts-set job 2)))
