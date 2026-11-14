(import
 (snail core base))

(record Work
  ((run (FnOnce → Unit))))

;; Owning a linear field makes the whole record linear.
(define (duplicate (work Work)) (→ (Pair Work Work))
  (new Pair (first work) (second work)))
