(import
 (snail core base))

;; A replacement consumes the linear record it is given.
(struct Job
  ((attempts I64)
   (work (FnOnce Unit))))

(: twice (-> Job (Pair Job Job)))
(define (twice job)
  (Pair (Job-attempts-set job 1) (Job-attempts-set job 2)))
