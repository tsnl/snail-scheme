(import
 (snail core base))

;; A replacement consumes the linear record it is given.
(struct Job
  ((attempts I64)
   (work (dyn (FnOnce -> Unit)))))

(: twice (impl (Fn Job -> (Pair Job Job))))
(define (twice job)
  (Pair (Job-attempts-set job 1) (Job-attempts-set job 2)))
